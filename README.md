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

| Parameter   | Type    | Default   | Description                              |
|-------------|---------|-----------|------------------------------------------|
| `color1`    | `Color` | `.bpink`  | Top gradient stop (mixed with `color4`)  |
| `color2`    | `Color` | `.bindigo`| Middle gradient stop                     |
| `color3`    | `Color` | `.bgreen` | Bottom gradient stop                     |
| `color4`    | `Color` | `.bindigo`| Color blended into `color1` at the top   |
| `noise`     | `Float` | `15.25`   | Value-noise scale                        |
| `strength`  | `Float` | `15.0`    | How strongly noise perturbs the ripple   |

```swift
MetalShaderBackgroundView(
    color1: .bpink, color2: .bindigo, color3: .bgreen, color4: .bpink,
    noise: 20, strength: 12
)
```

### Full control

Drive the animation yourself by supplying `time` and a timer publisher:

```swift
MetalShaderBackgroundView(
    color1: .bpink, color2: .bindigo, color3: .bgreen, color4: .bpink,
    time: myTime, noise: 15.25, strength: 15.0,
    timer: Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()
)
```

## How it works

The view renders a `LinearGradient` and applies a SwiftUI [`.layerEffect`](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) backed by a `[[stitchable]]` Metal function (`fbp`). The shader is compiled by SwiftPM into the package's `default.metallib` and resolved at runtime via `ShaderLibrary.bundle(Bundle.module)`.

## License

MIT © 2026 bubbld. See [LICENSE](LICENSE).

## Built by bubbld

bubbld is a studio building flagship native SwiftUI & Metal experiences for Apple platforms. `BubbldMetal` is the first of our open-source components. Want something like this in your app? Reach us at [info@bubbld.app](mailto:info@bubbld.app).
