#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <cassert>

#include <vector>
#include <string>
#include <iostream>

#ifdef USE_CUDA
#include "cuda-dpd.h"
#endif
#include "funnel-obstacle.h"

inline float saru(unsigned int seed1, unsigned int seed2, unsigned int seed3)
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
    
    float res = r / (4294967295.0f);
    return res;
}

using namespace std;

struct Bouncer;

struct Particles
{
    static int idglobal;
    
    int n, myidstart, steps_per_dump = 100;
    mutable int saru_tag;
    float L, xg = 0, yg = 0, zg = 0;
    vector<float> xp, yp, zp, xv, yv, zv, xa, ya, za;
    Bouncer * bouncer = nullptr;
    string name;

    void _dpd_forces_bipartite(const float kBT, const double dt,
			       const float * const srcxp, const float * const srcyp, const float * const srczp,
			       const float * const srcxv, const float * const srcyv, const float * const srczv,
			       const int nsrc,
			       const int giddstart, const int gidsstart)
	{
	    const float xinvdomainsize = 1 / L;
	    const float yinvdomainsize = 1 / L;
	    const float zinvdomainsize = 1 / L;

	    const float xdomainsize = L;
	    const float ydomainsize = L;
	    const float zdomainsize = L;

	    const float invrc = 1.;
	    const float gamma = 45;
	    const float sigma = sqrt(2 * gamma * kBT);
	    const float sigmaf = sigma / sqrt(dt);
	    const float aij = 2.5;

#ifdef USE_CUDA
	    if(srcxp == &xp.front())
		forces_dpd_cuda(&xp.front(), &yp.front(), &zp.front(),
				&xv.front(), &yv.front(), &zv.front(),
				&xa.front(), &ya.front(), &za.front(),
				n, 
				1, xdomainsize, ydomainsize, zdomainsize,
				aij,  gamma,  sigma,  1 / sqrt(dt));
	    else
		forces_dpd_cuda_bipartite(&xp.front(), &yp.front(), &zp.front(),
					  &xv.front(), &yv.front(), &zv.front(),
					  &xa.front(), &ya.front(), &za.front(),
					  n, giddstart,
					  srcxp,  srcyp,  srczp,
					  srcxv,  srcyv,  srczv,
					  NULL, NULL, NULL,
					  nsrc, gidsstart,
					  1, xdomainsize, ydomainsize, zdomainsize,
					  aij,  gamma,  sigma,  1 / sqrt(dt));
#else
	  
#pragma omp parallel for
	    for(int i = 0; i < n; ++i)
	    {
		float xf = 0, yf = 0, zf = 0;

		const int dpid = giddstart + i;
	
		for(int j = 0; j < nsrc; ++j)
		{
		    const int spid = gidsstart + j;
	    		
		    if (spid == dpid)
			continue;
		    
		    const float xdiff = xp[i] - srcxp[j];
		    const float ydiff = yp[i] - srcyp[j];
		    const float zdiff = zp[i] - srczp[j];
		    
		    const float _xr = xdiff - xdomainsize * floorf(0.5f + xdiff * xinvdomainsize);
		    const float _yr = ydiff - ydomainsize * floorf(0.5f + ydiff * yinvdomainsize);
		    const float _zr = zdiff - zdomainsize * floorf(0.5f + zdiff * zinvdomainsize);
		    
		    const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
		    float invrij = 1./sqrtf(rij2);

		    if (rij2 == 0)
			invrij = 100000;
	    
		    const float rij = rij2 * invrij;
		    const float wr = max((float)0, 1 - rij * invrc);
		    
		    const float xr = _xr * invrij;
		    const float yr = _yr * invrij;
		    const float zr = _zr * invrij;
		
		    const float rdotv = 
			xr * (xv[i] - srcxv[j]) +
			yr * (yv[i] - srcyv[j]) +
			zr * (zv[i] - srczv[j]);

		    const float mysaru = saru(min(spid, dpid), max(spid, dpid), saru_tag);
		    const float myrandnr = 3.464101615f * mysaru - 1.732050807f;
		 
		    const float strength = (aij - gamma * wr * rdotv + sigmaf * myrandnr) * wr;

		    xf += strength * xr;
		    yf += strength * yr;
		    zf += strength * zr;
		}

		xa[i] += xf;
		ya[i] += yf;
		za[i] += zf;
	    }

	    saru_tag++;
#endif
	}
    
    void acquire_global_id()
	{
	    myidstart = idglobal;
	    idglobal += n;
	}
    
    Particles (const int n, const float L):
	n(n), L(L), xp(n), yp(n), zp(n), xv(n), yv(n), zv(n), xa(n), ya(n), za(n), saru_tag(0)
	{
	    if (n > 0)
		acquire_global_id();
    
	    for(int i = 0; i < n; ++i)
	    {
		xp[i] = -L * 0.5 + drand48() * L;
		yp[i] = -L * 0.5 + drand48() * L;
		zp[i] = -L * 0.5 + drand48() * L; 
	    }
	}
    
    void diag(FILE * f, float t)
	{
	    float sv2 = 0, xm = 0, ym = 0, zm = 0;
	    
	    for(int i = 0; i < n; ++i)
	    {
		sv2 += xv[i] * xv[i] + yv[i] * yv[i] + zv[i] * zv[i];
		
		xm += xv[i];
		ym += yv[i];
		zm += zv[i];
	    }

	    float T = 0.5 * sv2 / (n * 3. / 2);

	    if (ftell(f) == 0)
		fprintf(f, "TIME\tkBT\tX-MOMENTUM\tY-MOMENTUM\tZ-MOMENTUM\n");

	    fprintf(f, "%s %+e\t%+e\t%+e\t%+e\t%+e\n", (f == stdout ? "DIAG:" : ""), t, T, xm, ym, zm);
	}
       
    void vmd_xyz(const char * path, bool append = false)
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
		fprintf(f, "1 %f %f %f\n", xp[i], yp[i], zp[i]);
    
	    fclose(f);

	    printf("vmd_xyz: wrote to <%s>\n", path);
	}

    // might be opened by OVITO and xmovie (xwindow-based utility)
    void lammps_dump(const char* path, size_t timestep)
    {
      bool append = timestep > 0;
      FILE * f = fopen(path, append ? "a" : "w");

      float boxLength = L;

      if (f == NULL)
      {
      printf("I could not open the file <%s>\n", path);
      printf("Aborting now.\n");
      abort();
      }

      // header
      fprintf(f, "ITEM: TIMESTEP\n%lu\n", timestep);
      fprintf(f, "ITEM: NUMBER OF ATOMS\n%d\n", n);
      fprintf(f, "ITEM: BOX BOUNDS pp pp pp\n%g %g\n%g %g\n%g %g\n",
          -boxLength/2.0, boxLength/2.0, -boxLength/2.0, boxLength/2.0, -boxLength/2.0, boxLength/2.0);

      fprintf(f, "ITEM: ATOMS id type xs ys zs\n");

      // positions <ID> <type> <x> <y> <z>
      // free particles have type 2, while rings 1
      size_t type = 1; //skip for now
      for (size_t i = 0; i < n; ++i) {
        fprintf(f, "%lu %lu %g %g %g\n", i, type, xp[i], yp[i], zp[i]);
      }

      fclose(f);
    }

    void _dpd_forces(const float kBT, const double dt);
    void equilibrate(const float kBT, const double tend, const double dt);
};

int Particles::idglobal;

struct Bouncer
{
    Particles frozen; //TODO consider moving to Sandwich

    Bouncer(const float L): frozen(0, L) {}
    virtual ~Bouncer() {}
    virtual void _mark(bool * const freeze, Particles p) = 0;
    virtual void bounce(Particles& dest, const float dt) = 0;
    virtual void compute_forces(const float kBT, const double dt, Particles& freeParticles) const = 0;
    
    virtual Particles carve(const Particles& p) //TODO consider moving to Sandwich the implementation
	{
	    bool * const freeze = new bool[p.n];
	    
	    _mark(freeze, p);
	    
	    Particles partition[2] = {Particles(0, p.L), Particles(0, p.L)};
	    
	    splitParticles(p, freeze, partition);

	    frozen = partition[0];
	    frozen.name = "frozen";
	    
	    for(int i = 0; i < frozen.n; ++i)
		frozen.xv[i] = frozen.yv[i] = frozen.zv[i] = 0;

	    delete [] freeze;
	    
	    return partition[1];
	}

    template<typename MaskType>
    static void splitParticles(const Particles& p, const MaskType& freezeMask,
            Particles* partition) // Particles[2] array
    {
        for(int i = 0; i < p.n; ++i)
        {
            const int slot = !freezeMask[i];

            partition[slot].xp.push_back(p.xp[i]);
            partition[slot].yp.push_back(p.yp[i]);
            partition[slot].zp.push_back(p.zp[i]);

            partition[slot].xv.push_back(p.xv[i]);
            partition[slot].yv.push_back(p.yv[i]);
            partition[slot].zv.push_back(p.zv[i]);

            partition[slot].xa.push_back(0);
            partition[slot].ya.push_back(0);
            partition[slot].za.push_back(0);

            partition[slot].n++;
        }

        partition[0].acquire_global_id();
        partition[1].acquire_global_id();
    }
};

#if 1

#else
struct Kirill
{
    bool isInside(const float x, const float y)
    {
        const float xc = 0, yc = 0;
        const float radius2 = 4;

        const float r2 =
        (x - xc) * (x - xc) +
        (y - yc) * (y - yc) ;

        return r2 < radius2;
    }

} kirill;
#endif
    
void Particles::_dpd_forces(const float kBT, const double dt)
{
    for(int i = 0; i < n; ++i)
    {
	xa[i] = xg;
	ya[i] = yg;
	za[i] = zg;
    }
    
    _dpd_forces_bipartite(kBT, dt,
			  &xp.front(), &yp.front(), &zp.front(),
			  &xv.front(), &yv.front(), &zv.front(), n, myidstart, myidstart);

    if (bouncer != nullptr) {
        bouncer->compute_forces(kBT, dt, *this);
    }
}

void Particles::equilibrate(const float kBT, const double tend, const double dt)
{
    auto _up  = [&](vector<float>& x, vector<float>& v, float f)
	{
	    for(int i = 0; i < n; ++i)
		x[i] += f * v[i];
	};

    auto _up_enforce = [&](vector<float>& x, vector<float>& v, float f)
	{
	    for(int i = 0; i < n; ++i)
	    {
		x[i] += f * v[i];
		x[i] -= L * floor(x[i] / L + 0.5);
	    }
	};
    
    _dpd_forces(kBT, dt);

    //vmd_xyz("ic.xyz", false);
    lammps_dump("evolution.dump", 0);

    FILE * fdiag = fopen("diag-equilibrate.txt", "w");

    const size_t nt = (int)(tend / dt);

    for(int it = 0; it < nt; ++it)
    {
	if (it % steps_per_dump == 0)
	{
	    printf("step %d\n", it);
	    float t = it * dt;
	    diag(fdiag, t);
	    diag(stdout, t);
	}
		
	_up(xv, xa, dt * 0.5);
	_up(yv, ya, dt * 0.5);
	_up(zv, za, dt * 0.5);

	_up_enforce(xp, xv, dt);
	_up_enforce(yp, yv, dt);
	_up_enforce(zp, zv, dt);

	if (bouncer != nullptr)
	    bouncer->bounce(*this, dt);
		
	_dpd_forces(kBT, dt);

	_up(xv, xa, dt * 0.5);
	_up(yv, ya, dt * 0.5);
	_up(zv, za, dt * 0.5);
	
	if (it % steps_per_dump == 0)
	    lammps_dump("evolution.dump", it);
	    //vmd_xyz((name == "" ? "evolution.xyz" : (name + "-evolution.xyz")).c_str(), it, it > 0);
    }

    fclose(fdiag);
}

struct SandwichBouncer: Bouncer
{
    float half_width = 1;
    
    SandwichBouncer( const float L):
	Bouncer(L) { }

    bool _handle_collision(float& x, float& y, float& z,
			   float& u, float& v, float& w,
			   float& dt)
	{
	    if (fabs(z) - half_width <= 0)
		return false;
	    
	    const float xold = x - dt * u;
	    const float yold = y - dt * v;
	    const float zold = z - dt * w;

	    assert(fabs(zold) - half_width <= 0);
	    assert(fabs(w) > 0);

	    const float s = 1 - 2 * signbit(w);
	    const float t = (s * half_width - zold) / w;

	    assert(t >= 0);
	    assert(t <= dt);
		    
	    const float lambda = 2 * t - dt;
		    
	    x = xold + lambda * u;
	    y = yold + lambda * v;
	    z = zold + lambda * w;
	    
	    assert(fabs(zold + lambda * w) - half_width <= 0);

	    u = -u;
	    v = -v;
	    w = -w;
	    dt = dt - t;

	    return true;
	}
    
    void bounce(Particles& dest, const float _dt)
	{
	    for(int i = 0; i < dest.n; ++i)
	    {
		float dt = _dt;
		float x = dest.xp[i];
		float y = dest.yp[i];
		float z = dest.zp[i];
		float u = dest.xv[i];
		float v = dest.yv[i];
		float w = dest.zv[i];
		
		if ( _handle_collision(x, y, z, u, v, w, dt) )
		{
		    dest.xp[i] = x;
		    dest.yp[i] = y;
		    dest.zp[i] = z;
		    dest.xv[i] = u;
		    dest.yv[i] = v;
		    dest.zv[i] = w;
		}
	    }
	}

    void _mark(bool * const freeze, Particles p)
	{
	    for(int i = 0; i < p.n; ++i)
		freeze[i] = !(fabs(p.zp[i]) <= half_width);
	}

    void compute_forces(const float kBT, const double dt, Particles& freeParticles) const
    {
        freeParticles._dpd_forces_bipartite(kBT, dt,
                      &frozen.xp.front(), &frozen.yp.front(), &frozen.zp.front(),
                      &frozen.xv.front(), &frozen.yv.front(), &frozen.zv.front(),
                      frozen.n, frozen.myidstart, frozen.myidstart);
    }
};

/*************************** Obstacle *************************/

// TODO compute index and than sort atoms in frozen layer according to it
// for now use this index for filtering only
class AngleIndex
{
    std::vector<int> index;
    float sectorSz;
    size_t nSectors;

    // give angle between [0, 2PI]
    float getAngle(const float x, const float y) const
    {
        return atan2(y, x) + M_PI;
    }

public:

    AngleIndex(float rc, float y0)
    : sectorSz(0.0f), nSectors(0.0f)
    {
        assert(y0 < 0);
        sectorSz = 2.0f * asin(rc/sqrt(-y0));
        nSectors = static_cast<size_t>(2.0f * M_PI) / sectorSz + 1;
    }

    void run(const std::vector<float>& xp, const std::vector<float>& yp)
    {
        index.resize(xp.size());
        for (size_t i = 0; i < index.size(); ++i)
            index[i] = computeIndex(xp[i], yp[i]);
    }

    bool isClose(int srcAngInd, size_t frParticleInd) const
    {
        int destAngInd = getIndex(frParticleInd);
        return destAngInd == srcAngInd
                || (destAngInd + 1)%nSectors == srcAngInd
                || (destAngInd + nSectors - 1)%nSectors == srcAngInd;
    }

    int computeIndex(const float x, const float y) const
    {
        float angle = getAngle(x, y);
        assert(angle >= 0.0f && angle <= 2.0f * M_PI);
        return trunc(angle/sectorSz);
    }

    int getIndex(size_t i) const { return index[i]; }
};

struct TomatoSandwich: SandwichBouncer
{
    float xc = 0, yc = 0, zc = 0;
    float radius2 = 1;

    const float rc = 1.0;

    RowFunnelObstacle funnelLS;
    Particles frozenLayer[3]; // three layers every one is rc width
    AngleIndex angleIndex[3];

    TomatoSandwich(const float boxLength)
    : SandwichBouncer(boxLength), funnelLS(7.0f, 10.0f, 10.0f, 64, 64),
<<<<<<< HEAD
      frozenLayer{Particles(0, boxLength), Particles(0, boxLength), Particles(0, boxLength)}
=======
      frozenLayer{Particles(0, boxLength), Particles(0, boxLength), Particles(0, boxLength)},
      angleIndex{AngleIndex(rc, funnelLS.getY0()), AngleIndex(rc, funnelLS.getY0()), AngleIndex(rc, funnelLS.getY0())}
>>>>>>> 6c8ee08b603fdd194e1a571aa24c01b178f1e1b1
    {}

    Particles carve(const Particles& particles)
    {
        Particles remaining0 = carveAllLayers(particles);
        return SandwichBouncer::carve(remaining0);
    }

    void _mark(bool * const freeze, Particles p)
	{
	    SandwichBouncer::_mark(freeze, p);

	    for(int i = 0; i < p.n; ++i)
	    {
		const float x = p.xp[i] - xc;
		const float y = p.yp[i] - yc;
#if 1
		freeze[i] |= funnelLS.isInside(x, y);
#else
		const float r2 = x * x + y * y;

		freeze[i] |= r2 < radius2;
#endif
	    }
	}
 
    float _compute_collision_time(const float _x0, const float _y0,
			  const float u, const float v, 
			  const float xc, const float yc, const float r2)
	{
	    const float x0 = _x0 - xc;
	    const float y0 = _y0 - yc;
	    	    
	    const float c = x0 * x0 + y0 * y0 - r2;
	    const float b = 2 * (x0 * u + y0 * v);
	    const float a = u * u + v * v;
	    const float d = sqrt(b * b - 4 * a * c);

	    return (-b - d) / (2 * a);
	}

    bool _handle_collision(float& x, float& y, float& z,
			   float& u, float& v, float& w,
			   float& dt)
	{
#if 1
	    if (!funnelLS.isInside(x, y))
		return false;

	    const float xold = x - dt * u;
	    const float yold = y - dt * v;
	    const float zold = z - dt * w;

	    float t = 0;
	    
	    for(int i = 1; i < 30; ++i)
	    {
		const float tcandidate = t + dt / (1 << i);
		const float xcandidate = xold + tcandidate * u;
		const float ycandidate = yold + tcandidate * v;
		
		 if (!funnelLS.isInside(xcandidate, ycandidate))
		     t = tcandidate;
	    }

	    const float lambda = 2 * t - dt;
		    
	    x = xold + lambda * u;
	    y = yold + lambda * v;
	    z = zold + lambda * w;
	   
	    u  = -u;
	    v  = -v;
	    w  = -w;
	    dt = dt - t;

	    return true;
	    
#else
	    const float r2 =
		(x - xc) * (x - xc) +
		(y - yc) * (y - yc) ;
		
	    if (r2 >= radius2)
		return false;
	    
	    assert(dt > 0);
			
	    const float xold = x - dt * u;
	    const float yold = y - dt * v;
	    const float zold = z - dt * w;

	    const float t = _compute_collision_time(xold, yold, u, v, xc, yc, radius2);
	    assert(t >= 0);
	    assert(t <= dt);
		    
	    const float lambda = 2 * t - dt;
		    
	    x = xold + lambda * u;
	    y = yold + lambda * v;
	    z = zold + lambda * w;
	    
	    u  = -u;
	    v  = -v;
	    w  = -w;
	    dt = dt - t;

	    return true;
#endif
	}
    
    void bounce(Particles& dest, const float _dt)
	{
#pragma omp parallel for
	    for(int i = 0; i < dest.n; ++i)
	    {
		float x = dest.xp[i];
		float y = dest.yp[i];
		float z = dest.zp[i];
		float u = dest.xv[i];
		float v = dest.yv[i];
		float w = dest.zv[i];
		float dt = _dt;
		    
		bool wascolliding = false, collision;
		int passes = 0;
		do
		{
		    collision = false;
		    collision |= SandwichBouncer::_handle_collision(x, y, z, u, v, w, dt);
		    collision |= _handle_collision(x, y, z, u, v, w, dt);
		    
		    wascolliding |= collision;
		    passes++;

		    if (passes >= 10)
			break;
		}
		while(collision);

		//if (passes >= 2)
		//    printf("solved a complex collision\n");
		
		if (wascolliding)
		{
		    dest.xp[i] = x;
		    dest.yp[i] = y;
		    dest.zp[i] = z;
		    dest.xv[i] = u;
		    dest.yv[i] = v;
		    dest.zv[i] = w;
		}
	    }
	}

    void compute_forces(const float kBT, const double dt, Particles& freeParticles) const
    {
        SandwichBouncer::compute_forces(kBT, dt, freeParticles);
        computePairDPD(kBT, dt, freeParticles);
    }

private:
    //dpd forces computations related methods
    Particles carveLayer(const Particles& input, size_t indLayer, float bottom, float top);
    Particles carveAllLayers(const Particles& p);
    void computeDPDPairForLayer(const float kBT, const double dt, int i, const float* coord,
                const float* vel, float* df, const float offsetX, int seed1) const;
    void computePairDPD(const float kBT, const double dt, Particles& freeParticles) const;
    void _dpd_forces_1particle(size_t layerIndex, const float kBT, const double dt,
            int i, const float* offset, const float* coord, const float* vel, float* df,
            const int giddstart) const;
};

Particles TomatoSandwich::carveLayer(const Particles& input, size_t indLayer, float bottom, float top)
{
    std::vector<bool> maskSkip(input.n, false);
    for (int i = 0; i < input.n; ++i)
    {
        int bbIndex = funnelLS.getBoundingBoxIndex(input.xp[i], input.yp[i]);
        if (bbIndex == 0 && input.zp[i] > bottom && input.zp[i] < top)
            maskSkip[i] = true;
    }
    Particles splitToSkip[2] = {Particles(0, input.L), Particles(0, input.L)};
    Bouncer::splitParticles(input, maskSkip, splitToSkip);

    frozenLayer[indLayer] = splitToSkip[0];
    angleIndex[indLayer].run(frozenLayer[indLayer].xp, frozenLayer[indLayer].yp);

    for(int i = 0; i < frozenLayer[indLayer].n; ++i)
        frozenLayer[indLayer].xv[i] = frozenLayer[indLayer].yv[i] = frozenLayer[indLayer].zv[i] = 0.0f;

    return splitToSkip[1];
}

Particles TomatoSandwich::carveAllLayers(const Particles& p)
{
    // in carving we get all particles inside the obstacle so they are not in consideration any more
    // But we don't need all these particles for this code, we cleaned them all except layer between [-rc/2, rc/2]
    std::vector<bool> maskFrozen(p.n);
    for (int i = 0; i < p.n; ++i)
    {
        // make holes in frozen planes for now
        maskFrozen[i] = funnelLS.isInside(p.xp[i], p.yp[i]);
    }

    Particles splittedParticles[2] = {Particles(0, p.L), Particles(0, p.L)};
    Bouncer::splitParticles(p, maskFrozen, splittedParticles);

    Particles pp = carveLayer(splittedParticles[0], 0, -3.0f * rc/2.0, -rc/2.0);
    Particles ppp = carveLayer(pp, 1, -rc/2.0, rc/2.0);
    carveLayer(ppp, 2, rc/2.0, 3.0 * rc/2.0);

    return splittedParticles[1];
}

void TomatoSandwich::computeDPDPairForLayer(const float kBT, const double dt, int i, const float* coord,
        const float* vel, float* df, const float offsetX, int seed1) const
{
    float w = 3.0f * rc; // width of the frozen layers

    float zh = coord[2] > 0.0f ? 0.5f : -0.5f;
    float zOffset = -trunc(coord[2] / w + zh) * w;
    // shift atom to the range [-w/2, w/2]
    float coordShifted[] = {coord[0], coord[1], coord[2] + zOffset};
    assert(coordShifted[2] >= -w/2.0f && coordShifted[2] <= w/2.0f);

    int coreLayerIndex = trunc((coordShifted[2] + w/2)/rc);
    if (coreLayerIndex == 3) // iff coordShifted[2] == 1.5, temporary workaround
        coreLayerIndex = 2;

    assert(coreLayerIndex >= 0 && coreLayerIndex < 3);

    float layersOffsetZ[] = {0.0f, 0.0f, 0.0f};
    if (coreLayerIndex == 0)
        layersOffsetZ[2] = -w;
    else if (coreLayerIndex == 2)
        layersOffsetZ[0] = w;

    for (int lInd = 0; lInd < 3; ++lInd) {
        float layerOffset[] = {offsetX, 0.0f, layersOffsetZ[lInd]};
        _dpd_forces_1particle(lInd, kBT, dt, i, layerOffset, coordShifted, vel, df, seed1);
    }
}

void TomatoSandwich::computePairDPD(const float kBT, const double dt, Particles& freeParticles) const
{
    int seed1 = freeParticles.myidstart;
    float xskin, yskin;
    funnelLS.getSkinWidth(xskin, yskin);

    for (int i = 0; i < freeParticles.n; ++i) {

        if (funnelLS.insideBoundingBox(freeParticles.xp[i], freeParticles.yp[i])) {

            // not sure it gives performance improvements since bounding box usually is small enough
            //if (!funnelLS.isBetweenLayers(freeParticles.xp[i], freeParticles.yp[i], 0.0f, rc + 1e-2))
            //    continue;

            //shifted position so coord.z == origin(layer).z which is 0
            float coord[] = {freeParticles.xp[i], freeParticles.yp[i], freeParticles.zp[i]};
            float vel[] = {freeParticles.xv[i], freeParticles.yv[i], freeParticles.zv[i]};
            float df[] = {0.0, 0.0, 0.0};

            // shift atom to the central box in the row
            float offsetCoordX = funnelLS.getOffset(coord[0]);
            coord[0] += offsetCoordX;

            computeDPDPairForLayer(kBT, dt, i, coord, vel, df, 0.0f, seed1);

            float frozenOffset = funnelLS.getCoreDomainLength(0);

            if ((fabs(coord[0]  - funnelLS.getCoreDomainLength(0)/2.0f) + xskin) < rc)
            {
                float signOfX = 1.0f - 2.0f * signbit(coord[0]);
                computeDPDPairForLayer(kBT, dt, i, coord, vel, df, signOfX*frozenOffset, seed1);
            }

            freeParticles.xa[i] += df[0];
            freeParticles.ya[i] += df[1];
            freeParticles.za[i] += df[2];
        }
    }
    ++frozenLayer[0].saru_tag;
    ++frozenLayer[1].saru_tag;
    ++frozenLayer[2].saru_tag;
}

void TomatoSandwich::_dpd_forces_1particle(size_t layerIndex, const float kBT, const double dt,
        int i, const float* offset,
        const float* coord, const float* vel, float* df, // float3 arrays
        const int giddstart) const
{
    const Particles& frLayer = frozenLayer[layerIndex];

    const float xdomainsize = frLayer.L;
    const float ydomainsize = frLayer.L;
    const float zdomainsize = frLayer.L;

    const float xinvdomainsize = 1.0f / xdomainsize;
    const float yinvdomainsize = 1.0f / xdomainsize;
    const float zinvdomainsize = 1.0f / zdomainsize;

    const float invrc = 1.0f;
    const float gamma = 45.0f;
    const float sigma = sqrt(2.0f * gamma * kBT);
    const float sigmaf = sigma / sqrt(dt);
    const float aij = 2.5f;

    float xf = 0, yf = 0, zf = 0;

    const int dpid = giddstart + i;


    int srcAngIndex = angleIndex[layerIndex].computeIndex(coord[0], coord[1]);
    for(int j = 0; j < frLayer.n; ++j)
    {
        if (!angleIndex[layerIndex].isClose(srcAngIndex, j)) {
            continue;
        }

        const int spid = frLayer.myidstart + j;

        if (spid == dpid)
        continue;

        const float xdiff = coord[0] - (frLayer.xp[j] + offset[0]);
        const float ydiff = coord[1] - (frLayer.yp[j] + offset[1]);
        const float zdiff = coord[2] - (frLayer.zp[j] + offset[2]);

        const float _xr = xdiff - xdomainsize * floorf(0.5f + xdiff * xinvdomainsize);
        const float _yr = ydiff - ydomainsize * floorf(0.5f + ydiff * yinvdomainsize);
        const float _zr = zdiff - zdomainsize * floorf(0.5f + zdiff * zinvdomainsize);

        const float rij2 = _xr * _xr + _yr * _yr + _zr * _zr;
        float invrij = 1./sqrtf(rij2);

        if (rij2 == 0)
            invrij = 100000;

        const float rij = rij2 * invrij;
        const float wr = max((float)0, 1 - rij * invrc);

        const float xr = _xr * invrij;
        const float yr = _yr * invrij;
        const float zr = _zr * invrij;

        assert(frLayer.xv[j] == 0 && frLayer.yv[j] == 0 && frLayer.zv[j] == 0); //TODO remove v
        const float rdotv =
        xr * (vel[0] - frLayer.xv[j]) +
        yr * (vel[1] - frLayer.yv[j]) +
        zr * (vel[2] - frLayer.zv[j]);

        const float mysaru = saru(min(spid, dpid), max(spid, dpid), frLayer.saru_tag);
        const float myrandnr = 3.464101615f * mysaru - 1.732050807f;

        const float strength = (aij - gamma * wr * rdotv + sigmaf * myrandnr) * wr;

        xf += strength * xr;
        yf += strength * yr;
        zf += strength * zr;
    }

    df[0] += xf;
    df[1] += yf;
    df[2] += zf;
}


int main()
{
<<<<<<< HEAD
    const float L = 20;
=======
    const float L = 10;
>>>>>>> 6c8ee08b603fdd194e1a571aa24c01b178f1e1b1
    const int Nm = 3;
    const int n = L * L * L * Nm;
    const float dt = 0.02;

    Particles particles(n, L);
    particles.equilibrate(.1, 200*dt, dt);

    const float sandwich_half_width = L / 2 - 1.7;
#if 1
    TomatoSandwich bouncer(L);
    bouncer.radius2 = 4;
    bouncer.half_width = sandwich_half_width;
#else
    SandwichBouncer bouncer(L);
    bouncer.half_width = sandwich_half_width;
#endif

    Particles remaining1 = bouncer.carve(particles);

    // check angle indexes
    Particles ppp[] = {Particles(0, L), Particles(0, L), Particles(0, L), Particles(0, L),
            Particles(0, L), Particles(0, L)};

    for (int k = 0; k < 3; ++k)
        for (int i = 0; i < bouncer.frozenLayer[k].n; ++i) {

            int slice = bouncer.angleIndex[k].getIndex(i);

            assert(slice < 6);
            ppp[slice].xp.push_back(bouncer.frozenLayer[k].xp[i]);
            ppp[slice].yp.push_back(bouncer.frozenLayer[k].yp[i]);
            ppp[slice].zp.push_back(bouncer.frozenLayer[k].zp[i]);
            ppp[slice].n++;
        }

    for (int i = 0; i < 6; ++i)
        ppp[i].lammps_dump("icy3.dump", i);


    bouncer.frozenLayer[0].lammps_dump("icy.dump", 0);
    bouncer.frozenLayer[1].lammps_dump("icy.dump", 1);
    bouncer.frozenLayer[2].lammps_dump("icy.dump", 2);

    bouncer.frozen.lammps_dump("icy2.dump", 0);
    remaining1.name = "fluid";
    
    remaining1.bouncer = &bouncer;
    remaining1.yg = 0.02;
    remaining1.steps_per_dump = 5;
<<<<<<< HEAD
    remaining1.equilibrate(.1, 2000*dt, dt);
=======
    remaining1.equilibrate(.1, 1000*dt, dt);
>>>>>>> 6c8ee08b603fdd194e1a571aa24c01b178f1e1b1
    printf("particles have been equilibrated");
}

    
