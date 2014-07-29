#include <cstdlib>
#include <cmath>
#include <cstdio>
#include <cassert>

#include <algorithm>

#include <thrust/device_vector.h>

#include "cuda-sem.h"
#include "../hacks.h"

__global__ void _update_pos(float * const xyzuvw, const float f, const int n, const float L)
{
    const int tid = threadIdx.x + blockDim.x * blockIdx.x;

    if (tid < n)
    {
	for(int c = 0; c < 3; ++c)
	{
	    const float xold = xyzuvw[c + 6 * tid];
	    
	    float xnew = xold + f * xyzuvw[3 + c + 6 * tid];
	    xnew -= L * floor((xnew + 0.5 * L) / L);
	    
	    xyzuvw[c + 6 * tid] = xnew;
	}
    }
}

__global__ void _update_vel(float * const xyzuvw, const float * const axayaz, const float f, const int n)
{
    const int tid = threadIdx.x + blockDim.x * blockIdx.x;

    if (tid < n)
    {
	for(int c = 0; c < 3; ++c)
	{
	    const float vold = xyzuvw[3 + c + 6 * tid];
	    
	    float vnew = vold + f * axayaz[c + 3 * tid];
	    	    
	    xyzuvw[3 + c + 6 * tid] = vnew;
	}
    }
}

__global__ void _diag_kbt(const float * const xyzuvw, float * const diag, const int n)
{
    const int tid = threadIdx.x + blockDim.x * blockIdx.x;

    if (tid < n)
	diag[tid] =
	    pow(xyzuvw[3 + 6 * tid], 2) +
	    pow(xyzuvw[4 + 6 * tid], 2) +
	    pow(xyzuvw[5 + 6 * tid], 2);
}

__global__ void _diag_p(const float * const xyzuvw, float * const diag, const int n, const int c)
{
    const int tid = threadIdx.x + blockDim.x * blockIdx.x;

    if (tid < n)
	diag[tid] = xyzuvw[3 + c + 6 * tid];
}

using namespace thrust;

void vmd_xyz(const char * path, device_vector<float>& _xyzuvw, const int n, bool append)
{
    host_vector<float> xyzuvw(_xyzuvw);
    
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
	fprintf(f, "1 %f %f %f\n",
		(float)xyzuvw[0 + 6 * i],
		(float)xyzuvw[1 + 6 * i],
		(float)xyzuvw[2 + 6 * i]);
    
    fclose(f);

    printf("vmd_xyz: wrote to <%s>\n", path);
}

class SimSEM
{
    const int n;
    const float L;
    device_vector<float> xyzuvw, axayaz, diag;

public:

    SimSEM(const int n, const float L): n(n), L(L), xyzuvw(6 * n), axayaz(3 * n), diag(n)
	{
	    srand48(6516L);
	    for(int i = 0; i < n; ++i)
	    {
		xyzuvw[0 + 6 *i] = -L * 0.5f +  drand48() * L;
		xyzuvw[1 + 6 *i] = -L * 0.5f +  drand48() * L;
		xyzuvw[2 + 6 *i] = -L * 0.5f +  drand48() * L;	
	    }
	}

    void _diag(FILE ** fs, const int nfs, float t)
	{
	    _diag_kbt<<< (n + 127) / 128, 128 >>>(_ptr(xyzuvw), _ptr(diag), n);
	    const float sv2 = reduce(diag.begin(), diag.end());
	    float T = 0.5 * sv2 / (n * 3. / 2);
	    
	    float p[3];
	    for(int c = 0; c < 3; ++c)
	    {
		_diag_p<<< (n + 127) / 128, 128 >>>(_ptr(xyzuvw), _ptr(diag), n, 0);
		p[c] = reduce(diag.begin(), diag.end());
	    }

	    for(int i = 0; i < nfs; ++i)
	    {
		FILE * f = fs[i];
		
		if (ftell(f) == 0)
		    fprintf(f, "TIME\tkBT\tX-MOMENTUM\tY-MOMENTUM\tZ-MOMENTUM\n");

		fprintf(f, "%s %+e\t%+e\t%+e\t%+e\t%+e\n", (f == stdout ? "DIAG:" : ""), t, T, p[0], p[1], p[2]);
	    }
	}

     void _f(const float dt)
	{
	    //np,  rc,  LX, LY, LZ,  gamma, temp, dt,   u0,    rho,  req, D
	    //1e3, 1.0, 10, 10, 10,  80,    0.1,  0.01, 0.001, 1.5,  0.85, 0.0001
	    const float rcutoff = 2.5, gamma = 80, temp = 0.1, u0 = 0.001, rho = 1.5, req = 0.85, D = .0001, rc = 1;
	 
	    forces_sem_cuda_nohost(_ptr(xyzuvw), _ptr(axayaz), NULL,
		    n, rcutoff, L, L, L, gamma, temp, dt, u0, rho, req, D, rc);
	};
    
    void run(const double tend, const double dt)
	{
	    vmd_xyz("ic.xyz", xyzuvw, n, false);

	    FILE * fdiags[2] = {stdout, fopen("diag.txt", "w") };

	    const size_t nt = (int)(tend / dt);

	    _f(dt);
	    
	    for(int it = 0; it < nt; ++it)
	    {
		if (it % 200 == 0)
		{
		    float t = it * dt;
		    _diag(fdiags, 2, t);
		}
		
		_update_vel<<<(n + 127) / 128, 128>>>(_ptr(xyzuvw), _ptr(axayaz), dt * 0.5, n);
		
		_update_pos<<<(n + 127) / 128, 128>>>(_ptr(xyzuvw), dt, n, L);
		
		_f(dt);

		_update_vel<<<(n + 127) / 128, 128>>>(_ptr(xyzuvw), _ptr(axayaz), dt * 0.5, n);
		
		if (it % 200 == 0)
		    vmd_xyz("evolution.xyz", xyzuvw, n, it > 0);
	    }

	    fclose(fdiags[1]);
	}
};

int main()
{
    printf("hello gpu only test\n");
    
    float L = 20;

    const float Nm = .25;
    const int n = L * L * L * Nm;

    SimSEM sim(n, L);
       
    sim.run(8, 0.01);
    
    return 0;
}
