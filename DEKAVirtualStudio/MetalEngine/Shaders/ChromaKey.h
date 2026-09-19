//
//  ChromaKey.h — CbCr-distance keyer with smooth falloff and spill suppression.
//  Works for green, blue or any custom key colour because it measures chroma distance,
//  not a hard-coded channel difference.
//
#ifndef ChromaKey_h
#define ChromaKey_h

#include "ShaderCommon.h"

/// 0 = background (key colour), 1 = foreground.
inline float chromaMatte(float2 cbcr, constant DEKAFrameUniforms& u) {
    float d = distance(cbcr, u.keyCbCr);
    float base = d - u.keySimilarity;
    return pow(saturate(base / max(u.keySmoothness, 1e-4)), 1.5);
}

/// Desaturates pixels whose chroma is close to the key colour (green/blue fringing, bounce light).
inline float3 spillSuppress(float3 rgb, float2 cbcr, constant DEKAFrameUniforms& u) {
    if (u.keySpill <= 0.0) { return rgb; }
    float d = distance(cbcr, u.keyCbCr);
    float base = d - u.keySimilarity;
    float keep = pow(saturate(base / max(u.keySpill, 1e-4)), 1.5);
    return mix(float3(luma709(rgb)), rgb, keep);
}

/// Edge control on the (optionally feathered) matte. edge > 0 chokes, edge < 0 spreads.
inline float refineEdge(float m, float edge) {
    float lo = max(0.0,  edge) * 0.5;
    float hi = 1.0 + min(0.0, edge) * 0.5;
    return saturate((m - lo) / max(hi - lo, 1e-3));
}

#endif
