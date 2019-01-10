#pragma once

#include <cuda_runtime.h>
#include <mpi.h>

#include "core/ymero_object.h"

class CellList;
class ParticleVector;

/**
 * Interface for classes computing particle interactions.
 *
 * At the moment cut-off radius is the part of the interface,
 * so every interaction will require cell-list creation.
 * The cut-off raduis has to be removed later from the interface,
 * such that only certain interactions require cell-lists.
 */
class Interaction : public YmrSimulationObject
{
public:
    /// Cut-off raduis
    float rc;

    Interaction(const YmrState *state, std::string name, float rc);

    virtual ~Interaction();

    /**
     * Ask ParticleVectors which the class will be working with to have specific properties
     * Default: ask nothing
     * Called from Simulation right after setup
     */
    virtual void setPrerequisites(ParticleVector *pv1, ParticleVector *pv2);

    /**
     * Init fields in particle vectors reuired before interaction
     * Default: do nothing
     * Called from Simulation at every step
     */
    virtual void initStep(ParticleVector *pv1, ParticleVector *pv2, cudaStream_t stream);

    /**
     * Interface to compute local interactions.
     * For now order of \e pv1 and \e pv2 is important for computational reasons,
     * this may be changed later on so that the best order is chosen automatically.
     *
     * @param pv1 first interacting ParticleVector
     * @param pv2 second interacting ParticleVector. If it is the same as
     *            the \p pv1, self interactions will be computed
     * @param cl1 cell-list built for the appropriate cut-off raduis #rc for \p pv1
     * @param cl2 cell-list built for the appropriate cut-off raduis #rc for \p pv2
     */
    virtual void regular(ParticleVector *pv1, ParticleVector *pv2,
                         CellList *cl1, CellList *cl2, cudaStream_t stream) = 0;

    /**
     * Interface to compute halo interactions. It principle it has to compute
     * pv1->halo() \<--\> pv2->local() and pv2->halo() \<--\> pv1->local().
     * See InteractionPair for more details
     *
     * @param pv1 first interacting ParticleVector
     * @param pv2 second interacting ParticleVector
     * @param cl1 cell-list built for the appropriate cut-off raduis #rc for \p pv1
     * @param cl2 cell-list built for the appropriate cut-off raduis #rc for \p pv2
     */
    virtual void halo(ParticleVector *pv1, ParticleVector *pv2, CellList *cl1,
                      CellList *cl2, cudaStream_t stream) = 0;
};
