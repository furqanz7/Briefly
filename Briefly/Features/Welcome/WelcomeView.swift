import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer(minLength: 88)

                Image("BrieflyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .blendMode(.screen)
                    .shadow(color: BrieflyTheme.glowViolet, radius: 42, x: 0, y: 0)
                    .shadow(color: BrieflyTheme.glowBlue, radius: 32, x: 0, y: 0)

                VStack(spacing: 14) {
                    Text("Welcome to\nBriefly")
                        .font(.custom("Yeager-Light", size: 48))
                        .tracking(0.25)
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BrieflyTheme.primaryText)

                    Text("AI summaries for news, live sports, job matches, and books. Clear, quick, and built for your day.")
                        .font(.system(size: 17, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineSpacing(5)
                        .padding(.horizontal, 22)
                }

                Spacer()

                Button {
                    appState.completeWelcome()
                } label: {
                    Text("Start Exploring")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(BrieflyTheme.actionGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }
                        .shadow(color: BrieflyTheme.glowViolet, radius: 24, x: 0, y: 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 42)
            }
        }
    }
}
