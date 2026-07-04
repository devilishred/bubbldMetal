//
//  MetalShaderBackgroundView.swift
//  BubbldMetal
//
//  An animated, GPU-driven SwiftUI background: a gradient distorted by a
//  `[[stitchable]]` Metal shader (`fbp`) doing ripple + value-noise
//  displacement. The shader is compiled into the package's `default.metallib`
//  and loaded via `ShaderLibrary.bundle(Bundle.module)`.
//

import SwiftUI
import Combine

public struct MetalShaderBackgroundView: View {

    /// Which `[[stitchable]]` Metal shader drives the background. Each case is a
    /// distinct look applied over the same gradient; `Configuration` knobs are
    /// reused across styles wherever they map naturally.
    public enum BackgroundStyle: String, CaseIterable, Hashable, Sendable {
        /// Ripple + value-noise displacement — the original bubbld look (`fbp`).
        case ripple
        /// Domain-warped fbm with a sharp specular crest — chrome/mercury.
        case liquidMetal
        /// Anisotropic grain with a moving specular sweep — brushed titanium.
        case brushedMetal
        /// Soft drifting bands of light over the gradient.
        case aurora
        /// Interfering sine fields with thin-film iridescence — oil-slick foil.
        case plasma

        /// Human-readable label for pickers and UI.
        public var displayName: String {
            switch self {
            case .ripple:       return "Ripple"
            case .liquidMetal:  return "Liquid Metal"
            case .brushedMetal: return "Brushed Metal"
            case .aurora:       return "Aurora"
            case .plasma:       return "Plasma"
            }
        }
    }

    /// The tunable knobs of the effect. Every value has a sensible default, so
    /// `Configuration()` reproduces the stock bubbld look and you only override
    /// what you care about.
    public struct Configuration: Equatable, Sendable {

        // MARK: Style

        /// Which shader drives the background. Defaults to `.ripple` (`fbp`).
        public var style: BackgroundStyle

        // MARK: Ripple shader

        /// Value-noise scale fed to the shader. Higher = finer grain.
        public var noise: Float
        /// How strongly the noise perturbs the ripple phase.
        public var strength: Float
        /// Number of wavefronts across the surface. Higher = tighter rings.
        public var rippleFrequency: Float
        /// Animation speed of the ripples over time.
        public var rippleSpeed: Float
        /// How far the ripple displaces the sampled image. Higher = more warp.
        public var displacementStrength: Float
        /// Strength of the metallic/iridescent highlight on the metal & plasma
        /// styles (0...1). Ignored by `.ripple` and `.aurora`.
        public var sheen: Float

        // MARK: Gradient

        /// How much `color4` is blended into `color1` at the top stop (0...1).
        public var topColorMix: Double
        /// Gradient start point.
        public var startPoint: UnitPoint
        /// Gradient end point.
        public var endPoint: UnitPoint

        // MARK: Motion & layout

        /// Radius (in points) of the orbiting ripple center.
        public var orbitRadius: Double
        /// Per-frame angular step of the orbiting ripple center. Higher = faster.
        public var orbitSpeed: Double
        /// Scale applied to the layer so the displaced edges stay covered.
        public var scale: CGFloat
        /// Maximum sample offset the layer effect may read from.
        public var maxSampleOffset: CGSize

        public init(
            style: BackgroundStyle = .ripple,
            noise: Float = 1.25,
            strength: Float = 5.0,
            rippleFrequency: Float = 16.0,
            rippleSpeed: Float = 3.0,
            displacementStrength: Float = 0.3,
            sheen: Float = 0.5,
            topColorMix: Double = 0.8,
            startPoint: UnitPoint = .top,
            endPoint: UnitPoint = .bottomTrailing,
            orbitRadius: Double = 300,
            orbitSpeed: Double = 0.001,
            scale: CGFloat = 1.1,
            maxSampleOffset: CGSize = CGSize(width: 300, height: 500)
        ) {
            self.style = style
            self.noise = noise
            self.strength = strength
            self.rippleFrequency = rippleFrequency
            self.rippleSpeed = rippleSpeed
            self.displacementStrength = displacementStrength
            self.sheen = sheen
            self.topColorMix = topColorMix
            self.startPoint = startPoint
            self.endPoint = endPoint
            self.orbitRadius = orbitRadius
            self.orbitSpeed = orbitSpeed
            self.scale = scale
            self.maxSampleOffset = maxSampleOffset
        }

        /// The stock bubbld look.
        public static let `default` = Configuration()

        /// Slow, soft, low-distortion — good behind dense content.
        public static let calm = Configuration(
            strength: 8, rippleFrequency: 10, rippleSpeed: 1.5,
            displacementStrength: 0.2, orbitSpeed: 0.0006
        )

        /// Fast, tight, high-distortion — a bold hero background.
        public static let intense = Configuration(noise: 5.24,
            strength: 22, rippleFrequency: 22, rippleSpeed: 7.5,
            displacementStrength: 0.45, orbitSpeed: 0.0016
        )

        /// Churning chrome/mercury — the `.liquidMetal` style, tuned.
        public static let liquidMetal = Configuration(
            style: .liquidMetal,
            noise: 2.5, strength: 6, displacementStrength: 0.25, sheen: 0.65,
            orbitSpeed: 0.0008
        )

        /// Brushed titanium with a rolling highlight — the `.brushedMetal` style.
        public static let brushedMetal = Configuration(
            style: .brushedMetal,
            noise: 3, strength: 9, displacementStrength: 0.08, sheen: 0.55,
            orbitSpeed: 0.0009
        )

        /// Soft drifting northern lights — the `.aurora` style, tuned.
        public static let aurora = Configuration(
            style: .aurora,
            noise: 2, strength: 6, rippleFrequency: 8, displacementStrength: 0.4,
            orbitSpeed: 0.0006
        )

        /// Oil-slick iridescent plasma — the `.plasma` style, tuned.
        public static let plasma = Configuration(
            style: .plasma,
            noise: 2, strength: 2, rippleFrequency: 10, displacementStrength: 0.5,
            sheen: 0.5, orbitSpeed: 0.001
        )

        /// The tuned preset for a given style — what `MetalShaderBackgroundView(style)`
        /// starts from before any modifiers are applied.
        public static func preset(for style: BackgroundStyle) -> Configuration {
            switch style {
            case .ripple:       return .default
            case .liquidMetal:  return .liquidMetal
            case .brushedMetal: return .brushedMetal
            case .aurora:       return .aurora
            case .plasma:       return .plasma
            }
        }
    }

    /// Top gradient stop; blended with `color4`.
    public var color1: Color
    /// Middle gradient stop.
    public var color2: Color
    /// Bottom gradient stop.
    public var color3: Color
    /// Color mixed into `color1` at the top of the gradient.
    public var color4: Color
    /// Tunable parameters for the effect.
    public var configuration: Configuration

    /// When set, the caller drives `time`; when `nil`, the view advances time itself.
    private var externalTime: Float?
    /// Animation clock — created internally, or supplied via `.timer(_:)`.
    private var timer: Publishers.Autoconnect<Timer.TimerPublisher>

    @State private var angle: Double = 0
    @State private var dragp: CGPoint = .zero
    @State private var time: Float = 0

    /// Create a background for the given `style`, seeded with that style's tuned
    /// preset. Refine it with chained modifiers:
    ///
    /// ```swift
    /// MetalShaderBackgroundView(.aurora)
    ///     .color1(.bpink)
    ///     .orbitSpeed(0.02)
    /// ```
    ///
    /// Drop `MetalShaderBackgroundView()` in with no arguments for the stock
    /// ripple look; it self-animates.
    public init(_ style: BackgroundStyle = .ripple) {
        self.color1 = .bpink
        self.color2 = .bindigo
        self.color3 = .bgreen
        self.color4 = .bindigo
        self.configuration = .preset(for: style)
        self.externalTime = nil
        self.timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    }

    // MARK: - Modifiers

    /// Returns a copy of `self` with `transform` applied — the engine behind
    /// every chainable modifier below.
    private func with(_ transform: (inout Self) -> Void) -> Self {
        var copy = self
        transform(&copy)
        return copy
    }

    // Style & bulk configuration

    /// Switch the shader style, keeping every other knob as-is.
    public func style(_ value: BackgroundStyle) -> Self { with { $0.configuration.style = value } }
    /// Replace the entire configuration in one shot.
    public func configuration(_ value: Configuration) -> Self { with { $0.configuration = value } }

    // Colors

    /// Top gradient stop (blended with `color4`).
    public func color1(_ value: Color) -> Self { with { $0.color1 = value } }
    /// Middle gradient stop.
    public func color2(_ value: Color) -> Self { with { $0.color2 = value } }
    /// Bottom gradient stop.
    public func color3(_ value: Color) -> Self { with { $0.color3 = value } }
    /// Color mixed into `color1` at the top of the gradient.
    public func color4(_ value: Color) -> Self { with { $0.color4 = value } }
    /// Set all four gradient colors at once.
    public func colors(_ c1: Color, _ c2: Color, _ c3: Color, _ c4: Color) -> Self {
        with { $0.color1 = c1; $0.color2 = c2; $0.color3 = c3; $0.color4 = c4 }
    }

    // Shader knobs

    /// Value-noise scale. Higher = finer grain.
    public func noise(_ value: Float) -> Self { with { $0.configuration.noise = value } }
    /// How strongly noise perturbs the effect.
    public func strength(_ value: Float) -> Self { with { $0.configuration.strength = value } }
    /// Number of wavefronts. Higher = tighter rings/bands.
    public func rippleFrequency(_ value: Float) -> Self { with { $0.configuration.rippleFrequency = value } }
    /// Animation speed of the ripples (`.ripple` only).
    public func rippleSpeed(_ value: Float) -> Self { with { $0.configuration.rippleSpeed = value } }
    /// How far the shader warps the sampled image.
    public func displacementStrength(_ value: Float) -> Self { with { $0.configuration.displacementStrength = value } }
    /// Metallic/iridescent highlight strength (metal & plasma styles).
    public func sheen(_ value: Float) -> Self { with { $0.configuration.sheen = value } }

    // Gradient

    /// Blend of `color4` into `color1` at the top stop (0...1).
    public func topColorMix(_ value: Double) -> Self { with { $0.configuration.topColorMix = value } }
    /// Gradient start point.
    public func startPoint(_ value: UnitPoint) -> Self { with { $0.configuration.startPoint = value } }
    /// Gradient end point.
    public func endPoint(_ value: UnitPoint) -> Self { with { $0.configuration.endPoint = value } }

    // Motion & layout

    /// Radius (in points) of the orbiting effect center.
    public func orbitRadius(_ value: Double) -> Self { with { $0.configuration.orbitRadius = value } }
    /// Per-frame angular step of the orbiting center. Higher = faster.
    public func orbitSpeed(_ value: Double) -> Self { with { $0.configuration.orbitSpeed = value } }
    /// Scale applied to the layer so displaced edges stay covered.
    public func scale(_ value: CGFloat) -> Self { with { $0.configuration.scale = value } }
    /// Maximum sample offset the layer effect may read from.
    public func maxSampleOffset(_ value: CGSize) -> Self { with { $0.configuration.maxSampleOffset = value } }

    // Full control (caller-driven animation)

    /// Drive the animation clock yourself. Pass the current `time`; combine with
    /// `.timer(_:)` to supply your own frame source.
    public func time(_ value: Float) -> Self { with { $0.externalTime = value } }
    /// Supply a custom frame-tick publisher (e.g. a slower or display-linked timer).
    public func timer(_ value: Publishers.Autoconnect<Timer.TimerPublisher>) -> Self { with { $0.timer = value } }

    /// Builds the `Shader` for the currently-selected `style`, passing only the
    /// uniforms that style's `[[stitchable]]` function declares.
    private var shader: Shader {
        let lib = ShaderLibrary.bundle(Bundle.module)
        let t = externalTime ?? time
        let c = configuration
        let common: [Shader.Argument] = [.boundingRect, .float2(dragp), .float(t)]

        let function: ShaderFunction
        let arguments: [Shader.Argument]
        switch c.style {
        case .ripple:
            function = lib.fbp
            arguments = common + [
                .float(c.noise), .float(c.strength),
                .float(c.rippleFrequency), .float(c.rippleSpeed),
                .float(c.displacementStrength),
            ]
        case .liquidMetal:
            function = lib.liquidMetal
            arguments = common + [
                .float(c.noise), .float(c.strength),
                .float(c.displacementStrength), .float(c.sheen),
            ]
        case .brushedMetal:
            function = lib.brushedMetal
            arguments = common + [
                .float(c.noise), .float(c.strength),
                .float(c.displacementStrength), .float(c.sheen),
            ]
        case .aurora:
            function = lib.aurora
            arguments = common + [
                .float(c.noise), .float(c.strength),
                .float(c.rippleFrequency), .float(c.displacementStrength),
            ]
        case .plasma:
            function = lib.plasma
            arguments = common + [
                .float(c.noise), .float(c.strength),
                .float(c.rippleFrequency), .float(c.displacementStrength),
                .float(c.sheen),
            ]
        }
        return Shader(function: function, arguments: arguments)
    }

    public var body: some View {
        LinearGradient(
            colors: [
                color1.mix(with: color4, by: configuration.topColorMix),
                color2,
                color3,
            ],
            startPoint: configuration.startPoint,
            endPoint: configuration.endPoint
        )
        .layerEffect(shader, maxSampleOffset: configuration.maxSampleOffset)
        .onReceive(timer) { _ in
            angle += configuration.orbitSpeed
            dragp = CGPoint(
                x: 5 + cos(angle) * configuration.orbitRadius,
                y: 5 + sin(angle) * configuration.orbitRadius
            )
            if externalTime == nil { time += 1.0 / 120.0 }
        }
        .frame(maxHeight: .infinity)
        .scaleEffect(configuration.scale)
        .ignoresSafeArea()
    }
}

#if DEBUG
#Preview("Bubbld Default") {
    MetalShaderBackgroundView()
}

#Preview("Intense Preset") {
    ZStack {
        MetalShaderBackgroundView().configuration(.intense)
    }
}

#Preview("Liquid Metal") {
    MetalShaderBackgroundView(.liquidMetal)
}

#Preview("Brushed Metal") {
    MetalShaderBackgroundView(.brushedMetal)
}

#Preview("Aurora") {
    MetalShaderBackgroundView(.aurora)
        .color1(.bpink)
        .orbitSpeed(0.02)
}

#Preview("Plasma") {
    MetalShaderBackgroundView(.plasma)
}

#Preview("Custom Colors & Knobs") {
    MetalShaderBackgroundView(.ripple)
        .colors(.bpink, .bindigo, .bgreen, .bpink)
        .noise(10)
        .rippleFrequency(2)
        .displacementStrength(0.4)
        .startPoint(.top)
        .endPoint(.bottom)
}

// MARK: - Interactive playground (Liquid Glass)

/// A live editor for every `Configuration` knob, floating in a Liquid Glass
/// panel over the animated background. Preview-only, and gated to iOS 26 /
/// macOS 26 where the Liquid Glass APIs exist — the shipping component still
/// deploys to iOS 18 / macOS 15.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
private struct PlaygroundView: View {
    @State private var config = MetalShaderBackgroundView.Configuration()
    @State private var color1: Color = .bpink
    @State private var color2: Color = .white
    @State private var color3: Color = .bgreen
    @State private var color4: Color = .bindigo

    var body: some View {
        ZStack(alignment: .bottom) {
            MetalShaderBackgroundView()
                .configuration(config)
                .colors(color1, color2, color3, color4)

            
            GlassEffectContainer(spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        presets

                        style

                        colors

                        GlassSliderRow(title: "Noise", value: $config.noise, range: 0...40)
                        GlassSliderRow(title: "Strength", value: $config.strength, range: 0...40)
                        GlassSliderRow(title: "Ripple Frequency", value: $config.rippleFrequency, range: 0...40)
                        GlassSliderRow(title: "Ripple Speed", value: $config.rippleSpeed, range: 0...10)
                        GlassSliderRow(title: "Displacement", value: $config.displacementStrength, range: 0...1)
                        GlassSliderRow(title: "Sheen", value: $config.sheen, range: 0...1)
                        GlassSliderRow(title: "Top Color Mix", value: $config.topColorMix, range: 0...1)
                        GlassSliderRow(title: "Orbit Radius", value: $config.orbitRadius, range: 0...600)
                        GlassSliderRow(title: "Orbit Speed", value: $config.orbitSpeed, range: 0...0.01)
                        GlassSliderRow(title: "Scale", value: $config.scale, range: 1...1.5)
                    }
                    .padding(20)
                }
                .frame(maxHeight: 380)
                .glassEffect(.clear, in: .rect(cornerRadius: 28))
                .padding()
            }
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button("Default") { config = .default }
                Button("Calm") { config = .calm }
                Button("Intense") { config = .intense }
                Button("Liquid") { config = .liquidMetal }
                Button("Brushed") { config = .brushedMetal }
                Button("Aurora") { config = .aurora }
                Button("Plasma") { config = .plasma }
            }
            .buttonStyle(.glass)
            .font(.caption.weight(.semibold))
        }
    }

    private var style: some View {
        Picker("Style", selection: $config.style) {
            ForEach(MetalShaderBackgroundView.BackgroundStyle.allCases, id: \.self) { s in
                Text(s.displayName).tag(s)
            }
        }
        .pickerStyle(.menu)
        .font(.caption.weight(.semibold))
    }

    private var colors: some View {
        HStack(spacing: 16) {
            ColorPicker("1", selection: $color1).labelsHidden()
            ColorPicker("2", selection: $color2).labelsHidden()
            ColorPicker("3", selection: $color3).labelsHidden()
            ColorPicker("4", selection: $color4).labelsHidden()
            Spacer()
        }
    }
}

/// A labeled slider with a live value readout, styled to read on glass.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
private struct GlassSliderRow<V>: View where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.3g", Double(value)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

#Preview("Liquid Glass Playground") {
    if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
        PlaygroundView()
    } else {
        Text("The playground requires iOS 26 / macOS 26 (Liquid Glass).")
            .padding()
    }
}
#endif
