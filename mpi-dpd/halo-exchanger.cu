#include <cstring>
#include <algorithm>

#include "halo-exchanger.h"

using namespace std;

HaloExchanger::HaloExchanger(MPI_Comm _cartcomm, int L, const int basetag):  L(L), basetag(basetag)
{
    assert(L % 2 == 0);
    assert(L >= 2);

    MPI_CHECK( MPI_Comm_dup(_cartcomm, &cartcomm));

    MPI_CHECK( MPI_Comm_rank(cartcomm, &myrank));
    MPI_CHECK( MPI_Comm_size(cartcomm, &nranks));

    MPI_CHECK( MPI_Cart_get(cartcomm, 3, dims, periods, coords) );

    for(int i = 0; i < 26; ++i)
    {
	int d[3] = { (i + 2) % 3 - 1, (i / 3 + 2) % 3 - 1, (i / 9 + 2) % 3 - 1 };

	recv_tags[i] = (2 - d[0]) % 3 + 3 * ((2 - d[1]) % 3 + 3 * ((2 - d[2]) % 3));

	int coordsneighbor[3];
	for(int c = 0; c < 3; ++c)
	    coordsneighbor[c] = coords[c] + d[c];

	MPI_CHECK( MPI_Cart_rank(cartcomm, coordsneighbor, dstranks + i) );

	const int nhalocells = pow(L, 3 - abs(d[0]) - abs(d[1]) - abs(d[2]));

	int estimate = 6 * nhalocells; //1;//max(128, (int)( 3 * nhalocells));
	estimate = 32 * ((estimate + 31) / 32);

	halosize[i].x = d[0] != 0 ? 1 : L;
	halosize[i].y = d[1] != 0 ? 1 : L;
	halosize[i].z = d[2] != 0 ? 1 : L;
	assert(nhalocells == halosize[i].x * halosize[i].y * halosize[i].z);

	recvhalos[i].expected = estimate;
	recvhalos[i].buf.resize(estimate);
	//recvhalos[i].secondary.resize(estimate);
	recvhalos[i].cellstarts.resize(nhalocells + 1);

	sendhalos[i].expected = estimate;
	sendhalos[i].buf.resize(estimate);
	//sendhalos[i].secondary.resize(estimate);
	sendhalos[i].scattered_entries.resize(estimate);
	sendhalos[i].cellstarts.resize(nhalocells + 1);
	sendhalos[i].tmpcount.resize(nhalocells + 1);
	sendhalos[i].tmpstart.resize(nhalocells + 1);
    }

    CUDA_CHECK(cudaHostAlloc((void **)&required_send_bag_size_host, sizeof(int) * 26, cudaHostAllocMapped));
    CUDA_CHECK(cudaHostGetDevicePointer(&required_send_bag_size, required_send_bag_size_host, 0));

    for(int i = 0; i < 7; ++i)
	CUDA_CHECK(cudaStreamCreate(streams + i));

    for(int i = 0, ctr = 1; i < 26; ++i)
    {
	int d[3] = { (i + 2) % 3 - 1, (i / 3 + 2) % 3 - 1, (i / 9 + 2) % 3 - 1 };

	const bool isface = abs(d[0]) + abs(d[1]) + abs(d[2]) == 1;

	code2stream[i] = 0;

	if (isface)
	{
	    code2stream[i] = ctr;
	    ctr++;
	}
    }
}

namespace PackingHalo
{
    __global__ void count(const int * const cellsstart, const int * const cellscount,
			  const int3 halo_offset, const int3 halo_size, const int L,
			  int * const output_start, int * const output_count)
    {
	assert(halo_size.x * halo_size.y * halo_size.z <= blockDim.x * gridDim.x);

	const int gid = threadIdx.x + blockDim.x * blockIdx.x;

	const int3 tmp = make_int3(gid % halo_size.x, (gid / halo_size.x) % halo_size.y, (gid / (halo_size.x * halo_size.y)));
	 
	const int3 dst = make_int3(halo_offset.x + tmp.x,
				   halo_offset.y + tmp.y,
				   halo_offset.z + tmp.z);

	const int nsize = halo_size.x * halo_size.y * halo_size.z;
	 
	if (gid < nsize)
	{
	    assert(dst.x >= 0 && dst.x < L);
	    assert(dst.y >= 0 && dst.y < L);
	    assert(dst.z >= 0 && dst.z < L);
	    
	    const int srcentry = dst.x + L * (dst.y + L * dst.z);

	    assert(srcentry < L * L * L);

	    output_start[gid] = cellsstart[srcentry];
	    output_count[gid] = cellscount[srcentry];
	}
	else
	    if (gid == nsize)
		output_start[gid] = output_count[gid] = 0;
    }
    
    __global__ void fill(const Particle * const particles, const int np, const int ncells,
			 const int * const start_src, const int * const count_src,
			 const int * const start_dst, 
			 Particle * const bag, const int bagsize, int * const scattered_entries, int * const required_bag_size, const int code)
    {
	assert(sizeof(Particle) == 6 * sizeof(float));
	assert(blockDim.x == warpSize);

	const int cellid = (threadIdx.x >> 4) + 2 * blockIdx.x;

	if (cellid > ncells)
	    return;
	
	const int tid = threadIdx.x & 0xf;
	
	const int base_src = start_src[cellid];
	const int base_dst = start_dst[cellid];
	const int nsrc = min(count_src[cellid], bagsize - base_dst);
	
	const int nfloats = nsrc * 6;
	for(int i = 2 * tid; i < nfloats; i += warpSize)
	{
	    const int lpid = i / 6;
	    const int dpid = base_dst + lpid;
	    const int spid = base_src + lpid;
	    const int c = i % 6;

	    *(float2 *)&bag[dpid].x[c] = *(float2 *)&particles[spid].x[c];
	}

	for(int lpid = tid; lpid < nsrc; lpid += warpSize / 2)
	{
	    const int dpid = base_dst + lpid;
	    const int spid = base_src + lpid;

	    scattered_entries[dpid] = spid;
	}
	
	if (cellid == ncells)
	    *required_bag_size = base_dst;
    }
    
    __global__ void fill_v1(const Particle * const particles, const int np,
			 const int * const start_src, const int * const count_src, const int L,
			 const int * const start_dst, 
			 Particle * const bag, const int bagsize, int * const scattered_entries, int * const required_bag_size, const int code)
    {
	assert(blockDim.x == warpSize);

	const int cellid = blockIdx.x;
	const int tid = threadIdx.x;

	const int base_src = start_src[cellid];
	const int base_dst = start_dst[cellid];

	const int nsrc = min(count_src[cellid], bagsize - base_dst);
	
	for(int i = tid; i < nsrc; i += warpSize)
	{
	    const int pid = base_src + i;

	    if (!(pid < np && pid >= 0))
	    {
		printf("ooooooooooops: pid %d, but np %d and nsrc is %d, cell id %d\n", pid, np, nsrc, cellid);
	    }
	    assert(pid < np && pid >= 0);
	    
	    bag[base_dst + i] = particles[pid];
	    scattered_entries[base_dst + i] = pid;

#ifndef NDEBUG
	    {
		int d[3] = { (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1 };
		
		for(int c = 0; c < 3; ++c)
		{
		    const float halo_start = max(d[c] * L - L/2 - 1, -L/2);
		    const float halo_end = min(d[c] * L + L/2 + 1, L/2);
		    const float eps = 1e-5;
		    if (!(particles[pid].x[c] >= halo_start - eps && particles[pid].x[c] < halo_end + eps))
		    {
			printf("fill particles (pack) oooops particle %d: %e %e %e component %d not within %f , %f eps %e\n", pid, 
			       particles[pid].x[0], particles[pid].x[1], particles[pid].x[2], c, halo_start, halo_end, eps);
		
		    }
		   
		    assert(particles[pid].x[c] >= halo_start - eps && particles[pid].x[c] < halo_end + eps);
		}
	    }
#endif
	}

	if (cellid == gridDim.x - 1)
	    *required_bag_size = base_dst;
    }

      __global__ void shift_recv_particles(Particle *const particles, const int n, const int L,
					 const int code, const int dx, const int dy, const int dz, const int rank)
      {
	  assert(sizeof(Particle) == 6 * sizeof(float));
	  assert(blockDim.x * gridDim.x >= n);

	  const int base = threadIdx.x + 6 * blockDim.x * blockIdx.x;
	  const int stop = min(base + 6 * blockDim.x, 6 * n);
	  const int d[3] = {dx, dy, dz};
	  
	  for(int e = base ; e < stop; e += blockDim.x)
	  {
	      const int pid = e / 6;
	      const int c = e % 6;

	      if (c < 3)
		  particles[pid].x[c] += d[c] * L;
	  }    	  
      }

    __global__ void shift_recv_particles4(float4 * const particles4, const int n4, const int np, const int L,
					 const int code, const int dx, const int dy, const int dz, const int rank)
      {
	  assert(sizeof(Particle) == 6 * sizeof(float));
	  assert(blockDim.x * gridDim.x >= n4);
	  assert(blockDim.x * gridDim.x >= (np * 6) / 4);

	  const int gid4 = threadIdx.x + blockDim.x * blockIdx.x;

	  if (gid4 >= n4)
	      return;

	  float4 t = particles4[gid4];

	  float data[4] = {t.x, t.y, t.z, t.w};

#pragma unroll
	  for(int i = 0; i < 4; ++i)
	  {
	      const int e = i + 4 * gid4;
	      const int c = e % 6;

	      data[i] += L * (dx * (c == 0) + dy * (c == 1) + dz * (c == 2));
	  }

	  if (gid4 * 4 + 4 <= np * 6)
	      particles4[gid4] = make_float4(data[0], data[1], data[2], data[3]);
	  else
	  {
	      particles4[gid4].x = data[0];
	      particles4[gid4].y = data[1];
	  }
      }

#ifndef NDEBUG
    __global__ void check_recv_particles(Particle *const particles, const int n, const int L,
					 const int code, const int rank)
    {
	assert(blockDim.x * gridDim.x >= n);

	const int pid = threadIdx.x + blockDim.x * blockIdx.x;

	if (pid >= n)
	    return;
	
	Particle myp = particles[pid];

	const int d[3] = { (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1 };

	assert(myp.x[0] <= -L / 2 || myp.x[0] >= L / 2 ||
	       myp.x[1] <= -L / 2 || myp.x[1] >= L / 2 || 
	       myp.x[2] <= -L / 2 || myp.x[2] >= L / 2);

	for(int c = 0; c < 3; ++c)
	{
	    const float halo_start = max(d[c] * L - L/2, -L/2 - 1);
	    const float halo_end = min(d[c] * L + L/2, L/2 + 1);
	    const float eps = 1e-5;
	    if (!(myp.x[c] >= halo_start - eps && myp.x[c] <= halo_end + eps))
		printf("ooops RANK %d: shift_recv_particle: pid %d \npos %f %f %f vel: %f %f %f halo_start-end: %f %f\neps: %f, code %d c: %d direction %d %d %d\n",
		       rank, pid, myp.x[0], myp.x[1], myp.x[2]
		       ,myp.u[0], myp.u[1], myp.u[2], halo_start, halo_end, eps, code, c,
		       d[0], d[1], d[2]);

	    assert(myp.x[c] >= halo_start - eps && myp.x[c] <= halo_end + eps);
	}
    }
#endif
    
    __global__ void shift_recv_particles_old(Particle *const particles, const int n, const int L,
					 const int code, const int dx, const int dy, const int dz, const int rank)
    {
	assert(blockDim.x * gridDim.x >= n);

	const int pid = threadIdx.x + blockDim.x * blockIdx.x;

	if (pid >= n)
	    return;
	
	Particle myp = particles[pid];
	const Particle oldp = myp;

	for(int c = 0; c < 3; ++c)
	    assert(myp.x[c] >= -L / 2 && myp.x[c] < L / 2);

	const int d[3] = {dx, dy, dz}; //{ (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1 };

	for(int c = 0; c < 3; ++c)
	    myp.x[c] += d[c] * L;

	particles[pid] = myp;

#ifndef NDEBUG

	assert(myp.x[0] <= -L / 2 || myp.x[0] >= L / 2 ||
	       myp.x[1] <= -L / 2 || myp.x[1] >= L / 2 || 
	       myp.x[2] <= -L / 2 || myp.x[2] >= L / 2);

	for(int c = 0; c < 3; ++c)
	{
	    const float halo_start = max(d[c] * L - L/2, -L/2 - 1);
	    const float halo_end = min(d[c] * L + L/2, L/2 + 1);
	    const float eps = 1e-5;
	    if (!(myp.x[c] >= halo_start - eps && myp.x[c] <= halo_end + eps))
		printf("ooops RANK %d: shift_recv_particle: pid %d \npos %f %f %f vel: %f %f %f halo_start-end: %f %f\neps: %f, code %d c: %d,\n original: %f %f %f %f %f %f, direction %d %d %d\n",
		       rank, pid, myp.x[0], myp.x[1], myp.x[2]
		       ,myp.u[0], myp.u[1], myp.u[2], halo_start, halo_end, eps, code, c,
		       oldp.x[0], oldp.x[1], oldp.x[2] ,oldp.u[0], oldp.u[1], oldp.u[2], d[0], d[1], d[2]);

	    assert(myp.x[c] >= halo_start - eps && myp.x[c] <= halo_end + eps);
	}

#endif
    }

#ifndef NDEBUG
    __global__ void check_send_particles(Particle * p, int n, int L, int code)
    {
	assert(blockDim.x * gridDim.x >= n);

	const int pid = threadIdx.x + blockDim.x * blockIdx.x;

	if (pid >= n)
	    return;

	assert(p[pid].x[0] >= -L / 2 || p[pid].x[0] < L / 2 ||
	       p[pid].x[1] >= -L / 2 || p[pid].x[1] < L / 2 || 
	       p[pid].x[2] >= -L / 2 || p[pid].x[2] < L / 2);

	const int d[3] = { (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1 };


	for(int c = 0; c < 3; ++c)
	{
	    const float halo_start = max(d[c] * L - L/2 - 1, -L/2);
	    const float halo_end = min(d[c] * L + L/2 + 1, L/2);
	    const float eps = 1e-5;
	    if (!(p[pid].x[c] >= halo_start - eps && p[pid].x[c] < halo_end + eps))
	    {
		printf("oooops particle %d: %e %e %e component %d not within %f , %f eps %f\n", pid, p[pid].x[0], p[pid].x[1], p[pid].x[2],
		       c, halo_start, halo_end, eps);
		
	    }
	    
	    assert(p[pid].x[c] >= halo_start - eps && p[pid].x[c] < halo_end + eps);
	}
    }
#endif
}

void HaloExchanger::pack_and_post(const Particle * const p, const int n, const int * const cellsstart, const int * const cellscount)
{
    CUDA_CHECK(cudaPeekAtLastError());

    nlocal = n;
    
    for(int i = 0; i < 26; ++i)
    {
	int d[3] = { (i + 2) % 3 - 1, (i / 3 + 2) % 3 - 1, (i / 9 + 2) % 3 - 1 };
	 
	int halo_start[3], halo_size[3];
	for(int c = 0; c < 3; ++c)
	{
	    halo_start[c] = max(d[c] * L - L/2 - 1, -L/2);
	    halo_size[c] = min(d[c] * L + L/2 + 1, L/2) - halo_start[c];
	}

	const int nentries = sendhalos[i].cellstarts.size;
	
	PackingHalo::count<<< (nentries + 127) / 128, 128, 0, streams[code2stream[i]] >>>
	    (cellsstart, cellscount,  make_int3(halo_start[0] + L/2 , halo_start[1] + L/2, halo_start[2] + L/2),
	     make_int3(halo_size[0], halo_size[1], halo_size[2]), L, sendhalos[i].tmpstart.data, sendhalos[i].tmpcount.data);
    }
    
    for(int i = 0; i < 26; ++i)
	scan.exclusive(streams[code2stream[i]], (uint*)sendhalos[i].cellstarts.devptr, (uint*)sendhalos[i].tmpcount.data,
		       sendhalos[i].tmpcount.size);
 
    for(int pass = 0; pass < 2; ++pass)
    {
	bool needsync = pass == 0;

	for(int i = 0; i < 26; ++i)
	{
	    bool fail = false;
	    int nrequired;

	    if (pass == 1)
	    {
		nrequired = required_send_bag_size_host[i];
		fail = sendhalos[i].buf.capacity < nrequired;
	    }

	    if (pass == 0 || fail)
	    {
		if (fail)
		{
		    printf("------------------- rank %d - code %d : oops now: %d, expected: %d required: %d, current capacity: %d\n", 
			   myrank, i, sendhalos[i].buf.size,
			   sendhalos[i].expected, nrequired, sendhalos[i].buf.capacity);
		    sendhalos[i].buf.resize(nrequired);
		    sendhalos[i].scattered_entries.resize(nrequired);
		    needsync = true;
		}
		
		const int nentries = sendhalos[i].cellstarts.size;
#if 1
		PackingHalo::fill<<<nentries, 32, 0, streams[code2stream[i]] >>>
		    (p, n, nentries - 1, sendhalos[i].tmpstart.data, sendhalos[i].tmpcount.data, sendhalos[i].cellstarts.devptr,
		     sendhalos[i].buf.devptr, sendhalos[i].buf.capacity, sendhalos[i].scattered_entries.data, required_send_bag_size + i, i);
#else
		PackingHalo::fill_v1<<<nentries, 32, 0, streams[code2stream[i]] >>>
		    (p, n, sendhalos[i].tmpstart.data, sendhalos[i].tmpcount.data, L, sendhalos[i].cellstarts.devptr,
		     sendhalos[i].buf.devptr, sendhalos[i].buf.capacity, sendhalos[i].scattered_entries.data, required_send_bag_size + i, i);
#endif
	    }

	    if (pass == 1)
	    {
		sendhalos[i].buf.size = nrequired;
		sendhalos[i].scattered_entries.size = nrequired;
	    }
	}

	CUDA_CHECK(cudaPeekAtLastError());

	if (needsync)
	    for(int i = 0; i < 7; ++i)
		CUDA_CHECK(cudaStreamSynchronize(streams[i]));
    }
	
#ifndef NDEBUG
    for(int i = 0; i < 26; ++i)
    {
    	const int nd = sendhalos[i].buf.size;
	
	if (nd > 0)
	    PackingHalo::check_send_particles<<<(nd + 127)/ 128, 128>>>(sendhalos[i].buf.devptr, nd, L, i);

	printf("send all good\n");
    }

    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaPeekAtLastError());
#endif

    for(int i = 0; i < 26; ++i)
    {
	assert(recvhalos[i].buf.capacity >= recvhalos[i].expected);
	
	MPI_CHECK( MPI_Irecv(recvhalos[i].buf.data, recvhalos[i].expected, Particle::datatype(), dstranks[i], 
			     basetag + recv_tags[i], cartcomm, recvreq + i) );
    }

    for(int i = 0; i < 26; ++i)
	MPI_CHECK( MPI_Irecv(recvhalos[i].cellstarts.data, recvhalos[i].cellstarts.size, MPI_INTEGER, dstranks[i],
			     basetag + recv_tags[i] + 350, cartcomm,  recvcellsreq + i) );

    for(int i = 0; i < 26; ++i)
	MPI_CHECK( MPI_Irecv(recv_counts + i, 1, MPI_INTEGER, dstranks[i],
			     basetag + recv_tags[i] + 150, cartcomm, recvcountreq + i) );
     
    for(int i = 0; i < 26; ++i)
	MPI_CHECK( MPI_Isend(sendhalos[i].cellstarts.data, sendhalos[i].cellstarts.size, MPI_INTEGER, dstranks[i],
			     basetag + i + 350, cartcomm,  sendcellsreq + i) );

    for(int i = 0; i < 26; ++i)
	MPI_CHECK( MPI_Isend(&sendhalos[i].buf.size, 1, MPI_INTEGER, dstranks[i], basetag +  i + 150, cartcomm, sendcountreq + i) );

    nsendreq = 0;
    
    for(int i = 0; i < 26; ++i)
    {
	const int count = sendhalos[i].buf.size;
	const int expected = sendhalos[i].expected;
	
	MPI_CHECK( MPI_Isend(sendhalos[i].buf.data, expected, Particle::datatype(), dstranks[i], 
			    basetag +  i, cartcomm, sendreq + nsendreq) );

	++nsendreq;
	
	if (count > expected)
	{
	    const int difference = count - expected;
	    printf("extra message from rank %d to rank %d! difference %d\n", myrank, dstranks[i], difference);
	    
	    MPI_CHECK( MPI_Isend(sendhalos[i].buf.data + expected, difference, Particle::datatype(), dstranks[i], 
				 basetag + i + 555, cartcomm, sendreq + nsendreq) );

	    ++nsendreq;
	}
    }
}

void HaloExchanger::wait_for_messages()
{
    CUDA_CHECK(cudaPeekAtLastError());
    
    {
	MPI_Status statuses[26];

	MPI_CHECK( MPI_Waitall(26, recvreq, statuses) );    
	MPI_CHECK( MPI_Waitall(26, recvcellsreq, statuses) );
	MPI_CHECK( MPI_Waitall(26, recvcountreq, statuses) );
	MPI_CHECK( MPI_Waitall(26, sendcellsreq, statuses) );
	MPI_CHECK( MPI_Waitall(26, sendcountreq, statuses) );
    }

    for(int i = 0; i < 26; ++i)
    {
	const int count = recv_counts[i];
	const int expected = recvhalos[i].expected;
	const int difference = count - expected;
	
	if (count <= expected)
	    recvhalos[i].buf.resize(count);
	else
	{
	    printf("RANK %d waiting for RECV-extra message: count %d expected %d (difference %d) from rank %d\n", 
		   myrank, count, expected, difference, dstranks[i]);
	    
	    recvhalos[i].buf.preserve_resize(count);

	    MPI_Status status;

	    MPI_Recv(recvhalos[i].buf.data + expected, difference, Particle::datatype(), dstranks[i], 
		     basetag + recv_tags[i] + 555, cartcomm, &status);

	}
    }

    {
	MPI_Status statuses[26];
	
	MPI_CHECK( MPI_Waitall(nsendreq, sendreq, statuses) );
    }
    
    for(int code = 0; code < 26; ++code)
    {
	const int count = recv_counts[code];
#if 1
	if (count > 0)
	{
	    const int n4 = (count * 6 + 3) / 4;
	    PackingHalo::shift_recv_particles4<<<(n4 + 127) / 128, 128, 0, streams[code2stream[code]]>>>(
		(float4 *)recvhalos[code].buf.devptr, n4, count, L, code, (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1, myrank);
	}
#else
	if (count > 0)
	    PackingHalo::shift_recv_particles<<<(count + 127) / 128, 128, 0, streams[code2stream[code]]>>>(
		recvhalos[code].buf.devptr, count, L, code, (code + 2) % 3 - 1, (code / 3 + 2) % 3 - 1, (code / 9 + 2) % 3 - 1, myrank);
#endif
    }

    CUDA_CHECK(cudaPeekAtLastError());

#ifndef NDEBUG
    for(int code = 0; code < 26; ++code)
    {
	const int count = recv_counts[code];
	
	if (count > 0)
	    PackingHalo::check_recv_particles<<<(count + 127) / 128, 128, 0, streams[code2stream[code]]>>>(
		recvhalos[code].buf.devptr, count, L, code, myrank);	
    }

    CUDA_CHECK(cudaPeekAtLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    printf("all good\n");
#endif
    
    
}

int HaloExchanger::nof_sent_particles()
{
    int s = 0;
    for(int i = 0; i < 26; ++i)
	s += sendhalos[i].buf.size;

    return s;
}

void HaloExchanger::exchange(Particle * const plocal, int nlocal, SimpleDeviceBuffer<Particle>& retval)
{
    CellLists cells(L);	
    cells.build(plocal, nlocal);
   
    pack_and_post(plocal, nlocal, cells.start, cells.count);
    wait_for_messages();

    int s = 0;
    for(int i = 0; i < 26; ++i)
	s += recvhalos[i].buf.size;
    
    retval.resize(s);

    s = 0;
    for(int i = 0; i < 26; ++i)
    {
	CUDA_CHECK(cudaMemcpy(retval.data + s, recvhalos[i].buf.devptr, recvhalos[i].buf.size * sizeof(Particle), cudaMemcpyDeviceToDevice));
	s += recvhalos[i].buf.size;
    }
}

HaloExchanger::~HaloExchanger()
{
    for(int i = 0; i < 7; ++i)
	CUDA_CHECK(cudaStreamDestroy(streams[i]));
    
    CUDA_CHECK(cudaFreeHost(required_send_bag_size));

    MPI_CHECK(MPI_Comm_free(&cartcomm));
}
