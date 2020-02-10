#pragma once

#include "interface.h"

#include <mirheo/core/containers.h>
#include <mirheo/core/datatypes.h>

#include <vector>

namespace mirheo
{

class Interaction;

class IntegratorSubStep : public Integrator
{
public:
    IntegratorSubStep(const MirState *state, const std::string& name, int substeps,
                      const std::vector<Interaction*>& fastForces);
    ~IntegratorSubStep();
    void saveSnapshotAndRegister(Saver&) override;

    void stage1(ParticleVector *pv, cudaStream_t stream) override;
    void stage2(ParticleVector *pv, cudaStream_t stream) override;

    void setPrerequisites(ParticleVector *pv) override;

protected:
    ConfigObject _saveSnapshot(Saver&, const std::string& typeName);

private:
    std::vector<Interaction*> fastForces_; /* interactions (self) called `substeps` times per time step */
    std::unique_ptr<Integrator> subIntegrator_;
    MirState subState_;
    
    int substeps_; /* number of substeps */
    DeviceBuffer<Force> slowForces_ {};
    DeviceBuffer<real4> previousPositions_ {};

    void updateSubState_();
};

} // namespace mirheo
