# BubbldMetal

> An animated, GPU-driven SwiftUI background powered by a stitchable Metal shader.
> Built by **[bubbld](https://bubbld.app)** — a native SwiftUI & Metal component studio.

![BubbldMetal demo](Docs/demo.gif)
<!-- TODO: add a recording of the animated background -->

## Features

- 🌊 Drop-in animated gradient with a ripple + value-noise Metal effect
- ⚡️ Self-animating out of the box, or fully caller-driven
- 🎨 Brand palette included (`.bpink` / `.bgreen` / `.bindigo`)
- 📦 Zero asset-catalog dependency — the shader ships inside the package bundle

## Requirements

- iOS 18 / macOS 15 / tvOS 18 / visionOS 2
- Xcode 16+ (builds on Apple platforms only — requires the Metal + SwiftUI SDK)

> **Note:** the shader is compiled by Xcode's build system. Build/test with Xcode or `xcodebuild` (the standard path when you add this to an app). The bare command-line `swift build` does not compile `.metal` sources, so CI must run on macOS with full Xcode selected.

## Installation

### Xcode

**File ▸ Add Package Dependencies…** and enter:

```
https://github.com/bubbld/BubbldMetal
```

### Package.swift

```swift
.package(url: "https://github.com/bubbld/BubbldMetal", from: "1.0.0")
```

…then add `"BubbldMetal"` to your target's dependencies.

## Usage

```swift
import SwiftUI
import BubbldMetal

struct ContentView: View {
    var body: some View {
        MetalShaderBackgroundView()   // brand defaults, self-animating
    }
}
```

## Customization

**Colors** are passed directly to the initializer (`color1`–`color4`, defaulting to the bubbld palette). **Everything else** lives on a `Configuration` value type — every field has a default, so you only set what you want to change:

```swift
MetalShaderBackgroundView(
    color1: .bpink, color2: .bindigo, color3: .bgreen, color4: .bpink,
    configuration: .init(noise: 20, rippleFrequency: 12, displacementStrength: 0.4)
)
```

### `Configuration`

| Field                  | Type        | Default              | Description                                   |
|------------------------|-------------|----------------------|-----------------------------------------------|
| `noise`                | `Float`     | `15.25`              | Value-noise scale (finer grain when higher)   |
| `strength`             | `Float`     | `15.0`               | How strongly noise perturbs the ripple phase  |
| `rippleFrequency`      | `Float`     | `16.0`               | Number of wavefronts (tighter rings when higher) |
| `rippleSpeed`          | `Float`     | `3.0`                | Ripple animation speed                        |
| `displacementStrength` | `Float`     | `0.3`                | How much the ripple warps the image           |
| `topColorMix`          | `Double`    | `0.8`                | Blend of `color4` into `color1` at the top    |
| `startPoint`           | `UnitPoint` | `.top`               | Gradient start                                |
| `endPoint`             | `UnitPoint` | `.bottomTrailing`    | Gradient end                                  |
| `orbitRadius`          | `Double`    | `300`                | Radius of the orbiting ripple center          |
| `orbitSpeed`           | `Double`    | `0.001`              | Orbit angular step per frame                  |
| `scale`                | `CGFloat`   | `1.1`                | Layer scale (keeps displaced edges covered)   |
| `maxSampleOffset`      | `CGSize`    | `300 × 500`          | Max offset the layer effect may sample        |

### Presets

```swift
MetalShaderBackgroundView(configuration: .calm)     // slow, soft, subtle
MetalShaderBackgroundView(configuration: .intense)  // fast, tight, bold
MetalShaderBackgroundView(configuration: .default)  // the stock look
```

### Interactive playground

Open the package in Xcode and run the **"Liquid Glass Playground"** preview in `MetalShaderBackgroundView.swift` to live-tune every `Configuration` knob (and the four colors) with sliders on a Liquid Glass panel. The playground requires iOS 26 / macOS 26; the component itself does not.

### Full control

Drive the animation yourself by supplying `time` and a timer publisher:

```swift
MetalShaderBackgroundView(
    color1: .bpink, color2: .bindigo, color3: .bgreen, color4: .bpink,
    time: myTime,
    configuration: .init(rippleSpeed: 4),
    timer: Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()
)
```

## How it works

The view renders a `LinearGradient` and applies a SwiftUI [`.layerEffect`](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) backed by a `[[stitchable]]` Metal function (`fbp`). The shader is compiled by SwiftPM into the package's `default.metallib` and resolved at runtime via `ShaderLibrary.bundle(Bundle.module)`.

## License

MIT © 2026 bubbld. See [LICENSE](LICENSE).

## Built by bubbld

bubbld is a studio building flagship native SwiftUI & Metal experiences for Apple platforms. Want something like this in your app? Reach us at [info@bubbld.app](mailto:info@bubbld.app).
