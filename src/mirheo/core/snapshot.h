#pragma once

#include <mirheo/core/utils/config.h>

#include <mpi.h>
#include <tuple>
#include <typeinfo>

namespace mirheo
{

class Integrator;
class Interaction;
class Mesh;
class Mirheo;
class MirState;
class ParticleVector;
class PostprocessPlugin;
class SimulationPlugin;

void _unknownRefStringError [[noreturn]] (const std::string &ref);
void _dynamicCastError [[noreturn]] (const char *from, const char *to);

class SaverContext
{
public:
    std::string path {"snapshot/"};
    MPI_Comm groupComm {MPI_COMM_NULL};
    std::map<std::string, int> counters;

    bool isGroupMasterTask() const;
};

class LoaderContext {
public:
    LoaderContext(std::string snapshotPath);
    LoaderContext(ConfigValue compute, ConfigValue postprocess,
                  std::string snapshotPath = "snapshot/");
    ~LoaderContext();

    const ConfigObject& getCompObjectConfig(const std::string& category,
                                            const std::string& name);

    template <typename T, typename ContainerT = T>
    std::shared_ptr<T> get(const ConfigRefString& ref)
    {
        const auto& container = getContainer<ContainerT>();
        auto it = container.find(parseNameFromRefString(ref));
        if (it == container.end())
            _unknownRefStringError(ref);
        if (T *p = dynamic_cast<T*>(it->second.get()))
            return {it->second, p};
        _dynamicCastError(typeid(it->second.get()).name(), typeid(T).name());
    }

    template <typename T>
    std::map<std::string, std::shared_ptr<T>>& getContainer()
    {
        return std::get<std::map<std::string, std::shared_ptr<T>>>(objects_);
    }

    const std::string& getPath() const { return path_; }
    const ConfigObject& getComp() const { return compConfig_.getObject(); }
    const ConfigObject& getPost() const { return postConfig_.getObject(); }

private:
    template <typename T, typename Factory>
    const std::shared_ptr<T>& _loadObject(Mirheo *mir, Factory factory);

    std::tuple<
        std::map<std::string, std::shared_ptr<Mesh>>,
        std::map<std::string, std::shared_ptr<ParticleVector>>,
        std::map<std::string, std::shared_ptr<Interaction>>,
        std::map<std::string, std::shared_ptr<Integrator>>> objects_;
    std::string path_;
    ConfigValue compConfig_;
    ConfigValue postConfig_;
};

/** This is a mechanism for avoiding undefined symbols during the linking phase
    since the Mirheo core is compiled independently from plugins. In other
    words, since plugins are treated as optional, this is a mechanism to add
    factory for loading plugin snapshots.

    First, each plugin set (such as the one provided with Mirheo) registers its
    factory. Then, during the snapshot loading, for each pair of stored
    compute/postprocess plugins, the `loadSnapshot` function will traverse
    every factory until one of them successfully constructs the plugins. If
    none of them do, an exception will be thrown.
 */
class PluginFactoryContainer
{
public:
    using PairPlugin = std::pair<std::shared_ptr<SimulationPlugin>,
                                 std::shared_ptr<PostprocessPlugin>>;

    /// Factory type. The factory receives the MirState object, loader, and at
    /// least one of the simulation and postprocess plugin configs.
    /// Note: Can be changed to std::function if needed.
    using FactoryType = PairPlugin(*)(
            bool computeTask, const MirState *, Loader&,
            const ConfigObject *sim, const ConfigObject *post);

    /// Get singleton.
    static PluginFactoryContainer& get() noexcept;

    /// Register the factory.
    void registerPluginFactory(FactoryType factory);

    /// Getter for the vector of factories.
    const std::vector<FactoryType>& getFactories() const noexcept {
        return factories_;
    }
private:
    std::vector<FactoryType> factories_;
};

/// Load the snapshot to the Mirheo object.
void loadSnapshot(Mirheo *mir, Loader& loader);

} // namespace mirheo
