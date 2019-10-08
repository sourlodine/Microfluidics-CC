#pragma once

#include <extern/variant/include/mpark/variant.hpp>

// forward declaration of pairwise kernels

class PairwiseDPD;

struct LJAwarenessNone;
struct LJAwarenessObject;
struct LJAwarenessRod;

template <class Awareness>
class PairwiseLJ;

class PairwiseMDPD;

class SimpleMDPDDensityKernel;
class WendlandC2DensityKernel;

template <typename DensityKernel>
class PairwiseDensity;

class LinearPressureEOS;
class QuasiIncompressiblePressureEOS;

template <typename PressureEOS, typename DensityKernel>
class PairwiseSDPD;

// corresponding parameters, visible by users

struct DPDParams
{
    using KernelType = PairwiseDPD;
    float a, gamma, kBT, power;
};

struct LJAwarenessParamsNone   {using KernelType = LJAwarenessNone;};
struct LJAwarenessParamsObject {using KernelType = LJAwarenessObject;};
struct LJAwarenessParamsRod
{
    using KernelType = LJAwarenessRod;
    int minSegmentsDist;
};

using VarLJAwarenessParams = mpark::variant<LJAwarenessParamsNone,
                                            LJAwarenessParamsObject,
                                            LJAwarenessParamsRod>;

struct LJParams
{
    float epsilon, sigma, maxForce;
    VarLJAwarenessParams varLJAwarenessParams;
};

struct MDPDParams
{
    using KernelType = PairwiseMDPD;
    float rd, a, b, gamma, kBT, power;
};


struct SimpleMDPDDensityKernelParams {using KernelType = SimpleMDPDDensityKernel;};
struct WendlandC2DensityKernelParams {using KernelType = WendlandC2DensityKernel;};

using VarDensityKernelParams = mpark::variant<SimpleMDPDDensityKernelParams,
                                              WendlandC2DensityKernelParams>;


struct DensityParams
{
    VarDensityKernelParams varDensityKernelParams;
};


struct LinearPressureEOSParams
{
    using KernelType = LinearPressureEOS;
    float soundSpeed, rho0;
};

struct QuasiIncompressiblePressureEOSParams
{
    using KernelType = QuasiIncompressiblePressureEOS;
    float p0, rhor;
};

using VarEOSParams = mpark::variant<LinearPressureEOSParams,
                                    QuasiIncompressiblePressureEOSParams>;


using VarSDPDDensityKernelParams = mpark::variant<WendlandC2DensityKernelParams>;

struct SDPDParams
{
    float viscosity, kBT;
    VarEOSParams varEOSParams;
    VarSDPDDensityKernelParams varDensityKernelParams;
};


using VarPairwiseParams = mpark::variant<DPDParams,
                                         LJParams,
                                         MDPDParams,
                                         DensityParams,
                                         SDPDParams>;


struct StressNoneParams {};

struct StressActiveParams
{
    float period; // compute stresses every this time in time units
};

using VarStressParams = mpark::variant<StressNoneParams, StressActiveParams>;
