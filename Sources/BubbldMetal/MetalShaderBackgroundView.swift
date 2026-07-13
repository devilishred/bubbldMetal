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
    public enum BackgroundStyle: String, CaseIterable, Hashable, Sendable, Codable {
        /// Ripple + value-noise displacement — the original bubbld look (`fbp`).
        case ripple
        /// Domain-warped fbm with a sharp specular crest — chrome/mercury.
        case liquidMetal
        /// Soft drifting bands of light over the gradient.
        case aurora
        /// Interfering sine fields with thin-film iridescence — oil-slick foil.
        case plasma
        /// Drifting fractal-noise clouds through a four-color palette.
        case clouds
        /// Wispy ink tendrils diffusing between two colors.
        case smoke
        /// Warped-fbm height field faked into a liquid-metal reflection.
        case chrome

        /// Human-readable label for pickers and UI.
        public var displayName: String {
            switch self {
            case .ripple:       return "Ripple"
            case .liquidMetal:  return "Liquid Metal"
            case .aurora:       return "Aurora"
            case .plasma:       return "Plasma"
            case .clouds:       return "Clouds"
            case .smoke:        return "Smoke"
            case .chrome:       return "Chrome"
            }
        }

        /// Whether this style is a self-generating `.colorEffect` (synthesizes
        /// its own color and ignores the gradient) rather than a `.layerEffect`
        /// that displaces the gradient. Determines which SwiftUI modifier drives it.
        public var isColorEffect: Bool {
            switch self {
            case .clouds, .smoke, .chrome: return true
            default:                       return false
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
            noise: Float = 15.25,
            strength: Float = 15.0,
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
        /// `noise` is pinned low so this stays smooth regardless of the stock
        /// ripple default.
        public static let calm = Configuration(
            noise: 1.25, strength: 8, rippleFrequency: 10, rippleSpeed: 1.5,
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

        /// Drifting fractal clouds — the `.clouds` style. `noise` = cloud
        /// frequency, `strength` = domain-warp, `rippleSpeed` = drift speed.
        public static let clouds = Configuration(
            style: .clouds, noise: 3.25, strength: 5, rippleSpeed: 3
        )

        /// Wispy ink smoke — the `.smoke` style (`color1` ink over `color2` bg).
        public static let smoke = Configuration(
            style: .smoke, noise: 3.25, strength: 5, rippleSpeed: 3
        )

        /// Liquid chrome — the `.chrome` style, tinted by `color1`.
        public static let chrome = Configuration(
            style: .chrome, noise: 3.25, strength: 5, rippleSpeed: 3
        )

        /// The tuned preset for a given style — what `MetalShaderBackgroundView(style)`
        /// starts from before any modifiers are applied.
        public static func preset(for style: BackgroundStyle) -> Configuration {
            switch style {
            case .ripple:       return .default
            case .liquidMetal:  return .liquidMetal
            case .aurora:       return .aurora
            case .plasma:       return .plasma
            case .clouds:       return .clouds
            case .smoke:        return .smoke
            case .chrome:       return .chrome
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
    /// When set, the view renders a single **deterministic** frame for this
    /// phase — driving both the noise clock and the orbiting sample center from
    /// the phase and the render size, with the internal timer disabled. This is
    /// what lets the same background render identically in a live preview and in
    /// an offscreen `ImageRenderer` (thumbnails, still/video export). Takes
    /// precedence over `externalTime` and the internal clock when non-`nil`.
    private var externalPhase: Double?
    /// Design-space width the deterministic orbit is measured against, so a
    /// small preview and a high-resolution export produce an identical frame.
    private var phaseReferenceWidth: CGFloat = 360
    /// Animation clock — created internally, or supplied via `.timer(_:)`.
    private var timer: Publishers.Autoconnect<Timer.TimerPublisher>

    @State private var angle: Double = 0
    @State private var dragp: CGPoint = .zero
    @State private var time: Float = 0
    /// Wall-clock timestamp of the previous tick, so animation speed is
    /// independent of the timer's frame rate; `nil` while paused.
    @State private var lastTick: Date?

    /// Freeze the animation when the user has enabled Reduce Motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Stop issuing GPU frames when the scene is backgrounded or inactive.
    @Environment(\.scenePhase) private var scenePhase

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
        self.externalPhase = nil
        // 30 fps is plenty for a soft background and roughly halves GPU/CPU
        // cost vs. 60. Speed is wall-clock based (see body), so this only trades
        // smoothness, not animation pace. Supply a faster clock via `.timer(_:)`.
        self.timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
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

    /// Render a single **deterministic** frame for `phase`, driving both the
    /// noise clock and the orbiting sample center from the phase and the render
    /// size, with the internal timer disabled. The same phase yields the same
    /// frame at any resolution, so a live preview and an offscreen
    /// `ImageRenderer` capture (thumbnail, still, or per-frame video export)
    /// agree exactly. Advance `phase` yourself to animate.
    ///
    /// - Parameters:
    ///   - value: The animation phase (advance ~`1/60` per frame for 60fps).
    ///   - referenceWidth: Design-space width the orbit radius is measured
    ///     against, so previews and exports at different sizes coincide.
    public func phase(_ value: Double, referenceWidth: CGFloat = 360) -> Self {
        with { $0.externalPhase = value; $0.phaseReferenceWidth = referenceWidth }
    }

    /// Builds the `Shader` for the currently-selected `style`, passing only the
    /// uniforms that style's `[[stitchable]]` function declares.
    private func makeShader(dragp: CGPoint, t: Float) -> Shader {
        let lib = ShaderLibrary.bundle(Bundle.module)
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

        // Color-effect styles: no orbiting center; they take `time`, the
        // noise frequency/warp/speed, and palette colors. The `strength` knob
        // is scaled to a domain-warp amount (matching the original cardmonkey
        // wiring) so the same knob reads sensibly across styles.
        case .clouds:
            function = lib.fractalClouds
            arguments = [
                .boundingRect, .float(t),
                .float(c.noise), .float(c.strength * 0.15), .float(c.rippleSpeed),
                .color(color1), .color(color2), .color(color3), .color(color4),
            ]
        case .smoke:
            function = lib.inkSmoke
            arguments = [
                .boundingRect, .float(t),
                .float(c.noise), .float(c.strength * 0.2), .float(c.rippleSpeed),
                .color(color1), .color(color2),
            ]
        case .chrome:
            function = lib.liquidChrome
            arguments = [
                .boundingRect, .float(t),
                .float(c.noise), .float(c.strength * 0.2), .float(c.rippleSpeed),
                .color(color1), .color(color2),
            ]
        }
        return Shader(function: function, arguments: arguments)
    }

    /// The base gradient the shader distorts (layer styles) or overwrites
    /// (color-effect styles).
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                color1.mix(with: color4, by: configuration.topColorMix),
                color2,
                color3,
            ],
            startPoint: configuration.startPoint,
            endPoint: configuration.endPoint
        )
    }

    public var body: some View {
        Group {
            if let phase = externalPhase {
                // Deterministic path: derive the noise clock and the orbiting
                // center purely from `phase` and the render size — no timer, no
                // @State mutation — so an offscreen `ImageRenderer` frame is
                // identical to the live one at any resolution.
                GeometryReader { geo in
                    effected(dragp: phaseDragp(phase: phase, size: geo.size),
                             t: Float(phase * 0.5))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                // Self-animating path: the internal (or supplied) clock advances
                // `time`/`dragp` on each tick.
                effected(dragp: dragp, t: externalTime ?? time)
                    .onReceive(timer) { date in
                        // Pause on Reduce Motion or when the scene isn't active:
                        // skip every state mutation so SwiftUI re-issues no GPU
                        // frames (the effect only redraws when `time`/`dragp`
                        // change). This is the biggest real-world power/heat win.
                        guard scenePhase == .active, !reduceMotion else {
                            lastTick = nil
                            return
                        }
                        // Advance by real elapsed time (clamped) so pace is
                        // constant at any frame rate and never lurches after a pause.
                        let dt = lastTick.map { min(date.timeIntervalSince($0), 1.0 / 15.0) } ?? (1.0 / 60.0)
                        lastTick = date
                        angle += configuration.orbitSpeed * 60.0 * dt
                        dragp = CGPoint(
                            x: 5 + cos(angle) * configuration.orbitRadius,
                            y: 5 + sin(angle) * configuration.orbitRadius
                        )
                        if externalTime == nil { time += Float(dt * 0.5) }
                    }
            }
        }
        .frame(maxHeight: .infinity)
        .scaleEffect(configuration.scale)
        .ignoresSafeArea()
    }

    /// The orbiting sample center for a given `phase`, in pixel space and
    /// centered on the view. The radius scales with render size (against
    /// `phaseReferenceWidth`) so preview and export frames coincide.
    private func phaseDragp(phase: Double, size: CGSize) -> CGPoint {
        let renderScale = Double(size.width / phaseReferenceWidth)
        let orbitAngle = phase * configuration.orbitSpeed * 60
        let radius = configuration.orbitRadius * renderScale
        return CGPoint(x: Double(size.width) / 2 + cos(orbitAngle) * radius,
                       y: Double(size.height) / 2 + sin(orbitAngle) * radius)
    }

    /// Applies the correct SwiftUI effect for the current style: `.colorEffect`
    /// for self-generating styles, `.layerEffect` for displacement styles.
    @ViewBuilder private func effected(dragp: CGPoint, t: Float) -> some View {
        let shader = makeShader(dragp: dragp, t: t)
        if configuration.style.isColorEffect {
            gradient.colorEffect(shader)
        } else {
            gradient.layerEffect(shader, maxSampleOffset: configuration.maxSampleOffset)
        }
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

#Preview("Aurora") {
    MetalShaderBackgroundView(.aurora)
        .color1(.bpink)
        .orbitSpeed(0.02)
}

#Preview("Plasma") {
    MetalShaderBackgroundView(.plasma)
}

#Preview("Clouds") {
    MetalShaderBackgroundView(.clouds)
}

#Preview("Smoke") {
    MetalShaderBackgroundView(.smoke)
        .colors(.white, .black, .black, .white)
}

#Preview("Chrome") {
    MetalShaderBackgroundView(.chrome)
        .color1(.cyan)
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
                Button("Aurora") { config = .aurora }
                Button("Plasma") { config = .plasma }
                Button("Clouds") { config = .clouds }
                Button("Smoke") { config = .smoke }
                Button("Chrome") { config = .chrome }
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
