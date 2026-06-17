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

    /// The tunable knobs of the effect. Every value has a sensible default, so
    /// `Configuration()` reproduces the stock bubbld look and you only override
    /// what you care about.
    public struct Configuration: Equatable, Sendable {

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
            noise: Float = 15.25,
            strength: Float = 15.0,
            rippleFrequency: Float = 16.0,
            rippleSpeed: Float = 3.0,
            displacementStrength: Float = 0.3,
            topColorMix: Double = 0.8,
            startPoint: UnitPoint = .top,
            endPoint: UnitPoint = .bottomTrailing,
            orbitRadius: Double = 300,
            orbitSpeed: Double = 0.001,
            scale: CGFloat = 1.1,
            maxSampleOffset: CGSize = CGSize(width: 300, height: 500)
        ) {
            self.noise = noise
            self.strength = strength
            self.rippleFrequency = rippleFrequency
            self.rippleSpeed = rippleSpeed
            self.displacementStrength = displacementStrength
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
        public static let intense = Configuration(
            strength: 22, rippleFrequency: 22, rippleSpeed: 4.5,
            displacementStrength: 0.45, orbitSpeed: 0.0016
        )
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
    private let externalTime: Float?
    /// Animation clock — created internally by the ergonomic init, or supplied by the caller.
    private let timer: Publishers.Autoconnect<Timer.TimerPublisher>

    @State private var angle: Double = 0
    @State private var dragp: CGPoint = .zero
    @State private var time: Float = 0

    /// Ergonomic initializer: brand-color defaults and a self-managing animation
    /// clock. Drop `MetalShaderBackgroundView()` into any view and it animates.
    public init(
        color1: Color = .bpink,
        color2: Color = .bindigo,
        color3: Color = .bgreen,
        color4: Color = .bindigo,
        configuration: Configuration = Configuration()
    ) {
        self.color1 = color1
        self.color2 = color2
        self.color3 = color3
        self.color4 = color4
        self.configuration = configuration
        self.externalTime = nil
        self.timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    }

    /// Full-control initializer: drive the `time` value and supply your own timer.
    public init(
        color1: Color,
        color2: Color,
        color3: Color,
        color4: Color,
        time: Float,
        configuration: Configuration = Configuration(),
        timer: Publishers.Autoconnect<Timer.TimerPublisher>
    ) {
        self.color1 = color1
        self.color2 = color2
        self.color3 = color3
        self.color4 = color4
        self.configuration = configuration
        self.externalTime = time
        self.timer = timer
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
        .layerEffect(
            ShaderLibrary.bundle(Bundle.module).fbp(
                .boundingRect,
                .float2(dragp),
                .float(externalTime ?? time),
                .float(configuration.noise),
                .float(configuration.strength),
                .float(configuration.rippleFrequency),
                .float(configuration.rippleSpeed),
                .float(configuration.displacementStrength)
            ),
            maxSampleOffset: configuration.maxSampleOffset
        )
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
        MetalShaderBackgroundView(configuration: .intense)
    }
}

#Preview("Custom Colors & Knobs") {
    MetalShaderBackgroundView(
        color1: .bpink,
        color2: .bindigo,
        color3: .bgreen,
        color4: .bpink,
        configuration: .init(
            noise: 10,
            rippleFrequency: 2,
            displacementStrength: 0.4,
            startPoint: .topLeading,
            endPoint: .bottom
        )
    )
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
            MetalShaderBackgroundView(
                color1: color1, color2: color2, color3: color3, color4: color4,
                configuration: config
            )

            
            GlassEffectContainer(spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        presets

                        colors

                        GlassSliderRow(title: "Noise", value: $config.noise, range: 0...40)
                        GlassSliderRow(title: "Strength", value: $config.strength, range: 0...40)
                        GlassSliderRow(title: "Ripple Frequency", value: $config.rippleFrequency, range: 0...40)
                        GlassSliderRow(title: "Ripple Speed", value: $config.rippleSpeed, range: 0...10)
                        GlassSliderRow(title: "Displacement", value: $config.displacementStrength, range: 0...1)
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
        HStack(spacing: 10) {
            Button("Default") { config = .default }
            Button("Calm") { config = .calm }
            Button("Intense") { config = .intense }
        }
        .buttonStyle(.glass)
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
