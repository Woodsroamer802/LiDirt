import SwiftUI

struct UnsupportedDeviceView: View {
    var onViewProjects: (() -> Void)?

    var body: some View {
        ZStack {
            LiDirtColors.gunmetal.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(LiDirtColors.constructionYellow)
                    .accessibilityHidden(true)

                Text("LiDAR required for scanning")
                    .font(LiDirtTypography.title)
                    .foregroundStyle(LiDirtColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("LiDirt capture uses Apple LiDAR scene reconstruction on Pro iPhone and iPad models. This device cannot start a scan — we do not offer a camera-only fake DEM.")
                    .font(LiDirtTypography.body)
                    .foregroundStyle(LiDirtColors.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Supported for capture")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Text("• iPhone Pro / Pro Max with LiDAR")
                    Text("• iPad Pro with LiDAR")
                    Text("• iOS 17 or later")
                }
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 12))

                Text("Field grade estimating. Not a certified survey.")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)

                if let onViewProjects {
                    Button("View projects (read-only)", action: onViewProjects)
                        .buttonStyle(LiDirtSecondaryButtonStyle())
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .navigationTitle("Unsupported")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        UnsupportedDeviceView(onViewProjects: {})
    }
}
