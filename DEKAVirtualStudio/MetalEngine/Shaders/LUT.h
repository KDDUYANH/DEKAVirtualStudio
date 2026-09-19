//
//  LUT.h — 3D LUT lookup with hardware trilinear interpolation.
//  The half-texel remap makes lattice point i land exactly on texel centre i, which is what
//  the .cube spec (and Resolve/Premiere) assume.
//
#ifndef LUT_h
#define LUT_h

#include "ShaderCommon.h"

inline float3 applyLUT(float3 c, texture3d<float, access::sample> lut, constant DEKAFrameUniforms& u) {
    if (u.lutEnabled == 0 || u.lutIntensity <= 0.0) { return c; }
    float3 range = max(u.lutDomainMax - u.lutDomainMin, float3(1e-5));
    float3 n = saturate((c - u.lutDomainMin) / range);
    float  scale = (u.lutSize - 1.0) / u.lutSize;
    float  off   = 0.5 / u.lutSize;
    float3 graded = lut.sample(kLinearClamp, n * scale + off).rgb;
    return mix(c, graded, u.lutIntensity);
}

#endif
