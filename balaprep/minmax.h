typedef struct {
        int g_block_id;
        int g_blockcnt;
        float3 minval;
        float3 maxval;
} sblockds_t;

#define MAXTHREADS 1024
#define WARPSIZE     32
#define MAXV     100000000.
#define MINV    -100000000.


__global__ void minmaxshuffle(float3 *d_data, float3 *d_min, float3 *d_max,
                                  int size, sblockds_t *ptoblockds) {
  __shared__ float3 mintemp[32];
  __shared__ float3 maxtemp[32];
  __shared__ float shrtmp[3][MAXTHREADS];

  __shared__ unsigned int my_blockId;
  float3 mintemp1, maxtemp1;
  float3 mindef, maxdef;
  float temp2;
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  if (threadIdx.x==0) {
         my_blockId = atomicAdd( &(ptoblockds->g_block_id), 1 );
  }
  mindef.x=MAXV;   mindef.y=MAXV;   mindef.z=MAXV;
  maxdef.x=MINV;   maxdef.y=MINV;   maxdef.z=MINV;
  __syncthreads();
  int tid = threadIdx.x;
  int xyz;
  for(int i=tid; i<3*blockDim.x; i+=blockDim.x) {
    xyz=i%3;
    if(xyz==0) {
      shrtmp[xyz][i/3] = (i/3+my_blockId*blockDim.x<size)?d_data[i/3+my_blockId*blockDim.x].x:MINV;
    } else if(xyz==1) {
      shrtmp[xyz][i/3] = (i/3+my_blockId*blockDim.x<size)?d_data[i/3+my_blockId*blockDim.x].y:MINV;
    } else {
      shrtmp[xyz][i/3] = (i/3+my_blockId*blockDim.x<size)?d_data[i/3+my_blockId*blockDim.x].z:MINV;
    }
  }
  __syncthreads();
  mintemp1.x = (tid+my_blockId*blockDim.x<size)?shrtmp[0][tid]:MAXV;
  mintemp1.y = (tid+my_blockId*blockDim.x<size)?shrtmp[1][tid]:MAXV;
  mintemp1.z = (tid+my_blockId*blockDim.x<size)?shrtmp[2][tid]:MAXV;
  maxtemp1.x = (tid+my_blockId*blockDim.x<size)?shrtmp[0][tid]:MINV;
  maxtemp1.y = (tid+my_blockId*blockDim.x<size)?shrtmp[1][tid]:MINV;
  maxtemp1.z = (tid+my_blockId*blockDim.x<size)?shrtmp[2][tid]:MINV;
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(mintemp1.x,d);
         mintemp1.x=(mintemp1.x>temp2)?temp2:mintemp1.x;
         temp2 = __shfl_up(mintemp1.y,d);
         mintemp1.y=(mintemp1.y>temp2)?temp2:mintemp1.y;
         temp2 = __shfl_up(mintemp1.z,d);
         mintemp1.z=(mintemp1.z>temp2)?temp2:mintemp1.z;
         temp2 = __shfl_up(maxtemp1.x,d);
         maxtemp1.x=(maxtemp1.x<temp2)?temp2:maxtemp1.x;
         temp2 = __shfl_up(maxtemp1.y,d);
         maxtemp1.y=(maxtemp1.y<temp2)?temp2:maxtemp1.y;
         temp2 = __shfl_up(maxtemp1.z,d);
         maxtemp1.z=(maxtemp1.z<temp2)?temp2:maxtemp1.z;
  }
  if (tid%32 == 31) {
    mintemp[tid/32] = mintemp1;
    maxtemp[tid/32] = maxtemp1;
  }
  __syncthreads();
  if (threadIdx.x < 32) {
        mintemp1= (tid < blockDim.x/32)?mintemp[threadIdx.x]:mindef;
        maxtemp1= (tid < blockDim.x/32)?maxtemp[threadIdx.x]:maxdef;
        for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(mintemp1.x,d);
         mintemp1.x=(mintemp1.x>temp2)?temp2:mintemp1.x;
         temp2 = __shfl_up(mintemp1.y,d);
         mintemp1.y=(mintemp1.y>temp2)?temp2:mintemp1.y;
         temp2 = __shfl_up(mintemp1.z,d);
         mintemp1.z=(mintemp1.z>temp2)?temp2:mintemp1.z;
         temp2 = __shfl_up(maxtemp1.x,d);
         maxtemp1.x=(maxtemp1.x<temp2)?temp2:maxtemp1.x;
         temp2 = __shfl_up(maxtemp1.y,d);
         maxtemp1.y=(maxtemp1.y<temp2)?temp2:maxtemp1.y;
         temp2 = __shfl_up(maxtemp1.z,d);
         maxtemp1.z=(maxtemp1.z<temp2)?temp2:maxtemp1.z;
        }
        if (tid < blockDim.x/32) {
          mintemp[tid] = mintemp1;
          maxtemp[tid] = maxtemp1;
        }
  }
  __syncthreads();
  mintemp1=mintemp[31];
  maxtemp1=maxtemp[31];
  if (threadIdx.x==(blockDim.x-1)) {
        do {} while( atomicAdd(&(ptoblockds->g_blockcnt),0) < my_blockId );
        mintemp1.x=(ptoblockds->minval.x<mintemp1.x)?ptoblockds->minval.x:mintemp1.x;
        maxtemp1.x=(ptoblockds->maxval.x>maxtemp1.x)?ptoblockds->maxval.x:maxtemp1.x;
        mintemp1.y=(ptoblockds->minval.y<mintemp1.y)?ptoblockds->minval.y:mintemp1.y;
        maxtemp1.y=(ptoblockds->maxval.y>maxtemp1.y)?ptoblockds->maxval.y:maxtemp1.y;
        mintemp1.z=(ptoblockds->minval.z<mintemp1.z)?ptoblockds->minval.z:mintemp1.z;
        maxtemp1.z=(ptoblockds->maxval.z>maxtemp1.z)?ptoblockds->maxval.z:maxtemp1.z;
        if(my_blockId==(gridDim.x-1)) { /* it is the last block; reset for next iteration */
                ptoblockds->minval=mindef;
                ptoblockds->maxval=maxdef;
                ptoblockds->g_blockcnt=0;
                ptoblockds->g_block_id=0;
                d_min[0]=mintemp1;
                d_max[0]=maxtemp1;
        } else {
                ptoblockds->minval=mintemp1;
                ptoblockds->maxval=maxtemp1;
                atomicAdd(&(ptoblockds->g_blockcnt),1);
        }
  }

}
