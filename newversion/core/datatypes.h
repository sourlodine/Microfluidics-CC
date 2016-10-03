#pragma once

#include <cuda.h>
#include <cstdlib>
#include <cstdint>
#include <cassert>
#include <type_traits>
#include <utility>

#include "logger.h"

//==================================================================================================================
// Basic types
//==================================================================================================================

struct Particle
{
	// 4-th coordinate is void
	float x[3];
	int32_t i1;
	float u[3];
	int32_t i2;
};

struct Acceleration
{
	// 4-th coordinate is void
	float a[4];
};


//==================================================================================================================
// Different data vectors
//==================================================================================================================

enum ResizeKind
{
	resizeAnew     = 0,
	resizePreserve = 1
};

enum SynchroKind
{
	synchronizeDevice = 0,
	synchronizeHost   = 1
};


template<typename T>
struct DeviceBuffer
{
	int capacity, size;
	T * devdata;

	DeviceBuffer(int n = 0): capacity(0), size(0), devdata(nullptr) { resize(n, resizeAnew); }

	~DeviceBuffer()
	{
		if (devdata != nullptr) logger.CUDA_Check(cudaFree(devdata));
	}

	void resize(const int n, ResizeKind kind = resizeAnew, cudaStream_t stream = 0)
	{
		T * dold = devdata;
		int oldsize = size;

		assert(n >= 0);
		size = n;
		if (capacity >= n) return;

		const int conservative_estimate = (int)ceil(1.1 * n);
		capacity = 128 * ((conservative_estimate + 129) / 128);

		logger.CUDA_Check(cudaMalloc(&devdata, sizeof(T) * capacity));

		if (kind == resizePreserve && dold != nullptr)
		{
			logger.CUDA_Check(cudaMemcpyAsync(devdata, dold, sizeof(T) * oldsize, cudaMemcpyDeviceToDevice, stream));
		}

		logger.CUDA_Check(cudaFree(dold));
	}

	void clear(cudaStream_t stream = 0)
	{
		logger.CUDA_Check( cudaMemsetAsync(devdata, 0, sizeof(T) * size, stream) );
	}

	template<typename Cont>
	auto copy(Cont& cont, cudaStream_t stream = 0) -> decltype((void)(cont.devdata), void())
	{
		static_assert(std::is_same<decltype(devdata), decltype(cont.devdata)>::value, "can't copy buffers of different types");

		resize(cont.size);
		logger.CUDA_Check( cudaMemcpyAsync(devdata, cont.devdata, sizeof(T) * size, cudaMemcpyDeviceToDevice, stream) );
	}

	template<typename Cont>
	auto copy(Cont& cont, cudaStream_t stream = 0) -> decltype((void)(cont.hostdata), void())
	{
		static_assert(std::is_same<decltype(devdata), decltype(cont.hostdata)>::value, "can't copy buffers of different types");

		resize(cont.size);
		logger.CUDA_Check( cudaMemcpyAsync(devdata, cont.hostdata, sizeof(T) * size, cudaMemcpyHostToDevice, stream) );
	}
};

template<typename T>
struct PinnedBuffer
{
	int capacity, size;
	T * hostdata, * devdata;

	PinnedBuffer(int n = 0): capacity(0), size(0), hostdata(nullptr), devdata(nullptr) { resize(n, resizeAnew); }

	~PinnedBuffer()
	{
		if (hostdata != nullptr) logger.CUDA_Check(cudaFreeHost(hostdata));
	}

	void resize(const int n, ResizeKind kind = resizeAnew, cudaStream_t stream = 0)
	{
		T * hold = hostdata;
		T * dold = devdata;
		int oldsize = size;

		assert(n >= 0);
		size = n;
		if (capacity >= n) return;

		const int conservative_estimate = (int)ceil(1.1 * n);
		capacity = 128 * ((conservative_estimate + 129) / 128);

		logger.CUDA_Check(cudaHostAlloc(&hostdata, sizeof(T) * capacity, cudaHostAllocDefault));
		logger.CUDA_Check(cudaMalloc(&devdata, sizeof(T) * capacity));

		if (kind == resizePreserve && hold != nullptr)
		{
			memcpy(hostdata, hold, sizeof(T) * oldsize);
			logger.CUDA_Check(cudaMemcpyAsync(devdata, dold, sizeof(T) * oldsize, cudaMemcpyDeviceToDevice, stream));
		}

		logger.CUDA_Check(cudaFreeHost(hold));
		logger.CUDA_Check(cudaFree(dold));
	}

	void synchronize(SynchroKind kind, cudaStream_t stream = 0)
	{
		if (kind == synchronizeDevice)
			logger.CUDA_Check(cudaMemcpyAsync(devdata, hostdata, sizeof(T) * size, cudaMemcpyHostToDevice, stream));
		else
		{
			logger.CUDA_Check(cudaMemcpyAsync(hostdata, devdata, sizeof(T) * size, cudaMemcpyDeviceToHost, stream));
			logger.CUDA_Check(cudaStreamSynchronize(stream));
		}
	}

	T& operator[](const int i)
	{
		return hostdata[i];
	}

	void clear(cudaStream_t stream = 0)
	{
		logger.CUDA_Check( cudaMemsetAsync(devdata, 0, sizeof(T) * size, stream) );
		memset(hostdata, 0, sizeof(T) * size);
	}

	template<typename Cont>
	auto copy(Cont& cont, cudaStream_t stream = 0) -> decltype((void)(cont.devdata), void())
	{
		static_assert(std::is_same<decltype(devdata), decltype(cont.devdata)>::value, "can't copy buffers of different types");

		resize(cont.size);
		logger.CUDA_Check( cudaMemcpyAsync(devdata, cont.devdata, sizeof(T) * size, cudaMemcpyDeviceToDevice, stream) );
	}

	template<typename Cont>
	auto copy(Cont& cont, cudaStream_t stream = 0) -> decltype((void)(cont.hostdata), void())
	{
		static_assert(std::is_same<decltype(hostdata), decltype(cont.hostdata)>::value, "can't copy buffers of different types");

		resize(cont.size);
		memcpy(hostdata, cont.hostdata, sizeof(T) * size);
	}
};

template<typename T>
struct HostBuffer
{
	int capacity, size;
	T * hostdata;

	HostBuffer(int n = 0): capacity(0), size(0), hostdata(nullptr) { resize(n); }

	~HostBuffer()
	{
		if (hostdata != nullptr) free(hostdata);
	}

	void resize(const int n, ResizeKind kind = resizeAnew)
	{
		T * hold = hostdata;
		int oldsize = size;

		assert(n >= 0);
		size = n;
		if (capacity >= n) return;

		const int conservative_estimate = (int)ceil(1.1 * n);
		capacity = 128 * ((conservative_estimate + 129) / 128);

		hostdata = (T*) malloc(sizeof(T) * capacity);

		if (kind == resizePreserve && hold != nullptr)
		{
			memcpy(hostdata, hold, sizeof(T) * oldsize);
		}

		free(hold);
	}

	T& operator[](const int i)
	{
		return hostdata[i];
	}

	void clear(cudaStream_t stream = 0)
	{
		memset(hostdata, 0, sizeof(T) * size);
	}

	template<typename Cont>
	auto copy(Cont& cont, cudaStream_t stream = 0) -> decltype((void)(cont.hostdata), void())
	{
		static_assert(std::is_same<decltype(hostdata), decltype(cont.hostdata)>::value, "can't copy buffers of different types");

		resize(cont.size);
		memcpy(hostdata, cont.hostdata, sizeof(T) * size);
	}

	template<typename Cont>
	auto copy(Cont& cont, cudaStream_t stream = 0) -> decltype((void)(cont.devdata), void())
	{
		static_assert(std::is_same<decltype(hostdata), decltype(cont.devdata)>::value, "can't copy buffers of different types");

		resize(cont.size);
		logger.CUDA_Check( cudaMemcpyAsync(hostdata, cont.devdata, sizeof(T) * size, cudaMemcpyDeviceToHost, stream) );
	}
};


template<typename T>
void swap(DeviceBuffer<T>& a, DeviceBuffer<T>& b, cudaStream_t stream)
{
	a.resize(b.size, resizePreserve, stream);
	b.resize(a.size, resizePreserve, stream);

	std::swap(a.devdata, b.devdata);
}

template<typename T>
void swap(HostBuffer<T>& a, HostBuffer<T>& b, cudaStream_t stream)
{
	a.resize(b.size, resizePreserve, stream);
	b.resize(a.size, resizePreserve, stream);

	std::swap(a.hostdata, b.hostdata);
}

template<typename T>
void swap(PinnedBuffer<T>& a, PinnedBuffer<T>& b, cudaStream_t stream)
{
	a.resize(b.size, resizePreserve, stream);
	b.resize(a.size, resizePreserve, stream);

	std::swap(a.devdata,  b.devdata);
	std::swap(a.hostdata, b.hostdata);
}









