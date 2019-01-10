#include <core/pvs/particle_vector.h>

#include "uniform_sphere_ic.h"
#include "helpers.h"

UniformSphereIC::UniformSphereIC(float density, float3 center, float radius, bool inside) :
    density(density),
    center(center),
    radius(radius),
    inside(inside)
{}

UniformSphereIC::UniformSphereIC(float density, PyTypes::float3 center, float radius, bool inside) :
    UniformSphereIC(density, make_float3(center), radius, inside)
{}

UniformSphereIC::~UniformSphereIC() = default;
    
void UniformSphereIC::exec(const MPI_Comm& comm, ParticleVector* pv, cudaStream_t stream)
{
    auto filterSphere = [this](float3 r) {
        r -= center;
        bool is_inside = length(r) <= radius;
        
        if (inside) return  is_inside;
        else        return !is_inside;
    };
    
    addUniformParticles(density, comm, pv, filterSphere, stream);
}

