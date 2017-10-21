#pragma once

/**
 * GPU-compatible struct of all the relevant data
 */
struct ROVview : public OVview
{
	LocalRigidObjectVector::RigidMotion *motions = nullptr;

	float3 J   = {0,0,0};
	float3 J_1 = {0,0,0};

	// TODO: implement this
	//float inertia[9];

	ROVview(RigidObjectVector* rov = nullptr, LocalRigidObjectVector* lrov = nullptr) :
		OVview(rov, lrov)
	{
		if (rov == nullptr || lrov == nullptr) return;

		motions = lrov->getDataPerObject<LocalRigidObjectVector::RigidMotion>("motions")->devPtr();

		// More fields
		J = rov->getInertiaTensor();
		J_1 = 1.0 / J;
	}
};

struct ROVview_withOldMotion : public ROVview
{
	LocalRigidObjectVector::RigidMotion *old_motions = nullptr;


	ROVview_withOldMotion(RigidObjectVector* rov = nullptr, LocalRigidObjectVector* lrov = nullptr) :
		ROVview(rov, lrov)
	{
		if (rov == nullptr || lrov == nullptr) return;

		old_motions = lrov->getDataPerObject<LocalRigidObjectVector::RigidMotion>("old_motions")->devPtr();
	}
};

