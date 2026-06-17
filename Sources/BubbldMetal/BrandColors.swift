//
//  BrandColors.swift
//  BubbldMetal
//
//  The bubbld brand palette, defined in code so the package carries no
//  asset-catalog dependency. Values match the original `.colorset` sRGB
//  components exactly (identical in light and dark appearances).
//

import SwiftUI

public extension Color {
    /// Bubbld pink — sRGB(0.940, 0.713, 1.000), ≈ #F0B6FF
    static let bpink = Color(.sRGB, red: 0.940, green: 0.713, blue: 1.000, opacity: 1.0)

    /// Bubbld green — sRGB(0.280, 1.000, 0.443), ≈ #47FF71
    static let bgreen = Color(.sRGB, red: 0.280, green: 1.000, blue: 0.443, opacity: 1.0)

    /// Bubbld indigo — sRGB(0.456, 0.500, 1.000), ≈ #7480FF
    static let bindigo = Color(.sRGB, red: 0.456, green: 0.500, blue: 1.000, opacity: 1.0)
}
