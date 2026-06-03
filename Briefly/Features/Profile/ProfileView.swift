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
                    .font(.system(size: 32, weight: .bold))
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
            Text("This permanently removes your account and saved articles.")
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
            VStack(alignment: .leading, spacing: 12) {
                Text(appState.session?.email ?? "No email")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text("Signed in to keep saved stories, books, jobs, and widgets synced.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
            }
            .padding(20)
            .background(BrieflyTheme.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text("This permanently deletes your Briefly account and saved data. This cannot be undone.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))

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
            .background(BrieflyTheme.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
