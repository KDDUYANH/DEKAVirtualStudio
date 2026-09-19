//
//  ShaderCommon.h — shared Metal helpers (Metal-only header, never imported by Swift)
//
#ifndef ShaderCommon_h
#define ShaderCommon_h

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

constexpr sampler kLinearClamp(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler kLinearRepeat(coord::normalized, address::repeat, filter::linear);
constexpr sampler kLinearZero(coord::normalized, address::clamp_to_zero, filter::linear);

inline float luma709(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

/// Rec.709 RGB -> (Cb, Cr) centred on 0. Used by the keyer.
inline float2 rgbToCbCr709(float3 c) {
    float y = luma709(c);
    return float2((c.b - y) / 1.8556, (c.r - y) / 1.5748);
}

/// Output-pixel UV -> camera-buffer UV (foreground transform, orientation, mirror).
inline float2 outputToSourceUV(float2 uv, constant DEKAFrameUniforms& u) {
    float2 p = (uv - 0.5 - u.fgOffset) / max(u.fgScale, float2(1e-3));
    p = p * u.srcAspectFix + 0.5;
    if (u.rotate180 != 0) { p = 1.0 - p; }
    if (u.mirror != 0)    { p.x = 1.0 - p.x; }
    return p;
}

inline bool insideUnit(float2 p) {
    return all(p >= 0.0) && all(p <= 1.0);
}

/// Decode one bi-planar 4:2:0 sample to display-referred RGB.
inline float3 decodeYCbCr(texture2d<float, access::sample> yTex,
                          texture2d<float, access::sample> cTex,
                          float2 srcUV,
                          constant DEKAFrameUniforms& u) {
    float  y  = yTex.sample(kLinearClamp, srcUV).r;
    float2 cc = cTex.sample(kLinearClamp, srcUV).rg;
    float3 ycc = (float3(y, cc) - u.yuvOffset) * u.yuvScale;
    return saturate(u.yuvToRgb * ycc);
}

#endif
