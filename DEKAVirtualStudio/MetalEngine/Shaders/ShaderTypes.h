//
//  ShaderTypes.h
//  DEKA Virtual Studio
//
//  Shared between Swift (via the bridging header) and Metal. Because both sides compile
//  the SAME struct definitions, the memory layout of the uniforms always matches.
//  Rules: only simd types + int/float. No bool (size differs between C and MSL).
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>


// ---- Enumerations (as int32 constants) -------------------------------------------------

// Key mode
#define DEKA_KEY_OFF      0
#define DEKA_KEY_CHROMA   1
#define DEKA_KEY_AI       2

// Background type
#define DEKA_BG_NONE      0
#define DEKA_BG_SOLID     1
#define DEKA_BG_GRADIENT  2
#define DEKA_BG_TEXTURE   3   // image or video

// Preview (monitor) mode — never affects the program output
#define DEKA_PREVIEW_PROGRAM   0
#define DEKA_PREVIEW_MATTE     1
#define DEKA_PREVIEW_ORIGINAL  2

// ---- Per-frame uniforms -----------------------------------------------------------------

typedef struct {
    // Input decode (camera is bi-planar 4:2:0 YCbCr)
    simd_float3x3 yuvToRgb;      // matrix for BT.601 / BT.709 chosen per frame from buffer attachments
    simd_float3   yuvOffset;     // (Y black, Cb mid, Cr mid)
    simd_float3   yuvScale;      // range expansion (video range -> full)

    // Foreground (camera) transform in output-normalized space
    simd_float2   fgScale;       // 1 = fill
    simd_float2   fgOffset;      // -0.5 ... 0.5
    simd_float2   srcAspectFix;  // aspect-fill correction when camera aspect != output aspect
    int       rotate180;     // landscape-left vs landscape-right
    int       mirror;        // front camera

    // ---- Color (display-referred Rec.709) ----
    simd_float3   lift;          // per channel, master folded in on CPU
    simd_float3   gammaRGB;
    simd_float3   gain;
    simd_float3   offset;
    simd_float3   wbGains;       // temperature/tint as linear-light RGB gains
    float         exposure;      // stops
    float         contrast;      // -1 ... 1
    float         highlights;    // -1 ... 1
    float         shadows;       // -1 ... 1
    float         whites;        // -1 ... 1
    float         blacks;        // -1 ... 1
    float         saturation;    // -1 ... 1
    float         vibrance;      // -1 ... 1
    float         hueRadians;
    float         midtoneDetail; // -1 ... 1 (needs blurred luma texture)
    int       colorEnabled;

    // ---- LUT ----
    simd_float3   lutDomainMin;
    simd_float3   lutDomainMax;
    float         lutSize;
    float         lutIntensity;  // 0 ... 1
    int       lutEnabled;

    // ---- Key ----
    simd_float2   keyCbCr;       // key colour in CbCr (centered at 0)
    float         keySimilarity;
    float         keySmoothness;
    float         keySpill;
    float         keyEdge;       // -1 (spread) ... 1 (choke)
    float         keyOpacity;
    int       keyMode;

    // ---- Background ----
    simd_float4   bgColorA;
    simd_float4   bgColorB;
    simd_float2   bgScale;
    simd_float2   bgOffset;
    simd_float2   bgAspectFix;   // aspect-fill correction for the background texture
    float         bgGradientAngle;
    float         bgOpacity;
    float         bgBrightness;  // -1 ... 1
    float         bgContrast;    // -1 ... 1
    int       bgType;

    // ---- Person shadow / light wrap ----
    simd_float2   shadowOffset;
    float         shadowOpacity;
    float         lightWrap;

    // ---- Graphics ----
    simd_float4   tickerRect;     // x, y, w, h in normalized output coords
    float         tickerScroll;   // normalized u offset in strip texture
    float         tickerStripAspect; // strip width / strip height in pixels
    int       graphicsEnabled;
    int       tickerEnabled;

    // ---- Misc ----
    simd_float2   outputSize;
    float         transitionMix;  // 0 = A, 1 = B
    int       previewMode;
} DEKAFrameUniforms;

typedef struct {
    int radius;       // taps each side
    int horizontal;   // 1 = horizontal pass, 0 = vertical
} DEKABlurParams;

typedef struct {
    simd_float2 scale;    // aspect-fit scale for the preview quad
    int     mode;     // DEKA_PREVIEW_*
    int     pad;
} DEKAPreviewUniforms;

#endif /* ShaderTypes_h */
