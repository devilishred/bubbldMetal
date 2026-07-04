import XCTest
import SwiftUI
@testable import BubbldMetal

#if canImport(Metal)
import Metal
#endif

final class BubbldMetalTests: XCTestCase {

    /// Brand colors are defined in code and resolve without an asset catalog.
    func testBrandColorsExist() {
        _ = Color.bpink
        _ = Color.bgreen
        _ = Color.bindigo
    }

    /// The view initializes via the style initializer and the fluent modifiers.
    func testViewInitializers() {
        _ = MetalShaderBackgroundView()
        _ = MetalShaderBackgroundView(.aurora)
            .color1(.bpink)
            .orbitSpeed(0.02)
        _ = MetalShaderBackgroundView(.ripple)
            .colors(.bpink, .bindigo, .bgreen, .bpink)
            .noise(20)
            .rippleFrequency(12)
            .displacementStrength(0.4)
            .sheen(0.7)
            .time(1.0)
            .timer(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect())
        _ = MetalShaderBackgroundView().configuration(.intense)
    }

    /// Configuration defaults match the original hardcoded shader/layout values.
    func testConfigurationDefaults() {
        let config = MetalShaderBackgroundView.Configuration.default
        XCTAssertEqual(config.style, .ripple)
        XCTAssertEqual(config.rippleFrequency, 16.0)
        XCTAssertEqual(config.rippleSpeed, 3.0)
        XCTAssertEqual(config.displacementStrength, 0.3)
        XCTAssertEqual(config.sheen, 0.5)
        XCTAssertEqual(config.topColorMix, 0.8)
        XCTAssertEqual(config.scale, 1.1)
    }

    /// Every style has a stable raw value and a non-empty display name, and the
    /// per-style presets select the matching style.
    func testBackgroundStylesAndPresets() {
        XCTAssertEqual(MetalShaderBackgroundView.BackgroundStyle.allCases.count, 5)
        for style in MetalShaderBackgroundView.BackgroundStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty)
        }
        XCTAssertEqual(MetalShaderBackgroundView.Configuration.liquidMetal.style, .liquidMetal)
        XCTAssertEqual(MetalShaderBackgroundView.Configuration.brushedMetal.style, .brushedMetal)
        XCTAssertEqual(MetalShaderBackgroundView.Configuration.aurora.style, .aurora)
        XCTAssertEqual(MetalShaderBackgroundView.Configuration.plasma.style, .plasma)
    }

    /// The view initializes with each background style, and each style's
    /// initializer seeds the matching tuned preset.
    func testViewInitializesForEveryStyle() {
        for style in MetalShaderBackgroundView.BackgroundStyle.allCases {
            _ = MetalShaderBackgroundView(style)
            XCTAssertEqual(MetalShaderBackgroundView.Configuration.preset(for: style).style, style)
        }
    }

    /// Smoke test: the `.metal` source compiled into a `default.metallib` in the
    /// package bundle and exposes the stitchable `fbp` function. Skips cleanly on
    /// machines without a GPU (e.g. headless CI runners).
    func testShaderLibraryLoadsFromBundle() throws {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available on this machine.")
        }
        let library = try device.makeDefaultLibrary(bundle: .module)
        for name in ["fbp", "liquidMetal", "brushedMetal", "aurora", "plasma"] {
            XCTAssertNotNil(library.makeFunction(name: name),
                            "Expected stitchable function `\(name)` in default.metallib")
        }
        #else
        throw XCTSkip("Metal is not available on this platform.")
        #endif
    }
}
