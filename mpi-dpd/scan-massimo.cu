#include <cstdio>

#include "common.h"
#include "scan-massimo.h"

typedef struct {
        int g_block_id;
        int g_blockcnt;
        int sum;
} sblockds_t;

#define MAXTHREADS 1024
#define WARPSIZE     32

__global__ void exclscn2e(int *d_data0, int *d_output0,
                        int *d_data1, int *d_output1,
                        int *d_data2, int *d_output2,
                        int *d_data3, int *d_output3,
                        int *d_data4, int *d_output4,
                        int *d_data5, int *d_output5,
                        int *d_data6, int *d_output6,
                        int *d_data7, int *d_output7) {
        const int twid=threadIdx.x%32;
        int wid=threadIdx.x/32;
        switch(wid) {
          case 0:
                if(twid<2) {
                        d_output0[twid]=d_data0[0]*twid;
                }
          return;
          case 1:
                if(twid<2) {
                        d_output1[twid]=d_data1[0]*twid;
                }
          return;
          case 2:
                if(twid<2) {
                        d_output2[twid]=d_data2[0]*twid;
                }
          return;
          case 3:
                if(twid<2) {
                        d_output3[twid]=d_data3[0]*twid;
                }
          return;
          case 4:
                if(twid<2) {
                        d_output4[twid]=d_data4[0]*twid;
                }
          return;
          case 5:
                if(twid<2) {
                        d_output5[twid]=d_data5[0]*twid;
                }
          return;
          case 6:
                if(twid<2) {
                        d_output6[twid]=d_data6[0]*twid;
                }
          return;
          case 7:
                if(twid<2) {
                        d_output7[twid]=d_data7[0]*twid;
                }
          return;
        }
}

__global__ void exclscnmb2e(int *d_data0, int *d_output0,
                        int *d_data1, int *d_output1,
                        int *d_data2, int *d_output2,
                        int *d_data3, int *d_output3,
                        int *d_data4, int *d_output4,
                        int *d_data5, int *d_output5,
                        int *d_data6, int *d_output6,
                        int *d_data7, int *d_output7) {
        const int twid=threadIdx.x;
        switch(blockIdx.x) {
          case 0:
                if(twid<2) {
                        d_output0[twid]=d_data0[0]*twid;
                }
          return;
          case 1:
                if(twid<2) {
                        d_output1[twid]=d_data1[0]*twid;
                }
          return;
          case 2:
                if(twid<2) {
                        d_output2[twid]=d_data2[0]*twid;
                }
          return;
          case 3:
                if(twid<2) {
                        d_output3[twid]=d_data3[0]*twid;
                }
          return;
          case 4:
                if(twid<2) {
                        d_output4[twid]=d_data4[0]*twid;
                }
          return;
          case 5:
                if(twid<2) {
                        d_output5[twid]=d_data5[0]*twid;
                }
          return;
          case 6:
                if(twid<2) {
                        d_output6[twid]=d_data6[0]*twid;
                }
          return;
          case 7:
                if(twid<2) {
                        d_output7[twid]=d_data7[0]*twid;
                }
          return;
        }
}

__global__ void exclscn2w(int *d_data, int *d_output, int size) {
  __shared__ int temp[32];
  int temp1, temp2, temp4;
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  const int tid = threadIdx.x;
  temp4 = temp1 = (tid+blockIdx.x*blockDim.x<size)?d_data[tid+blockIdx.x*blockDim.x]:0;
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
        if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (tid >= 32) { temp1 += temp[0]; }
  if(tid+blockIdx.x*blockDim.x<size) {
        d_output[tid+blockIdx.x*blockDim.x]=temp1-temp4;
  }
}

__global__ void exclscnmb2w(int *d_data0, int *d_output0,
                                int *d_data1, int *d_output1,
                                int *d_data2, int *d_output2,
                                int *d_data3, int *d_output3,
                                int *d_data4, int *d_output4,
                                int *d_data5, int *d_output5,
                                int *d_data6, int *d_output6,
                                int *d_data7, int *d_output7,
                                int *d_data8, int *d_output8,
                                int *d_data9, int *d_output9,
                                int *d_data10, int *d_output10,
                                int *d_data11, int *d_output11,
                                int size) {
  __shared__ int temp[32];
  int temp1, temp2, temp4;
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  const int tid = threadIdx.x;
  switch(blockIdx.x) {
    case 0:
      temp4 = temp1 = (tid<size)?d_data0[tid]:0;
    break;
    case 1:
      temp4 = temp1 = (tid<size)?d_data1[tid]:0;
    break;
    case 2:
      temp4 = temp1 = (tid<size)?d_data2[tid]:0;
    break;
    case 3:
      temp4 = temp1 = (tid<size)?d_data3[tid]:0;
    break;
    case 4:
      temp4 = temp1 = (tid<size)?d_data4[tid]:0;
    break;
    case 5:
      temp4 = temp1 = (tid<size)?d_data5[tid]:0;
    break;
    case 6:
      temp4 = temp1 = (tid<size)?d_data6[tid]:0;
    break;
    case 7:
      temp4 = temp1 = (tid<size)?d_data7[tid]:0;
    break;
    case 8:
      temp4 = temp1 = (tid<size)?d_data8[tid]:0;
    break;
    case 9:
      temp4 = temp1 = (tid<size)?d_data9[tid]:0;
    break;
    case 10:
      temp4 = temp1 = (tid<size)?d_data10[tid]:0;
    break;
    case 11:
      temp4 = temp1 = (tid<size)?d_data11[tid]:0;
    break;
  }
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
         if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (tid >= 32) { temp1 += temp[0]; }
  if(tid<size) {
    switch(blockIdx.x) {
    case 0:
      d_output0[tid]=temp1-temp4;
    break;
    case 1:
      d_output1[tid]=temp1-temp4;
    break;
    case 2:
      d_output2[tid]=temp1-temp4;
    break;
    case 3:
      d_output3[tid]=temp1-temp4;
    break;
    case 4:
      d_output4[tid]=temp1-temp4;
    break;
    case 5:
      d_output5[tid]=temp1-temp4;
    break;
    case 6:
      d_output6[tid]=temp1-temp4;
    break;
    case 7:
      d_output7[tid]=temp1-temp4;
    break;
    case 8:
      d_output8[tid]=temp1-temp4;
    break;
    case 9:
      d_output9[tid]=temp1-temp4;
    break;
    case 10:
      d_output10[tid]=temp1-temp4;
    break;
    case 11:
      d_output11[tid]=temp1-temp4;
    break;
    }
  }
}

__global__ void exclscnmb2ew(int *d_data0, int *d_output0,
                                int *d_data1, int *d_output1,
                                int *d_data2, int *d_output2,
                                int *d_data3, int *d_output3,
                                int *d_data4, int *d_output4,
                                int *d_data5, int *d_output5,
                                int *d_data6, int *d_output6,
                                int *d_data7, int *d_output7,
                                int *d_data8, int *d_output8,
                                int *d_data9, int *d_output9,
                                int *d_data10, int *d_output10,
                                int *d_data11, int *d_output11,
                                int *d_data20, int *d_output20,
                                int *d_data21, int *d_output21,
                                int *d_data22, int *d_output22,
                                int *d_data23, int *d_output23,
                                int *d_data24, int *d_output24,
                                int *d_data25, int *d_output25,
                                int *d_data26, int *d_output26,
                                int *d_data27, int *d_output27,
                                int size) {
  __shared__ int temp[32];
  int temp1, temp2, temp4;
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  const int tid = threadIdx.x;
  switch(blockIdx.x) {
    case 0:
      temp4 = temp1 = (tid<size)?d_data0[tid]:0;
    break;
    case 1:
      temp4 = temp1 = (tid<size)?d_data1[tid]:0;
    break;
    case 2:
      temp4 = temp1 = (tid<size)?d_data2[tid]:0;
    break;
    case 3:
      temp4 = temp1 = (tid<size)?d_data3[tid]:0;
    break;
    case 4:
      temp4 = temp1 = (tid<size)?d_data4[tid]:0;
    break;
    case 5:
      temp4 = temp1 = (tid<size)?d_data5[tid]:0;
    break;
    case 6:
      temp4 = temp1 = (tid<size)?d_data6[tid]:0;
    break;
    case 7:
      temp4 = temp1 = (tid<size)?d_data7[tid]:0;
    break;
    case 8:
      temp4 = temp1 = (tid<size)?d_data8[tid]:0;
    break;
    case 9:
      temp4 = temp1 = (tid<size)?d_data9[tid]:0;
    break;
    case 10:
      temp4 = temp1 = (tid<size)?d_data10[tid]:0;
    break;
    case 11:
      temp4 = temp1 = (tid<size)?d_data11[tid]:0;
    break;
  }
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
         if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (tid >= 32) { temp1 += temp[0]; }
  if(tid<size) {
    switch(blockIdx.x) {
    case 0:
      d_output0[tid]=temp1-temp4;
      if(tid<2) {
          d_output20[tid]=d_data20[0]*tid;
      }
    break;
    case 1:
      d_output1[tid]=temp1-temp4;
      if(tid<2) {
          d_output21[tid]=d_data21[0]*tid;
      }
    break;
    case 2:
      d_output2[tid]=temp1-temp4;
      if(tid<2) {
          d_output22[tid]=d_data22[0]*tid;
      }
    break;
    case 3:
      d_output3[tid]=temp1-temp4;
      if(tid<2) {
          d_output23[tid]=d_data23[0]*tid;
      }
    break;
    case 4:
      d_output4[tid]=temp1-temp4;
      if(tid<2) {
          d_output24[tid]=d_data24[0]*tid;
      }
    break;
    case 5:
      d_output5[tid]=temp1-temp4;
      if(tid<2) {
          d_output25[tid]=d_data25[0]*tid;
      }
    break;
    case 6:
      d_output6[tid]=temp1-temp4;
      if(tid<2) {
          d_output26[tid]=d_data26[0]*tid;
      }
    break;
    case 7:
      d_output7[tid]=temp1-temp4;
      if(tid<2) {
          d_output27[tid]=d_data27[0]*tid;
      }
    break;
    case 8:
      d_output8[tid]=temp1-temp4;
    break;
    case 9:
      d_output9[tid]=temp1-temp4;
    break;
    case 10:
      d_output10[tid]=temp1-temp4;
    break;
    case 11:
      d_output11[tid]=temp1-temp4;
    break;
    }
  }
}


__global__ void exclscnmb(int *d_data, int *d_output, int size) {
  __shared__ int temp[32];
  int temp1, temp2, temp3, temp4;
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  int tid = threadIdx.x;
  temp4 = temp1 = (tid+blockIdx.x*blockDim.x<size)?d_data[tid+blockIdx.x*blockDim.x]:0;
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
        if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (threadIdx.x < 32) {
        temp2 = 0;
        if (tid < blockDim.x/32) {
                temp2 = temp[threadIdx.x];
        }
        for (int d=1; d<32; d<<=1) {
         temp3 = __shfl_up(temp2,d);
         if (tid%32 >= d) {temp2 += temp3;}
        }
        if (tid < blockDim.x/32) { temp[tid] = temp2; }
  }
  __syncthreads();
  if (tid >= 32) { temp1 += temp[tid/32 - 1]; }
  __syncthreads();
  if(tid+blockIdx.x*blockDim.x<size) {
        d_output[tid+blockIdx.x*blockDim.x]=temp1-temp4;
  }
}

__global__ void exclscan(int *d_data, int *d_output, int size, sblockds_t *ptoblockds) {
  __shared__ int temp[32];
  __shared__ unsigned int my_blockId;
  int temp1, temp2, temp3, temp4;
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  if (threadIdx.x==0) {
         my_blockId = atomicAdd( &(ptoblockds->g_block_id), 1 );
  }
  __syncthreads();
  int tid = threadIdx.x;
  temp4 = temp1 = (tid+my_blockId*blockDim.x<size)?d_data[tid+my_blockId*blockDim.x]:0;
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
        if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (threadIdx.x < 32) {
        temp2 = 0;
        if (tid < blockDim.x/32) {
                temp2 = temp[threadIdx.x];
        }
        for (int d=1; d<32; d<<=1) {
         temp3 = __shfl_up(temp2,d);
         if (tid%32 >= d) {temp2 += temp3;}
        }
        if (tid < blockDim.x/32) { temp[tid] = temp2; }
  }
  __syncthreads();
  if (tid >= 32) { temp1 += temp[tid/32 - 1]; }
  __syncthreads();
  if (threadIdx.x==(blockDim.x-1)) {
        do {} while( atomicAdd(&(ptoblockds->g_blockcnt),0) < my_blockId );
        temp[0]=ptoblockds->sum;
        if(my_blockId==(gridDim.x-1)) { /* it is the last block; reset for next iteration */
                ptoblockds->sum=0;
                ptoblockds->g_blockcnt=0;
                ptoblockds->g_block_id=0;
        } else {
                ptoblockds->sum=temp[0]+temp1;
                atomicAdd(&(ptoblockds->g_blockcnt),1);
        }
        __threadfence();  // wait for write completion
  }
  __syncthreads();
  temp1+=temp[0];
  if(tid+my_blockId*blockDim.x<size) {
        d_output[tid+my_blockId*blockDim.x]=temp1-temp4;
  }
}

__global__ void excl26scan(  const int *d_data30,  int *d_output30,
                             const int *d_data31,  int *d_output31,
                             const int *d_data32,  int *d_output32,
                             const int *d_data33,  int *d_output33,
                             const int *d_data34,  int *d_output34,
                             const int *d_data35,  int *d_output35,
                             const int *d_data0, int *d_output0,
                             const int *d_data1, int *d_output1,
                             const int *d_data2, int *d_output2,
                             const int *d_data3, int *d_output3,
                             const int *d_data4, int *d_output4,
                             const int *d_data5, int *d_output5,
                             const int *d_data6, int *d_output6,
                             const int *d_data7, int *d_output7,
                             const int *d_data8, int *d_output8,
                             const int *d_data9, int *d_output9,
                             const int *d_data10, int *d_output10,
                             const int *d_data11, int *d_output11,
                             const int *d_data20, int *d_output20,
                             const int *d_data21, int *d_output21,
                             const int *d_data22, int *d_output22,
                             const int *d_data23, int *d_output23,
                             const int *d_data24, int *d_output24,
                             const int *d_data25, int *d_output25,
                             const int *d_data26, int *d_output26,
                             const int *d_data27, int *d_output27,
                             const int size, int size1, sblockds_t *ptoblockds) {
  __shared__ int temp[32];
  __shared__ unsigned int my_blockId;
  int temp1, temp2, temp3, temp4;
  const int which=blockIdx.x/((size1+(blockDim.x-1))/blockDim.x);
  if(blockDim.x>MAXTHREADS) {
        printf("Invalid number of threads per block: %d, must be <=%d\n",blockDim.x,MAXTHREADS);
  }
  temp3=6*((size1+(blockDim.x-1))/blockDim.x);
  int tid = threadIdx.x;
  if(blockIdx.x>=temp3) {
	goto smallscan;
  }
  if (threadIdx.x==0) {
         my_blockId = atomicAdd( &(ptoblockds[which].g_block_id), 1 );
  }
  __syncthreads();
  switch(which) {
    case 0:
      temp4 = temp1 = (tid+my_blockId*blockDim.x<size1)?
                       d_data30[tid+my_blockId*blockDim.x]:0;
    break;
    case 1:
      temp4 = temp1 = (tid+my_blockId*blockDim.x<size1)?
                       d_data31[tid+my_blockId*blockDim.x]:0;
    break;
    case 2:
      temp4 = temp1 = (tid+my_blockId*blockDim.x<size1)?
                       d_data32[tid+my_blockId*blockDim.x]:0;
    break;
    case 3:
      temp4 = temp1 = (tid+my_blockId*blockDim.x<size1)?
                       d_data33[tid+my_blockId*blockDim.x]:0;
    break;
    case 4:
      temp4 = temp1 = (tid+my_blockId*blockDim.x<size1)?
                       d_data34[tid+my_blockId*blockDim.x]:0;
    break;
    case 5:
      temp4 = temp1 = (tid+my_blockId*blockDim.x<size1)?
                       d_data35[tid+my_blockId*blockDim.x]:0;
    break;
  }

  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
        if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (threadIdx.x < 32) {
        temp2 = 0;
        if (tid < blockDim.x/32) {
                temp2 = temp[threadIdx.x];
        }
        for (int d=1; d<32; d<<=1) {
         temp3 = __shfl_up(temp2,d);
         if (tid%32 >= d) {temp2 += temp3;}
        }
        if (tid < blockDim.x/32) { temp[tid] = temp2; }
  }
  __syncthreads();
  if (tid >= 32) { temp1 += temp[tid/32 - 1]; }
  __syncthreads();
  if (threadIdx.x==(blockDim.x-1)) {
        do {} while( atomicAdd(&(ptoblockds[which].g_blockcnt),0) < my_blockId );
        temp[0]=ptoblockds[which].sum;
        if(my_blockId==(((size1+(blockDim.x-1))/blockDim.x)-1)) { /* it is the last block; reset for next iteration */
                ptoblockds[which].sum=0;
                ptoblockds[which].g_blockcnt=0;
                ptoblockds[which].g_block_id=0;
        } else {
                ptoblockds[which].sum=temp[0]+temp1;
                atomicAdd(&(ptoblockds[which].g_blockcnt),1);
        }
        __threadfence();  // wait for write completion
  }
  __syncthreads();
  temp1+=temp[0];
  if(tid+my_blockId*blockDim.x<size1) {
    switch(which) {
        case 0:
          d_output30[tid+my_blockId*blockDim.x]=temp1-temp4;
        break;
        case 1:
          d_output31[tid+my_blockId*blockDim.x]=temp1-temp4;
        break;
        case 2:
          d_output32[tid+my_blockId*blockDim.x]=temp1-temp4;
        break;
        case 3:
          d_output33[tid+my_blockId*blockDim.x]=temp1-temp4;
        break;
        case 4:
          d_output34[tid+my_blockId*blockDim.x]=temp1-temp4;
        break;
        case 5:
          d_output35[tid+my_blockId*blockDim.x]=temp1-temp4;
        break;
    }
  }
  return;
smallscan:
  if(tid>=(((size+WARPSIZE-1)/WARPSIZE)*WARPSIZE)) {
	return;
  }
  switch(blockIdx.x-temp3) {
    case 0:
      temp4 = temp1 = (tid<size)?d_data0[tid]:0;
    break;
    case 1:
      temp4 = temp1 = (tid<size)?d_data1[tid]:0;
    break;
    case 2:
      temp4 = temp1 = (tid<size)?d_data2[tid]:0;
    break;
    case 3:
      temp4 = temp1 = (tid<size)?d_data3[tid]:0;
    break;
    case 4:
      temp4 = temp1 = (tid<size)?d_data4[tid]:0;
    break;
    case 5:
      temp4 = temp1 = (tid<size)?d_data5[tid]:0;
    break;
    case 6:
      temp4 = temp1 = (tid<size)?d_data6[tid]:0;
    break;
    case 7:
      temp4 = temp1 = (tid<size)?d_data7[tid]:0;
    break;
    case 8:
      temp4 = temp1 = (tid<size)?d_data8[tid]:0;
    break;
    case 9:
      temp4 = temp1 = (tid<size)?d_data9[tid]:0;
    break;
    case 10:
      temp4 = temp1 = (tid<size)?d_data10[tid]:0;
    break;
    case 11:
      temp4 = temp1 = (tid<size)?d_data11[tid]:0;
    break;
    default:
    return;
  }
  for (int d=1; d<32; d<<=1) {
         temp2 = __shfl_up(temp1,d);
         if (tid%32 >= d) temp1 += temp2;
  }
  if (tid%32 == 31) temp[tid/32] = temp1;
  __syncthreads();
  if (tid >= 32) { temp1 += temp[0]; }
  if(tid<size) {
    switch(blockIdx.x-temp3) {
    case 0:
      d_output0[tid]=temp1-temp4;
      if(tid<2) {
          d_output20[tid]=d_data20[0]*tid;
      }
    break;
    case 1:
      d_output1[tid]=temp1-temp4;
      if(tid<2) {
          d_output21[tid]=d_data21[0]*tid;
      }
    break;
    case 2:
      d_output2[tid]=temp1-temp4;
      if(tid<2) {
          d_output22[tid]=d_data22[0]*tid;
      }
    break;
    case 3:
      d_output3[tid]=temp1-temp4;
      if(tid<2) {
          d_output23[tid]=d_data23[0]*tid;
      }
    break;
    case 4:
      d_output4[tid]=temp1-temp4;
      if(tid<2) {
          d_output24[tid]=d_data24[0]*tid;
      }
    break;
    case 5:
      d_output5[tid]=temp1-temp4;
      if(tid<2) {
          d_output25[tid]=d_data25[0]*tid;
      }
    break;
    case 6:
      d_output6[tid]=temp1-temp4;
      if(tid<2) {
          d_output26[tid]=d_data26[0]*tid;
      }
    break;
    case 7:
      d_output7[tid]=temp1-temp4;
      if(tid<2) {
          d_output27[tid]=d_data27[0]*tid;
      }
    break;
    case 8:
      d_output8[tid]=temp1-temp4;
    break;
    case 9:
      d_output9[tid]=temp1-temp4;
    break;
    case 10:
      d_output10[tid]=temp1-temp4;
    break;
    case 11:
      d_output11[tid]=temp1-temp4;
    break;
    }
  }
}

#include <algorithm>

void scan_massimo(const int * const count[26], int * const result[26], const int sizes[26], cudaStream_t stream)
{
    static int newscani=1;
#if 0
    static  sblockds_t *ptoblockds[26];
#else
    static  sblockds_t *ptoblockds;
#endif
     static int mb[6], mw[12];
    if(newscani) {
   	 CUDA_CHECK(cudaMalloc((void **)&ptoblockds,6*sizeof(sblockds_t)));
         CUDA_CHECK(cudaMemset(ptoblockds,0,6*sizeof(sblockds_t)));
#if 0
   	 for(int i = 0; i < 26; ++i) {
   	 CUDA_CHECK(cudaMalloc((void **)&ptoblockds[i],sizeof(sblockds_t)));
         CUDA_CHECK(cudaMemset(ptoblockds[i],0,sizeof(sblockds_t)));
    	}
#endif
	mb[0]=8;
	mb[1]=17;
	mb[2]=20;
	mb[3]=23;
	mb[4]=24;
	mb[5]=25;
	mw[0]=2;
	mw[1]=5;
	mw[2]=6;
	mw[3]=7;
	mw[4]=11;
	mw[5]=14;
	mw[6]=15;
	mw[7]=16;
	mw[8]=18;
	mw[9]=19;
	mw[10]=21;
	mw[11]=22;
   	newscani=0;
    }

    const int maxsize = *std::max_element(sizes, sizes + 26);
    printf("maxsize is %d\n", maxsize);
#define NTHREADS 1024
	excl26scan<<<12+(6*((maxsize+NTHREADS-1)/NTHREADS)),NTHREADS,0, stream>>>(
	    count[mb[0]] , result[mb[0]],
	    count[mb[1]] , result[mb[1]],
	    count[mb[2]] , result[mb[2]],
	    count[mb[3]] , result[mb[3]],
	    count[mb[4]] , result[mb[4]],
	    count[mb[5]] , result[mb[5]],
	    count[mw[0]] , result[mw[0]],
	    count[mw[1]] , result[mw[1]],
	    count[mw[2]] , result[mw[2]],
	    count[mw[3]] , result[mw[3]],
	    count[mw[4]] , result[mw[4]],
	    count[mw[5]] , result[mw[5]],
	    count[mw[6]] , result[mw[6]],
	    count[mw[7]] , result[mw[7]],
	    count[mw[8]] , result[mw[8]],
	    count[mw[9]] , result[mw[9]],
	    count[mw[10]], result[mw[10]],
	    count[mw[11]], result[mw[11]],
	    count[0]     , result[0],
	    count[1]     , result[1],
	    count[3]     , result[3],
	    count[4]     , result[4],
	    count[9]     , result[9],
	    count[10]    , result[10],
	    count[12]    , result[12],
	    count[13]    , result[13],
	    maxsize, 49, ptoblockds);

	CUDA_CHECK(cudaPeekAtLastError());
	CUDA_CHECK(cudaDeviceSynchronize());
	
}


#undef MAXTHREADS
#undef WARPSIZE
