#include <plugins/stats.h>
#include <plugins/simple_serializer.h>
#include <core/datatypes.h>
#include <core/containers.h>
#include <core/simulation.h>
#include <core/helper_math.h>

__inline__ __device__ float warpReduceSum(float val)
{
#pragma unroll
	for (int offset = warpSize/2; offset > 0; offset /= 2)
	{
		val += __shfl_down(val, offset);
	}
	return val;
}

__inline__ __device__ float3 warpReduceSum(float3 val)
{
#pragma unroll
	for (int offset = warpSize/2; offset > 0; offset /= 2)
	{
		val.x += __shfl_down(val.x, offset);
		val.y += __shfl_down(val.y, offset);
		val.z += __shfl_down(val.z, offset);
	}
	return val;
}

__global__ void totalMomentumEnergy(const float4* coosvels, const float mass, int n, ReductionType* momentum, ReductionType* energy)
{
	const int tid = blockIdx.x * blockDim.x + threadIdx.x;
	const int wid = tid % warpSize;
	if (tid >= n) return;

	const float3 vel = make_float3(coosvels[2*tid+1]);

	float3 myMomentum = vel*mass;
	float myEnergy = dot(vel, vel) * mass*0.5f;

	myMomentum = warpReduceSum(myMomentum);
	myEnergy   = warpReduceSum(myEnergy);

	if (wid == 0)
	{
		atomicAdd(momentum+0, (ReductionType)myMomentum.x);
		atomicAdd(momentum+1, (ReductionType)myMomentum.y);
		atomicAdd(momentum+2, (ReductionType)myMomentum.z);
		atomicAdd(energy,     (ReductionType)myEnergy);
	}
}

void SimulationStats::afterIntegration()
{
	if (currentTimeStep % fetchEvery != 0) return;

	auto& pvs = sim->getParticleVectors();

	momentum.pushStream(stream);
	energy  .pushStream(stream);

	momentum.clear();
	energy  .clear();

	nparticles = 0;
	for (auto& pv : pvs)
	{
		totalMomentumEnergy<<< (pv->np+127)/128, 128, 0, stream >>> ((float4*)pv->coosvels.devPtr(), pv->mass, pv->np, momentum.devPtr(), energy.devPtr());
		nparticles += pv->np;
	}

	momentum.downloadFromDevice();
	energy  .downloadFromDevice();

	needToDump = true;
}

void SimulationStats::serializeAndSend()
{
	if (needToDump)
	{
		float tm = timer.elapsedAndReset() / (currentTimeStep < fetchEvery ? 1.0f : fetchEvery);
		SimpleSerializer::serialize(sendBuffer, tm, currentTime, currentTimeStep, nparticles, momentum, energy);
		send(sendBuffer.hostPtr(), sendBuffer.size());
		needToDump = false;
	}
}

PostprocessStats::PostprocessStats(std::string name) :
		PostprocessPlugin(name)
{
	float f;
	int   i;
	DeviceBuffer<ReductionType> m(3), e(1);

	// real exec time, simulation time,
	// timestep; # of particles,
	// momentum, energy
	size = SimpleSerializer::totSize(f, f, i, i, m, e);
	data.resize(size);

	if (std::is_same<ReductionType, float>::value)
		mpiReductionType = MPI_FLOAT;
	else if (std::is_same<ReductionType, double>::value)
		mpiReductionType = MPI_DOUBLE;
	else
		die("Incompatible type");
}

void PostprocessStats::deserialize(MPI_Status& stat)
{
	float currentTime, realTime;
	int nparticles, currentTimeStep;
	HostBuffer<ReductionType> momentum(3), energy(1);

	SimpleSerializer::deserialize(data, realTime, currentTime, currentTimeStep, nparticles, momentum, energy);

    MPI_Check( MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &nparticles,        &nparticles,        1, MPI_INT,          MPI_SUM, 0, comm) );
    MPI_Check( MPI_Reduce(rank == 0 ? MPI_IN_PLACE : energy.hostPtr(),   energy.hostPtr(),   1, mpiReductionType, MPI_SUM, 0, comm) );
    MPI_Check( MPI_Reduce(rank == 0 ? MPI_IN_PLACE : momentum.hostPtr(), momentum.hostPtr(), 3, mpiReductionType, MPI_SUM, 0, comm) );

    MPI_Check( MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &realTime,          &realTime,          1, MPI_FLOAT,        MPI_MAX, 0, comm) );

    if (rank == 0)
    {
    	momentum[0] /= (double)nparticles;
    	momentum[1] /= (double)nparticles;
    	momentum[2] /= (double)nparticles;
    	const ReductionType temperature = energy[0] / ( (3/2.0)*nparticles );

    	printf("Stats at timestep %d (simulation time %f):\n", currentTimeStep, currentTime);
    	printf("\tOne timespep takes %.2f ms", realTime);
    	printf("\tTotal number of particles: %d\n", nparticles);
    	printf("\tAverage momentum: [%e %e %e]\n", momentum[0], momentum[1], momentum[2]);
    	printf("\tTemperature: %.4f\n\n", temperature);
    }
}


