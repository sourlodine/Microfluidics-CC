#include "uniform_ic.h"

#include <random>

#include <core/pvs/particle_vector.h>
#include <core/logger.h>


UniformIC::UniformIC(float density) : density(density)
{   }

UniformIC::~UniformIC() = default;


/**
 * Particles will be initialized such that the number of particles \f$ n_p \f$ in
 * each unit cell of the domain follows:
 *
 * \f$
 * \begin{cases}
 *   p \left( n_p = \left\lfloor \rho \right\rfloor \right) = \left\lceil \rho \right\rceil - \rho \\
 *   p \left( n_p = \left\lceil \rho \right\rceil \right) = \rho - \left\lfloor \rho \right\rfloor
 * \end{cases}
 * \f$
 *
 * Here \f$ \rho \f$ is the target number density: #density
 *
 * Each particle will have a unique id across all MPI processes in Particle::i1.
 *
 * \rst
 * .. note::
 *    Currently ids are only 32-bit wide
 * \endrst
 */
void UniformIC::exec(const MPI_Comm& comm, ParticleVector* pv, cudaStream_t stream)
{
    auto domain = pv->state->domain;

    int3 ncells = make_int3( ceilf(domain.localSize) );
    float3 h = domain.localSize / make_float3(ncells);

    float volume = h.x*h.y*h.z;
    float avg = volume * density;
    int predicted = round(avg * ncells.x*ncells.y*ncells.z * 1.05);
    pv->local()->resize_anew(predicted);

    int rank;
    MPI_Check( MPI_Comm_rank(comm, &rank) );

    std::hash<std::string> nameHash;
    const int seed = rank + nameHash(pv->name);
    std::mt19937 gen(seed);
    std::uniform_real_distribution<float> udistr(0, 1);

    int wholeInCell = floor(density);
    float fracInCell = density - wholeInCell;

    double3 avgMomentum{0,0,0};
    int mycount = 0;
    for (int i=0; i<ncells.x; i++)
        for (int j=0; j<ncells.y; j++)
            for (int k=0; k<ncells.z; k++)
            {
                int nparts = wholeInCell;
                if (udistr(gen) < fracInCell) nparts++;

                for (int p=0; p<nparts; p++)
                {
                    pv->local()->resize(mycount+1,  stream);
                    auto cooPtr = pv->local()->coosvels.hostPtr();

                    cooPtr[mycount].r.x = i*h.x - 0.5*domain.localSize.x + udistr(gen);
                    cooPtr[mycount].r.y = j*h.y - 0.5*domain.localSize.y + udistr(gen);
                    cooPtr[mycount].r.z = k*h.z - 0.5*domain.localSize.z + udistr(gen);
                    cooPtr[mycount].i1 = mycount;

                    cooPtr[mycount].u.x = 0.0f * (udistr(gen) - 0.5);
                    cooPtr[mycount].u.y = 0.0f * (udistr(gen) - 0.5);
                    cooPtr[mycount].u.z = 0.0f * (udistr(gen) - 0.5);

                    avgMomentum.x += cooPtr[mycount].u.x;
                    avgMomentum.y += cooPtr[mycount].u.y;
                    avgMomentum.z += cooPtr[mycount].u.z;

                    cooPtr[mycount].i1 = mycount;
                    mycount++;
                }
            }

    avgMomentum.x /= mycount;
    avgMomentum.y /= mycount;
    avgMomentum.z /= mycount;

    auto cooPtr = pv->local()->coosvels.hostPtr();
    for (int i=0; i<mycount; i++)
    {
        cooPtr[i].u.x -= avgMomentum.x;
        cooPtr[i].u.y -= avgMomentum.y;
        cooPtr[i].u.z -= avgMomentum.z;
    }

    int totalCount=0; // TODO: int64!
    MPI_Check( MPI_Exscan(&mycount, &totalCount, 1, MPI_INT, MPI_SUM, comm) );
    for (int i=0; i < pv->local()->size(); i++)
        pv->local()->coosvels[i].i1 += totalCount;
    
    //pv->createIndicesHost();

    pv->local()->coosvels.uploadToDevice(stream);
    pv->local()->extraPerParticle.getData<Particle>("old_particles")->copy(pv->local()->coosvels, stream);

    debug2("Generated %d %s particles", pv->local()->size(), pv->name.c_str());
}
