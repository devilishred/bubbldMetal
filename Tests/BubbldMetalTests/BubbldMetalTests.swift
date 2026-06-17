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

    /// The view initializes via both public initializers.
    func testViewInitializers() {
        _ = MetalShaderBackgroundView()
        _ = MetalShaderBackgroundView(configuration: .intense)
        _ = MetalShaderBackgroundView(
            color1: .bpink, color2: .bindigo, color3: .bgreen, color4: .bpink,
            time: 1.0,
            configuration: .init(noise: 20, rippleFrequency: 12, displacementStrength: 0.4),
            timer: Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
        )
    }

    /// Configuration defaults match the original hardcoded shader/layout values.
    func testConfigurationDefaults() {
        let config = MetalShaderBackgroundView.Configuration.default
        XCTAssertEqual(config.rippleFrequency, 16.0)
        XCTAssertEqual(config.rippleSpeed, 3.0)
        XCTAssertEqual(config.displacementStrength, 0.3)
        XCTAssertEqual(config.topColorMix, 0.8)
        XCTAssertEqual(config.scale, 1.1)
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
        XCTAssertNotNil(library.makeFunction(name: "fbp"), "Expected stitchable function `fbp` in default.metallib")
        #else
        throw XCTSkip("Metal is not available on this platform.")
        #endif
    }
}
