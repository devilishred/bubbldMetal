

https://github.com/user-attachments/assets/4c439c8e-588c-4f51-a9ed-4f55d1f3fb42



# BubbldMetal

> Animated, GPU-driven SwiftUI backgrounds — 17 hand-written `[[stitchable]]` Metal shaders behind a one-line view.

## Features

- 🎨 17 background styles, each seeded with a tuned preset
- 🌓 Optional halftone / ordered-dither pass over any style
- ⚡️ Self-animating out of the box, or fully caller-driven
- 🎯 Deterministic `.phase()` rendering — preview, export and video frames agree exactly
- ♿️ Honors Reduce Motion, and stops issuing GPU frames when backgrounded
- 📦 Shaders ship inside the package bundle; no asset-catalog setup

## Requirements

iOS 18 · macOS 15 · tvOS 18 · visionOS 2 · Xcode 16+

> Xcode's build system compiles the `.metal` sources. Build and test with Xcode or `xcodebuild`; bare `swift build` does not compile Metal, so CI needs macOS with full Xcode selected.

## Installation

**File ▸ Add Package Dependencies…** with `https://github.com/devilishred/bubbldMetal`, or:

```swift
.package(url: "https://github.com/devilishred/bubbldMetal", from: "1.0.0")
```

…then add `"BubbldMetal"` to your target's dependencies.

## Usage

```swift
import SwiftUI
import BubbldMetal

MetalShaderBackgroundView()         // stock ripple, self-animating
MetalShaderBackgroundView(.aurora)  // any style, with its tuned preset
```

Chain modifiers to override individual knobs. Each returns a new view, so order doesn't matter and any subset works:

```swift
MetalShaderBackgroundView(.marble)
    .colors(.bpink, .bindigo, .black, .bgreen)
    .noise(12)
    .orbitSpeed(0.02)
```

## Styles

| Style | Look | Knobs |
|---|---|---|
| `.ripple` | Ripple + value-noise displacement | `noise`, `strength`, `rippleFrequency`, `rippleSpeed`, `displacementStrength` |
| `.liquidMetal` | Churning chrome/mercury — domain-warped fbm with a specular crest | `noise`, `strength`, `displacementStrength`, `sheen`, `rippleSpeed` |
| `.aurora` | Soft drifting bands of light | `noise`, `strength`, `rippleFrequency`, `displacementStrength`, `rippleSpeed` |
| `.plasma` | Oil-slick plasma — interfering sines with thin-film iridescence | `noise`, `strength`, `rippleFrequency`, `displacementStrength`, `sheen` |
| `.clouds` | Drifting fractal clouds through the palette | `noise`, `strength`, `rippleSpeed` |
| `.smoke` | Wispy ink tendrils, `color1` over `color2` | `noise`, `strength`, `rippleSpeed` |
| `.chrome` | Liquid chrome — fbm as a height field, lit with a faked metallic reflection | `noise`, `strength`, `rippleSpeed` |
| `.grain` | Grainy gradient — soft palette blobs under shimmering film grain | `noise`, `strength`, `rippleSpeed` |
| `.silk` | Draped satin ribbons with a sweeping specular sheen | `noise`, `strength`, `rippleSpeed` |
| `.blobs` | Lava-lamp metaballs on incommensurate orbits | `noise`, `strength`, `rippleSpeed` |
| `.bokeh` | Drifting soft-focus light discs, twinkling | `noise`, `strength`, `rippleSpeed` |
| `.holoFoil` | Diagonal rainbow sheen over a diamond micro-pattern, with sparkle glints | `noise`, `strength`, `rippleSpeed` |
| `.marble` | Ink-marbling veins — a folded sine over a two-level domain warp | `noise`, `strength`, `rippleSpeed` |
| `.caustics` | Underwater light webs from counter-scrolling Voronoi | `noise`, `strength`, `rippleSpeed` |
| `.stainedGlass` | Hard-edged Voronoi panes with dark leading, slowly morphing | `noise`, `strength`, `rippleSpeed` |
| `.nebula` | Deep-space clouds with a sparse twinkling starfield | `noise`, `strength`, `rippleSpeed` |
| `.topo` | Animated contour lines over a soft elevation tint | `noise`, `strength`, `rippleSpeed` |

`.ripple`, `.liquidMetal`, `.aurora` and `.plasma` are `.layerEffect` shaders — they displace and re-light the gradient underneath, so `gradientKind` / `startPoint` / `endPoint` shape the result. The other thirteen are self-generating `.colorEffect` shaders: they synthesize color from noise and the palette, ignoring the gradient geometry.

For the thirteen `.colorEffect` styles, `noise` reads as scale or density, `strength` as warp or distortion, and `rippleSpeed` as drift rate; all of them take the four palette colors. `.plasma` has no speed knob.

## Modifiers

| Group | Modifiers |
|---|---|
| Color | `.color1(_:)` … `.color4(_:)`, `.colors(_:_:_:_:)`, `.topColorMix(_:)` |
| Gradient | `.gradientKind(_:)` — `.linear` / `.radial` / `.angular` — `.startPoint(_:)`, `.endPoint(_:)` |
| Pattern | `.noise(_:)` detail, `.strength(_:)` warp, `.rippleFrequency(_:)`, `.displacementStrength(_:)`, `.sheen(_:)` |
| Motion | `.rippleSpeed(_:)`, `.orbitRadius(_:)`, `.orbitSpeed(_:)`, `.time(_:)`, `.timer(_:)`, `.phase(_:referenceWidth:)` |
| Sampling | `.scale(_:)`, `.maxSampleOffset(_:)` |
| Post | `.dither(cell:levels:mark:)`, `.noDither()` |
| Wholesale | `.style(_:)`, `.configuration(_:)` |

Presets are available through `.configuration(_:)` — `.default`, `.calm`, `.intense`, plus one per style.

## Dither

```swift
MetalShaderBackgroundView(.clouds).dither(cell: 10, levels: 3, mark: .dot)
```

Pixelates the field into `cell`-point cells, quantizes each to `levels` steps per channel with a 4×4 Bayer matrix, and draws every cell as `mark` — `.square`, `.dot`, `.plus`, `.lines`, `.hatch` or `.diamond`. One Bayer lookup and a quantize per pixel, so it's lighter than the noise styles, and it inherits the underlying animation for free.

## Deterministic frames

`.phase(_:)` renders a single frame from the phase and the render size with the internal clock disabled, so the same phase yields the same frame at any resolution — a small live preview and a full-resolution `ImageRenderer` capture coincide exactly. Advance the phase yourself to animate, or drive the live clock with `.time(_:)` and `.timer(_:)`.

```swift
MetalShaderBackgroundView(.marble).phase(0.25)
```

## How it works

The view renders a gradient and applies a SwiftUI [`.layerEffect`](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) or `.colorEffect` backed by the `[[stitchable]]` Metal function for the current style. Xcode compiles the shaders into the package's `default.metallib`, resolved at runtime via `ShaderLibrary.bundle(Bundle.module)`.

Open the package in Xcode and run the **Liquid Glass Playground** preview in `MetalShaderBackgroundView.swift` to live-tune every knob with sliders (requires iOS 26 / macOS 26; the component itself does not).

## License

MIT
