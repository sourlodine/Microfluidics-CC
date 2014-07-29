//
//  Simulation.cpp
//  CTC
//
//  Created by Dmitry Alexeev on 23.07.14.
//  Copyright (c) 2014 Dmitry Alexeev. All rights reserved.
//

#include "Simulation.h"
#include "Savers.h"
#include "Cpukernels.h"

//**********************************************************************************************************************
// Simulation implementation
//**********************************************************************************************************************
void stupidLoad(Particles** part, string fname)
{
    ifstream in(fname);
    
    assert(in.good());
    int type;
    
    int i=0;
    while (in.good())
    {
        in >> type;
        in >> part[type]->x(i) >> part[type]->y(i) >> part[type]->z(i);
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

Simulation::Simulation(int nTypes, real dt) : nTypes(nTypes), dt(dt)
{
	step = 0;
	xlo   = configParser->getf("Basic", "xlo");
    xhi   = configParser->getf("Basic", "xhi");
    ylo   = configParser->getf("Basic", "ylo");
    yhi   = configParser->getf("Basic", "yhi");
    zlo   = configParser->getf("Basic", "zlo");
    zhi   = configParser->getf("Basic", "zhi");
    
    part = new Particles* [nTypes];
}

void Simulation::setIC()
{
    for (int type=0; type<nTypes; type++)
    {
        part[type]	  = new Particles;
        part[type]->n = configParser->geti("Particles", "N"+to_string(type+1));
        _allocate(part[type]);
    }
    
    // Initial conditions for positions and velocities
	mt19937 gen;
    uniform_real_distribution<real> ux(xlo, xhi);
    uniform_real_distribution<real> uy(ylo, yhi);
    uniform_real_distribution<real> uz(zlo, zhi);
    
    uniform_real_distribution<real> uphi(0, 2*M_PI);
    uniform_real_distribution<real> utheta(0, M_PI*0.75);
    
    
    if (nTypes>1) setLattice(part[1], 15, 15, 15, part[1]->n);
    //stupidLoad(part, "/Users/alexeedm/Documents/projects/CTC/CTC/makefiles/dump.txt");
    
    double xl = 0;//mymin(part[1]->x, part[1]->n);
    double xh = 0;//mymax(part[1]->x, part[1]->n);
    
    double yl = 0;//mymin(part[1]->y, part[1]->n);
    double yh = 0;//mymax(part[1]->y, part[1]->n);
    
    double zl = 0;//mymin(part[1]->z, part[1]->n);
    double zh = 0;//mymax(part[1]->z, part[1]->n);
    
    
    for (int i=0; i<part[0]->n; i++)
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
    
    for (int type=0; type<nTypes; type++)
    {
        _fill(part[type]->vdata, 3*part[type]->n, (real)0.0);
        _fill(part[type]->adata, 3*part[type]->n, (real)0.0);
        
        _fill(part[type]->m, part[type]->n, (real)1.0);
        _fill(part[type]->label, part[type]->n, 0);
    }
    
    evaluator = new InteractionTable(nTypes, part, profiler, xlo, xhi, ylo, yhi, zlo, zhi);
}

void Simulation::loadRestart(string fname)
{
    ifstream in(fname.c_str(), ios::in | ios::binary);
    
    int n;
    in.read((char*)&n, sizeof(int));
    
    if (n != nTypes) die("Using %d types, asked for %d\n", nTypes, n);
    
    for (int i = 0; i<nTypes; i++)
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
    }
    
    in.close();
    
    real zmax = -1000;
    real zmin =  1000;
    for (int i = 0; i<part[1]->n; i++)
    {
        zmax = max(zmax, part[1]->z(i));
        zmin = min(zmin, part[1]->z(i));
    }
    
    // !!! 3.31661 -2.64321
    // 3.31299 -2.63933
    walls.push_back(new LJwallz(configParser->getf("Plates", "topz",  1e9), configParser->getf("Plates", "topv", 0)));
    walls.push_back(new LJwallz(configParser->getf("Plates", "botz", -1e9), configParser->getf("Plates", "botv", 0)));
    
    evaluator = new InteractionTable(nTypes, part, profiler, xlo, xhi, ylo, yhi, zlo, zhi);
}

void Simulation::setLattice(Particles* p, real lx, real ly, real lz, int n)
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

real Simulation::Ktot(int type)
{
    real res = 0;
    
    if (type < 0)
    {
        for (int t=0; t<nTypes; t++)
            res += _kineticNrg(part[t]);
    }
    else
    {
        res = _kineticNrg(part[type]);
    }
	return res;
}

void Simulation::linMomentum(real& px, real& py, real& pz, int type)
{
    real _px = 0, _py = 0, _pz = 0;
    px = py = pz = 0;
    
	if (type < 0)
    {
        for (int t=0; t<nTypes; t++)
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

void Simulation::angMomentum(real& Lx, real& Ly, real& Lz, int type)
{
    real _Lx = 0, _Ly = 0, _Lz = 0;
    Lx = Ly = Lz = 0;
    
	if (type < 0)
    {
        for (int t=0; t<nTypes; t++)
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

void Simulation::centerOfMass(real& mx, real& my, real& mz, int type)
{
    real _mx = 0, _my = 0, _mz = 0;
    mx = my = mz = 0;
    
	if (type < 0)
    {
        for (int t=0; t<nTypes; t++)
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

void Simulation::rdf(int a, real* bins, real h, int nBins)
{
    _rdf(part, evaluator->cells, a, bins, h, nBins, (xhi - xlo)*(yhi - ylo)*(zhi - zlo));
}


void Simulation::velocityVerlet()
{
    profiler.start("Pre-force");
    {
        for (auto w : walls)
        {
            w->VVpre(dt);
        }
        
        for (int type = 0; type < nTypes; type++)
        {
            _axpy(part[type]->vdata, part[type]->adata, 3*part[type]->n, dt*0.5);
            _axpy(part[type]->xdata, part[type]->vdata, 3*part[type]->n, dt);
            
            _normalize(part[type]->xdata, part[type]->n, xlo, xhi, 0);
            _normalize(part[type]->xdata, part[type]->n, ylo, yhi, 1);
            _normalize(part[type]->xdata, part[type]->n, zlo, zhi, 2);
            
            _fill(part[type]->adata, 3*part[type]->n, (real)0.0);
        }
    }
    profiler.stop();
    
    profiler.start("CellList");
    evaluator->doCells();
    profiler.stop();
    
    evaluator->evalForces(step);
    
    profiler.start("Post-force");
    {
        for (auto w : walls)
        {
            w->force(part[1]);
        }
        
        if (dt*step > configParser->getf("Plates", "startF", 1e9))
        {
            walls[1]->fix();
            walls[0]->addF(configParser->getf("Plates", "applyF", 0));
        }
        
        for (int type = 0; type < nTypes; type++)
        {
            _nuscal(part[type]->adata, part[type]->m,       part[type]->n);
            _axpy(part[type]->vdata,   part[type]->adata, 3*part[type]->n, dt*0.5);
        }
        
        for (auto w : walls)
        {
            w->VVpost(dt);
        }
    }
    profiler.stop();
}

void Simulation::runOneStep()
{
    profiler.start("Other");
	for (typename list<Saver*>::iterator it = savers.begin(), end = savers.end(); it != end; ++it)
	{
		if ((step % (*it)->getPeriod()) == 0) (*it)->exec();
	}
    profiler.stop();
	
	if (step == 0)
        evaluator->evalForces(step);
    
	step++;
	velocityVerlet();
}

void Simulation::registerSaver(Saver* saver, int period)
{
    if (period > 0)
    {
        saver->setEnsemble(this);
        saver->setPeriod(period);
        savers.push_back(saver);
    }
}
