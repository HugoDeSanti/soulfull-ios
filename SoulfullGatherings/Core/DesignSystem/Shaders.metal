//
//  Shaders.metal
//  Soulfull Gatherings
//
//  The atmosphere layer of the design system. Five stitchable functions,
//  each reachable through a wrapper in ShaderFX.swift — feature code never
//  calls ShaderLibrary directly:
//
//    filmGrain     colorEffect       breathing photographic grain
//    aurora        colorEffect       domain-warped tonal drift (hero backdrops)
//    shimmer       layerEffect       diagonal specular sweep across glass
//    noiseDissolve layerEffect       organic dissolve for stage transitions
//    ripple        distortionEffect  radial wave for backdrop changes
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

// MARK: - Film grain (colorEffect)

/// Animated photographic grain. `intensity` ≈ 0.04–0.08 for backdrops.
[[ stitchable ]] half4 filmGrain(float2 position, half4 color, float time, float intensity) {
    float seed = floor(time * 18.0);                  // re-roll the grain ~18 fps
    float n = hash21(position + float2(seed * 31.7, seed * 11.3));
    half g = half((n - 0.5) * intensity);
    return half4(color.rgb + half3(g) * color.a, color.a);
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

// MARK: - Shimmer (layerEffect)

/// One diagonal specular band sweeping the layer as `progress` runs 0→1.
[[ stitchable ]] half4 shimmer(float2 position, SwiftUI::Layer layer,
                               float4 bounds, float progress, float intensity) {
    half4 c = layer.sample(position);
    float2 size = max(bounds.zw, float2(1.0, 1.0));
    float2 uv = (position - bounds.xy) / size;
    float band = uv.x + uv.y * 0.45;
    float center = mix(-0.5, 1.5, progress);
    float d = band - center;
    float glow = exp(-d * d / 0.01) * intensity;
    return half4(c.rgb + half3(glow) * c.a, c.a);
}

// MARK: - Noise dissolve (layerEffect)

/// Organic burn-style dissolve. `progress` 0 = fully visible, 1 = gone.
/// A faint warm lift hugs the dissolving edge so the change feels lit,
/// not deleted.
[[ stitchable ]] half4 noiseDissolve(float2 position, SwiftUI::Layer layer,
                                     float progress, float scale) {
    half4 c = layer.sample(position);
    if (progress <= 0.0) { return c; }

    float n = fbm(position / max(scale, 1.0));
    // Remap noise (≈0.1–0.9 from fbm) so progress 0→1 covers it fully.
    n = saturate((n - 0.1) * 1.25);
    float edge = 0.10;
    float keep = smoothstep(progress - edge, progress + edge, n + edge * 2.0 * (1.0 - progress));

    float rim = keep * (1.0 - smoothstep(0.0, edge * 3.0, n - progress));
    half3 warm = half3(0.96, 0.88, 0.62);
    half3 rgb = c.rgb + warm * half(rim * 0.35) * c.a;

    return half4(rgb * half(keep), c.a * half(keep));
}

// MARK: - Ripple (distortionEffect)

/// Radial wave radiating from `origin`, damped by distance and by `progress`
/// so it always settles flat by 1.0.
[[ stitchable ]] float2 ripple(float2 position, float2 origin,
                               float progress, float amplitude, float wavelength) {
    float2 dir = position - origin;
    float d = length(dir);
    float damp = exp(-d / 900.0) * (1.0 - progress) * (1.0 - progress);
    float wave = sin((d / max(wavelength, 1.0) - progress * 14.0) * 6.28318);
    float2 unit = d > 0.001 ? dir / d : float2(0.0, 0.0);
    return position + unit * wave * amplitude * damp;
}
