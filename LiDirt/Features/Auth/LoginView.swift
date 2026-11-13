import SwiftUI

struct LoginView: View {
    var onContinue: () -> Void

    @State private var email = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LiDirtColors.gunmetalDeep, LiDirtColors.gunmetal, LiDirtColors.gunmetalElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 8) {
                    Text("LiDirt")
                        .font(LiDirtTypography.brand)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                    Text("Field grade and volume estimating")
                        .font(LiDirtTypography.body)
                        .foregroundStyle(LiDirtColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Email")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    TextField("you@company.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(LiDirtColors.textPrimary)
                }
                .padding(.horizontal, 24)

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(LiDirtPrimaryButtonStyle(disabled: email.trimmingCharacters(in: .whitespaces).isEmpty))
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)

                Text("Auth is a local stub for this MVP. Scan upload uses a configurable API base URL.")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

#Preview {
    LoginView(onContinue: {})
}
