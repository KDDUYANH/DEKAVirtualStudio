//
//  ColorGrade.h — real-time primary grade (GPU). Order matters and mirrors a colourist's node:
//  linear exposure/WB -> tone (blacks/whites, shadows/highlights, contrast) -> detail
//  -> lift/gamma/gain/offset -> hue -> saturation/vibrance.
//
#ifndef ColorGrade_h
#define ColorGrade_h

#include "ShaderCommon.h"

inline float3 decodeDisplay(float3 c) { return pow(max(c, 0.0), 2.4); }        // BT.1886 EOTF
inline float3 encodeDisplay(float3 c) { return pow(max(c, 0.0), 1.0 / 2.4); }

inline float3 rotateHue(float3 c, float angle) {
    if (angle == 0.0) { return c; }
    const float3 k = float3(0.57735026919);
    float cs = cos(angle), sn = sin(angle);
    return c * cs + cross(k, c) * sn + k * dot(k, c) * (1.0 - cs);
}

/// `srcLuma` / `blurLuma` are only used for midtone detail (local contrast).
inline float3 colorGrade(float3 c, float srcLuma, float blurLuma, constant DEKAFrameUniforms& u) {
    if (u.colorEnabled == 0) { return c; }

    // 1. Exposure + white balance in linear light (physically meaningful).
    float3 lin = decodeDisplay(c) * exp2(u.exposure) * u.wbGains;
    c = encodeDisplay(lin);

    // 2. Black / white points.
    float blackOut = 0.10 * u.blacks;
    float whiteOut = 1.0 + 0.20 * u.whites;
    c = blackOut + c * (whiteOut - blackOut);

    // 3. Shadows / highlights — luminance-masked gain so neutrals stay neutral.
    float L = luma709(saturate(c));
    float shMask = 1.0 - smoothstep(0.0, 0.55, L); shMask *= shMask;
    float hiMask = smoothstep(0.45, 1.0, L);       hiMask *= hiMask;
    c *= 1.0 + 0.8 * u.shadows * shMask;
    c  = mix(c, (u.highlights >= 0.0) ? c + (1.0 - c) * 0.5 * u.highlights : c * (1.0 + 0.6 * u.highlights), hiMask);

    // 4. Contrast around mid-grey (display space pivot 0.435 ≈ 18% grey through 2.4 gamma).
    const float pivot = 0.435;
    c = (c - pivot) * (1.0 + u.contrast) + pivot;

    // 5. Midtone detail — unsharp mask on luma, weighted to midtones.
    if (u.midtoneDetail != 0.0) {
        float mid = 1.0 - abs(L * 2.0 - 1.0);
        c += (srcLuma - blurLuma) * u.midtoneDetail * 2.0 * mid;
    }

    // 6. Lift / Gamma / Gain / Offset (per channel; master is folded in on the CPU).
    c = c * u.gain + u.lift * (1.0 - c);
    c = pow(max(c, 0.0), 1.0 / max(u.gammaRGB, float3(0.05)));
    c += u.offset;

    // 7. Hue.
    c = rotateHue(c, u.hueRadians);

    // 8. Saturation + vibrance (vibrance protects already-saturated colours).
    float Y = luma709(c);
    c = mix(float3(Y), c, 1.0 + u.saturation);
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float vib = u.vibrance * (1.0 - saturate(mx - mn));
    c = mix(float3(Y), c, 1.0 + vib);

    return saturate(c);
}

#endif
