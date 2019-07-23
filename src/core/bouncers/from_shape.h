#pragma once

#include "interface.h"

/**
 * Implements bounce-back from analytical shapes
 */
template <class Shape>
class BounceFromRigidShape : public Bouncer
{
public:

    BounceFromRigidShape(const MirState *state, std::string name);
    ~BounceFromRigidShape();

    void setup(ObjectVector *ov) override;

    void setPrerequisites(ParticleVector *pv) override;
    std::vector<std::string> getChannelsToBeExchanged() const override;
    std::vector<std::string> getChannelsToBeSentBack() const override;
    
protected:

    void exec(ParticleVector *pv, CellList *cl, bool local, cudaStream_t stream) override;
};
