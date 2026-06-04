import SwiftUI

struct AccountGateView: View {
    let title: String
    let message: String
    let buttonTitle: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingAuth = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(0.18))
                    .frame(width: 70, height: 70)
                    .overlay {
                        Circle()
                            .stroke(BrieflyTheme.accent.opacity(0.36), lineWidth: 1)
                    }

                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button {
                Haptics.selection()
                isShowingAuth = true
            } label: {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(BrieflyTheme.actionGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: BrieflyTheme.cardCornerRadius, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.96))
                .overlay {
                    BrieflyTheme.surfaceGradient
                        .clipShape(RoundedRectangle(cornerRadius: BrieflyTheme.cardCornerRadius, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: BrieflyTheme.cardCornerRadius, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.88), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sheet(isPresented: $isShowingAuth) {
            AuthView()
                .environmentObject(appState)
        }
        .onChange(of: appState.session != nil) { _, isSignedIn in
            if isSignedIn {
                isShowingAuth = false
                dismiss()
            }
        }
    }
}
