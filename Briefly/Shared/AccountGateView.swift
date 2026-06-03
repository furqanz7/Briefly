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
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(BrieflyTheme.accent)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
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
        .background(BrieflyTheme.card(colorScheme))
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
