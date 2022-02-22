// Copyright 2020 ETH Zurich. All Rights Reserved.
#pragma once

#include <mirheo/core/datatypes.h>
#include <mirheo/core/utils/reflection.h>
#include <mirheo/core/utils/variant.h>

namespace mirheo
{

// forward declaration of pairwise kernels

class PairwiseDPD;
class PairwiseNoRandomDPD;
class PairwiseLJ;

struct AwarenessNone;
struct AwarenessObject;
struct AwarenessRod;

template <class Awareness>
class PairwiseRepulsiveLJ;

template <class Awareness>
class PairwiseGrowingRepulsiveLJ;

class PairwiseMDPD;

template <class Awareness>
class PairwiseMorse;

class SimpleMDPDDensityKernel;
class WendlandC2DensityKernel;

template <typename DensityKernel>
class PairwiseDensity;

class LinearPressureEOS;
class QuasiIncompressiblePressureEOS;

template <typename PressureEOS, typename DensityKernel>
class PairwiseSDPD;

// corresponding parameters, visible by users

/// Dissipative Particle Dynamics  parameters
struct DPDParams
{
    using KernelType = PairwiseDPD; ///< the corresponding kernel
    real a;     ///< conservative force coefficient
    real gamma; ///< dissipative force conservative
    real kBT;   ///< temperature in energy units
    real power; ///< exponent of the envelope of the viscous kernel
};
MIRHEO_MEMBER_VARS(DPDParams, a, gamma, kBT, power);

/// Dissipative Particle Dynamics parameters with no fluctuations
struct NoRandomDPDParams
{
    using KernelType = PairwiseNoRandomDPD; ///< the corresponding kernel
    real a;     ///< conservative force coefficient
    real gamma; ///< dissipative force conservative
    real kBT;   ///< temperature in energy units
    real power; ///< exponent of the envelope of the viscous kernel
};
MIRHEO_MEMBER_VARS(NoRandomDPDParams, a, gamma, kBT, power);

/// Lennard-Jones parameters
struct LJParams
{
    using KernelType = PairwiseLJ; ///< the corresponding kernel
    real epsilon; ///< force coefficient
    real sigma;   ///< radius with zero energy in LJ potential
};
MIRHEO_MEMBER_VARS(LJParams, epsilon, sigma);

/// Parameters for no awareness in pairwise interactions
struct AwarenessParamsNone
{
    using KernelType = AwarenessNone; ///< the corresponding kernel
};
MIRHEO_MEMBER_VARS(AwarenessParamsNone);

/// Parameters for object awareness in pairwise interactions
struct AwarenessParamsObject
{
    using KernelType = AwarenessObject; ///< the corresponding kernel
};
MIRHEO_MEMBER_VARS(AwarenessParamsObject);

/// Parameters for rod awareness in pairwise interactions
struct AwarenessParamsRod
{
    using KernelType = AwarenessRod; ///< the corresponding kernel
    int minSegmentsDist; ///< number of segments away to ignore the self interaction
};
MIRHEO_MEMBER_VARS(AwarenessParamsRod, minSegmentsDist);

/// variant of all awareness modes
using VarAwarenessParams = mpark::variant<AwarenessParamsNone,
                                          AwarenessParamsObject,
                                          AwarenessParamsRod>;


/// Repulsive Lennard-Jones parameters
struct RepulsiveLJParams
{
    real epsilon;  ///< force coefficient
    real sigma;    ///< radius with zero energy in LJ potential
    real maxForce; ///< cap force
    VarAwarenessParams varAwarenessParams; ///< awareness
};
MIRHEO_MEMBER_VARS(RepulsiveLJParams, epsilon, sigma, maxForce, varAwarenessParams);

/// Growing Repulsive Lennard-Jones parameters
struct GrowingRepulsiveLJParams
{
    real epsilon;  ///< force coefficient
    real sigma;    ///< radius with zero energy in LJ potential
    real maxForce; ///< cap force
    VarAwarenessParams varAwarenessParams; ///< awareness
    real initialLengthFraction; ///< initial factor for the length scale
    real growUntil; ///< time after which the length factor is one
};
MIRHEO_MEMBER_VARS(GrowingRepulsiveLJParams, epsilon, sigma, maxForce, varAwarenessParams, initialLengthFraction, growUntil);


/// Morse parameters
struct MorseParams
{
    real De; ///< force coefficient
    real r0; ///< zero force distance
    real beta; ///< interaction range parameter
    VarAwarenessParams varAwarenessParams; ///< awareness
};
MIRHEO_MEMBER_VARS(MorseParams, De, r0, beta, varAwarenessParams);


/// Multi-body Dissipative Particle Dynamics parameters
struct MDPDParams
{
    using KernelType = PairwiseMDPD; ///< the corresponding kernel
    real rd;    ///< density cut-off radius
    real a;     ///< conservative force coefficient (repulsive)
    real b;     ///< conservative force coefficient (attractive)
    real gamma; ///< dissipative force conservative
    real kBT;   ///< temperature in energy units
    real power; ///< exponent of the envelope of the viscous kernel
};
MIRHEO_MEMBER_VARS(MDPDParams, rd, a, b, gamma, kBT, power);

/// Density parameters for MDPD
struct SimpleMDPDDensityKernelParams
{
    using KernelType = SimpleMDPDDensityKernel; ///< the corresponding kernel
};
MIRHEO_MEMBER_VARS(SimpleMDPDDensityKernelParams);

/// Density parameters for Wendland C2 function
struct WendlandC2DensityKernelParams
{
    using KernelType = WendlandC2DensityKernel; ///< the corresponding kernel
};
MIRHEO_MEMBER_VARS(WendlandC2DensityKernelParams);

/// variant of all density types
using VarDensityKernelParams = mpark::variant<SimpleMDPDDensityKernelParams,
                                              WendlandC2DensityKernelParams>;

/// Density parameters
struct DensityParams
{
    VarDensityKernelParams varDensityKernelParams; ///< kernel parameters
};
MIRHEO_MEMBER_VARS(DensityParams, varDensityKernelParams);


/// parameters for linear equation of state
struct LinearPressureEOSParams
{
    using KernelType = LinearPressureEOS; ///< the corresponding kernel
    real soundSpeed; ///< Speed of sound
    real rho0;       ///< reference density
};
MIRHEO_MEMBER_VARS(LinearPressureEOSParams, soundSpeed, rho0);

/// parameters for quasi incompressible equation of state
struct QuasiIncompressiblePressureEOSParams
{
    using KernelType = QuasiIncompressiblePressureEOS;  ///< the corresponding kernel
    real p0;   ///< pressure magnitude
    real rhor; ///< reference density
};
MIRHEO_MEMBER_VARS(QuasiIncompressiblePressureEOSParams, p0, rhor);

/// variant of all equation of states parameters
using VarEOSParams = mpark::variant<LinearPressureEOSParams,
                                    QuasiIncompressiblePressureEOSParams>;

/// variant of all density kernels compatible with SDPD
using VarSDPDDensityKernelParams = mpark::variant<WendlandC2DensityKernelParams>;

/// Smoothed Dissipative Particle Dynamics parameters
struct SDPDParams
{
    real viscosity; ///< dynamic viscosity of the fluid
    real kBT;       ///< temperature in energy units
    VarEOSParams varEOSParams; ///< equation of state
    VarSDPDDensityKernelParams varDensityKernelParams; ///< density kernel
};
MIRHEO_MEMBER_VARS(SDPDParams, viscosity, kBT, varEOSParams, varDensityKernelParams);

/// variant of all possible pairwise interactions
using VarPairwiseParams = mpark::variant<DPDParams,
                                         LJParams,
                                         MorseParams,
                                         RepulsiveLJParams,
                                         GrowingRepulsiveLJParams,
                                         MDPDParams,
                                         DensityParams,
                                         SDPDParams>;


/// parameters when the stress is not active
struct StressNoneParams {};
MIRHEO_MEMBER_VARS(StressNoneParams);

/// parameters when the stress is active
struct StressActiveParams
{
    real period; ///< compute stresses every this time in time units
};
MIRHEO_MEMBER_VARS(StressActiveParams, period);

/// active/non active stress parameters
using VarStressParams = mpark::variant<StressNoneParams, StressActiveParams>;

} // namespace mirheo
