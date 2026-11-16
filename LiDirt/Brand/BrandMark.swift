import SwiftUI

/// Circular house / excavator / soil-layer mark from the LiDirt brand logo asset.
struct BrandMark: View {
    var size: CGFloat = 120

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("LiDirt")
    }
}

#Preview {
    ZStack {
        LiDirtColors.gunmetal.ignoresSafeArea()
        BrandMark(size: 160)
    }
}
