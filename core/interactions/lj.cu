#include "lj.h"

#include <core/cuda_common.h>
#include <core/celllist.h>
#include <core/pvs/object_vector.h>

#include "pairwise_engine.h"
#include "wrapper_macro.h"

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



InteractionLJ::InteractionLJ(std::string name, float rc, float sigma, float epsilon) :
		Interaction(name, rc), sigma(sigma), epsilon(epsilon)
{ }

void InteractionLJ::_compute(InteractionType type, ParticleVector* pv1, ParticleVector* pv2, CellList* cl1, CellList* cl2, const float t, cudaStream_t stream)
{
	const float epsx24_sigma = 24.0*epsilon/sigma;
	const float rc2 = rc*rc;

	auto ljCore = [=, *this] __device__ ( Particle dst, Particle src ) {
		return pairwiseLJ( dst, src, sigma, epsx24_sigma, rc2);
	};

	WRAP_INTERACTON(ljCore)
}

/**
 * LJ interaction, to prevent overlap of the rigid objects
 */
InteractionLJ_objectAware::InteractionLJ_objectAware(std::string name, float rc, float sigma, float epsilon) :
		Interaction(name, rc), sigma(sigma), epsilon(epsilon)
{ }

void InteractionLJ_objectAware::_compute(InteractionType type, ParticleVector* pv1, ParticleVector* pv2, CellList* cl1, CellList* cl2, const float t, cudaStream_t stream)
{
	auto ov1 = dynamic_cast<ObjectVector*>(pv1);
	auto ov2 = dynamic_cast<ObjectVector*>(pv2);
	if (ov1 == nullptr && ov2 == nullptr)
		die("Object-aware LJ interaction can only be used with objects");

	const float epsx24_sigma = 24.0*epsilon/sigma;
	const float rc2 = rc*rc;
	const bool self = (pv1 == pv2);

	const auto view1 = create_OVview(ov1, ov1 ? ov1->local() : nullptr);
	const auto view2 = create_OVview(ov2, ov2 ? ov2->local() : nullptr);

	if (view1.comAndExtents == nullptr && view2.comAndExtents == nullptr)
		warn("Neither of the pvs (%s or %s) has required property 'com_extents', trying to move on",
				pv1->name.c_str(), pv2->name.c_str());

	auto ljCore_Obj = [=, *this] __device__ ( Particle dst, Particle src ) {
		const int dstObjId = dst.s21;
		const int srcObjId = src.s21;

		if (dstObjId == srcObjId && self) return make_float3(0.0f);

		float3 dstCom = make_float3(0.0f);
		float3 srcCom = make_float3(0.0f);
		if (view1.comAndExtents != nullptr) dstCom = view1.comAndExtents[dstObjId].com;
		if (view2.comAndExtents != nullptr) srcCom = view2.comAndExtents[srcObjId].com;

		return pairwiseLJ_objectAware( dst, src,
				(view1.comAndExtents != nullptr), dstCom,
				(view2.comAndExtents != nullptr), srcCom,
				sigma, epsx24_sigma, rc2);
	};

	WRAP_INTERACTON(ljCore_Obj)
}
