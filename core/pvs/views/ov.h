#pragma once

#include <core/rigid_kernels/rigid_motion.h>

/**
 * GPU-compatible struct of all the relevant data
 */
struct OVview : public PVview
{
	int nObjects = 0, objSize = 0;
	float objMass = 0, invObjMass = 0;

	LocalObjectVector::COMandExtent *comAndExtents = nullptr;
	int* ids = nullptr;

	OVview(ObjectVector* ov = nullptr, LocalObjectVector* lov = nullptr) :
		PVview(ov, lov)
	{
		if (ov == nullptr || lov == nullptr) return;

		// More fields
		nObjects = lov->nObjects;
		objSize = ov->objSize;
		objMass = objSize * mass;
		invObjMass = 1.0 / objMass;

		// Required data per object
		comAndExtents = lov->extraPerObject.getData<LocalObjectVector::COMandExtent>("com_extents")->devPtr();
		ids           = lov->extraPerObject.getData<int>("ids")->devPtr();
	}
};

struct OVviewWithAreaVolume : public OVview
{
	float2* area_volumes = nullptr;

	OVviewWithAreaVolume(ObjectVector* ov = nullptr, LocalObjectVector* lov = nullptr) :
		OVview(ov, lov)
	{
		if (ov == nullptr || lov == nullptr) return;

		area_volumes = lov->extraPerObject.getData<float2>("area_volumes")->devPtr();
	}
};

struct OVviewWithOldPartilces : public OVview
{
	float4* old_particles = nullptr;

	OVviewWithOldPartilces(ObjectVector* ov = nullptr, LocalObjectVector* lov = nullptr) :
		OVview(ov, lov)
	{
		if (ov == nullptr || lov == nullptr) return;

		old_particles = reinterpret_cast<float4*>( lov->extraPerObject.getData<Particle>("old_particles")->devPtr() );
	}
};


