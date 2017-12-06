#include "pairwise.h"

#include <core/utils/cuda_common.h>
#include <core/utils/kernel_launch.h>
#include <core/celllist.h>
#include <core/pvs/particle_vector.h>
#include <core/logger.h>

#include "pairwise_kernels.h"

#include "pairwise_interactions/dpd.h"
#include "pairwise_interactions/lj.h"
#include "pairwise_interactions/lj_object_aware.h"

/**
 * Convenience macro wrapper
 *
 * Select one of the available kernels for external interaction depending
 * on the number of particles involved, report it and call
 */
#define DISPATCH_EXTERNAL(P1, P2, P3, TPP, INTERACTION_FUNCTION)                \
do{ debug2("Dispatched to "#TPP" thread(s) per particle variant");              \
	SAFE_KERNEL_LAUNCH(                                                         \
			computeExternalInteractions_##TPP##tpp<P1 COMMA P2 COMMA P3>,       \
			getNblocks(TPP*view.size, nth), nth, 0, stream,                     \
			view, cl2->cellInfo(), rc*rc, INTERACTION_FUNCTION); } while (0)

#define CHOOSE_EXTERNAL(P1, P2, P3, INTERACTION_FUNCTION)                                              \
do{  if (view.size < 1000  ) { DISPATCH_EXTERNAL(P1, P2, P3, 27, INTERACTION_FUNCTION); }              \
else if (view.size < 10000 ) { DISPATCH_EXTERNAL(P1, P2, P3, 9,  INTERACTION_FUNCTION); }              \
else if (view.size < 400000) { DISPATCH_EXTERNAL(P1, P2, P3, 3,  INTERACTION_FUNCTION); }              \
else                         { DISPATCH_EXTERNAL(P1, P2, P3, 1,  INTERACTION_FUNCTION); } } while(0)

/**
 * Compute forces between all the pairs of particles that are closer
 * than #rc to each other.
 *
 * Depending on \p type and whether \p pv1 == \p pv2 call
 * computeSelfInteractions() or computeExternalInteractions_1tpp()
 * (or other variants of external interaction kernels).
 *
 * @tparam PariwiseInteraction is a functor that computes the force
 * given a pair of particles. It has to
 * provide two functions:
 * - This function will be called once before interactions computation
 *   and allows the functor to obtain required variables or data
 *   channels from the two ParticleVector and CellList:
 *   \code setup(ParticleVector* pv1, ParticleVector* pv2, CellList* cl1, CellList* cl2, float t) \endcode
 *
 * - This should be a \c \_\_device\_\_ operator that computes
 *   the force. It will be called for each close enough particle pair:
 *   \code float3 operator()(const Particle dst, int dstId, const Particle src, int srcId) const \endcode
 *   Return value of that call is force acting on the first particle,
 *   force acting on the second one is just opposite.
 */
template<class PariwiseInteraction>
void InteractionPair<PariwiseInteraction>::_compute(InteractionType type,
		ParticleVector* pv1, ParticleVector* pv2, CellList* cl1, CellList* cl2, const float t, cudaStream_t stream)
{
	interaction.setup(pv1, pv2, cl1, cl2, t);

	if (type == InteractionType::Regular)
	{
		/*  Self interaction */
		if (pv1 == pv2)
		{
			const int np = pv1->local()->size();
			debug("Computing internal forces for %s (%d particles)", pv1->name.c_str(), np);

			const int nth = 128;

			auto cinfo = cl1->cellInfo();
			SAFE_KERNEL_LAUNCH(
					computeSelfInteractions,
					getNblocks(np, nth), nth, 0, stream,
					np, cinfo, rc*rc, interaction );
		}
		else /*  External interaction */
		{
			const int np1 = pv1->local()->size();
			const int np2 = pv2->local()->size();
			debug("Computing external forces for %s - %s (%d - %d particles)", pv1->name.c_str(), pv2->name.c_str(), np1, np2);

			PVview view(pv1, pv1->local());
			const int nth = 128;
			if (np1 > 0 && np2 > 0)
				CHOOSE_EXTERNAL(true, true, true, interaction );
		}
	}

	/*  Halo interaction */
	if (type == InteractionType::Halo)
	{
		const int np1 = pv1->halo()->size();  // note halo here
		const int np2 = pv2->local()->size();
		debug("Computing halo forces for %s(halo) - %s (%d - %d particles)", pv1->name.c_str(), pv2->name.c_str(), np1, np2);

		PVview view(pv1, pv1->halo());
		const int nth = 128;
		if (np1 > 0 && np2 > 0)
			if (dynamic_cast<ObjectVector*>(pv1) == nullptr) // don't need forces for pure particle halo
				CHOOSE_EXTERNAL(false, true, false, interaction );
			else
				CHOOSE_EXTERNAL(true,  true, false, interaction );
	}
}

template class InteractionPair<Pairwise_DPD>;
template class InteractionPair<Pairwise_LJ>;
template class InteractionPair<Pairwise_LJObjectAware>;


