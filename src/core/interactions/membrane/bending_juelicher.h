#pragma once

#include  "common.h"

namespace bendingJuelicher
{
    struct GPU_BendingParams
    {
        float kb, H0;
    };

    __device__ inline float supplementaryDihedralAngle(float3 v0, float3 v1, float3 v2, float3 v3)
    {
        //       v3
        //     /   \
        //   v2 --- v0
        //     \   /
        //       V
        //       v1

        // dihedral: 0123    

        float3 n, k, nk;
        n  = cross(v1 - v0, v2 - v0);
        k  = cross(v2 - v0, v3 - v0);
        nk = cross(n, k);

        float theta = atan2(length(nk), dot(n, k));
        theta = dot(v2-v0, nk) < 0 ? -theta : theta;
        return theta;
    }

    __device__ inline float compute_lenTheta(float3 v0, float3 v1, float3 v2, float3 v3)
    {
        float len = length(v2 - v0);
        float theta = supplementaryDihedralAngle(v0, v1, v2, v3);
        return len * theta;
    }

    __global__ void computeAreasAndCurvatures(OVviewWithJuelicherQuants view, MembraneMeshView mesh)
    {
        int rbcId = blockIdx.x;
        int offset = rbcId * mesh.nvertices;

        float lenThetaTot = 0.0f;

        for (int idv0 = threadIdx.x; idv0 < mesh.nvertices; idv0 += blockDim.x) {

            int startId = mesh.maxDegree * idv0;
            int degree = mesh.degrees[idv0];

            int idv1 = mesh.adjacent[startId];
            int idv2 = mesh.adjacent[startId+1];

            float3 v0 = fetchVertex(view, offset + idv0);
            float3 v1 = fetchVertex(view, offset + idv1);
            float3 v2 = fetchVertex(view, offset + idv2);

            float area = 0;
            float lenTheta = 0;
        
            #pragma unroll 2
            for (int i = 0; i < degree; i++) {

                int idv3 = mesh.adjacent[startId + (i+2) % degree];
                float3 v3 = fetchVertex(view, offset + idv3);

                area     += 0.3333333f * triangleArea(v0, v1, v2);
                lenTheta += compute_lenTheta(v0, v1, v2, v3);

                v1 = v2;
                v2 = v3;
            }

            view.vertexAreas          [offset + idv0] = area;
            view.vertexMeanCurvatures [offset + idv0] = lenTheta / (4 * area);
        
            lenThetaTot += lenTheta;
        }

        lenThetaTot = warpReduce( lenThetaTot, [] (float a, float b) { return a+b; } );

        if (__laneid() == 0)
            atomicAdd(&view.lenThetaTot[rbcId], lenThetaTot);
    }

    __device__ inline float3 force_len(float H0, float theta, float3 v0, float3 v2, float Hv0, float Hv2)
    {
        float3 d = normalize(v0 - v2);
        return (Hv0 + Hv2 - 2 * H0) * theta * d;
    }

    __device__ inline float3 force_theta(float H0, float3 v0, float3 v1, float3 v2, float3 v3, float Hv0, float Hv2, float3 &f1)
    {
        float3 n, k, v20, v21, v23;

        v20 = v0 - v2;
        v21 = v1 - v2;
        v23 = v3 - v2;
    
        n = cross(v21, v20);
        k = cross(v20, v23);

        float inv_lenn = rsqrt(dot(n,n));
        float inv_lenk = rsqrt(dot(k,k));

        float cotangent2n = dot(v20, v21) * inv_lenn;
        float cotangent2k = dot(v23, v20) * inv_lenk;
    
        float3 d1 = (-dot(v20, v20)  * inv_lenn*inv_lenn) * n;
        float3 d0 =
            (cotangent2n * inv_lenn) * n +
            (cotangent2k * inv_lenk) * k;

        float coef = (Hv0 + Hv2 - 2*H0);

        f1 = coef * d1;
        return coef * d0;
    }

    __device__ inline float3 force_area(float H0, float3 v0, float3 v1, float3 v2, float Hv0, float Hv1, float Hv2)
    {
        float coef = -0.333333f * (Hv0 * Hv0 + Hv1 * Hv1 + Hv2 * Hv2 - 3 * H0 * H0);

        float3 n  = normalize(cross(v1-v0, v2-v0));
        float3 d0 = cross(n, v2 - v1);

        return coef * d0;
    }


    __global__ void computeBendingForces(OVviewWithJuelicherQuants view,
                                         MembraneMeshView mesh,
                                         GPU_BendingParams parameters)
    {
        int pid = threadIdx.x + blockDim.x * blockIdx.x;
        int locId = pid % mesh.nvertices;
        int rbcId = pid / mesh.nvertices;
        int offset = rbcId * mesh.nvertices;

        if (pid >= view.nObjects * mesh.nvertices) return;

        int startId = mesh.maxDegree * locId;
        int degree = mesh.degrees[locId];

        int idv1 = mesh.adjacent[startId];
        int idv2 = mesh.adjacent[startId+1];

        float3 v0 = fetchVertex(view, pid);
        float3 v1 = fetchVertex(view, offset + idv1);
        float3 v2 = fetchVertex(view, offset + idv2);

        float Hv0 = view.vertexMeanCurvatures[pid];
        float Hv1 = view.vertexMeanCurvatures[offset + idv1];
        float Hv2 = view.vertexMeanCurvatures[offset + idv2];

        float3 f0 = make_float3(0.f, 0.f, 0.f);
    
#pragma unroll 2
        for (int i = 0; i < degree; i++) {

            float3 f1;
            int idv3 = mesh.adjacent[startId + (i+2) % degree];
            float3 v3 = fetchVertex(view, offset + idv3);
            float Hv3 = view.vertexMeanCurvatures[offset + idv3];

            float theta = supplementaryDihedralAngle(v0, v1, v2, v3);        

            f0 += force_len(parameters.H0, theta, v0, v2, Hv0, Hv2);
            f0 += force_theta(parameters.H0, v0, v1, v2, v3, Hv0, Hv2, f1);
            f0 += force_area(parameters.H0, v0, v1, v2, Hv0, Hv1, Hv2);

            atomicAdd(view.forces + offset + idv1, parameters.kb * f1);
        
            v1   = v2;   v2   = v3;
            Hv1  = Hv2;  Hv2  = Hv3;        
            idv1 = idv2; idv2 = idv3;        
        }

        atomicAdd(view.forces + pid, parameters.kb * f0);
    }
}
