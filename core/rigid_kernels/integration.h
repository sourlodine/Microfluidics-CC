#pragma once

#include <core/pvs/object_vector.h>
#include <core/pvs/rigid_object_vector.h>
#include <core/cuda_common.h>
#include <core/rigid_kernels/quaternion.h>


__global__ void collectRigidForces(const float4 * coosvels, const float4 * forces,
		LocalRigidObjectVector::RigidMotion* motion, LocalRigidObjectVector::COMandExtent* props,
		const int nObj, const int objSize)
{
	const int objId = blockIdx.x;
	const int tid = threadIdx.x;
	if (objId >= nObj) return;

	float3 force  = make_float3(0);
	float3 torque = make_float3(0);
	const float3 com = props[objId].com;

	// Find the total force and torque
#pragma unroll 3
	for (int i = tid; i < objSize; i += blockDim.x)
	{
		const int offset = (objId * objSize + i);

		const float3 frc = make_float3(forces[offset]);
		const float3 r   = make_float3(coosvels[offset*2]) - com;

		force += frc;
		torque += cross(r, frc);
	}

	force  = warpReduce( force,  [] (float a, float b) { return a+b; } );
	torque = warpReduce( torque, [] (float a, float b) { return a+b; } );

	if ( (tid % warpSize) == 0)
	{
		atomicAdd(&motion[objId].force,  force);
		atomicAdd(&motion[objId].torque, torque);
	}
}

/**
 * J is the diagonal moment of inertia tensor, J_1 is its inverse (simply 1/Jii)
 * Velocity-Verlet fused is used at the moment
 */
__global__ void integrateRigidMotion(LocalRigidObjectVector::RigidMotion* motions,
		const float3 J, const float3 J_1, const float invMass, const int nObj, const float dt)
{
	const int objId = threadIdx.x + blockDim.x * blockIdx.x;
	if (objId >= nObj) return;

	//**********************************************************************************
	// Rotation
	//**********************************************************************************
	float4 q     = motions[objId].q;
	float3 omega = motions[objId].omega;
	float3 tau   = motions[objId].torque;

	// FIXME allow for non-diagonal inertia tensors

	// tau = J dw/dt + w x Jw  =>  dw/dt = J'*tau - J'*(w x Jw)
	float3 dw_dt = J_1 * tau - J_1 * cross(omega, J*omega);
	omega += dw_dt * dt;

	// XXX: using OLD q and NEW w ?
	// d^2q / dt^2 = 1/2 * (dw/dt*q + w*dq/dt)
	float4 dq_dt = compute_dq_dt(q, omega);
	float4 d2q_dt2 = 0.5f*(multiplyQ(f3toQ(dw_dt), q) + multiplyQ(f3toQ(omega), dq_dt));

	dq_dt += d2q_dt2 * dt;
	q     += dq_dt   * dt;

	// Normalize q
	q = normalize(q);

	motions[objId].prevQ  = motions[objId].q;
	motions[objId].q      = q;
	motions[objId].omega  = omega;

	//**********************************************************************************
	// Translation
	//**********************************************************************************
	float3 force = motions[objId].force;
	float3 vel = motions[objId].vel;
	vel += force*dt * invMass;

	motions[objId].r     += vel*dt;
	motions[objId].vel    = vel;
}


// TODO: rotate initial config instead of incremental rotations
__global__ void applyRigidMotion(float4 * coosvels, const float4 * __restrict__ initial, LocalRigidObjectVector::RigidMotion* motions, const int nObj, const int objSize)
{
	const int pid = threadIdx.x + blockDim.x * blockIdx.x;
	const int objId = pid / objSize;
	const int locId = pid % objSize;

	if (pid >= nObj*objSize) return;

	const auto motion = motions[objId];

	Particle p(coosvels, pid);

	p.r = motion.r + rotate( f4tof3(initial[locId]), motion.q );
	p.u = motion.vel + cross(motion.omega, p.r - motion.r);

	coosvels[2*pid]   = p.r2Float4();
	coosvels[2*pid+1] = p.u2Float4();
}

__global__ void clearRigidForces(LocalRigidObjectVector::RigidMotion* motions, const int nObj)
{
	const int objId = threadIdx.x + blockDim.x * blockIdx.x;
	if (objId >= nObj) return;

	motions[objId].force  = make_float3(0.0f);
	motions[objId].torque = make_float3(0.0f);
}



