import SwiftUI

/// Brand tokens aligned to the Figma Make LiDirt ops shell (`#1b2224` / `#f5c518`).
enum LiDirtColors {
    /// Primary workspace background — Make app shell.
    static let gunmetal = Color(red: 0.106, green: 0.133, blue: 0.141) // #1b2224
    /// Elevated panels / sidebar / cards — Make `#20282b`.
    static let gunmetalElevated = Color(red: 0.125, green: 0.157, blue: 0.169) // #20282b
    static let gunmetalDeep = Color(red: 0.082, green: 0.106, blue: 0.114) // ~#151b1d

    /// Primary actions, borders, accents — construction yellow `#f5c518`.
    static let constructionYellow = Color(red: 0.961, green: 0.773, blue: 0.094)
    static let constructionYellowPressed = Color(red: 0.85, green: 0.68, blue: 0.08)

    static let textPrimary = Color(red: 0.910, green: 0.925, blue: 0.933) // #e8ecee
    static let textSecondary = Color(red: 0.78, green: 0.80, blue: 0.82)
    static let textMuted = Color(red: 0.518, green: 0.565, blue: 0.580) // #849094

    static let hairline = Color.white.opacity(0.07)

    static let coverageGood = Color(red: 0.30, green: 0.75, blue: 0.40)
    static let coverageThin = Color(red: 0.95, green: 0.70, blue: 0.20)
    static let coverageMissing = Color(red: 0.85, green: 0.30, blue: 0.28)

    static let danger = Color(red: 0.90, green: 0.35, blue: 0.30)
}

extension ShapeStyle where Self == Color {
    static var lidirtGunmetal: Color { LiDirtColors.gunmetal }
    static var lidirtYellow: Color { LiDirtColors.constructionYellow }
}
