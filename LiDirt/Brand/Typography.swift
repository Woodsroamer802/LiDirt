import SwiftUI

enum LiDirtTypography {
    static let brand = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 18, weight: .semibold, design: .default)
    static let body = Font.system(size: 16, weight: .regular, design: .default)
    static let caption = Font.system(size: 13, weight: .medium, design: .default)
    static let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let score = Font.system(size: 56, weight: .bold, design: .rounded)
}

struct LiDirtPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LiDirtTypography.headline)
            .foregroundStyle(LiDirtColors.gunmetalDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(disabled
                          ? LiDirtColors.textMuted
                          : (configuration.isPressed
                             ? LiDirtColors.constructionYellowPressed
                             : LiDirtColors.constructionYellow))
            )
            .opacity(configuration.isPressed && !disabled ? 0.92 : 1)
    }
}

struct LiDirtSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LiDirtTypography.headline)
            .foregroundStyle(LiDirtColors.constructionYellow)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LiDirtColors.constructionYellow, lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LiDirtColors.gunmetalElevated.opacity(configuration.isPressed ? 0.8 : 1))
                    )
            )
    }
}
