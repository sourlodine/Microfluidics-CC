#include "mirheo_state.h"

#include <mirheo/core/logger.h>
#include <mirheo/core/utils/restart_helpers.h>
#include <mirheo/core/utils/config.h>

namespace mirheo
{

static const std::string fname = "state.mirheo";

MirState::MirState(DomainInfo domain, real dt) :
    domain(domain),
    dt(dt),
    currentTime(0),
    currentStep(0)
{}

MirState::MirState(const MirState&) = default;

MirState& MirState::operator=(MirState other)
{
    swap(other);
    return *this;
}

MirState::~MirState() = default;

void MirState::swap(MirState& other)
{
    std::swap(domain,      other.domain);
    std::swap(dt,          other.dt);
    std::swap(currentTime, other.currentTime);
    std::swap(currentStep, other.currentStep);
}

static bool isMasterRank(MPI_Comm comm)
{
    int rank;
    MPI_Check( MPI_Comm_rank(comm, &rank) );
    return rank == 0;
}

void MirState::reinitTime()
{
    currentTime = 0;
    currentStep = 0;
}

void MirState::checkpoint(MPI_Comm comm, std::string folder)
{
    if (!isMasterRank(comm))
        return;
    
    real3 gsz, gst, lsz;
    gsz = domain.globalSize;
    gst = domain.globalStart;
    lsz = domain.localSize;

    TextIO::write(folder + fname,
                  gsz.x, gsz.y, gsz.z,
                  gst.x, gst.y, gst.z,
                  lsz.x, lsz.y, lsz.z,
                  dt, currentTime, currentStep);
}

void MirState::restart(MPI_Comm comm, std::string folder)
{
    if (!isMasterRank(comm))
        return;    
    
    real3 gsz, gst, lsz;
    auto filename = folder + fname;
    auto good = TextIO::read(filename,
                             gsz.x, gsz.y, gsz.z,
                             gst.x, gst.y, gst.z,
                             lsz.x, lsz.y, lsz.z,
                             dt, currentTime, currentStep);

    if (!good) die("failed to read '%s'\n", filename.c_str());
    
    domain.globalSize  = gsz;
    domain.globalStart = gst;
    domain.localSize   = lsz;
}

Config ConfigDumper<MirState>::dump(const MirState &state) {
    return Config::Dictionary{
        {"__type", "MirState"},
        {"domainGlobalStart", state.domain.globalStart},
        {"domainGlobalSize", state.domain.globalSize},
        {"dt", state.dt},
        {"currentTime", state.currentTime},
        {"currentStep", state.currentStep},
    };
}

} // namespace mirheo
