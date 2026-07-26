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
    // Sine-free hash (Dave Hoskins' hash12) — avoids a transcendental `sin`
    // per octave, which is the dominant per-pixel cost of every fbm style.
    float3 p3 = fract(float3(st.x, st.y, st.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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

// Three-octave fBm for the most expensive styles (Liquid Metal, Aurora), which
// evaluate fBm 4–5× per pixel. Two fewer octaves ≈ 40% less noise work with
// little visible loss at full-screen background scale.
static inline float m_fbm3(float2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 3; i++) {
        value += amplitude * m_noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// MARK: - Edge-safe sampling helpers
//
// The `.layerEffect` styles below warp the sample coordinate before reading the
// gradient. When the warp pushes a coordinate outside [0,1] the layer has no
// content there, which is what produced the two artifacts we kept chasing:
//   • transparent "blank" gaps  — sampling past the edge returns nothing;
//   • edge "smear" streaks       — a hard clamp pins to one border pixel and
//                                  stretches its color inward.
// The two helpers remove both at the source.

// Fold a coordinate back into [0,1] by REFLECTION rather than clamping. A clamp
// repeats a single edge pixel (the smear); a mirror continues the interior,
// which is nearly invisible over a smooth gradient. Identity inside [0,1].
static inline float2 m_reflectUV(float2 x) {
    x = fmod(abs(x), 2.0);
    return mix(x, 2.0 - x, step(1.0, x));
}

// Smoothly ramps to 0 within `margin` of every edge. Multiplying the
// displacement by this vanishes the warp at the border, so the sample
// coordinate simply never leaves the interior near the edges — where the
// overshoot is most common — while the centre keeps the full effect.
static inline float m_edgeFalloff(float2 uv, float margin) {
    float2 f = smoothstep(0.0, margin, uv) * smoothstep(0.0, margin, 1.0 - uv);
    return f.x * f.y;
}


// MARK: - Liquid / molten metal

[[ stitchable ]] half4 liquidMetal(float2 pos, SwiftUI::Layer l, float4 boundingBox,
                                   float2 dragp, float time,
                                   float noise, float strength,
                                   float displacementStrength, float sheen,
                                   float speed) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    // Flow rate is driven by `speed` (the Ripple Speed knob), like Clouds/Smoke.
    float t = time * max(speed, 0.05);
    float2 q = uv * noise;

    // Turbulent domain warp (warp-of-warp, à la Smoke): each layer evolves at a
    // DIFFERENT rate and direction, so the field shears and churns organically
    // instead of sliding in one rigid diagonal. This is what makes it read as
    // molten rather than a translating texture.
    float2 w1 = float2(m_fbm3(q + float2(0.0, t * 0.11)),
                       m_fbm3(q + float2(3.1, 1.7) - t * 0.09));
    float2 w2 = float2(m_fbm3(q + strength * 0.12 * w1 + float2(t * 0.13, 0.0)),
                       m_fbm3(q + strength * 0.12 * w1 + float2(2.3, 5.9) - t * 0.06));
    float h = m_fbm3(q + strength * 0.12 * w2);

    // Fade the warp to zero at the borders, then reflect any residual overshoot
    // — no clamp streaks, no transparent gaps. The specular below still runs to
    // the edge, so only the geometric distortion eases off, not the metal look.
    float fade = m_edgeFalloff(uv, 0.12);
    float2 displaced = uv + (w2 - 0.5) * displacementStrength * fade;
    half4 color = l.sample(m_reflectUV(displaced) * size);

    // Metallic specular: a sharp highlight riding the crests of the height field.
    float spec = pow(saturate(h), 4.0);
    color.rgb = mix(color.rgb, half3(1.0), half(spec * sheen));
    return color;
}


// MARK: - Aurora waves

[[ stitchable ]] half4 aurora(float2 pos, SwiftUI::Layer l, float4 boundingBox,
                              float2 dragp, float time,
                              float noise, float strength,
                              float rippleFrequency, float displacementStrength,
                              float speed) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    // Drift is driven by `speed` (the Ripple Speed knob). It used to be a fixed
    // `time * 0.3`, so the slider did nothing and the bands barely moved.
    float t = time * max(speed, 0.05) * 0.15;

    // Gently roll the whole gradient vertically.
    float wave = sin(uv.x * rippleFrequency + t) * 0.06
               + (m_fbm3(uv * noise + float2(t * 0.5, 0.0)) - 0.5) * strength * 0.05;
    float fade = m_edgeFalloff(uv, 0.12);
    float2 displaced = uv + float2(0.0, wave) * displacementStrength * fade;
    half4 color = l.sample(m_reflectUV(displaced) * size);

    // Three stacked bands of light that drift AND undulate over time — the fbm
    // term now advances with `t`, so the curtains actually shift shape instead
    // of sitting still.
    float glow = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float center = 0.25 + fi * 0.25
                     + sin(uv.x * rippleFrequency * 0.4 + t + fi * 1.7) * 0.1
                     + (m_fbm3(uv * noise + float2(t * 0.3, fi * 3.1)) - 0.5) * 0.2;
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

    float fade = m_edgeFalloff(uv, 0.12);
    float2 displaced = uv + float2(sin(v), cos(v)) * displacementStrength * 0.1 * fade;
    half4 color = l.sample(m_reflectUV(displaced) * size);

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
    // Sleepy clouds: a slow overall drift plus gentle IN-PLACE billowing. Smoke
    // boils via a fast warp-of-warp churn; clouds evolve their warp field slowly
    // so puffs form and dissolve where they sit instead of translating rigidly.
    float t = time * speed * 0.35;
    float2 drift = float2(t * 0.02, t * 0.008);

    // Each warp component advances on its own slow clock in a different
    // direction, so the field shears and morphs internally — the missing
    // "movement inside" — while staying far calmer than smoke's churn.
    float2 w = float2(m_fbm(q + drift + float2(0.0, t * 0.05)),
                      m_fbm(q + drift + float2(5.2, 1.3) - t * 0.04));
    float density = m_fbm(q + warp * 0.6 * w + drift);

    // Puffy: a narrow band with a raised floor leaves calm open sky between
    // fuller clouds, and a second smoothstep rounds the tops into soft
    // cauliflower rather than ragged edges.
    density = smoothstep(0.42, 0.82, density);
    density = density * density * (3.0 - 2.0 * density);

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
                                    half4 highlight, half4 shadow) {
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

    // Two-tone metal: shadows take Color 2, crests take Color 1 (by the faux-
    // reflection luminance), so valleys are colored rather than black. A white
    // specular glint on top keeps the chrome sheen.
    float3 metal = mix(float3(shadow.rgb), float3(highlight.rgb), lum);
    metal = mix(metal, float3(1.0), spec * 0.5);
    return half4(half3(saturate(metal)), 1.0);
}


// MARK: - Extra hash / cell-noise helpers for the 2026 style batch

// 2D-in / 2D-out hash (Dave Hoskins' hash22) for jittered grids & Voronoi.
static inline float2 m_hash22(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((float2(p3.x, p3.x) + float2(p3.y, p3.z)) * float2(p3.z, p3.y));
}

// Animated Voronoi: F1 (distance to nearest feature point), with the points
// breathing on sine orbits so cells morph instead of translating.
static inline float m_voronoiF1(float2 p, float t) {
    float2 i = floor(p);
    float2 f = fract(p);
    float md = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(x, y);
            float2 o = m_hash22(i + g);
            o = 0.5 + 0.4 * sin(t + 6.2831 * o);
            float2 r = g + o - f;
            md = min(md, dot(r, r));
        }
    }
    return sqrt(md);
}


// MARK: - Grain (soft gradient field + film grain)

// The "grainy gradient" look: a slow low-frequency fbm melts the four palette
// colors into soft blurred blobs, under per-pixel film grain that shimmers in
// slowly wandering patches (fully still whenever `speed` is 0).
// `frequency` = blob scale, `warp` = grain amount, `speed` = drift.
[[ stitchable ]] half4 grainStyle(float2 pos, half4 color, float4 boundingBox,
                                  float time, float frequency, float warp, float speed,
                                  half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    // Fast enough to visibly drift and morph; each field moves on its own
    // clock/direction so the blobs churn rather than translate.
    float t = time * speed * 0.5;
    float2 q = uv * max(frequency * 0.4, 0.2);

    float a = m_fbm(q + float2(t * 0.22, -t * 0.14));
    float b = m_fbm(q + float2(4.7, 2.3) - t * 0.18);
    float m = m_fbm(float2(q.y, q.x) + float2(1.9, 7.3) + t * 0.11);
    float3 top = mix(float3(c1.rgb), float3(c2.rgb), smoothstep(0.25, 0.75, a));
    float3 bot = mix(float3(c3.rgb), float3(c4.rgb), smoothstep(0.25, 0.75, b));
    float3 col = mix(top, bot, smoothstep(0.2, 0.8, m));

    // Film grain over the field. A fully static hash read as frozen next to
    // the drifting blobs — so the speckle re-seeds on a film-like cadence,
    // but only inside patches of a slowly wandering mask: parts of the frame
    // shimmer while the rest holds still, and the live regions breathe
    // around the canvas instead of the whole texture flickering at once.
    // Everything keys off `t`, so speed 0 / pause / stills stay deterministic.
    float gStatic = m_random(pos) - 0.5;
    float cadence = floor(t * 5.0);   // ~8 fps at default speed: sparkle, not strobe
    float gLive = m_random(pos + float2(cadence * 13.37, cadence * 7.77)) - 0.5;
    float breathe = m_fbm(q * 1.7 + float2(-t * 0.16, t * 0.21) + float2(3.1, 5.4));
    float live = smoothstep(0.35, 0.75, breathe);
    float g = mix(gStatic, gLive, live * 0.85);
    col += g * saturate(warp) * 0.35;
    return half4(half3(saturate(col)), 1.0);
}


// MARK: - Silk (flowing satin ribbons, two colors)

// Layered sine waves with an fbm-perturbed phase read as draped satin:
// shadow-to-highlight fabric shading plus a slowly sweeping specular sheen.
[[ stitchable ]] half4 silk(float2 pos, half4 color, float4 boundingBox,
                            float time, float frequency, float warp, float speed,
                            half4 highlight, half4 shadow) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.25;
    float2 q = uv * max(frequency, 0.5);

    float phase = q.x * 1.8 + q.y * 1.2
                + (m_fbm3(q * 1.5 + float2(t * 0.2, 0.0)) - 0.5) * warp * 6.0;
    float f = sin(phase * 3.0 + t)
            + 0.5 * sin(phase * 5.0 - t * 0.7)
            + 0.25 * sin(phase * 9.0 + t * 0.4);
    float lum = saturate(0.5 + 0.3 * f);
    float3 col = mix(float3(shadow.rgb), float3(highlight.rgb), lum);

    // Moving sheen: a tight specular band drifting across the folds.
    float spec = pow(saturate(0.5 + 0.5 * sin(phase * 3.0 + t + 1.2)), 24.0);
    col += spec * 0.35;
    return half4(half3(saturate(col)), 1.0);
}


// MARK: - Blobs (lava-lamp metaballs)

// Five metaballs on incommensurate sine orbits, their summed field mapped
// through the four-color palette. `frequency` = blob size, `warp` = organic
// edge wobble, `speed` = drift.
[[ stitchable ]] half4 blobs(float2 pos, half4 color, float4 boundingBox,
                             float time, float frequency, float warp, float speed,
                             half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float t = time * speed * 0.2;

    float field = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 c = float2(0.5 * aspect, 0.5)
                 + float2(sin(t * (0.60 + 0.13 * fi) + fi * 2.4),
                          cos(t * (0.50 + 0.11 * fi) + fi * 1.9))
                 * (0.18 + 0.06 * sin(fi * 3.7 + t * 0.3));
        float2 d = p - c;
        field += (0.004 + 0.0035 * max(frequency, 0.5)) / (dot(d, d) + 1e-4);
    }
    // Organic edges: fbm wobble on the field before thresholding.
    field += (m_fbm3(p * 6.0 + t * 0.5) - 0.5) * warp * 2.0;
    float d = saturate(field * 0.55);

    float3 col = float3(c3.rgb);
    col = mix(col, float3(c2.rgb), smoothstep(0.35, 0.55, d));
    col = mix(col, float3(c1.rgb), smoothstep(0.55, 0.80, d));
    col = mix(col, float3(c4.rgb), smoothstep(0.88, 1.00, d));
    return half4(half3(col), 1.0);
}


// MARK: - Bokeh (drifting soft-focus light discs)

// Three jittered-grid layers of defocused discs twinkling over a two-color
// backdrop. `frequency` = disc density, `speed` = drift + twinkle rate.
[[ stitchable ]] half4 bokeh(float2 pos, half4 color, float4 boundingBox,
                             float time, float frequency, float warp, float speed,
                             half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.15;

    float3 col = mix(float3(c3.rgb), float3(c2.rgb), uv.y);

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float scale = max(frequency, 1.0) * (1.2 + fi * 1.1);
        float2 g = uv * scale + float2(t * (0.08 + fi * 0.05), t * 0.03 * (fi - 1.0));
        float2 id = floor(g);
        float2 f = fract(g);
        float2 rnd = m_hash22(id + fi * 17.0);
        float2 center = 0.5 + (rnd - 0.5) * 0.55;
        float r = 0.14 + 0.22 * m_random(id + fi * 31.0);
        float twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * (2.0 + rnd.x * 3.0) + rnd.y * 6.2831));
        // Wide smoothstep = defocused edge; nearer layers are softer + dimmer.
        float disc = smoothstep(r, r * (0.25 + 0.2 * fi), length(f - center));
        float3 tint = mix(float3(c1.rgb), float3(c4.rgb), rnd.x);
        col += disc * twinkle * (0.30 - 0.06 * fi) * tint;
    }
    return half4(half3(saturate(col)), 1.0);
}


// MARK: - Holo Foil (the sticker foil as a full-bleed background)

// Diagonal rainbow sheen sweeping over a diamond micro-pattern with sparkle
// glints — the app's holographic-sticker identity as a wallpaper. Two colors:
// `base` (the metal ground) and `tint` (pulled into the sheen).
[[ stitchable ]] half4 holoFoil(float2 pos, half4 color, float4 boundingBox,
                                float time, float frequency, float warp, float speed,
                                half4 base, half4 tint) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.6;

    // Simulated tilt: the light direction orbits.
    float ang = t * 0.8;
    float d = dot(uv - 0.5, float2(cos(ang), sin(ang)));

    // Diamond micro-pattern etched into the foil.
    float2 q = uv * max(frequency, 0.3) * 24.0;
    float diamond = abs(fract(q.x + q.y) - 0.5) + abs(fract(q.x - q.y) - 0.5);

    // Rainbow band: position along the light axis + the micro-pattern + a
    // little fbm shimmer, all scrolling with time so the colors visibly flow
    // even between tilt sweeps.
    float band = d * 3.0 + diamond * warp * 3.0
               + m_fbm3(uv * 6.0 + t * 0.4) * 0.5
               + t * 0.5;
    float3 irid = 0.5 + 0.5 * cos(6.2831 * (band + float3(0.0, 0.33, 0.67)));

    float3 ground = mix(float3(base.rgb), float3(tint.rgb), saturate(0.5 + d * 1.5));
    float3 col = mix(ground, irid, 0.55);
    return half4(half3(saturate(col)), 1.0);
}


// MARK: - Marble (ink-marbling veins)

// A folded sine over a two-level fbm domain warp: thin bright veins snaking
// through a softly varying base — suminagashi / polished stone.
[[ stitchable ]] half4 marble(float2 pos, half4 color, float4 boundingBox,
                              float time, float frequency, float warp, float speed,
                              half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.04;          // geologic pace
    float2 q = uv * max(frequency, 0.5);

    float2 w1 = float2(m_fbm(q + float2(0.0, t)),
                       m_fbm(q + float2(3.1, 1.7) - t * 0.8));
    float2 w2 = float2(m_fbm(q + warp * 4.0 * w1 + t * 0.5),
                       m_fbm(q + warp * 4.0 * w1 + float2(2.3, 5.9)));
    float v = sin((q.x + q.y) * 1.5 + (w2.x - 0.5) * warp * 18.0);

    float vein = pow(1.0 - abs(v), 6.0);
    float3 baseCol = mix(float3(c2.rgb), float3(c3.rgb), m_fbm(q * 0.6 + w1 * 0.5));
    float3 veinCol = mix(float3(c1.rgb), float3(c4.rgb), m_fbm(q * 1.3 + 7.7));
    float3 col = mix(baseCol, veinCol, saturate(vein));
    return half4(half3(col), 1.0);
}


// MARK: - Caustics (underwater light webs)

// Two counter-scrolling animated Voronoi layers multiplied into the bright
// ridge web that dances on a pool floor, over a depth gradient.
[[ stitchable ]] half4 caustics(float2 pos, half4 color, float4 boundingBox,
                                float time, float frequency, float warp, float speed,
                                half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.3;
    float2 q = uv * max(frequency, 1.0);

    float v1 = m_voronoiF1(q, t);
    float v2 = m_voronoiF1(q * 1.7 + 3.1, t * 1.23 + 1.0);
    // The web: bright where BOTH fields are near a ridge; `warp` sharpens.
    float web = pow(saturate(1.0 - v1 * v2 * 1.6), 2.0 + warp * 6.0);

    float3 water = mix(float3(c2.rgb), float3(c3.rgb), uv.y);
    water = mix(water, float3(c4.rgb), m_fbm3(q * 0.5 + t * 0.1) * 0.35);
    float3 col = water + float3(c1.rgb) * web * 0.9;
    return half4(half3(saturate(col)), 1.0);
}


// MARK: - Stained Glass (hard-edged Voronoi cells)

// Voronoi cells each filled from the four-color palette with dark leading
// between them. Feature points breathe so the panes slowly morph.
// `frequency` = pane count, `warp` = leading thickness.
[[ stitchable ]] half4 stainedGlass(float2 pos, half4 color, float4 boundingBox,
                                    float time, float frequency, float warp, float speed,
                                    half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.1;
    float2 q = uv * max(frequency, 1.0);

    // F1/F2 Voronoi with the winning cell's id, for edges + per-cell color.
    float2 i = floor(q);
    float2 f = fract(q);
    float f1 = 8.0, f2 = 8.0;
    float2 winner = float2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(x, y);
            float2 o = m_hash22(i + g);
            o = 0.5 + 0.35 * sin(t + 6.2831 * o);
            float d = dot(g + o - f, g + o - f);
            if (d < f1) { f2 = f1; f1 = d; winner = i + g; }
            else if (d < f2) { f2 = d; }
        }
    }
    float edge = sqrt(f2) - sqrt(f1);

    // Pick this pane's color from the palette; a second hash varies its depth.
    float h = m_random(winner + 0.5);
    float shade = 0.8 + 0.2 * m_random(winner + 9.7);
    float3 pane;
    if      (h < 0.25) pane = float3(c1.rgb);
    else if (h < 0.50) pane = float3(c2.rgb);
    else if (h < 0.75) pane = float3(c3.rgb);
    else               pane = float3(c4.rgb);
    pane *= shade;

    // Dark leading between panes; `warp` sets its thickness.
    float lead = smoothstep(0.02, 0.05 + warp * 0.25, edge);
    float3 col = mix(float3(0.05), pane, lead);
    return half4(half3(col), 1.0);
}


// MARK: - Nebula (deep-space clouds + starfield)

// Clouds' domain-warp recipe pushed dark and high-contrast, with a sparse
// twinkling starfield on top.
[[ stitchable ]] half4 nebula(float2 pos, half4 color, float4 boundingBox,
                              float time, float frequency, float warp, float speed,
                              half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.15;
    float2 q = uv * max(frequency, 0.5);

    float2 w = float2(m_fbm(q + float2(0.0, t * 0.06)),
                      m_fbm(q + float2(5.2, 1.3) - t * 0.05));
    float d = m_fbm(q + warp * 3.0 * w + float2(t * 0.02, 0.0));
    d = pow(smoothstep(0.3, 0.9, d), 1.4);

    // Deep space -> mid gas -> bright core, with the fourth color glowing
    // through the densest gas (no starfield — it read as white speckles).
    float3 col = float3(c3.rgb) * 0.25;
    col = mix(col, float3(c2.rgb), smoothstep(0.15, 0.6, d));
    col = mix(col, float3(c1.rgb), smoothstep(0.6, 0.95, d));
    col = mix(col, float3(c4.rgb), smoothstep(0.9, 1.0, d) * 0.5);
    return half4(half3(saturate(col)), 1.0);
}


// MARK: - Topo (animated contour lines)

// Contour lines of a slowly morphing fbm height field over a soft elevation
// tint — a living topographic map. `frequency` = terrain scale,
// `warp` = ruggedness, `speed` = morph rate.
[[ stitchable ]] half4 topo(float2 pos, half4 color, float4 boundingBox,
                            float time, float frequency, float warp, float speed,
                            half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 size = float2(boundingBox[2], boundingBox[3]);
    float2 uv = pos / size;
    float t = time * speed * 0.06;
    float2 q = uv * max(frequency, 0.5);

    float2 w = float2(m_fbm3(q + t), m_fbm3(q + float2(4.2, 1.7) - t * 0.8));
    float h = m_fbm(q + warp * 2.0 * w);

    // Elevation shading between two colors, contour lines in a third.
    float3 col = mix(float3(c2.rgb), float3(c3.rgb), h);

    float bands = 14.0;
    float f = fract(h * bands);
    // Screen-space-ish anti-aliased thin line at each band edge.
    float line = smoothstep(0.10, 0.02, min(f, 1.0 - f));
    col = mix(col, float3(c1.rgb), line * 0.9);

    // Peaks tinted with the fourth color.
    col = mix(col, float3(c4.rgb), smoothstep(0.78, 0.95, h) * 0.4);
    return half4(half3(col), 1.0);
}


// MARK: - Halftone / ordered-dither post-process
//
// A `.layerEffect` applied *on top of* any other style (or a plain gradient):
// it pixelates the layer beneath into cells, then quantizes each cell to
// `levels` steps per channel using a 4x4 Bayer ordered-dither matrix, giving
// the retro dithered-gradient look. `mark` chooses how each cell is drawn:
//   0 = fill the whole cell (square)   — flat cells, dithered transitions
//   1 = round halftone dot (grows darker) on a white ground
//   2 = plus / cross glyph on a white ground
// Because it samples the composited layer below, it works over ripple, clouds,
// plasma, etc. — not just one field.

// Bayer 4x4 threshold matrix, normalized to [0,1).
constant float bayer4[16] = {
     0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
     3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
    15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0,
};

[[ stitchable ]] half4 halftoneDither(float2 pos, SwiftUI::Layer l, float4 boundingBox,
                                      float cellSize, float levels, float mark,
                                      float referenceWidth) {
    // cellSize is in design-space points: scale by the render width against the
    // reference width (like the orbit radius) so an 8pt cell looks the same in
    // the live preview and a full-resolution wallpaper export. Without this,
    // export cells shrank ~3x on phones (14x on Mac) and the effect vanished.
    float rs = referenceWidth > 0.5 ? (boundingBox[2] / referenceWidth) : 1.0;
    float cs = max(cellSize * rs, 1.0);

    // Pixelate: snap to the cell and sample the field at the cell's center.
    float2 cellIndex = floor(pos / cs);
    float2 cellCenter = (cellIndex + 0.5) * cs;
    half4 base = l.sample(cellCenter);

    // One ordered-dither threshold per cell (constant across the cell), so
    // adjacent cells alternate quantization levels — the checkerboard texture.
    int bx = int(cellIndex.x - 4.0 * floor(cellIndex.x / 4.0));
    int by = int(cellIndex.y - 4.0 * floor(cellIndex.y / 4.0));
    float threshold = bayer4[by * 4 + bx];

    // Dithered posterize to `levels` steps per channel.
    float steps = max(levels - 1.0, 1.0);
    float3 q = clamp(round(float3(base.rgb) * steps + (threshold - 0.5)) / steps, 0.0, 1.0);

    if (mark < 0.5) {
        return half4(half3(q), base.a);            // square: fill the cell
    }

    // Mark shapes draw the quantized color as a glyph on a white ground, sized
    // by how dark the cell is (classic halftone behavior).
    float2 f = (pos - cellCenter) / (cs * 0.5);    // local coords, ~[-1, 1]
    float lum = dot(q, float3(0.299, 0.587, 0.114));
    float amount = 1.0 - lum;                       // darker cell → bigger mark
    float3 ground = float3(1.0);

    bool on;
    if (mark < 1.5) {
        on = length(f) < amount * 1.2;              // round dot
    } else {
        float arm = amount * 0.9;                    // plus / cross
        on = (abs(f.x) < arm) || (abs(f.y) < arm);
    }
    return half4(half3(on ? q : ground), base.a);
}
