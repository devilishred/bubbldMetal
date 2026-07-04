

https://github.com/user-attachments/assets/4c439c8e-588c-4f51-a9ed-4f55d1f3fb42



# BubbldMetal

> An animated, GPU-driven SwiftUI background powered by a stitchable Metal shader.

## Features

- 🌊 Drop-in animated gradient with a ripple + value-noise Metal effect
- 🪞 Five background styles — ripple, liquid metal, brushed metal, aurora, plasma
- ⚡️ Self-animating out of the box, or fully caller-driven
- 🎨 Brand palette included (`.bpink` / `.bgreen` / `.bindigo`)
- 📦 Zero asset-catalog dependency — the shaders ship inside the package bundle

## Requirements

- iOS 18 / macOS 15 / tvOS 18 / visionOS 2
- Xcode 16+ (builds on Apple platforms only — requires the Metal + SwiftUI SDK)

> **Note:** the shader is compiled by Xcode's build system. Build/test with Xcode or `xcodebuild` (the standard path when you add this to an app). The bare command-line `swift build` does not compile `.metal` sources, so CI must run on macOS with full Xcode selected.

## Installation

### Xcode

**File ▸ Add Package Dependencies…** and enter:

```
https://github.com/bubbld/bubbldMetal
```

### Package.swift

```swift
.package(url: "https://github.com/bubbld/bubbldMetal", from: "1.0.0")
```

…then add `"BubbldMetal"` to your target's dependencies.

## Usage

```swift
import SwiftUI
import BubbldMetal

struct ContentView: View {
    var body: some View {
        MetalShaderBackgroundView()   // stock ripple, self-animating
    }
}
```

## Customization

Pick a style in the initializer, then chain SwiftUI-style modifiers — one per knob. Each initializer seeds that style's tuned preset, so you only override what you want:

```swift
MetalShaderBackgroundView(.aurora)
    .color1(.bpink)
    .orbitSpeed(0.02)
    .displacementStrength(0.4)
```

Every modifier returns a new `MetalShaderBackgroundView`, so order doesn't matter and any subset works.

### Modifiers

| Modifier                     | Type              | Description                                    |
|------------------------------|-------------------|------------------------------------------------|
| `.style(_:)`                 | `BackgroundStyle` | Switch shader style, keeping other knobs       |
| `.color1(_:)` … `.color4(_:)`| `Color`           | Individual gradient stops                      |
| `.colors(_:_:_:_:)`          | `Color × 4`       | Set all four gradient colors at once           |
| `.noise(_:)`                 | `Float`           | Value-noise scale (finer grain when higher)    |
| `.strength(_:)`              | `Float`           | How strongly noise perturbs the effect         |
| `.rippleFrequency(_:)`       | `Float`           | Number of wavefronts (tighter when higher)     |
| `.rippleSpeed(_:)`           | `Float`           | Ripple animation speed (`.ripple` only)        |
| `.displacementStrength(_:)`  | `Float`           | How much the shader warps the image            |
| `.sheen(_:)`                 | `Float`           | Metallic/iridescent highlight (metal & plasma) |
| `.topColorMix(_:)`           | `Double`          | Blend of `color4` into `color1` at the top     |
| `.startPoint(_:)`            | `UnitPoint`       | Gradient start                                 |
| `.endPoint(_:)`              | `UnitPoint`       | Gradient end                                   |
| `.orbitRadius(_:)`           | `Double`          | Radius of the orbiting effect center           |
| `.orbitSpeed(_:)`            | `Double`          | Orbit angular step per frame                   |
| `.scale(_:)`                 | `CGFloat`         | Layer scale (keeps displaced edges covered)    |
| `.maxSampleOffset(_:)`       | `CGSize`          | Max offset the layer effect may sample         |
| `.configuration(_:)`         | `Configuration`   | Replace the whole configuration in one shot    |
| `.time(_:)` / `.timer(_:)`   | see below         | Caller-driven animation                        |

### Background styles

Choose a shader in the initializer. Every style renders over the same gradient and responds to the modifiers that map to it:

```swift
MetalShaderBackgroundView(.liquidMetal)
```

| Style           | Look                                                    | Knobs used                                             |
|-----------------|--------------------------------------------------------|--------------------------------------------------------|
| `.ripple`       | Original ripple + value-noise displacement (`fbp`)     | `noise`, `strength`, `rippleFrequency`, `rippleSpeed`, `displacementStrength` |
| `.liquidMetal`  | Churning chrome/mercury (domain-warped fbm + specular) | `noise`, `strength`, `displacementStrength`, `sheen`   |
| `.brushedMetal` | Brushed titanium with a rolling highlight              | `noise`, `strength`, `displacementStrength`, `sheen`   |
| `.aurora`       | Soft drifting bands of light                           | `noise`, `strength`, `rippleFrequency`, `displacementStrength` |
| `.plasma`       | Oil-slick iridescent plasma                            | `noise`, `strength`, `rippleFrequency`, `displacementStrength`, `sheen` |

The defaults behind the modifiers (the same fields exposed on the underlying `Configuration` value type, if you'd rather build one and pass it to `.configuration(_:)`):

| Field                  | Default              |     | Field                  | Default              |
|------------------------|----------------------|-----|------------------------|----------------------|
| `noise`                | `1.25`               |     | `topColorMix`          | `0.8`                |
| `strength`             | `5.0`                |     | `startPoint`           | `.top`               |
| `rippleFrequency`      | `16.0`               |     | `endPoint`             | `.bottomTrailing`    |
| `rippleSpeed`          | `3.0`                |     | `orbitRadius`          | `300`                |
| `displacementStrength` | `0.3`                |     | `orbitSpeed`           | `0.001`              |
| `sheen`                | `0.5`                |     | `scale`                | `1.1`                |
|                        |                      |     | `maxSampleOffset`      | `300 × 500`          |

> Each style's initializer seeds a *tuned* preset (not the bare defaults above), so `MetalShaderBackgroundView(.plasma)` already looks good before you touch a modifier.

### Presets

The stock ripple presets are still available via `.configuration(_:)`:

```swift
MetalShaderBackgroundView().configuration(.default)   // the stock ripple look
MetalShaderBackgroundView().configuration(.calm)      // slow, soft, subtle
MetalShaderBackgroundView().configuration(.intense)   // fast, tight, bold
```

### Interactive playground

Open the package in Xcode and run the **"Liquid Glass Playground"** preview in `MetalShaderBackgroundView.swift` to live-tune every knob (and the four colors) with sliders on a Liquid Glass panel. The playground requires iOS 26 / macOS 26; the component itself does not.

### Full control

Drive the animation clock yourself with `.time(_:)` and `.timer(_:)`:

```swift
MetalShaderBackgroundView(.ripple)
    .rippleSpeed(4)
    .time(myTime)
    .timer(Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect())
```

## How it works

The view renders a `LinearGradient` and applies a SwiftUI [`.layerEffect`](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) backed by a `[[stitchable]]` Metal function chosen by the current style (`fbp` for `.ripple`, plus `liquidMetal` / `brushedMetal` / `aurora` / `plasma`). The shaders are compiled by Xcode into the package's `default.metallib` and resolved at runtime via `ShaderLibrary.bundle(Bundle.module)`.

## License

MIT 

