//
//  Shaders.metal
//  Soulfull Gatherings
//
//  The atmosphere layer of the design system. One stitchable function,
//  reachable through `AuroraBackground` in ShaderFX.swift — feature code
//  never calls ShaderLibrary directly:
//
//    aurora        colorEffect       domain-warped tonal drift (the player)
//
//  The film grain, shimmer sweep, noise dissolve and ripple were removed
//  with the move to still motion: a selection, a stage change and a tap now
//  fade rather than glint, burn or ripple, and nothing crawls over a page.
//
//  Everything drifts at breath pace — time inputs are pre-scaled by the
//  Swift wrappers so a "1.0" speed reads calm, never busy.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MARK: - Noise helpers

static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * vnoise(p);
        p = p * 2.03 + float2(17.0, 9.0);
        amp *= 0.5;
    }
    return v;
}

// MARK: - Aurora (colorEffect)

/// Domain-warped fbm blended across three brand tones. Apply to an opaque
/// fill; the wrapper passes `boundingRect` so the field scales to the view.
[[ stitchable ]] half4 aurora(float2 position, half4 color, float4 bounds,
                              float time, half4 toneA, half4 toneB, half4 toneC) {
    float2 size = max(bounds.zw, float2(1.0, 1.0));
    float2 uv = (position - bounds.xy) / size.y;      // y-normalized, keeps aspect

    float t = time;
    float2 q = float2(fbm(uv * 1.4 + float2(0.0, t)),
                      fbm(uv * 1.4 + float2(5.2, -t * 0.7)));
    float2 r = float2(fbm(uv * 2.1 + 2.6 * q + float2(1.7, 9.2) + t * 0.4),
                      fbm(uv * 1.9 + 2.2 * q + float2(8.3, 2.8) - t * 0.3));
    float f = fbm(uv * 1.8 + 2.4 * r);

    half3 col = mix(toneA.rgb, toneB.rgb, half(smoothstep(0.18, 0.66, f)));
    col = mix(col, toneC.rgb, half(smoothstep(0.45, 0.95, length(q) * 0.85)));
    // Soft luminance swell where the field folds — the "glow ridges".
    col += half3(0.045) * half(smoothstep(0.62, 0.94, f));

    return half4(col * color.a, color.a);
}
