#include "rigid.h"

#include <core/integrators/rigid_vv.h>
#include <core/pvs/particle_vector.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/rigid_kernels/rigid_motion.h>

#include <fstream>
#include <random>

static PyTypes::VectorOfFloat3 readXYZ(std::string fname)
{
    PyTypes::VectorOfFloat3 positions;
    int n;
    float dummy;
    std::string line;

    std::ifstream fin(fname);
    if (!fin.good())
        die("XYZ ellipsoid file %s not found", fname.c_str());
    fin >> n;

    // skip the comment line
    std::getline(fin, line);
    std::getline(fin, line);

    positions.resize(n);
    for (int i = 0; i < n; ++i)
        fin >> dummy >> positions[i][0] >> positions[i][1] >> positions[i][2];
    return positions;
}



RigidIC::RigidIC(PyTypes::VectorOfFloat7 com_q, std::string xyzfname) :
    RigidIC(com_q, readXYZ(xyzfname))
{}

RigidIC::RigidIC(PyTypes::VectorOfFloat7 com_q, const PyTypes::VectorOfFloat3& coords) :
    com_q(com_q),
    coords(coords)
{}

RigidIC::RigidIC(PyTypes::VectorOfFloat7 com_q,
                 const PyTypes::VectorOfFloat3& coords,
                 const PyTypes::VectorOfFloat3& comVelocities) :
    com_q(com_q),
    coords(coords),
    comVelocities(comVelocities)
{
    if (com_q.size() != comVelocities.size())
        die("Incompatible sizes of initial positions and rotations");
}

RigidIC::~RigidIC() = default;


static PinnedBuffer<float4> getInitialPositions(const PyTypes::VectorOfFloat3& in,
                                                cudaStream_t stream)
{
    PinnedBuffer<float4> out(in.size());
    
    for (int i = 0; i < in.size(); ++i)
        out[i] = make_float4(in[i][0], in[i][1], in[i][2], 0);
        
    out.uploadToDevice(stream);
    return out;
}

static void checkInitialPositions(const DomainInfo& domain,
                                  const PinnedBuffer<float4>& positions)
{
    if (positions.size() < 1)
        die("Expect at least one particle per rigid object");

    const float3 r0 = make_float3(positions[0]);
    
    float3 low {r0}, hig {r0};
    for (auto r4 : positions)
    {
        const float3 r = make_float3(r4);
        low = fminf(low, r);
        hig = fmaxf(hig, r);
    }

    const auto L = domain.localSize;
    const auto l = hig - low;

    const auto Lmax = std::max(L.x, std::max(L.y, L.z));
    const auto lmax = std::max(l.x, std::max(l.y, l.z));

    if (lmax >= Lmax)
        warn("Object dimensions are larger than the domain size");
}

static std::vector<RigidMotion> createMotions(const DomainInfo& domain,
                                              const PyTypes::VectorOfFloat7& com_q,
                                              const PyTypes::VectorOfFloat3& comVelocities)
{
    std::vector<RigidMotion> motions;

    for (size_t i = 0; i < com_q.size(); ++i)
    {
        const auto& entry = com_q[i];
        
        // Zero everything at first
        RigidMotion motion{};
        
        motion.r = {entry[0], entry[1], entry[2]};
        motion.q = make_rigidReal4( make_float4(entry[3], entry[4], entry[5], entry[6]) );
        motion.q = normalize(motion.q);
        
        if (i < comVelocities.size())
            motion.vel = {comVelocities[i][0], comVelocities[i][1], comVelocities[i][2]};

        if (domain.inSubDomain(motion.r))
        {
            motion.r = make_rigidReal3( domain.global2local(make_float3(motion.r)) );
            motions.push_back(motion);
        }
    }
    return motions;
}

void RigidIC::exec(const MPI_Comm& comm, ParticleVector *pv, cudaStream_t stream)
{
    auto ov = dynamic_cast<RigidObjectVector*>(pv);
    if (ov == nullptr)
        die("Can only generate rigid object vector");

    const auto domain = ov->state->domain;

    ov->initialPositions = getInitialPositions(coords, stream);
    checkInitialPositions(domain, ov->initialPositions);

    auto lov = ov->local();
    
    if (ov->objSize != ov->initialPositions.size())
        die("Object size and XYZ initial conditions don't match in size for '%s': %d vs %d",
            ov->name.c_str(), ov->objSize, ov->initialPositions.size());

    const auto motions = createMotions(domain, com_q, comVelocities);
    const auto nObjs = motions.size();
    
    lov->resize_anew(nObjs * ov->objSize);

    auto& ovMotions = *lov->dataPerObject.getData<RigidMotion>(ChannelNames::motions);
    std::copy(motions.begin(), motions.end(), ovMotions.begin());
    ovMotions.uploadToDevice(stream);

    auto& positions = lov->positions();
    
    positions.uploadToDevice(stream);
    lov->velocities().uploadToDevice(stream);
    lov->computeGlobalIds(comm, stream);

    auto& oldPositions = *lov->dataPerParticle.getData<float4>(ChannelNames::oldPositions);
    oldPositions.copy(positions, stream);

    info("Read %d %s objects", nObjs, ov->name.c_str());

    // Do the initial rotation
    lov->forces().clear(stream);
    MirState dummyState(ov->state->domain, /* dt */ 0.f);
    IntegratorVVRigid integrator(&dummyState, "__dummy__");
    integrator.stage2(pv, stream);
}

