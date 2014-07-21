/*
 *  Simulation.h
 *  hpchw
 *
 *  Created by Dmitry Alexeev on 17.10.13.
 *  Copyright 2013 ETH Zurich. All rights reserved.
 *
 */

#pragma once

#include <list>
#include <iostream>
#include <fstream>
#include <sys/stat.h>
#include <errno.h>
#include <string>
#include <assert.h>

#include "Particles.h"
#include "Profiler.h"
#include "Potential.h"
#include "timer.h"
#include "Misc.h"
#ifdef MD_USE_CELLLIST
#include "CellList.h"
#endif

#ifdef __MD_USE_CUDA__
#include "Gpukernels.h"
#else
#include "Cpukernels.h"
#endif

using namespace std;

template <int N>
class Saver;

//**********************************************************************************************************************
// Let no one ignorant of geometry enter here
//**********************************************************************************************************************

// http://www.codeproject.com/Articles/75423/Loop-Unrolling-over-Template-Arguments
template<int Begin, int End, int Step = 1>
struct Unroller {
    template<typename Action>
    static void step(Action& action) {
        action(Begin);
        Unroller<Begin+Step, End, Step>::step(action);
    }
};

template<int End, int Step>
struct Unroller<End, End, Step> {
    template<typename Action>
    static void step(Action& action) {
    }
};
// Mind the gap


template<int ibeg, int iend, int jbeg, int jend>
struct Unroller2 {
    static void step(Profiler& p) {
#ifdef MD_USE_CELLLIST
        Forces::_Cells<ibeg, jbeg> force;
#else
        Forces::_N2<ibeg, jbeg> force;
#endif
        p.start("Forces " + to_string(ibeg) + " <-> " + to_string(jbeg));
        force();
        p.stop();
        Unroller2<ibeg, iend, jbeg+1, jend>::step(p);
    }
};

template<int ibeg, int iend, int jend>
struct Unroller2<ibeg, iend, jend, jend> {
    static void step(Profiler& p) {
        Unroller2<ibeg+1, iend, ibeg+1, jend>::step(p);
    }
};

template<int iend, int jend>
struct Unroller2<iend, iend, jend, jend> {
    static void step(Profiler& p) {
    }
};

//**********************************************************************************************************************
// Simulation
//**********************************************************************************************************************

Particles**  Forces::Arguments::part;
vector<real> Forces::Arguments::rCuts;
real Forces::Arguments::xlo;
real Forces::Arguments::ylo;
real Forces::Arguments::zlo;
real Forces::Arguments::xhi;
real Forces::Arguments::yhi;
real Forces::Arguments::zhi;
#ifdef MD_USE_CELLLIST
Cells<Particles>** Forces::Arguments::cells;
#endif


struct LJwallz
{
    real z;
    real v;
    real a;
    const real mass = 1;
    
    LJwallz(real z, real v):z(z), v(v), a(0) {};
    
    void VVpre(real dt)
    {
        v += a * dt*0.5;
        z += v * dt;
    }
    
    void VVpost(real dt)
    {
        v += a * dt*0.5;
    }
    
    void force(Particles* part)
    {
        static const real rCut  = 2;
        static const real sigma = 0.5;
        static const real eps   = 0.001;
        
        a = 0;
        for (int i = 0; i<part->n; i++)
        {
            if (fabs(part->z(i) - z) < rCut)
            {
                real r = fabs(part->z(i) - z);
                real s_r = sigma / r;
                real s_r2 = s_r*s_r;
                real f5 = s_r*s_r2*s_r2; // 5
                
                real f11 = s_r*f5*f5;    // 11
                
                real f = eps * 1/(sigma*sigma) * (3*f5 - f11) * (part->z(i) - z);
                part->az(i) -= f / part->m[i];
                a += f / mass;
                a -= 0.01*v;
                
                if (f > 100) info("wall: %.5f,   part %.5f,   r: %.4f   f5: %.4f  f11: %.4f\n", z, part->z(i), r, 3*f5, f11);
            }
        }
        
        //info("%.5f   %.5f   %.5f\n", z, v, a);
    }
    
    void fix()
    {
        a = 0;
        v = 0;
    }
    
    void addF(real f)
    {
        a += f/mass;
    }
    
};



template<int N>
class Simulation
{
private:
	int  step;
	real xlo, ylo, zlo, xhi, yhi, zhi;
	real dt;
	
	Particles* part[N];
	list<Saver<N>*>	savers;
    
#ifdef MD_USE_CELLLIST
	Cells<Particles>* cells[N];
#endif
		
	void velocityVerlet();
    
    template<int type>
    void integrate();
	
public:
	Profiler profiler;
    
    vector<LJwallz*> walls;

	Simulation (real);
	void setLattice(Particles* p, real lx, real ly, real lz, int n);
    void setIC(vector<int>, vector<real>);
    void loadRestart(string fname, vector<real>);
	
	real Ktot(int = -1);
	void linMomentum (real& px, real& py, real& pz, int = -1);
	void angMomentum (real& px, real& py, real& pz, int = -1);
	void centerOfMass(real& mx, real& my, real& mz, int = -1);
	
	inline int getIter() { return step; }
	inline Particles** getParticles() { return part; }
	
	void getPositions(int&, real*, real*);
	void registerSaver(Saver<N>*, int);
	void runOneStep();
};


//**********************************************************************************************************************
// Saver
//**********************************************************************************************************************

template<int N>
class Saver
{
public:
    static string folder;

protected:
	int period;
	ofstream* file;
	Simulation<N>* my;
    
    bool opened;
	
public:
	Saver (ostream* cOut) : file((ofstream*)cOut) { opened = false; }
	Saver (string fname)
	{
        if (fname == "screen")
        {
            file = (ofstream*)&cout;
            opened = false;
            return;
        }
        
		file = new ofstream((this->folder+fname).c_str());
        opened = true;
	}
	Saver (){};
    ~Saver () { if (!opened) file->close(); }
	
	inline  void setEnsemble(Simulation<N>* e);
	inline  void setPeriod(int);
	inline  int  getPeriod();
	
	inline static bool makedir(string name)
	{
		folder = name;
		if (mkdir(folder.c_str(), S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH) != 0 && errno != EEXIST) return false;
		return true;
	}
	
	virtual void exec() = 0;
};

template<int N>
inline void Saver<N>::setPeriod(int p)
{
	period = p;
}

template<int N>
inline int Saver<N>::getPeriod()
{
	return period;
}

template<int N>
inline void Saver<N>::setEnsemble(Simulation<N>* e)
{
	my = e;
}

//**********************************************************************************************************************
// Simulation implementation
//**********************************************************************************************************************

void stupidLoad(Particles** part, string fname)
{
    // "HONCBFPSKYI"
    static int mapping[256];
    mapping['H'] = 0;
    mapping['O'] = 1;
    mapping['N'] = 2;
    mapping['C'] = 3;
    mapping['B'] = 4;
    
    ifstream in(fname);
    
    assert(in.good());
    char dummy;
    
    int i=0;
    while (in.good())
    {
        in >> dummy;
        in >> part[mapping[dummy]]->x(i) >> part[mapping[dummy]]->y(i) >> part[mapping[dummy]]->z(i);
        i++;
    }
    in.close();
    info("Read %d entries\n", i);
}

template<typename T>
T mymax(T* arr, int n)
{
    T res = arr[0];
    for (int i=1; i<n; i++)
        if (res < arr[i]) res = arr[i];
    return res;
}

template<typename T>
T mymin(T* arr, int n)
{
    T res = arr[0];
    for (int i=1; i<n; i++)
        if (res > arr[i]) res = arr[i];
    return res;
}

template<int N>
Simulation<N>::Simulation(real deltat)
{
    // Various initializations
	dt		  = deltat;
	
	step = 0;
	xlo   = configParser->getf("Basic", "xlo");
    xhi   = configParser->getf("Basic", "xhi");
    ylo   = configParser->getf("Basic", "ylo");
    yhi   = configParser->getf("Basic", "yhi");
    zlo   = configParser->getf("Basic", "zlo");
    zhi   = configParser->getf("Basic", "zhi");
       
    Forces::Arguments::part = part;
    Forces::Arguments::xlo = xlo;
    Forces::Arguments::xhi = xhi;
    Forces::Arguments::ylo = ylo;
    Forces::Arguments::yhi = yhi;
    Forces::Arguments::zlo = zlo;
    Forces::Arguments::zhi = zhi;
#ifdef MD_USE_CELLLIST
    Forces::Arguments::cells = cells;
#endif
}

template<int N>
void Simulation<N>::setIC(vector<int> num, vector<real> rCuts)
{
    for (int type=0; type<N; type++)
    {
        part[type]	  = new Particles;
        part[type]->n = num[type];
        _allocate(part[type]);
    }

    // Initial conditions for positions and velocities
	mt19937 gen;
    uniform_real_distribution<real> ux(xlo, xhi);
    uniform_real_distribution<real> uy(ylo, yhi);
    uniform_real_distribution<real> uz(zlo, zhi);
    
    uniform_real_distribution<real> uphi(0, 2*M_PI);
    uniform_real_distribution<real> utheta(0, M_PI*0.75);
    
    
    if (N>1) setLattice(part[1], 8, 8, 8, part[1]->n);
    //stupidLoad(part, "/Users/alexeedm/Documents/projects/CTC/CTC/makefiles/dump.txt");
    
    double xl = 0;//mymin(part[1]->x, part[1]->n);
    double xh = 0;//mymax(part[1]->x, part[1]->n);
    
    double yl = 0;//mymin(part[1]->y, part[1]->n);
    double yh = 0;//mymax(part[1]->y, part[1]->n);
    
    double zl = 0;//mymin(part[1]->z, part[1]->n);
    double zh = 0;//mymax(part[1]->z, part[1]->n);
    
    
    for (int i=0; i<num[0]; i++)
    {
        do
        {
            part[0]->x(i) = ux(gen);
            part[0]->y(i) = uy(gen);
            part[0]->z(i) = uz(gen);
        } while (xl < part[0]->x(i) && part[0]->x(i) < xh &&
                 yl < part[0]->y(i) && part[0]->y(i) < yh &&
                 zl < part[0]->z(i) && part[0]->z(i) < zh);
    }
    
    //setLattice(part[0]->x, part[0]->y, part[0]->z, L, L, L, part[0]->n);
    // Initialize cell list if we need it
#ifdef MD_USE_CELLLIST
    real lower[3]  = {xlo, ylo, zlo};
    real higher[3] = {xhi, yhi, zhi};
    
    for (int type=0; type<N; type++)
        if (part[type]->n > 0) cells[type] = new Cells<Particles>(part[type], part[type]->n, rCuts[type], lower, higher);
        else cells[type] = NULL;

#endif
    
    for (int type=0; type<N; type++)
    {
        _fill(part[type]->vdata, 3*part[type]->n, (real)0.0);
        _fill(part[type]->adata, 3*part[type]->n, (real)0.0);
        
        _fill(part[type]->m, part[type]->n, (real)1.0);
        _fill(part[type]->label, part[type]->n, 0);
    }
    
    Forces::Arguments::rCuts = rCuts;
}

template<int N>
void Simulation<N>::loadRestart(string fname, vector<real> rCuts)
{
    real lower[3]  = {xlo, ylo, zlo};
    real higher[3] = {xhi, yhi, zhi};
    
    ifstream in(fname.c_str(), ios::in | ios::binary);
    
    int n;
    in.read((char*)&n, sizeof(int));
    
    if (n != N) die("Compiled for %d types, asked %d\n", N, n);
    
    for (int i = 0; i<N; i++)
    {
        in.read((char*)&n, sizeof(int));
        
        part[i]	   = new Particles;
        part[i]->n = n;
        _allocate(part[i]);
        
        in.read((char*)part[i]->xdata,  3*n*sizeof(real));
        in.read((char*)part[i]->vdata,  3*n*sizeof(real));
        
        in.read((char*)part[i]->m,  n*sizeof(real));
        in.read((char*)part[i]->label, n*sizeof(int));
        
        _fill(part[i]->adata, 3*part[i]->n, (real)0.0);
        _fill(part[i]->vdata, 3*part[i]->n, (real)0.0); // !!!

#ifdef MD_USE_CELLLIST
        if (part[i]->n > 0) cells[i] = new Cells<Particles>(part[i], part[i]->n, rCuts[i], lower, higher);
        else cells[i] = NULL;
#endif
    }
    
    in.close();
    
    Forces::Arguments::rCuts = rCuts;
    
    real zmax = -1000;
    real zmin =  1000;
    for (int i = 0; i<part[1]->n; i++)
    {
        zmax = max(zmax, part[1]->z(i));
        zmin = min(zmin, part[1]->z(i));
    }
    
    // !!!
    walls.push_back(new LJwallz(3.45142, 0.000));
    walls.push_back(new LJwallz(-2.77443, -0.000));
}

template<int N>
void Simulation<N>::setLattice(Particles* p, real lx, real ly, real lz, int n)
{
	real h = pow(lx*ly*lz/n, 1.0/3);
    int nx = ceil(lx/h);
    int ny = ceil(ly/h);
    //int nz = ceil((real)n/(nx*ny));
	
	int i=1;
	int j=1;
	int k=1;
	
	for (int tot=0; tot<n; tot++)
	{
		p->x(tot) = i*h - lx/2;
		p->y(tot) = j*h - ly/2;
		p->z(tot) = k*h - lz/2;
		
		i++;
		if (i > nx)
		{
			j++;
			i = 1;
		}
		
		if (j > ny)
		{
			k++;
			j = 1;
		}
	}
}

template<int N>
real Simulation<N>::Ktot(int type)
{
    real res = 0;
    
    if (type < 0)
    {
        for (int t=0; t<N; t++)
            res += _kineticNrg(part[t]);
    }
    else
    {
        res = _kineticNrg(part[type]);
    }
	return res;
}

template<int N>
void Simulation<N>::linMomentum(real& px, real& py, real& pz, int type)
{
    real _px = 0, _py = 0, _pz = 0;
    px = py = pz = 0;
    
	if (type < 0)
    {
        for (int t=0; t<N; t++)
        {
            _linMomentum(part[t], _px, _py, _pz);
            px += _px;
            py += _py;
            pz += _pz;
        }
    }
    else
    {
        _linMomentum(part[type], px, py, pz);
    }
}

template<int N>
void Simulation<N>::angMomentum(real& Lx, real& Ly, real& Lz, int type)
{
    real _Lx = 0, _Ly = 0, _Lz = 0;
    Lx = Ly = Lz = 0;
    
	if (type < 0)
    {
        for (int t=0; t<N; t++)
        {
            _angMomentum(part[t], _Lx, _Ly, _Lz);
            Lx += _Lx;
            Ly += _Ly;
            Lz += _Lz;
        }
    }
    else
    {
        _angMomentum(part[type], Lx, Ly, Lz);
    }
}

template<int N>
void Simulation<N>::centerOfMass(real& mx, real& my, real& mz, int type)
{
    real _mx = 0, _my = 0, _mz = 0;
    mx = my = mz = 0;
    
	if (type < 0)
    {
        for (int t=0; t<N; t++)
        {
            _centerOfMass(part[t], _mx, _my, _mz);
            mx += _mx;
            my += _my;
            mz += _mz;
        }
    }
    else
    {
        _centerOfMass(part[type], mx, my, mz);
    }
}

template<int N>
void Simulation<N>::velocityVerlet()
{
    auto prep = [&](int type)
    {
        _axpy(part[type]->vdata, part[type]->adata, 3*part[type]->n, dt*0.5);
        _axpy(part[type]->xdata, part[type]->vdata, 3*part[type]->n, dt);
        
        _normalize(part[type]->xdata, part[type]->n, xlo, xhi, 0);
        _normalize(part[type]->xdata, part[type]->n, ylo, yhi, 1);
        _normalize(part[type]->xdata, part[type]->n, zlo, zhi, 2);
        
        _fill(part[type]->adata, 3*part[type]->n, (real)0.0);
    };
    
    profiler.start("Integration");
    for (auto w : walls)
    {
        w->VVpre(dt);
    }
    Unroller<0, N>::step(prep);
    profiler.stop();
  
#ifdef MD_USE_CELLLIST
    auto docells = [&](int type)
    {
        if (cells[type] != NULL) cells[type]->migrate();
    };
    
    profiler.start("CellList");
    Unroller<0, N>::step(docells);
    profiler.stop();
#endif
    
    Unroller2<0, N, 0, N>::step(profiler);
    
    for (auto w : walls)
    {
        w->force(part[1]);
    }
    
    if (dt*step > 100)
    {
        walls[1]->fix();
        walls[0]->addF(0.1);
    }
    
    auto fin = [&](int type)
    {
        _nuscal(part[type]->adata, part[type]->m,       part[type]->n);
        _axpy(part[type]->vdata,   part[type]->adata, 3*part[type]->n, dt*0.5);
    };
    
    Unroller<0, N>::step(fin);
    
    for (auto w : walls)
    {
        w->VVpost(dt);
    }
}

template<int N>
void Simulation<N>::runOneStep()
{
    profiler.start("Other");
	for (typename list<Saver<N>*>::iterator it = savers.begin(), end = savers.end(); it != end; ++it)
	{
		if ((step % (*it)->getPeriod()) == 0) (*it)->exec();
	}
    profiler.stop();
	
	if (step == 0)
    {
        Unroller2<0, N, 0, N>::step(profiler);
//        debug("\n\n\n\n\n\n\n");
//        Unroller3<0, N, 0, N>::step();
//        
//        for (int i = 0; i< part[1]->n; i++)
//        {
//            if (fabs(part[1]->ax(i) - part[1]->bx(i)) > 1e-5)
//                warn("X, i = %3i:  %.6f   instead of  %.6f !!\n", i, part[1]->bx(i), part[1]->ax(i));
//            
//            if (fabs(part[1]->ay(i) - part[1]->by(i)) > 1e-5)
//                warn("Y, i = %3i:  %.6f   instead of  %.6f !!\n", i, part[1]->by(i), part[1]->ay(i));
//            
//            if (fabs(part[1]->az(i) - part[1]->bz(i)) > 1e-5)
//                warn("Z, i = %3i:  %.6f   instead of  %.6f !!\n", i, part[1]->bz(i), part[1]->az(i));
//        }
    }
    
	step++;
	velocityVerlet();
}

template<int N>
void Simulation<N>::registerSaver(Saver<N>* saver, int period)
{
    if (period > 0)
    {
        saver->setEnsemble(this);
        saver->setPeriod(period);
        savers.push_back(saver);
    }
}







