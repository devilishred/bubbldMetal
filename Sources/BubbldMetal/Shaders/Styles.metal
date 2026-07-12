//
//  Styles.metal
//  BubbldMetal
//
//  Alternate `[[stitchable]]` background styles selected via
//  `Configuration.style`. Each function is a SwiftUI `.layerEffect` that
//  distorts and re-lights the underlying gradient in a different way:
//
//    • liquidMetal  — domain-warped fbm with a sharp specular crest (chrome)
//    • brushedMetal — anisotropic grain + a moving specular sweep (titanium)
//    • aurora       — soft drifting bands of light over the gradient
//    • plasma       — interfering sines with thin-film iridescence (oil-slick)
//
//  The noise helpers are namespaced with an `m_` prefix so they never collide
//  with the identically-purposed helpers in `fbp.metal` when both translation
//  units are linked into the package's `default.metallib`.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

static inline float m_random(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

static inline float m_noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    float a = m_random(i);
    float b = m_random(i + float2(1.0, 0.0));
    float c = m_random(i + float2(0.0, 1.0));
    float d = m_random(i + float2(1.0, 1.0));

    // Quintic (smootherstep) interpolation for continuous derivatives.
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    return mix(mix(a, b, u.x),
               mix(c, d, u.x), u.y);
}

// Fractal Brownian motion: five octaves of value noise.
static inline float m_fbm(float2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * m_noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}


// MARK: - Liquid / molten metal

[[ stitchable ]] half4 liquidMetal(float2 pos, SwiftUI::Layer l, float4 boundingBox,
                                   float2 dragp, float time,
                                   float noise, float strength,
                                   float displacementStrength, float sheen) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float2 c = dragp / size;
    float t = time * 0.15;

    // Two-stage domain warp — the churning body of the metal.
    float2 q = float2(m_fbm(uv * noise + t),
                      m_fbm(uv * noise + float2(5.2, 1.3)));
    float2 r = float2(m_fbm(uv * noise + strength * 0.1 * q + float2(1.7, 9.2) + t),
                      m_fbm(uv * noise + strength * 0.1 * q + float2(8.3, 2.8) - t));
    float h = m_fbm(uv * noise + strength * 0.1 * r + length(uv - c));

    float2 displaced = uv + (r - 0.5) * displacementStrength;
    half4 color = l.sample(clamp(displaced, 0.0, 1.0) * size);

    // Metallic specular: a sharp highlight riding the crests of the height field.
    float spec = pow(saturate(h), 4.0);
    color.rgb = mix(color.rgb, half3(1.0), half(spec * sheen));
    return color;
}


// MARK: - Aurora waves

[[ stitchable ]] half4 aurora(float2 pos, SwiftUI::Layer l, float4 boundingBox,
                              float2 dragp, float time,
                              float noise, float strength,
                              float rippleFrequency, float displacementStrength) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * 0.3;

    // Gently roll the whole gradient vertically.
    float wave = sin(uv.x * rippleFrequency + t) * 0.05
               + (m_fbm(uv * noise + t * 0.2) - 0.5) * strength * 0.05;
    float2 displaced = uv + float2(0.0, wave) * displacementStrength;
    half4 color = l.sample(clamp(displaced, 0.0, 1.0) * size);

    // Three stacked, drifting bands of light.
    float glow = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float center = 0.25 + fi * 0.25
                     + sin(uv.x * rippleFrequency * 0.4 + t + fi * 1.7) * 0.08
                     + (m_fbm(uv * noise + fi * 3.1) - 0.5) * 0.15;
        glow += smoothstep(0.08, 0.0, abs(uv.y - center));
    }
    color.rgb += half3(saturate(glow) * 0.5);
    return color;
}


// MARK: - Plasma / iridescent

[[ stitchable ]] half4 plasma(float2 pos, SwiftUI::Layer l, float4 boundingBox,
                              float2 dragp, float time,
                              float noise, float strength,
                              float rippleFrequency, float displacementStrength, float sheen) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * 0.8;

    // Interfering sine fields perturbed by fbm.
    float v = sin(uv.x * rippleFrequency + t)
            + sin(uv.y * rippleFrequency + t * 1.1)
            + sin((uv.x + uv.y) * rippleFrequency * 0.7 + t * 1.3)
            + (m_fbm(uv * noise + t * 0.2) - 0.5) * strength;

    float2 displaced = uv + float2(sin(v), cos(v)) * displacementStrength * 0.1;
    half4 color = l.sample(clamp(displaced, 0.0, 1.0) * size);

    // Thin-film iridescence: a phase-shifted cosine palette shimmering with v.
    half phase = half(v) * 0.15h;
    half3 irid = half3(0.5) + half3(0.5) * cos(6.2831h * (phase + half3(0.0h, 0.33h, 0.67h)));
    color.rgb = mix(color.rgb, irid, half(sheen) * 0.6h);
    return color;
}


// MARK: - Color-effect styles (self-generating; ignore the base color)
//
// The three below are `.colorEffect` shaders, not `.layerEffect`: their second
// implicit parameter is `half4 color` (the current pixel) rather than a
// `SwiftUI::Layer`, and they synthesize the output color entirely from noise,
// so the gradient underneath is overwritten.

// Drifting fractal-noise clouds: domain-warped fbm advected over time, mapped
// through a four-color palette across the cloud density.
[[ stitchable ]] half4 fractalClouds(float2 pos, half4 color, float4 boundingBox,
                                     float time, float frequency, float warp, float speed,
                                     half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float freq = max(frequency, 0.5);
    float2 q = uv * freq;
    float t = time * speed;
    float2 drift = float2(t * 0.08, t * 0.05);

    // Warp the sample coordinates by another fbm for puffy shapes; the churn
    // term (t * 0.15) evolves the field over time so it morphs, not just pans.
    float2 w = float2(m_fbm(q + drift),
                      m_fbm(q + drift + float2(5.2, 1.3) + t * 0.15));
    float density = m_fbm(q + warp * w + drift);
    density = smoothstep(0.15, 0.95, density);

    // Four-stop palette across the cloud density.
    float3 col;
    if (density < 0.33) {
        col = mix(float3(c3.rgb), float3(c2.rgb), density / 0.33);
    } else if (density < 0.66) {
        col = mix(float3(c2.rgb), float3(c1.rgb), (density - 0.33) / 0.33);
    } else {
        col = mix(float3(c1.rgb), float3(c4.rgb), (density - 0.66) / 0.34);
    }
    return half4(half3(col), 1.0);
}


// Ink smoke: heavily domain-warped fbm (warp of a warp) advected over time,
// high-contrast so it reads as wispy tendrils diffusing between two colors
// (ink over background). `frequency` = detail, `warp` = tendril distortion.
[[ stitchable ]] half4 inkSmoke(float2 pos, half4 color, float4 boundingBox,
                                float time, float frequency, float warp, float speed,
                                half4 inkColor, half4 bgColor) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float freq = max(frequency, 0.5);
    float2 q = uv * freq;
    float t = time * speed;

    float2 w1 = float2(m_fbm(q + float2(0.0, t * 0.10)),
                       m_fbm(q + float2(3.1, 1.7) - t * 0.08));
    float2 w2 = float2(m_fbm(q + warp * w1 + t * 0.12),
                       m_fbm(q + warp * w1 + float2(2.3, 5.9)));
    float d = m_fbm(q + warp * w2);
    d = pow(smoothstep(0.25, 0.85, d), 1.5);

    float3 col = mix(float3(bgColor.rgb), float3(inkColor.rgb), d);
    return half4(half3(col), 1.0);
}


// Liquid chrome: treat a warped fbm as a height field, derive a surface
// normal by finite differences, then fake a metallic reflection — diffuse +
// specular + sinusoidal "chrome" bands from the height, lightly tinted.
[[ stitchable ]] half4 liquidChrome(float2 pos, half4 color, float4 boundingBox,
                                    float time, float frequency, float warp, float speed,
                                    half4 tint) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float freq = max(frequency, 0.5);
    float2 q = uv * freq;
    float t = time * speed;

    float2 wv = float2(m_fbm(q + float2(t * 0.10, 0.0)),
                       m_fbm(q + float2(0.0, t * 0.08) + 2.7));
    float2 p = q + warp * wv;

    float e = 0.02 * freq;
    float h  = m_fbm(p);
    float hx = m_fbm(p + float2(e, 0.0));
    float hy = m_fbm(p + float2(0.0, e));
    float3 n = normalize(float3(-(hx - h) / e, -(hy - h) / e, 1.0));

    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 lightDir = normalize(float3(0.6, 0.7, 0.5));
    float diff = max(dot(n, lightDir), 0.0);
    float spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0);
    float bands = 0.5 + 0.5 * sin(h * 18.0 + t);
    float lum = clamp(0.15 + diff * 0.5 + bands * 0.35 + spec, 0.0, 1.0);

    float3 chrome = mix(float3(lum), float3(lum) * float3(tint.rgb) * 1.3, 0.35);
    return half4(half3(chrome), 1.0);
}
