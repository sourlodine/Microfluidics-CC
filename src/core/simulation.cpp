#include "simulation.h"

#include <core/bouncers/interface.h>
#include <core/celllist.h>
#include <core/initial_conditions/interface.h>
#include <core/integrators/interface.h>
#include <core/interactions/interface.h>
#include <core/managers/interactions.h>
#include <core/mpi/api.h>
#include <core/object_belonging/interface.h>
#include <core/pvs/object_vector.h>
#include <core/pvs/particle_vector.h>
#include <core/task_scheduler.h>
#include <core/utils/folders.h>
#include <core/utils/make_unique.h>
#include <core/utils/restart_helpers.h>
#include <core/walls/interface.h>
#include <core/ymero_state.h>
#include <plugins/interface.h>

#include <algorithm>
#include <cuda_profiler_api.h>

#define TASK_LIST(OP)                                                   \
    OP(checkpoint                          , "Checkpoint")              \
    OP(cellLists                           , "Build cell-lists")        \
    OP(integration                         , "Integration")             \
    OP(clearIntermediate                   , "Clear intermediate")      \
    OP(haloIntermediateInit                , "Halo intermediate init")  \
    OP(haloIntermediateFinalize            , "Halo intermediate finalize") \
    OP(localIntermediate                   , "Local intermediate")      \
    OP(haloIntermediate                    , "Halo intermediate")       \
    OP(accumulateInteractionIntermediate   , "Accumulate intermediate") \
    OP(gatherInteractionIntermediate       , "Gather intermediate")     \
    OP(clearFinalOutput                    , "Clear forces")            \
    OP(haloInit                            , "Halo init")               \
    OP(haloFinalize                        , "Halo finalize")           \
    OP(localForces                         , "Local forces")            \
    OP(haloForces                          , "Halo forces")             \
    OP(accumulateInteractionFinal          , "Accumulate forces")       \
    OP(objHaloInit                         , "Object halo init")        \
    OP(objHaloFinalize                     , "Object halo finalize")    \
    OP(objForcesInit                       , "Object forces exchange: init") \
    OP(objForcesFinalize                   , "Object forces exchange: finalize") \
    OP(clearObjHaloForces                  , "Clear object halo forces") \
    OP(clearObjLocalForces                 , "Clear object local forces") \
    OP(objLocalBounce                      , "Local object bounce")     \
    OP(objHaloBounce                       , "Halo object bounce")      \
    OP(correctObjBelonging                 , "Correct object belonging") \
    OP(wallBounce                          , "Wall bounce")             \
    OP(wallCheck                           , "Wall check")              \
    OP(redistributeInit                    , "Redistribute init")       \
    OP(redistributeFinalize                , "Redistribute finalize")   \
    OP(objRedistInit                       , "Object redistribute init") \
    OP(objRedistFinalize                   , "Object redistribute finalize") \
    OP(pluginsBeforeCellLists              , "Plugins: before cell lists") \
    OP(pluginsBeforeForces                 , "Plugins: before forces")  \
    OP(pluginsSerializeSend                , "Plugins: serialize and send") \
    OP(pluginsBeforeIntegration            , "Plugins: before integration") \
    OP(pluginsAfterIntegration             , "Plugins: after integration") \
    OP(pluginsBeforeParticlesDistribution  , "Plugins: before particles distribution")


struct SimulationTasks
{
#define DECLARE(NAME, DESC) TaskScheduler::TaskID NAME ;

    TASK_LIST(DECLARE);

#undef DECLARE    
};

Simulation::Simulation(const MPI_Comm &cartComm, const MPI_Comm &interComm, YmrState *state,
                       int globalCheckpointEvery, std::string checkpointFolder,
                       bool gpuAwareMPI)
    : nranks3D(nranks3D),
      interComm(interComm),
      state(state),
      globalCheckpointEvery(globalCheckpointEvery),
      checkpointFolder(checkpointFolder),
      gpuAwareMPI(gpuAwareMPI),
      scheduler(std::make_unique<TaskScheduler>()),
      tasks(std::make_unique<SimulationTasks>()),
      interactionManager(std::make_unique<InteractionManager>())
{
    int nranks[3], periods[3], coords[3];

    MPI_Check(MPI_Comm_dup(cartComm, &this->cartComm));
    MPI_Check(MPI_Cart_get(cartComm, 3, nranks, periods, coords));
    MPI_Check(MPI_Comm_rank(cartComm, &rank));

    nranks3D = {nranks[0], nranks[1], nranks[2]};
    rank3D   = {coords[0], coords[1], coords[2]};

    createFoldersCollective(cartComm, checkpointFolder);

    state->reinitTime();
    
    info("Simulation initialized, subdomain size is [%f %f %f], subdomain starts "
         "at [%f %f %f]",
         state->domain.localSize.x, state->domain.localSize.y, state->domain.localSize.z,
         state->domain.globalStart.x, state->domain.globalStart.y, state->domain.globalStart.z);    
}

Simulation::~Simulation()
{
    MPI_Check( MPI_Comm_free(&cartComm) );
}


//================================================================================================
// Access for plugins
//================================================================================================


std::vector<ParticleVector*> Simulation::getParticleVectors() const
{
    std::vector<ParticleVector*> res;
    for (auto& pv : particleVectors)
        res.push_back(pv.get());

    return res;
}

ParticleVector* Simulation::getPVbyName(std::string name) const
{
    auto pvIt = pvIdMap.find(name);
    return (pvIt != pvIdMap.end()) ? particleVectors[pvIt->second].get() : nullptr;
}

std::shared_ptr<ParticleVector> Simulation::getSharedPVbyName(std::string name) const
{
    auto pvIt = pvIdMap.find(name);
    return (pvIt != pvIdMap.end()) ? particleVectors[pvIt->second] : std::shared_ptr<ParticleVector>(nullptr);
}

ParticleVector* Simulation::getPVbyNameOrDie(std::string name) const
{
    auto pv = getPVbyName(name);
    if (pv == nullptr)
        die("No such particle vector: %s", name.c_str());
    return pv;
}

ObjectVector* Simulation::getOVbyNameOrDie(std::string name) const
{
    auto pv = getPVbyName(name);
    auto ov = dynamic_cast<ObjectVector*>(pv);
    if (pv == nullptr)
        die("No such particle vector: %s", name.c_str());
    return ov;
}

Wall* Simulation::getWallByNameOrDie(std::string name) const
{
    if (wallMap.find(name) == wallMap.end())
        die("No such wall: %s", name.c_str());

    auto it = wallMap.find(name);
    return it->second.get();
}

CellList* Simulation::gelCellList(ParticleVector* pv) const
{
    auto clvecIt = cellListMap.find(pv);
    if (clvecIt == cellListMap.end())
        die("Particle Vector '%s' is not registered or broken", pv->name.c_str());

    if (clvecIt->second.size() == 0)
        return nullptr;
    else
        return clvecIt->second[0].get();
}

MPI_Comm Simulation::getCartComm() const
{
    return cartComm;
}

float Simulation::getCurrentDt() const
{
    return state->dt;
}

float Simulation::getCurrentTime() const
{
    return state->currentTime;
}

float Simulation::getMaxEffectiveCutoff() const
{
    return interactionManager->getMaxEffectiveCutoff();
}

void Simulation::saveDependencyGraph_GraphML(std::string fname) const
{
    if (rank == 0)
        scheduler->saveDependencyGraph_GraphML(fname);
}

void Simulation::startProfiler() const
{
    CUDA_Check( cudaProfilerStart() );
}

void Simulation::stopProfiler() const
{
    CUDA_Check( cudaProfilerStop() );
}

//================================================================================================
// Registration
//================================================================================================

void Simulation::registerParticleVector(std::shared_ptr<ParticleVector> pv, std::shared_ptr<InitialConditions> ic, int checkpointEvery)
{
    std::string name = pv->name;

    if (name == "none" || name == "all" || name == "")
        die("Invalid name for a particle vector (reserved word or empty): '%s'", name.c_str());
    
    if (pv->name.rfind("_", 0) == 0)
        die("Identifier of Particle Vectors cannot start with _");

    if (pvIdMap.find(name) != pvIdMap.end())
        die("More than one particle vector is called %s", name.c_str());

    if (restartStatus != RestartStatus::Anew)
        pv->restart(cartComm, restartFolder);
    else
    {
        if (ic != nullptr)
            ic->exec(cartComm, pv.get(), 0);
    }

    pvsCheckPointPrototype.push_back({pv.get(), checkpointEvery});

    auto ov = dynamic_cast<ObjectVector*>(pv.get());
    if(ov != nullptr)
    {
        info("Registered object vector '%s', %d objects, %d particles", name.c_str(), ov->local()->nObjects, ov->local()->size());
        objectVectors.push_back(ov);
    }
    else
        info("Registered particle vector '%s', %d particles", name.c_str(), pv->local()->size());

    particleVectors.push_back(std::move(pv));
    pvIdMap[name] = particleVectors.size() - 1;
}

void Simulation::registerWall(std::shared_ptr<Wall> wall, int every)
{
    std::string name = wall->name;

    if (wallMap.find(name) != wallMap.end())
        die("More than one wall is called %s", name.c_str());

    checkWallPrototypes.push_back({wall.get(), every});

    // Let the wall know the particle vector associated with it
    wall->setup(cartComm);
    if (restartStatus != RestartStatus::Anew)
        wall->restart(cartComm, restartFolder);

    info("Registered wall '%s'", name.c_str());

    wallMap[name] = std::move(wall);
}

void Simulation::registerInteraction(std::shared_ptr<Interaction> interaction)
{
    std::string name = interaction->name;
    if (interactionMap.find(name) != interactionMap.end())
        die("More than one interaction is called %s", name.c_str());

    if (restartStatus != RestartStatus::Anew)
        interaction->restart(cartComm, restartFolder);

    interactionMap[name] = std::move(interaction);
}

void Simulation::registerIntegrator(std::shared_ptr<Integrator> integrator)
{
    std::string name = integrator->name;
    if (integratorMap.find(name) != integratorMap.end())
        die("More than one integrator is called %s", name.c_str());

    if (restartStatus != RestartStatus::Anew)
        integrator->restart(cartComm, restartFolder);
    
    integratorMap[name] = std::move(integrator);
}

void Simulation::registerBouncer(std::shared_ptr<Bouncer> bouncer)
{
    std::string name = bouncer->name;
    if (bouncerMap.find(name) != bouncerMap.end())
        die("More than one bouncer is called %s", name.c_str());

    if (restartStatus != RestartStatus::Anew)
        bouncer->restart(cartComm, restartFolder);
    
    bouncerMap[name] = std::move(bouncer);
}

void Simulation::registerObjectBelongingChecker(std::shared_ptr<ObjectBelongingChecker> checker)
{
    std::string name = checker->name;
    if (belongingCheckerMap.find(name) != belongingCheckerMap.end())
        die("More than one splitter is called %s", name.c_str());

    if (restartStatus != RestartStatus::Anew)
        checker->restart(cartComm, restartFolder);
    
    belongingCheckerMap[name] = std::move(checker);
}

void Simulation::registerPlugin(std::shared_ptr<SimulationPlugin> plugin)
{
    std::string name = plugin->name;

    bool found = false;
    for (auto& pl : plugins)
        if (pl->name == name) found = true;

    if (found)
        die("More than one plugin is called %s", name.c_str());

    if (restartStatus != RestartStatus::Anew)
        plugin->restart(cartComm, restartFolder);
    
    plugins.push_back(std::move(plugin));
}

//================================================================================================
// Applying something to something else
//================================================================================================

void Simulation::setIntegrator(std::string integratorName, std::string pvName)
{
    if (integratorMap.find(integratorName) == integratorMap.end())
        die("No such integrator: %s", integratorName.c_str());
    auto integrator = integratorMap[integratorName].get();

    auto pv = getPVbyNameOrDie(pvName);

    if (pvsIntegratorMap.find(pvName) != pvsIntegratorMap.end())
        die("particle vector '%s' already set to integrator '%s'",
            pvName.c_str(), pvsIntegratorMap[pvName].c_str());

    pvsIntegratorMap[pvName] = integratorName;
    
    integrator->setPrerequisites(pv);

    integratorsStage1.push_back([integrator, pv] (cudaStream_t stream) {
        integrator->stage1(pv, stream);
    });

    integratorsStage2.push_back([integrator, pv] (cudaStream_t stream) {
        integrator->stage2(pv, stream);
    });
}

void Simulation::setInteraction(std::string interactionName, std::string pv1Name, std::string pv2Name)
{
    auto pv1 = getPVbyNameOrDie(pv1Name);
    auto pv2 = getPVbyNameOrDie(pv2Name);

    if (interactionMap.find(interactionName) == interactionMap.end())
        die("No such interaction: %s", interactionName.c_str());
    auto interaction = interactionMap[interactionName].get();    

    float rc = interaction->rc;
    interactionPrototypes.push_back({rc, pv1, pv2, interaction});
}

void Simulation::setBouncer(std::string bouncerName, std::string objName, std::string pvName)
{
    auto pv = getPVbyNameOrDie(pvName);

    auto ov = dynamic_cast<ObjectVector*> (getPVbyName(objName));
    if (ov == nullptr)
        die("No such object vector: %s", objName.c_str());

    if (bouncerMap.find(bouncerName) == bouncerMap.end())
        die("No such bouncer: %s", bouncerName.c_str());
    auto bouncer = bouncerMap[bouncerName].get();

    bouncer->setup(ov);
    bouncer->setPrerequisites(pv);
    bouncerPrototypes.push_back({bouncer, pv});
}

void Simulation::setWallBounce(std::string wallName, std::string pvName)
{
    auto pv = getPVbyNameOrDie(pvName);

    if (wallMap.find(wallName) == wallMap.end())
        die("No such wall: %s", wallName.c_str());
    auto wall = wallMap[wallName].get();

    wall->setPrerequisites(pv);
    wallPrototypes.push_back( {wall, pv} );
}

void Simulation::setObjectBelongingChecker(std::string checkerName, std::string objName)
{
    auto ov = dynamic_cast<ObjectVector*>(getPVbyNameOrDie(objName));
    if (ov == nullptr)
        die("No such object vector %s", objName.c_str());

    if (belongingCheckerMap.find(checkerName) == belongingCheckerMap.end())
        die("No such belonging checker: %s", checkerName.c_str());
    auto checker = belongingCheckerMap[checkerName].get();

    // TODO: do this normal'no blyat!
    checker->setup(ov);
}

//
//
//

void Simulation::applyObjectBelongingChecker(std::string checkerName,
            std::string source, std::string inside, std::string outside,
            int checkEvery, int checkpointEvery)
{
    auto pvSource = getPVbyNameOrDie(source);

    if (inside == outside)
        die("Splitting into same pvs: %s into %s %s",
                source.c_str(), inside.c_str(), outside.c_str());

    if (source != inside && source != outside)
        die("At least one of the split destinations should be the same as source: %s into %s %s",
                source.c_str(), inside.c_str(), outside.c_str());

    if (belongingCheckerMap.find(checkerName) == belongingCheckerMap.end())
        die("No such belonging checker: %s", checkerName.c_str());

    if (getPVbyName(inside) != nullptr && inside != source)
        die("Cannot split into existing particle vector: %s into %s %s",
                source.c_str(), inside.c_str(), outside.c_str());

    if (getPVbyName(outside) != nullptr && outside != source)
        die("Cannot split into existing particle vector: %s into %s %s",
                source.c_str(), inside.c_str(), outside.c_str());


    auto checker = belongingCheckerMap[checkerName].get();

    std::shared_ptr<ParticleVector> pvInside, pvOutside;

    if (inside != "none" && getPVbyName(inside) == nullptr)
    {
        pvInside = std::make_shared<ParticleVector> (state, inside, pvSource->mass);
        registerParticleVector(pvInside, nullptr, checkpointEvery);
    }

    if (outside != "none" && getPVbyName(outside) == nullptr)
    {
        pvOutside = std::make_shared<ParticleVector> (state, outside, pvSource->mass);
        registerParticleVector(pvOutside, nullptr, checkpointEvery);
    }

    splitterPrototypes.push_back({checker, pvSource, getPVbyName(inside), getPVbyName(outside)});

    belongingCorrectionPrototypes.push_back({checker, getPVbyName(inside), getPVbyName(outside), checkEvery});
}

static void sortDescendingOrder(std::vector<float>& v)
{
    std::sort(v.begin(), v.end(), [] (float a, float b) { return a > b; });
}

// assume sorted array (ascending or descending)
static void removeDuplicatedElements(std::vector<float>& v, float tolerance)
{
    auto it = std::unique(v.begin(), v.end(), [=] (float a, float b) { return fabs(a - b) < tolerance; });
    v.resize( std::distance(v.begin(), it) );    
}

void Simulation::prepareCellLists()
{
    info("Preparing cell-lists");

    std::map<ParticleVector*, std::vector<float>> cutOffMap;

    // Deal with the cell-lists and interactions
    for (auto prototype : interactionPrototypes)
    {
        float rc = prototype.rc;
        cutOffMap[prototype.pv1].push_back(rc);
        cutOffMap[prototype.pv2].push_back(rc);
    }

    for (auto& cutoffPair : cutOffMap)
    {
        auto& pv      = cutoffPair.first;
        auto& cutoffs = cutoffPair.second;

        sortDescendingOrder(cutoffs);
        removeDuplicatedElements(cutoffs, rcTolerance);

        bool primary = true;

        // Don't use primary cell-lists with ObjectVectors
        if (dynamic_cast<ObjectVector*>(pv) != nullptr)
            primary = false;

        for (auto rc : cutoffs)
        {
            cellListMap[pv].push_back(primary ?
                    std::make_unique<PrimaryCellList>(pv, rc, state->domain.localSize) :
                    std::make_unique<CellList>       (pv, rc, state->domain.localSize));
            primary = false;
        }
    }

    for (auto& pv : particleVectors)
    {
        auto pvptr = pv.get();
        if (cellListMap[pvptr].empty())
        {
            const float defaultRc = 1.f;
            bool primary = true;

            // Don't use primary cell-lists with ObjectVectors
            if (dynamic_cast<ObjectVector*>(pvptr) != nullptr)
                primary = false;

            cellListMap[pvptr].push_back
                (primary ?
                 std::make_unique<PrimaryCellList>(pvptr, defaultRc, state->domain.localSize) :
                 std::make_unique<CellList>       (pvptr, defaultRc, state->domain.localSize));
        }
    }
}

// Choose a CL with smallest but bigger than rc cell
static CellList* selectBestClist(std::vector<std::unique_ptr<CellList>>& cellLists, float rc, float tolerance)
{
    float minDiff = 1e6;
    CellList* best = nullptr;
    
    for (auto& cl : cellLists) {
        float diff = cl->rc - rc;
        if (diff > -tolerance && diff < minDiff) {
            best    = cl.get();
            minDiff = diff;
        }
    }
    return best;
}

void Simulation::prepareInteractions()
{
    info("Preparing interactions");

    for (auto& prototype : interactionPrototypes)
    {
        auto  rc = prototype.rc;
        auto pv1 = prototype.pv1;
        auto pv2 = prototype.pv2;

        auto& clVec1 = cellListMap[pv1];
        auto& clVec2 = cellListMap[pv2];

        CellList *cl1, *cl2;

        cl1 = selectBestClist(clVec1, rc, rcTolerance);
        cl2 = selectBestClist(clVec2, rc, rcTolerance);
        
        auto inter = prototype.interaction;

        inter->setPrerequisites(pv1, pv2, cl1, cl2);

        interactionManager->add(inter, pv1, pv2, cl1, cl2);
    }
}

void Simulation::prepareBouncers()
{
    info("Preparing object bouncers");

    for (auto& prototype : bouncerPrototypes)
    {
        auto bouncer = prototype.bouncer;
        auto pv      = prototype.pv;

        if (pvsIntegratorMap.find(pv->name) == pvsIntegratorMap.end())
            die("Setting bouncer '%s': particle vector '%s' has no integrator, required for bounce back",
                bouncer->name.c_str(), pv->name.c_str());
        
        auto& clVec = cellListMap[pv];

        if (clVec.empty()) continue;

        CellList *cl = clVec[0].get();

        regularBouncers.push_back([bouncer, pv, cl] (cudaStream_t stream) {
            bouncer->bounceLocal(pv, cl, stream);
        });

        haloBouncers.   push_back([bouncer, pv, cl] (cudaStream_t stream) {
            bouncer->bounceHalo (pv, cl, stream);
        });
    }
}

void Simulation::prepareWalls()
{
    info("Preparing walls");

    for (auto& prototype : wallPrototypes)
    {
        auto wall = prototype.wall;
        auto pv   = prototype.pv;

        auto& clVec = cellListMap[pv];

        if (clVec.empty()) continue;

        CellList *cl = clVec[0].get();

        wall->attach(pv, cl);
    }

    for (auto& wall : wallMap)
    {
        auto wallPtr = wall.second.get();

        // All the particles should be removed from within the wall,
        // even those that do not interact with it
        // Only frozen wall particles will remain
        for (auto& anypv : particleVectors)
            wallPtr->removeInner(anypv.get());
    }
}

void Simulation::preparePlugins()
{
    info("Preparing plugins");
    for (auto& pl : plugins) {
        debug("Setup and handshake of plugin %s", pl->name.c_str());
        pl->setup(this, cartComm, interComm);
        pl->handshake();
    }
    info("done Preparing plugins");
}


void Simulation::prepareEngines()
{
    auto redistImp              = std::make_unique<ParticleRedistributor>();
    auto haloImp                = std::make_unique<ParticleHaloExchanger>();
    auto haloIntermediateImp    = std::make_unique<ParticleHaloExchanger>();
    auto objRedistImp           = std::make_unique<ObjectRedistributor>();
    auto objHaloImp             = std::make_unique<ObjectHaloExchanger>();
    auto objHaloIntermediateImp = std::make_unique<ObjectHaloExchanger>();
    auto objForcesImp           = std::make_unique<ObjectForcesReverseExchanger>(objHaloImp.get());

    debug("Attaching particle vectors to halo exchanger and redistributor");
    for (auto& pv : particleVectors)
    {
        auto  pvPtr       = pv.get();
        auto& cellListVec = cellListMap[pvPtr];        

        if (cellListVec.size() == 0) continue;

        CellList *clInt = interactionManager->getLargestCellListNeededForIntermediate(pvPtr);
        CellList *clOut = interactionManager->getLargestCellListNeededForFinal(pvPtr);

        auto extraInt = interactionManager->getExtraIntermediateChannels(pvPtr);
        // auto extraOut = interactionManager->getExtraFinalChannels(pvPtr); // TODO: for reverse exchanger

        auto cl = cellListVec[0].get();
        auto ov = dynamic_cast<ObjectVector*>(pvPtr);
        
        if (ov == nullptr) {
            redistImp->attach(pvPtr, cl);
            
            if (clInt != nullptr)
                haloIntermediateImp->attach(pvPtr, clInt, {});

            if (clOut != nullptr)
                haloImp->attach(pvPtr, clOut, extraInt);            
        }
        else {
            objRedistImp->attach(ov);

            if (clInt != nullptr)
                objHaloIntermediateImp->attach(ov, clInt->rc, {});

            auto extraToExchange = extraInt;
            
            for (auto& entry : bouncerMap)
            {
                auto& bouncer = entry.second;
                if (bouncer->getObjectVector() == ov)
                {
                    auto extraChannels = bouncer->getChannelsToBeExchanged();
                    std::copy(extraChannels.begin(), extraChannels.end(),
                              std::back_inserter(extraToExchange));
                }
            }

            objHaloImp  ->attach(ov, cl->rc, extraToExchange); // always active because of bounce back; TODO: check if bounce back is active
            objForcesImp->attach(ov);
        }
    }
    
    std::function< std::unique_ptr<ExchangeEngine>(std::unique_ptr<ParticleExchanger>) > makeEngine;
    
    // If we're on one node, use a singleNode engine
    // otherwise use MPI
    if (nranks3D.x * nranks3D.y * nranks3D.z == 1)
        makeEngine = [this] (std::unique_ptr<ParticleExchanger> exch) {
            return std::make_unique<SingleNodeEngine> (std::move(exch));
        };
    else
        makeEngine = [this] (std::unique_ptr<ParticleExchanger> exch) {
            return std::make_unique<MPIExchangeEngine> (std::move(exch), cartComm, gpuAwareMPI);
        };
    
    redistributor       = makeEngine(std::move(redistImp));
    halo                = makeEngine(std::move(haloImp));
    haloIntermediate    = makeEngine(std::move(haloIntermediateImp));
    objRedistibutor     = makeEngine(std::move(objRedistImp));
    objHalo             = makeEngine(std::move(objHaloImp));
    objHaloIntermediate = makeEngine(std::move(objHaloIntermediateImp));
    objHaloForces       = makeEngine(std::move(objForcesImp));
}

void Simulation::execSplitters()
{
    info("Splitting particle vectors with respect to object belonging");

    for (auto& prototype : splitterPrototypes)
    {
        auto checker = prototype.checker;
        auto src     = prototype.pvSrc;
        auto inside  = prototype.pvIn;
        auto outside = prototype.pvOut;

        checker->splitByBelonging(src, inside, outside, 0);
    }
}

void Simulation::init()
{
    info("Simulation initiated");

    prepareCellLists();

    prepareInteractions();
    prepareBouncers();
    prepareWalls();

    interactionManager->check();

    CUDA_Check( cudaDeviceSynchronize() );

    preparePlugins();
    prepareEngines();

    assemble();
    
    // Initial preparation
    scheduler->forceExec( tasks->objHaloInit, 0 );
    scheduler->forceExec( tasks->objHaloFinalize, 0 );
    scheduler->forceExec( tasks->clearObjHaloForces, 0 );
    scheduler->forceExec( tasks->clearObjLocalForces, 0 );

    execSplitters();
}

void Simulation::assemble()
{    
    info("Time-step is set to %f", getCurrentDt());

#define INIT(NAME, DESC) tasks -> NAME = scheduler->createTask(DESC);
    TASK_LIST(INIT);
#undef INIT

    if (globalCheckpointEvery > 0)
        scheduler->addTask(tasks->checkpoint,
                           [this](cudaStream_t stream) { this->checkpoint(); },
                           globalCheckpointEvery);

    for (auto prototype : pvsCheckPointPrototype)
        if (prototype.checkpointEvery > 0 && globalCheckpointEvery == 0) {
            info("Will save checkpoint of particle vector '%s' every %d timesteps",
                 prototype.pv->name.c_str(), prototype.checkpointEvery);

            scheduler->addTask( tasks->checkpoint, [prototype, this] (cudaStream_t stream) {
                prototype.pv->checkpoint(cartComm, checkpointFolder);
            }, prototype.checkpointEvery );
        }


    for (auto& clVec : cellListMap)
        for (auto& cl : clVec.second)
        {
            auto clPtr = cl.get();
            scheduler->addTask(tasks->cellLists, [clPtr] (cudaStream_t stream) { clPtr->build(stream); } );
        }

    // Only particle forces, not object ones here
    for (auto& pv : particleVectors)
    {
        auto pvPtr = pv.get();
        scheduler->addTask(tasks->clearFinalOutput,
                           [this, pvPtr] (cudaStream_t stream) { interactionManager->clearIntermediates(pvPtr, stream); } );
        scheduler->addTask(tasks->clearIntermediate,
                           [this, pvPtr] (cudaStream_t stream) { interactionManager->clearFinal(pvPtr, stream); } );
    }

    for (auto& pl : plugins)
    {
        auto plPtr = pl.get();

        scheduler->addTask(tasks->pluginsBeforeCellLists, [plPtr, this] (cudaStream_t stream) {
            plPtr->beforeCellLists(stream);
        });

        scheduler->addTask(tasks->pluginsBeforeForces, [plPtr, this] (cudaStream_t stream) {
            plPtr->beforeForces(stream);
        });

        scheduler->addTask(tasks->pluginsSerializeSend, [plPtr] (cudaStream_t stream) {
            plPtr->serializeAndSend(stream);
        });

        scheduler->addTask(tasks->pluginsBeforeIntegration, [plPtr] (cudaStream_t stream) {
            plPtr->beforeIntegration(stream);
        });

        scheduler->addTask(tasks->pluginsAfterIntegration, [plPtr] (cudaStream_t stream) {
            plPtr->afterIntegration(stream);
        });

        scheduler->addTask(tasks->pluginsBeforeParticlesDistribution, [plPtr] (cudaStream_t stream) {
            plPtr->beforeParticleDistribution(stream);
        });
    }


    // If we have any non-object vectors
    if (particleVectors.size() != objectVectors.size())
    {
        scheduler->addTask(tasks->haloIntermediateInit, [this] (cudaStream_t stream) {
            haloIntermediate->init(stream);
        });

        scheduler->addTask(tasks->haloIntermediateFinalize, [this] (cudaStream_t stream) {
            haloIntermediate->finalize(stream);
        });

        scheduler->addTask(tasks->haloInit, [this] (cudaStream_t stream) {
            halo->init(stream);
        });

        scheduler->addTask(tasks->haloFinalize, [this] (cudaStream_t stream) {
            halo->finalize(stream);
        });

        scheduler->addTask(tasks->redistributeInit, [this] (cudaStream_t stream) {
            redistributor->init(stream);
        });

        scheduler->addTask(tasks->redistributeFinalize, [this] (cudaStream_t stream) {
            redistributor->finalize(stream);
        });
    }


    scheduler->addTask(tasks->localIntermediate,
                       [this] (cudaStream_t stream) {
                           interactionManager->executeLocalIntermediate(stream);
                       });

    scheduler->addTask(tasks->haloIntermediate,
                       [this] (cudaStream_t stream) {
                           interactionManager->executeHaloIntermediate(stream);
                       });

    scheduler->addTask(tasks->localForces,
                       [this] (cudaStream_t stream) {
                           interactionManager->executeLocalFinal(stream);
                       });

    scheduler->addTask(tasks->haloForces,
                       [this] (cudaStream_t stream) {
                           interactionManager->executeHaloFinal(stream);
                       });
    

    scheduler->addTask(tasks->gatherInteractionIntermediate,
                       [this] (cudaStream_t stream) {
                           interactionManager->gatherIntermediate(stream);
                       });

    scheduler->addTask(tasks->accumulateInteractionIntermediate,
                       [this] (cudaStream_t stream) {
                           interactionManager->accumulateIntermediates(stream);
                       });
            
    scheduler->addTask(tasks->accumulateInteractionFinal,
                       [this] (cudaStream_t stream) {
                           interactionManager->accumulateFinal(stream);
                       });


    for (auto& integrator : integratorsStage2)
        scheduler->addTask(tasks->integration, [integrator, this] (cudaStream_t stream) {
            integrator(stream);
        });


    for (auto ov : objectVectors)
        scheduler->addTask(tasks->clearObjHaloForces, [ov] (cudaStream_t stream) {
            ov->halo()->forces.clear(stream);
        });

    // As there are no primary cell-lists for objects
    // we need to separately clear real obj forces and forces in the cell-lists
    for (auto ovPtr : objectVectors)
    {
        scheduler->addTask(tasks->clearObjLocalForces, [ovPtr] (cudaStream_t stream) {
            ovPtr->local()->forces.clear(stream);
        });

        scheduler->addTask(tasks->clearObjLocalForces,
                           [this, ovPtr] (cudaStream_t stream) {
                               interactionManager->clearFinal(ovPtr, stream);
                           });
    }

    for (auto& bouncer : regularBouncers)
        scheduler->addTask(tasks->objLocalBounce, [bouncer, this] (cudaStream_t stream) {
            bouncer(stream);
    });

    for (auto& bouncer : haloBouncers)
        scheduler->addTask(tasks->objHaloBounce, [bouncer, this] (cudaStream_t stream) {
            bouncer(stream);
    });

    for (auto& prototype : belongingCorrectionPrototypes)
    {
        auto checker = prototype.checker;
        auto pvIn    = prototype.pvIn;
        auto pvOut   = prototype.pvOut;
        auto every   = prototype.every;

        if (every > 0)
        {
            scheduler->addTask(tasks->correctObjBelonging, [checker, pvIn, pvOut] (cudaStream_t stream) {
                if (pvIn  != nullptr) checker->splitByBelonging(pvIn,  pvIn, pvOut, stream);
                if (pvOut != nullptr) checker->splitByBelonging(pvOut, pvIn, pvOut, stream);
            }, every);
        }
    }

    if (objectVectors.size() > 0)
    {
        scheduler->addTask(tasks->objHaloInit, [this] (cudaStream_t stream) {
            objHalo->init(stream);
        });

        scheduler->addTask(tasks->objHaloFinalize, [this] (cudaStream_t stream) {
            objHalo->finalize(stream);
        });

        scheduler->addTask(tasks->objForcesInit, [this] (cudaStream_t stream) {
            objHaloForces->init(stream);
        });

        scheduler->addTask(tasks->objForcesFinalize, [this] (cudaStream_t stream) {
            objHaloForces->finalize(stream);
        });

        scheduler->addTask(tasks->objRedistInit, [this] (cudaStream_t stream) {
            objRedistibutor->init(stream);
        });

        scheduler->addTask(tasks->objRedistFinalize, [this] (cudaStream_t stream) {
            objRedistibutor->finalize(stream);
        });
    }

    for (auto& wall : wallMap)
    {
        auto wallPtr = wall.second.get();
        scheduler->addTask(tasks->wallBounce, [wallPtr, this] (cudaStream_t stream) {    
            wallPtr->bounce(stream);
        });
    }

    for (auto& prototype : checkWallPrototypes)
    {
        auto wall  = prototype.wall;
        auto every = prototype.every;

        if (every > 0)
            scheduler->addTask(tasks->wallCheck, [this, wall] (cudaStream_t stream) { wall->check(stream); }, every);
    }
    
    scheduler->addDependency(tasks->pluginsBeforeCellLists, { tasks->cellLists }, {});
    
    scheduler->addDependency(tasks->checkpoint, { tasks->clearFinalOutput }, { tasks->cellLists });

    scheduler->addDependency(tasks->correctObjBelonging, { tasks->cellLists }, {});

    scheduler->addDependency(tasks->cellLists, {tasks->clearFinalOutput, tasks->clearIntermediate}, {});

    
    scheduler->addDependency(tasks->pluginsBeforeForces, {tasks->localForces, tasks->haloForces}, {tasks->clearFinalOutput});
    scheduler->addDependency(tasks->pluginsSerializeSend, {tasks->pluginsBeforeIntegration, tasks->pluginsAfterIntegration}, {tasks->pluginsBeforeForces});

    scheduler->addDependency(tasks->clearObjHaloForces, {tasks->objHaloBounce}, {tasks->objHaloFinalize});

    scheduler->addDependency(tasks->objForcesInit, {}, {tasks->haloForces});
    scheduler->addDependency(tasks->objForcesFinalize, {tasks->accumulateInteractionFinal}, {tasks->objForcesInit});

    scheduler->addDependency(tasks->localIntermediate, {}, {tasks->clearIntermediate});
    scheduler->addDependency(tasks->haloIntermediateInit, {}, {tasks->clearIntermediate, tasks->cellLists});
    scheduler->addDependency(tasks->haloIntermediateFinalize, {}, {tasks->haloIntermediateInit});
    scheduler->addDependency(tasks->haloIntermediate, {}, {tasks->haloIntermediateFinalize});
    scheduler->addDependency(tasks->accumulateInteractionIntermediate, {}, {tasks->localIntermediate, tasks->haloIntermediate});
    scheduler->addDependency(tasks->gatherInteractionIntermediate, {}, {tasks->accumulateInteractionIntermediate});

    scheduler->addDependency(tasks->localForces, {}, {tasks->gatherInteractionIntermediate});
    scheduler->addDependency(tasks->haloInit, {}, {tasks->pluginsBeforeForces, tasks->gatherInteractionIntermediate, tasks->cellLists});
    scheduler->addDependency(tasks->haloFinalize, {}, {tasks->haloInit});
    scheduler->addDependency(tasks->haloForces, {}, {tasks->haloFinalize});
    scheduler->addDependency(tasks->accumulateInteractionFinal, {tasks->integration}, {tasks->haloForces, tasks->localForces});

    scheduler->addDependency(tasks->pluginsBeforeIntegration, {tasks->integration}, {tasks->accumulateInteractionFinal});
    scheduler->addDependency(tasks->wallBounce, {}, {tasks->integration});
    scheduler->addDependency(tasks->wallCheck, {tasks->redistributeInit}, {tasks->wallBounce});

    scheduler->addDependency(tasks->objHaloInit, {}, {tasks->integration, tasks->objRedistFinalize});
    scheduler->addDependency(tasks->objHaloFinalize, {}, {tasks->objHaloInit});

    scheduler->addDependency(tasks->objLocalBounce, {tasks->objHaloFinalize}, {tasks->integration, tasks->clearObjLocalForces});
    scheduler->addDependency(tasks->objHaloBounce, {}, {tasks->integration, tasks->objHaloFinalize, tasks->clearObjHaloForces});

    scheduler->addDependency(tasks->pluginsAfterIntegration, {tasks->objLocalBounce, tasks->objHaloBounce}, {tasks->integration, tasks->wallBounce});

    scheduler->addDependency(tasks->pluginsBeforeParticlesDistribution, {},
                             {tasks->integration, tasks->wallBounce, tasks->objLocalBounce, tasks->objHaloBounce, tasks->pluginsAfterIntegration});
    scheduler->addDependency(tasks->redistributeInit, {}, {tasks->pluginsBeforeParticlesDistribution});
    scheduler->addDependency(tasks->redistributeFinalize, {}, {tasks->redistributeInit});

    scheduler->addDependency(tasks->objRedistInit, {}, {tasks->integration, tasks->wallBounce, tasks->objForcesFinalize, tasks->pluginsAfterIntegration});
    scheduler->addDependency(tasks->objRedistFinalize, {}, {tasks->objRedistInit});
    scheduler->addDependency(tasks->clearObjLocalForces, {tasks->objLocalBounce}, {tasks->integration, tasks->objRedistFinalize});

    scheduler->setHighPriority(tasks->objForcesInit);
    scheduler->setHighPriority(tasks->haloIntermediateInit);
    scheduler->setHighPriority(tasks->haloIntermediateFinalize);
    scheduler->setHighPriority(tasks->haloIntermediate);
    scheduler->setHighPriority(tasks->haloInit);
    scheduler->setHighPriority(tasks->haloFinalize);
    scheduler->setHighPriority(tasks->haloForces);
    scheduler->setHighPriority(tasks->pluginsSerializeSend);

    scheduler->setHighPriority(tasks->clearObjLocalForces);
    scheduler->setHighPriority(tasks->objLocalBounce);
    
    scheduler->compile();
}

void Simulation::run(int nsteps)
{
    int begin = state->currentStep, end = state->currentStep + nsteps;

    info("Will run %d iterations now", nsteps);


    for (state->currentStep = begin; state->currentStep < end; state->currentStep++)
    {
        debug("===============================================================================\n"
                "Timestep: %d, simulation time: %f", state->currentStep, state->currentTime);

        scheduler->run();
        
        state->currentTime += state->dt;
    }

    // Finish the redistribution by rebuilding the cell-lists
    scheduler->forceExec( tasks->cellLists, 0 );

    info("Finished with %d iterations", nsteps);
    MPI_Check( MPI_Barrier(cartComm) );

    for (auto& pl : plugins)
        pl->finalize();

    if (interComm != MPI_COMM_NULL)
    {
        int dummy = -1;
        int tag = 424242;

        MPI_Check( MPI_Send(&dummy, 1, MPI_INT, rank, tag, interComm) );
        debug("Sending stopping message to the postprocess");
    }
}


void Simulation::restart(std::string folder)
{
    bool beginning =  particleVectors    .empty() &&
                      wallMap            .empty() &&
                      interactionMap     .empty() &&
                      integratorMap      .empty() &&
                      bouncerMap         .empty() &&
                      belongingCheckerMap.empty() &&
                      plugins            .empty();
    
    if (!beginning)
        die("Tried to restart partially initialized simulation! Please only call restart() before registering anything");
                      
    restartStatus = RestartStatus::RestartStrict;
    restartFolder = folder;
    
    TextIO::read(folder + "_simulation.state", state->currentTime, state->currentStep);
}

void Simulation::checkpoint()
{
    if (rank == 0)
        TextIO::write(checkpointFolder + "_simulation.state", state->currentTime, state->currentStep);

    CUDA_Check( cudaDeviceSynchronize() );
    
    info("Writing simulation state, into folder %s", checkpointFolder.c_str());
        
    for (auto& pv : particleVectors)
        pv->checkpoint(cartComm, checkpointFolder);
    
    for (auto& handler : bouncerMap)
        handler.second->checkpoint(cartComm, checkpointFolder);
    
    for (auto& handler : integratorMap)
        handler.second->checkpoint(cartComm, checkpointFolder);
    
    for (auto& handler : interactionMap)
        handler.second->checkpoint(cartComm, checkpointFolder);
    
    for (auto& handler : wallMap)
        handler.second->checkpoint(cartComm, checkpointFolder);
    
    for (auto& handler : belongingCheckerMap)
        handler.second->checkpoint(cartComm, checkpointFolder);
    
    for (auto& handler : plugins)
        handler->checkpoint(cartComm, checkpointFolder);
    
    CUDA_Check( cudaDeviceSynchronize() );
}





