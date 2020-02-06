#pragma once

#include "mirheo_state.h"

#include <mirheo/core/utils/common.h>

#include <mpi.h>
#include <string>

namespace mirheo
{

/**
 * Base class for all the objects of Mirheo
 * Only stores name and provides interface for
 * checkpoint / restart mechanism
 */
class MirObject
{
public:
    MirObject(const std::string& name);
    virtual ~MirObject();

    const std::string& getName() const noexcept {return name_;}
    const char* getCName() const {return name_.c_str();}
    
    virtual void checkpoint(MPI_Comm comm, const std::string& path, int checkPointId);  /// Save handler state
    virtual void restart   (MPI_Comm comm, const std::string& path);  /// Restore handler state
    virtual ConfigDictionary writeSnapshot(Dumper& dumper);

    std::string createCheckpointName      (const std::string& path, const std::string& identifier, const std::string& extension) const;
    std::string createCheckpointNameWithId(const std::string& path, const std::string& identifier, const std::string& extension, int checkpointId) const;
    void createCheckpointSymlink(MPI_Comm comm, const std::string& path, const std::string& identifier, const std::string& extension, int checkpointId) const;

private:
    const std::string name_;
};

/**
 * Base class for the objects of Mirheo simulation task
 * may additionally store global quantities in the future
 */
class MirSimulationObject : public MirObject
{
public:
    MirSimulationObject(const MirState *state, const std::string& name);
    ~MirSimulationObject();

    const MirState* getState() const {return state;}
    virtual void setState(const MirState *state);
    
private:
    const MirState *state;
};

// Common dumper to the template dumper below. This way we don't need the
// definition of Config here.
struct ConfigMirObjectDumper {
    // Automatically adds `name` key to the returned dictionary. 
    static Config dump(Dumper& dumper, MirObject& obj);
};

/// ConfigDumper specialization for MirObject and derived classes.
template <typename T>
struct ConfigDumper<T, std::enable_if_t<std::is_base_of<MirObject, T>::value>>
    : ConfigMirObjectDumper
{ };

} // namespace mirheo
