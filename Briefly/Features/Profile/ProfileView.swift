import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingSignOutConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deletionError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Profile")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                if appState.session == nil {
                    AccountGateView(
                        title: "Account is optional",
                        message: "You can read Briefly without signing in. Sign in to save books, track jobs, and use personal widgets.",
                        buttonTitle: "Sign In or Create Account"
                    )
                } else {
                    signedInContent
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
        .confirmationDialog(
            "Sign out?",
            isPresented: $isShowingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                appState.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out of Briefly?")
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and synced Briefly data.")
        }
        .alert("Could not delete account", isPresented: deleteErrorBinding, actions: {
            Button("OK") {
                deletionError = nil
            }
        }, message: {
            Text(deletionError ?? "")
        })
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 15) {
                ZStack {
                    Circle()
                        .fill(BrieflyTheme.accent.opacity(0.18))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .stroke(BrieflyTheme.accent.opacity(0.34), lineWidth: 1)
                        }

                    Image(systemName: "person.fill")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.session?.email ?? "No email")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("Saved stories, books, jobs, and reading progress are synced.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineSpacing(3)
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(BrieflyTheme.cardBase.opacity(0.94))
                    .overlay {
                        BrieflyTheme.surfaceGradient
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
            }

            Button {
                isShowingSignOutConfirmation = true
            } label: {
                Text("Sign Out")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(BrieflyTheme.actionGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 12) {
                Text("Delete Account")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text("This permanently deletes your Briefly account and saved data. This cannot be undone.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.secondaryText)

                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        if isDeletingAccount {
                            ProgressView().tint(.white)
                        }
                        Text(isDeletingAccount ? "Deleting Account..." : "Delete Account")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
            }
            .padding(20)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.red.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await appState.deleteAccount()
        } catch {
            deletionError = error.localizedDescription
            Haptics.error()
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { isPresented in
                if !isPresented {
                    deletionError = nil
                }
            }
        )
    }
}
