#include "mirheo_object.h"

#include <mirheo/core/logger.h>
#include <mirheo/core/utils/folders.h>

namespace mirheo
{

MirObject::MirObject(std::string name) :
    name(name)
{}

MirObject::~MirObject() = default;

void MirObject::checkpoint(__UNUSED MPI_Comm comm, __UNUSED const std::string& path, __UNUSED int checkpointId) {}
void MirObject::restart   (__UNUSED MPI_Comm comm, __UNUSED const std::string& path) {}


static void appendIfNonEmpty(std::string& base, const std::string& toAppend)
{
    if (toAppend != "")
        base += "." + toAppend;
}

static std::string createBaseName(const std::string& path,
                                  const std::string& name,
                                  const std::string& identifier)
{
    auto base = path + "/" + name;
    appendIfNonEmpty(base, identifier);
    return base;    
}


std::string MirObject::createCheckpointName(const std::string& path, const std::string& identifier, const std::string& extension) const
{
    auto base = createBaseName(path, name, identifier);
    appendIfNonEmpty(base, extension);
    return base;
}

std::string MirObject::createCheckpointNameWithId(const std::string& path, const std::string& identifier, const std::string& extension, int checkpointId) const
{
    auto base = createBaseName(path, name, identifier);
    base += "-" + getStrZeroPadded(checkpointId);
    appendIfNonEmpty(base, extension);
    return base;
}

void MirObject::createCheckpointSymlink(MPI_Comm comm, const std::string& path, const std::string& identifier, const std::string& extension, int checkpointId) const
{
    int rank;
    MPI_Check( MPI_Comm_rank(comm, &rank) );

    if (rank == 0) {
        const std::string lnname = createCheckpointName      (path, identifier, extension);
        const std::string  fname = createCheckpointNameWithId(path, identifier, extension, checkpointId);
        const std::string command = "ln -f " + fname + " " + lnname;
        
        if ( system(command.c_str()) != 0 )
            error("Could not create symlink '%s' for checkpoint file '%s'",
                  lnname.c_str(), fname.c_str());
    }    
}


MirSimulationObject::MirSimulationObject(const MirState *state, const std::string& name) :
    MirObject(name),
    state(state)
{}

MirSimulationObject::~MirSimulationObject() = default;

} // namespace mirheo
