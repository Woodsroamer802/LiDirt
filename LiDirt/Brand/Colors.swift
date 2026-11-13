import SwiftUI

enum LiDirtColors {
    /// Primary workspace background — gunmetal gray.
    static let gunmetal = Color(red: 0.18, green: 0.20, blue: 0.22)
    static let gunmetalElevated = Color(red: 0.24, green: 0.26, blue: 0.28)
    static let gunmetalDeep = Color(red: 0.12, green: 0.13, blue: 0.15)

    /// Primary actions, borders, accents — construction yellow.
    static let constructionYellow = Color(red: 0.96, green: 0.78, blue: 0.12)
    static let constructionYellowPressed = Color(red: 0.85, green: 0.68, blue: 0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.78, green: 0.80, blue: 0.82)
    static let textMuted = Color(red: 0.55, green: 0.58, blue: 0.60)

    static let coverageGood = Color(red: 0.30, green: 0.75, blue: 0.40)
    static let coverageThin = Color(red: 0.95, green: 0.70, blue: 0.20)
    static let coverageMissing = Color(red: 0.85, green: 0.30, blue: 0.28)

    static let danger = Color(red: 0.90, green: 0.35, blue: 0.30)
}

extension ShapeStyle where Self == Color {
    static var lidirtGunmetal: Color { LiDirtColors.gunmetal }
    static var lidirtYellow: Color { LiDirtColors.constructionYellow }
}
