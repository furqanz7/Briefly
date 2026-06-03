import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BrieflyTheme.premiumBackground.ignoresSafeArea()

            if appState.isBootstrapping {
                ProgressView()
                    .tint(BrieflyTheme.accent)
            } else if !appState.hasCompletedWelcome {
                WelcomeView()
            } else if appState.passwordRecoverySession != nil {
                AuthView()
            } else {
                MainTabView()
            }
        }
        .task {
            await appState.bootstrap()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: appState.hasCompletedWelcome)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: appState.session != nil)
    }
}
