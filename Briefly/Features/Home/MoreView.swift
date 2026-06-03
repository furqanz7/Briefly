import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var appliedJobs: [JobListing] = []
    private let jobsStore = LocalSavedJobsStore()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    destinations
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear(perform: loadAppliedJobs)
            .onReceive(NotificationCenter.default.publisher(for: AppNotifications.appliedJobsDidChange)) { _ in
                loadAppliedJobs()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text("Account, saved stories, and your job application tracker.")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))
        }
    }

    private var destinations: some View {
        VStack(spacing: 12) {
            NavigationLink {
                SavedView()
            } label: {
                MoreDestinationRow(
                    icon: "bookmark.fill",
                    title: "Saved Stories",
                    subtitle: "Bookmarks from Home",
                    tint: BrieflyTheme.accentBlue
                )
            }

            NavigationLink {
                ProfileView()
            } label: {
                MoreDestinationRow(
                    icon: "person.fill",
                    title: "Profile",
                    subtitle: appState.session == nil ? "Sign in or create account" : appState.session?.email ?? "Account",
                    tint: BrieflyTheme.accent
                )
            }

            NavigationLink {
                AppliedJobsView()
            } label: {
                MoreDestinationRow(
                    icon: "checkmark.seal.fill",
                    title: "Applied Jobs",
                    subtitle: appState.session == nil ? "Sign in to track applications" : "\(appliedJobs.count) tracked",
                    tint: .green
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func loadAppliedJobs() {
        appliedJobs = appState.session == nil ? [] : jobsStore.fetchApplied()
    }
}

private struct AppliedJobsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var appliedJobs: [JobListing] = []
    private let jobsStore = LocalSavedJobsStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Applied Jobs")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text("Jobs you confirmed after opening the apply link.")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))

                appliedJobsSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadAppliedJobs)
        .onReceive(NotificationCenter.default.publisher(for: AppNotifications.appliedJobsDidChange)) { _ in
            loadAppliedJobs()
        }
    }

    private var appliedJobsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.session == nil {
                AccountGateView(
                    title: "Sign in to track applications",
                    message: "Applied jobs are tied to your account so they stay available after you close the app.",
                    buttonTitle: "Sign In or Create Account"
                )
            } else if appliedJobs.isEmpty {
                Text("Open a job link from Jobs, close the in-app browser, then confirm that you applied. It will appear here.")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(BrieflyTheme.card(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(appliedJobs) { job in
                        AppliedJobRow(job: job)
                    }
                }
            }
        }
    }

    private func loadAppliedJobs() {
        appliedJobs = appState.session == nil ? [] : jobsStore.fetchApplied()
    }
}

private struct MoreDestinationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText)
        }
        .padding(16)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct AppliedJobRow: View {
    let job: JobListing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.company.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.accent)
                        .lineLimit(1)

                    Text(job.title)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(spacing: 2) {
                    Text("\(job.matchScore)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("match")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(BrieflyTheme.accent.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                Label(job.location, systemImage: "location.fill")
                Label(job.postedDisplayText, systemImage: "clock.fill")
            }
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(BrieflyTheme.secondaryText)
            .lineLimit(1)
        }
        .padding(18)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}
