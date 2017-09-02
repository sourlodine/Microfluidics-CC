#include <core/dpd-rng.h>
#include <core/particle_vector.h>
#include <core/interaction_engine.h>
#include <core/helper_math.h>
#include <core/interactions.h>
#include <core/cuda_common.h>
#include <core/object_vector.h>
#include <core/rbc_vector.h>

//==================================================================================================================
// Interaction wrapper macro
//==================================================================================================================

#define WRAP_INTERACTON(INTERACTION_FUNCTION)                                                                                                                         \
	if (type == InteractionType::Regular)                                                                                                                             \
	{                                                                                                                                                                 \
		/*  Self interaction */                                                                                                                                       \
		if (pv1 == pv2)                                                                                                                                               \
		{                                                                                                                                                             \
			debug2("Computing internal forces for %s (%d particles)", pv1->name.c_str(), pv1->local()->size());                                                       \
                                                                                                                                                                      \
			const int nth = 128;                                                                                                                                      \
			if (pv1->local()->size() > 0)                                                                                                                             \
				computeSelfInteractions<<< (pv1->local()->size() + nth - 1) / nth, nth, 0, stream >>>(                                                                \
						pv1->local()->size(), (float4*)cl->coosvels->devPtr(), (float*)cl->forces->devPtr(),                                                          \
						cl->cellInfo(), cl->cellsStartSize.devPtr(), rc*rc, INTERACTION_FUNCTION);                                                                    \
		}                                                                                                                                                             \
		else /*  External interaction */                                                                                                                              \
		{                                                                                                                                                             \
			debug2("Computing external forces for %s - %s (%d - %d particles)", pv1->name.c_str(), pv2->name.c_str(), pv1->local()->size(), pv2->local()->size());    \
                                                                                                                                                                      \
			const int nth = 128;                                                                                                                                      \
			if (pv1->local()->size() > 0 && pv2->local()->size() > 0)                                                                                                 \
				computeExternalInteractions<true, true, true> <<< (pv2->local()->size() + nth - 1) / nth, nth, 0, stream >>>(                                         \
						pv2->local()->size(),                                                                                                                         \
						(float4*)pv2->local()->coosvels.devPtr(), (float*)pv2->local()->forces.devPtr(),                                                              \
						(float4*)cl->coosvels->devPtr(), (float*)cl->forces->devPtr(),                                                                                \
						cl->cellInfo(), cl->cellsStartSize.devPtr(),                                                                                                  \
						rc*rc, INTERACTION_FUNCTION);                                                                                                                 \
		}                                                                                                                                                             \
	}                                                                                                                                                                 \
                                                                                                                                                                      \
	/*  Halo interaction */                                                                                                                                           \
	if (type == InteractionType::Halo)                                                                                                                                \
	{                                                                                                                                                                 \
		debug2("Computing halo forces for %s - %s(halo) (%d - %d particles)", pv1->name.c_str(), pv2->name.c_str(), pv1->local()->size(), pv2->halo()->size());       \
                                                                                                                                                                      \
		const int nth = 128;                                                                                                                                          \
		if (pv1->local()->size() > 0 && pv2->halo()->size() > 0)                                                                                                      \
			computeExternalInteractions<false, true, false> <<< (pv2->halo()->size() + nth - 1) / nth, nth, 0, stream >>>(                                            \
					pv2->halo()->size(),                                                                                                                              \
					(float4*)pv2->halo()->coosvels.devPtr(), nullptr,                                                                                                 \
					(float4*)cl->coosvels->devPtr(), (float*)cl->forces->devPtr(),                                                                                    \
					cl->cellInfo(), cl->cellsStartSize.devPtr(),                                                                                                      \
					rc*rc, INTERACTION_FUNCTION);                                                                                                                     \
	}


//==================================================================================================================
// DPD interactions
//==================================================================================================================

inline __device__ float viscosityKernel(const float x, const float k)
{
	if (fabs(k - 1.0f)   < 1e-6f) return x;
	if (fabs(k - 0.5f)   < 1e-6f) return sqrtf(fabs(x));
	if (fabs(k - 0.25f)  < 1e-6f) return sqrtf(fabs(sqrtf(fabs(x))));
	if (fabs(k - 0.125f) < 1e-6f) return sqrtf(fabs(sqrtf(fabs(sqrtf(fabs(x))))));

    return powf(fabs(x), k);
}

__device__ __forceinline__ float3 pairwiseDPD(
		Particle dst, Particle src,
		const float adpd, const float gammadpd, const float sigmadpd,
		const float rc2, const float invrc, const float k, const float seed)
{
	const float3 dr = dst.r - src.r;
	const float rij2 = dot(dr, dr);
	if (rij2 > rc2) return make_float3(0.0f);

	const float invrij = rsqrtf(max(rij2, 1e-20f));
	const float rij = rij2 * invrij;
	const float argwr = 1.0f - rij*invrc;
	const float wr = viscosityKernel(argwr, k);

	const float3 dr_r = dr * invrij;
	const float3 du = dst.u - src.u;
	const float rdotv = dot(dr_r, du);

	const float myrandnr = Logistic::mean0var1(seed, min(src.i1, dst.i1), max(src.i1, dst.i1));

	const float strength = adpd * argwr - (gammadpd * wr * rdotv + sigmadpd * myrandnr) * wr;

	return dr_r * strength;
}


//==================================================================================================================
// LJ interactions
//==================================================================================================================

__device__ inline float3 pairwiseLJ(Particle dst, Particle src, const float sigma, const float epsx24_sigma, const float rc2)
{
	const float3 dr = dst.r - src.r;
	const float rij2 = dot(dr, dr);

	if (rij2 > rc2) return make_float3(0.0f);

	const float rs2 = sigma*sigma / rij2;
	const float rs4 = rs2*rs2;
	const float rs8 = rs4*rs4;
	const float rs14 = rs8*rs4*rs2;

	return dr * epsx24_sigma * (2*rs14 - rs8);
}

__device__ inline float3 pairwiseLJ_objectAware(Particle dst, Particle src,
		bool isDstObj, float3 dstCom,
		bool isSrcObj, float3 srcCom,
		const float sigma, const float epsx24_sigma, const float rc2)
{
	const float3 dr = dst.r - src.r;

	const bool dstSide = dot(dr, dst.r-dstCom) < 0.0f;
	const bool srcSide = dot(dr, srcCom-src.r) < 0.0f;

	if (dstSide && (!isSrcObj)) return make_float3(0.0f);
	if ((!isDstObj) && srcSide) return make_float3(0.0f);
	if (dstSide && srcSide)     return make_float3(0.0f);

	return pairwiseLJ(dst, src, sigma, epsx24_sigma, rc2);
}

//==================================================================================================================
//==================================================================================================================


/**
 * Regular DPD interaction
 */
InteractionDPD::InteractionDPD(pugi::xml_node node)
{
	name = node.attribute("name").as_string("");
	rc   = node.attribute("rc").as_float(1.0f);

	power = node.attribute("power").as_float(1.0f);
	a     = node.attribute("a")    .as_float(50);
	gamma = node.attribute("gamma").as_float(20);

	const float dt  = node.attribute("dt") .as_float(0.01);
	const float kBT = node.attribute("kbt").as_float(1.0);

	sigma = sqrt(2 * gamma * kBT / dt);
}

void InteractionDPD::_compute(InteractionType type, ParticleVector* pv1, ParticleVector* pv2, CellList* cl, const float t, cudaStream_t stream)
{
	// Better to use random number in the seed instead of periodically changing time
	const float seed = drand48();
	const float rc2 = rc*rc;
	const float rc_1 = 1.0 / rc;
	auto dpdCore = [=, *this] __device__ ( Particle dst, Particle src ) {
		return pairwiseDPD( dst, src, a, gamma, sigma, rc2, rc_1, power, seed);
	};

	WRAP_INTERACTON(dpdCore)
}

/**
 * LJ interaction, to prevent overlap of the rigid objects
 */
InteractionLJ_objectAware::InteractionLJ_objectAware(pugi::xml_node node)
{
	name = node.attribute("name").as_string("");
	rc   = node.attribute("rc").as_float(1.0f);

	epsilon = node.attribute("power").as_float(10.0f);
	sigma   = node.attribute("a")    .as_float(0.5f);
}

void InteractionLJ_objectAware::_compute(InteractionType type, ParticleVector* pv1, ParticleVector* pv2, CellList* cl, const float t, cudaStream_t stream)
{
	auto ov1 = dynamic_cast<ObjectVector*>(pv1);
	auto ov2 = dynamic_cast<ObjectVector*>(pv2);
	if (ov1 == nullptr && ov2 == nullptr)
		die("Object-aware LJ interaction can only be used with objects");

	const float epsx24_sigma = 24.0*epsilon/sigma;
	const float rc2 = rc*rc;
	const bool self = (pv1 == pv2);

	const LocalObjectVector::COMandExtent* dstComExt = (ov1 != nullptr) ? ov1->local()->comAndExtents.devPtr() : nullptr;
	const LocalObjectVector::COMandExtent* srcComExt = (ov2 != nullptr) ? ov2->local()->comAndExtents.devPtr() : nullptr;

	auto ljCore = [=, *this] __device__ ( Particle dst, Particle src ) {
		const int dstObjId = dst.s21;
		const int srcObjId = src.s21;

		if (dstObjId == srcObjId && self) return make_float3(0.0f);

		float3 dstCom = make_float3(0.0f);
		float3 srcCom = make_float3(0.0f);
		if (dstComExt != nullptr) dstCom = dstComExt[dstObjId].com;
		if (srcComExt != nullptr) srcCom = srcComExt[srcObjId].com;

		return pairwiseLJ_objectAware( dst, src, (dstComExt != nullptr), dstCom, (srcComExt != nullptr), srcCom, sigma, epsx24_sigma, rc2);
	};

	WRAP_INTERACTON(ljCore)
}


void InteractionRBCMembrane::_compute(InteractionType type, ParticleVector* pv1, ParticleVector* pv2, CellList* cl, const float t, cudaStream_t stream)
{
	if (pv1 != pv2)
		die("Internal RBC forces can't be computed between two different particle vectors");

	auto rbcv = dynamic_cast<RBCvector*>(pv1);
	if (rbcv == nullptr)
		die("Internal RBC forces can only be computed with RBC object vector");

	int nthreads = 128;
	int nRbcs  = rbcv->local()->nObjects;
	int nVerts = rbcv->mesh.nvertices;


	dim3 avThreads(256, 1);
	dim3 avBlocks( 1, nRbcs );
//	computeAreaAndVolume <<< avBlocks, avThreads, 0, stream >>> (
//			(float4*)rbcv->local()->coosvels.devPtr(), rbcv->local()->mesh, nRbcs,
//			rbcv->local()->areas.devPtr(), rbcv->local()->volumes.devPtr());

	int blocks = getNblocks(nRbcs*nVerts*rbcv->mesh.maxDegree, nthreads);

//	computeMembraneForces <<<blocks, nthreads, 0, stream>>> (
//			(float4*)rbcv->local()->coosvels.devPtr(), rbcv->local()->mesh, nRbcs,
//			rbcv->local()->areas.devPtr(), rbcv->local()->volumes.devPtr(),
//			(float4*)rbcv->local()->forces.devPtr());
}











