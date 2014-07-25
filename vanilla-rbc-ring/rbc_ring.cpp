/*
 * rbc_ring.cpp
 *
 *  Created on: Jul 16, 2014
 *      Author: kirill lykov
 */
#include <iostream>
#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <cassert>

#include <algorithm>
#include <vector>
#include <cmath>

using namespace std;

typedef double real;

typedef std::vector<real> hvector;

// global variables
const real boxLength = 10.0;

const size_t nrings = 5;
const size_t natomsPerRing = 10;
const size_t nfluidAtoms = boxLength * boxLength * boxLength; // density 1
const size_t natoms = nrings * natomsPerRing + nfluidAtoms;

hvector xp(natoms), yp(natoms), zp(natoms),
             xv(natoms), yv(natoms), zv(natoms),
             xa(natoms), ya(natoms), za(natoms);

// dpd parameters
const real dtime = 0.001;
const real kbT = 0.1;
const size_t timeEnd = 500;

const real a0 = 500.0, gamma0 = 4.5, cut = 1.2, cutsq = cut * cut, kPower = 0.25,
    sigma = sqrt(2.0 * kbT * gamma0);

// WLC bond parameters (assumed DPD length unit is 0.5*real)
const real lambda = 2.5e-4;
const real lmax  = 1.3;

// bending angle parameters
const real kbend = 50.0 * kbT;
const real theta = M_PI - 2.0 * M_PI / natomsPerRing;

// misc parameters
const size_t outEvery = 50;
const real ringRadius = 1.0;

#ifdef NEWTONIAN
#include <random>
std::random_device rd;
std::mt19937 gen(rd());
std::normal_distribution<> dgauss(0, 1);

real getGRand(size_t, size_t, size_t)
{
  return dgauss(gen);
}
#else
real saru(unsigned int seed1, unsigned int seed2, unsigned int seed3)
{
    seed3 ^= (seed1<<7)^(seed2>>6);
    seed2 += (seed1>>4)^(seed3>>15);
    seed1 ^= (seed2<<9)+(seed3<<8);
    seed3 ^= 0xA5366B4D*((seed2>>11) ^ (seed1<<1));
    seed2 += 0x72BE1579*((seed1<<4)  ^ (seed3>>16));
    seed1 ^= 0X3F38A6ED*((seed3>>5)  ^ (((signed int)seed2)>>22));
    seed2 += seed1*seed3;
    seed1 += seed3 ^ (seed2>>2);
    seed2 ^= ((signed int)seed2)>>17;

    int state  = 0x79dedea3*(seed1^(((signed int)seed1)>>14));
    int wstate = (state + seed2) ^ (((signed int)state)>>8);
    state  = state + (wstate*(wstate^0xdddf97f5));
    wstate = 0xABCB96F7 + (wstate>>1);

    state  = 0x4beb5d59*state + 0x2600e1f7; // LCG
    wstate = wstate + 0x8009d14b + ((((signed int)wstate)>>31)&0xda879add); // OWS

    unsigned int v = (state ^ (state>>26))+wstate;
    unsigned int r = (v^(v>>20))*0x6957f5a7;

    real res = r / (4294967295.0);
    return res;
}

real getGRand(size_t i, size_t j, size_t idtimestep)
{
  const real mysaru = saru(min(i, j), max(i, j), idtimestep);
  return 3.464101615 * mysaru - 1.732050807;
}
#endif

// might be opened by OVITO and xmovie
void lammps_dump(const char* path, real* xs, real* ys, real* zs, const size_t natoms, size_t timestep, real boxLength)
{
  bool append = timestep > 0;
  FILE * f = fopen(path, append ? "a" : "w");

  if (f == NULL)
  {
    std::cout << "I could not open the file " << path << "Aborting now" << std::endl;
    abort();
  }

  // header
  fprintf(f, "ITEM: TIMESTEP\n%lu\n", timestep);
  fprintf(f, "ITEM: NUMBER OF ATOMS\n%lu\n", natoms);
  fprintf(f, "ITEM: BOX BOUNDS pp pp pp\n%g %g\n%g %g\n%g %g\n",
      -boxLength/2.0, boxLength/2.0, -boxLength/2.0, boxLength/2.0, -boxLength/2.0, boxLength/2.0);

  fprintf(f, "ITEM: ATOMS id type xs ys zs\n");

  // positions <ID> <type> <x> <y> <z>
  // free particles have type 2, while rings 1
  for (size_t i = 0; i < natoms; ++i) {
    int type = i > nrings * natomsPerRing ? 2 : 1;
    fprintf(f, "%lu %d %g %g %g\n", i, type, xs[i], ys[i], zs[i]);
  }

  fclose(f);
}

void dump_force(const char* path,  const hvector& xs, const hvector& ys,
                const hvector& zs, const int n, bool append)
{
    FILE * f = fopen(path, append ? "a" : "w");
    if (f == NULL)
    {
      printf("I could not open the file <%s>\n", path);
      printf("Aborting now.\n");
      abort();
    }

    fprintf(f, "%d\n", n);
    fprintf(f, "mymolecule\n");

    for(int i = 0; i < n; ++i)
      fprintf(f, "%d %f %f %f\n", i, xs[i], ys[i], zs[i]);

    fclose(f);

    printf("vmd_xyz: wrote to <%s>\n", path);
}

real innerProd(const real* v1, const real* v2)
{
  return v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2];
}

real norm2(const real* v)
{
  return v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
}

struct SaxpyOp {
  const real m_coeff;
  SaxpyOp(real coeff) : m_coeff(coeff) {}
  /*__host__ __device__*/ real operator()(const real& x, const real& y) const
  {
    return m_coeff * x + y;
  }
};

// delta is difference between coordinates of particles in a bond
void minImage(real* delta)
{
  for (size_t i = 0; i < 3; ++i)
    if (fabs(delta[i]) > 0.5 * boxLength) {
      if (delta[i] < 0.0) delta[i] += boxLength;
      else delta[i] -= boxLength;
    }
}

// set up coordinates
void getRandPoint(real& x, real& y, real& z)
{
   x = drand48() * boxLength - boxLength/2.0;
   y = drand48() * boxLength - boxLength/2.0;
   z = drand48() * boxLength - boxLength/2.0;
}

bool areEqual(const real& left, const real& right)
{
    const real tolerance = 1e-2;
    return fabs(left - right) < tolerance;
}

// **** initialization *****
void addRing(size_t indRing)
{
  real cmass[3];
  getRandPoint(cmass[0], cmass[1], cmass[2]);

  for (size_t indLocal = 0; indLocal < natomsPerRing; ++indLocal) {
    size_t i = natomsPerRing * indRing + indLocal;
    real angle = 2.0 * M_PI / natomsPerRing * i;
    xp[i] = ringRadius * cos(angle) + cmass[0];
    yp[i] = ringRadius * sin(angle) + cmass[1];
    zp[i] = cmass[2];
  }
}

void initPositions()
{
  for (size_t indRing = 0; indRing < nrings; ++indRing) {
    addRing(indRing);
  }

  for (size_t i = nrings * natomsPerRing; i < natoms; ++i) {
    getRandPoint(xp[i], yp[i], zp[i]);
  }
}

// forces computations splitted by the type
void calcDpdForces(size_t timeStep)
{
  real dtinvsqrt = 1.0 / sqrt(dtime);
  for (size_t i = 0; i < natoms; ++i)
  {
#ifdef NEWTONIAN
    for (size_t j = i + 1; j < natoms; ++j)
#else
    for (size_t j = 0; j < natoms; ++j)
#endif
    {
      if (i == j) continue;
      real del[] = {xp[i] - xp[j], yp[i] - yp[j], zp[i] - zp[j]};
      minImage(del);

      real rsq = norm2(del);
      if (rsq < cutsq)
      {
        real r = sqrt(rsq);
        real rinv = 1.0 / r;
        real delv[] = {xv[i] - xv[j], yv[i] - yv[j], zv[i] - zv[j]};

        real dot = innerProd(del, delv);
        real randnum = getGRand(i, j, timeStep);

        // conservative force = a0 * wd
        // drag force = -gamma * wd^2 * (delx dot delv) / r
        // random force = sigma * wd * rnd * dtinvsqrt;
        real wd = pow(1.0 - r/cut, kPower);
        double fpair = a0 * (1.0 - r/cut);
        fpair -= gamma0 * wd * wd * dot * rinv;
        fpair += sigma * wd * randnum * dtinvsqrt;
        fpair *= rinv;

        // finally modify forces
        xa[i] += del[0] * fpair;
        ya[i] += del[1] * fpair;
        za[i] += del[2] * fpair;

#ifdef NEWTONIAN
        xa[j] -= del[0] * fpair;
        ya[j] -= del[1] * fpair;
        za[j] -= del[2] * fpair;
#endif
      }
    }
  }
}

// f_wlc(x) = -0.25KbT/p*((1 - x)^-2 + 4x - 1),
// where x := rij/l_max, p is persistent length
// if we assume that water is always after rings
// than it will work with solvent
void calcBondForcesWLC()
{
  for (size_t indRing = 0; indRing < nrings; ++indRing)
  {
    for (size_t indLocal = 0; indLocal < natomsPerRing; ++indLocal)
    {
      size_t i1 = natomsPerRing * indRing + indLocal;
      size_t i2 = natomsPerRing * indRing + (indLocal + 1) % natomsPerRing;
      real del[] = {xp[i1] - xp[i2], yp[i1] - yp[i2], zp[i1] - zp[i2]};
      minImage(del);

      real rsq = norm2(del);
      real lsq = lmax * lmax;
      if (rsq > lsq) { //0.9025 is from the FNS_SFO_2006
        //std::cerr << "WORM bond too long: " << timestep << " " << sqrt(rsq) << std::endl;
        assert(false); // debug me
      }

      real rdl = sqrt(rsq / lsq); //rij/l

      real fbond = 1.0 / ( (1.0 - rdl) * (1.0 - rdl) ) + 4.0 * rdl - 1.0;

       //0.25kbT/lambda[..]
      fbond *= -0.25 * kbT / lambda;

      // finally modify forces
      xa[i1] += del[0] * fbond;
      ya[i1] += del[1] * fbond;
      za[i1] += del[2] * fbond;

      xa[i2] -= del[0] * fbond;
      ya[i2] -= del[1] * fbond;
      za[i2] -= del[2] * fbond;
    }
  }
}

void calcAngleForcesBend()
{
  for (size_t indRing = 0; indRing < nrings; ++indRing)
  {
    for (size_t indLocal = 0; indLocal < natomsPerRing; ++indLocal)
    {
      size_t i1 = natomsPerRing * indRing + indLocal;
      size_t i2 = natomsPerRing * indRing + (indLocal + 1) % natomsPerRing;
      size_t i3 = natomsPerRing * indRing + (indLocal + 2) % natomsPerRing;

      // 1st bond
      real del1[] = {xp[i1] - xp[i2], yp[i1] - yp[i2], zp[i1] - zp[i2]};
      minImage(del1);
      real rsq1 = norm2(del1);
      real r1 = sqrt(rsq1);

      // 2nd bond
      real del2[] = {xp[i3] - xp[i2], yp[i3] - yp[i2], zp[i3] - zp[i2]};
      minImage(del2);
      real rsq2 = norm2(del2);
      real r2 = sqrt(rsq2);

      // c = cosine of angle
      real c = del1[0] * del2[0] + del1[1] * del2[1] + del1[2] * del2[2];
      c /= r1 * r2;
      if (c > 1.0) c = 1.0;
      if (c < -1.0) c = -1.0;
      c *= -1.0;

      real a11 = kbend * c / rsq1;
      real a12 = -kbend / (r1 * r2);
      real a22 = kbend * c / rsq2;

      real f1[] = {a11 * del1[0] + a12 * del2[0], a11 * del1[1] + a12 * del2[1], a11 * del1[2] + a12 * del2[2]};
      real f3[] = {a22 * del2[0] + a12 * del1[0], a22 * del2[1] + a12 * del1[1], a22 * del2[2] + a12 * del1[2]};

      // apply force to each of 3 atoms
      xa[i1] += f1[0];
      ya[i1] += f1[1];
      za[i1] += f1[2];

      xa[i2] -= f1[0] + f3[0];
      ya[i2] -= f1[1] + f3[1];
      za[i2] -= f1[2] + f3[2];

      xa[i3] += f3[0];
      ya[i3] += f3[1];
      za[i3] += f3[2];
    }
  }
}

void addStretchForce()
{
  real externalForce = 250.0;
  xa[0] += externalForce;
  xa[5] -= externalForce;
}

void addDrivingForce()
{
  real drivingForceY = 100.0;
  std::for_each(ya.begin(), ya.end(), [&](real& in) { in += drivingForceY; });
}

void computeForces(size_t timeStep)
{
  fill(xa.begin(), xa.end(), 0.0);
  fill(ya.begin(), ya.end(), 0.0);
  fill(za.begin(), za.end(), 0.0);

  calcDpdForces(timeStep);
  calcBondForcesWLC();
  calcAngleForcesBend();

  //addStretchForce();
  addDrivingForce();
}

void pbcPerAtomsPerDim(size_t ind, vector<real>& coord)
{
  real boxlo = -0.5 * boxLength;
  real boxhi = 0.5 * boxLength;
  if (coord[ind] < boxlo) {
    coord[ind] += boxLength;
  }
  if (coord[ind] >= boxhi) {
    coord[ind] -= boxLength;
    coord[ind] = std::max(coord[ind], boxlo);
  }
}

void pbc()
{
  for (size_t i = 0; i < natoms; ++i) {
    pbcPerAtomsPerDim(i, xp);
    pbcPerAtomsPerDim(i, yp);
    pbcPerAtomsPerDim(i, zp);
  }
}

void computeDiams()
{
  real axisal[] = {xp[0] - xp[5], yp[0] - yp[5], zp[0] - zp[5]};
  real daxial = sqrt(norm2(axisal));
  real transverse[] = {0.5 * (xp[2] + xp[3] - xp[7] - xp[8]),
      0.5 * (yp[2] + yp[3] - yp[7] - yp[8]),
      0.5 * (zp[2] + zp[3] - zp[7] - zp[8])};
  real dtrans = sqrt(norm2(transverse));
  std::cout << "Daxial=" << daxial << ", Dtras=" << dtrans << std::endl;
}

int main()
{
  std::cout << "Started computing" << std::endl;
  initPositions();
  FILE * fstat = fopen("diag.txt", "w");

  for (size_t timeStep = 0; timeStep < timeEnd; ++timeStep)
  {
    if (timeStep % outEvery == 0)
    {
      std::cout << "t=" << timeStep << std::endl;
      //computeDiams();
      //printStatistics(fstat, timeStep);
    }

    // initial integration of velocity-verlet
    std::transform(xa.begin(), xa.end(), xv.begin(), xv.begin(), SaxpyOp(dtime * 0.5));
    std::transform(ya.begin(), ya.end(), yv.begin(), yv.begin(), SaxpyOp(dtime * 0.5));
    std::transform(za.begin(), za.end(), zv.begin(), zv.begin(), SaxpyOp(dtime * 0.5));

    std::transform(xv.begin(), xv.end(), xp.begin(), xp.begin(), SaxpyOp(dtime));
    std::transform(yv.begin(), yv.end(), yp.begin(), yp.begin(), SaxpyOp(dtime));
    std::transform(zv.begin(), zv.end(), zp.begin(), zp.begin(), SaxpyOp(dtime));

    pbc();
    if (timeStep % outEvery == 0)
      lammps_dump("evolution.dump", &xp.front(), &yp.front(), &zp.front(), natoms, timeStep, boxLength);

    computeForces(timeStep);

    //final integration of velocity-verlet
    std::transform(xa.begin(), xa.end(), xv.begin(), xv.begin(), SaxpyOp(dtime * 0.5));
    std::transform(ya.begin(), ya.end(), yv.begin(), yv.begin(), SaxpyOp(dtime * 0.5));
    std::transform(za.begin(), za.end(), zv.begin(), zv.begin(), SaxpyOp(dtime * 0.5));
  }

  fclose(fstat);
  std::cout << "Ended computing" << std::endl;
  return 0;
}


