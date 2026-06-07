import SwiftUI
import UIKit
import UserNotifications

struct MoreView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var appliedJobs: [JobListing] = []
    private let jobsService = SavedJobsService()

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
            .task {
                await loadAppliedJobs()
            }
            .onChange(of: appState.session?.userID) {
                Task { await loadAppliedJobs() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppNotifications.appliedJobsDidChange)) { _ in
                Task { await loadAppliedJobs() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("Account, saved stories, applied jobs, and synced progress.")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BrieflyTheme.secondaryText)
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
                    subtitle: "Bookmarks synced to your account",
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
                NotificationSettingsView()
            } label: {
                MoreDestinationRow(
                    icon: "bell.badge.fill",
                    title: "Notifications",
                    subtitle: appState.session == nil ? "Sign in to enable alerts" : "Job alerts based on recent activity",
                    tint: BrieflyTheme.accentBlue
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

    private func loadAppliedJobs() async {
        guard let session = appState.session else {
            appliedJobs = []
            return
        }

        appliedJobs = (try? await jobsService.fetchAppliedJobs(session: session)) ?? []
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var preferences = NotificationPreferences.defaults()
    @State private var isSaving = false
    @State private var notice: String?

    private let notificationService = NotificationService.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    Text("Personal alerts for the things you actually follow in Briefly.")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineSpacing(3)
                }

                if appState.session == nil {
                    AccountGateView(
                        title: "Sign in to enable notifications",
                        message: "Briefly ties notification preferences and job activity to your account so alerts follow you across devices.",
                        buttonTitle: "Sign In or Create Account"
                    )
                } else {
                    statusCard
                    preferenceSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .onChange(of: appState.session?.userID) {
            Task { await load() }
        }
        .onChange(of: preferences.dailyBriefEnabled) { savePreferences() }
        .onChange(of: preferences.jobsEnabled) { savePreferences() }
        .onChange(of: preferences.sportsEnabled) { savePreferences() }
        .onChange(of: preferences.readingGoalEnabled) { savePreferences() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.18))
                        .frame(width: 54, height: 54)

                    Image(systemName: statusIcon)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(statusTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)

                    Text(statusMessage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineSpacing(3)
                }
            }

            if authorizationStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    notificationButtonLabel("Open Settings")
                }
                .buttonStyle(.plain)
            } else if !authorizationStatus.allowsSettingsNotifications {
                Button {
                    Task { await enableNotifications() }
                } label: {
                    notificationButtonLabel(isSaving ? "Enabling..." : "Enable Notifications")
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }

            if let notice {
                Text(notice)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.94))
                .overlay {
                    LinearGradient(
                        colors: [statusTint.opacity(0.14), BrieflyTheme.elevatedCard.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.84), lineWidth: 1)
        }
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alert Types")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            NotificationToggleRow(
                icon: "briefcase.fill",
                title: "Job Matches",
                subtitle: "Based on recent searches, opens, saves, and applications.",
                tint: BrieflyTheme.accent,
                isOn: $preferences.jobsEnabled
            )

            NotificationToggleRow(
                icon: "sparkles",
                title: "Daily Brief",
                subtitle: "A quiet reminder when your fresh brief is ready.",
                tint: BrieflyTheme.accentBlue,
                isOn: $preferences.dailyBriefEnabled
            )

            NotificationToggleRow(
                icon: "sportscourt.fill",
                title: "Sports",
                subtitle: "Scores and live moments for followed games.",
                tint: .green,
                isOn: $preferences.sportsEnabled
            )

            NotificationToggleRow(
                icon: "books.vertical.fill",
                title: "Reading Goal",
                subtitle: "Progress nudges when you are behind your goal.",
                tint: .orange,
                isOn: $preferences.readingGoalEnabled
            )
        }
    }

    private func notificationButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(BrieflyTheme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(BrieflyTheme.actionGradient)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load() async {
        authorizationStatus = await notificationService.currentAuthorizationStatus()
        guard let session = appState.session else {
            preferences = .defaults()
            return
        }

        preferences = (try? await notificationService.loadPreferences(session: session)) ?? .defaults(userID: session.userID)
    }

    private func enableNotifications() async {
        guard let session = appState.session, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            authorizationStatus = try await notificationService.requestAuthorizationAndRegister(session: session)
            notice = authorizationStatus.allowsSettingsNotifications
                ? "Notifications are enabled for this device."
                : "Notifications were not enabled."
            Haptics.success()
        } catch {
            notice = "Briefly could not enable notifications yet."
            Haptics.error()
        }
    }

    private func savePreferences() {
        guard let session = appState.session else { return }
        Task {
            try? await notificationService.savePreferences(preferences, session: session)
        }
    }

    private var statusTitle: String {
        switch authorizationStatus {
        case .authorized:
            return "Notifications On"
        case .provisional, .ephemeral:
            return "Quiet Notifications On"
        case .denied:
            return "Notifications Off"
        case .notDetermined:
            return "Not Enabled Yet"
        @unknown default:
            return "Notification Status Unknown"
        }
    }

    private var statusMessage: String {
        switch authorizationStatus {
        case .authorized:
            return "This device can receive Briefly alerts."
        case .provisional, .ephemeral:
            return "Briefly can send quiet alerts. You can adjust this in Settings."
        case .denied:
            return "Enable notifications in iOS Settings to receive Briefly alerts."
        case .notDetermined:
            return "Turn on alerts when you want Briefly to notify you."
        @unknown default:
            return "Open iOS Settings if alerts are not arriving."
        }
    }

    private var statusIcon: String {
        authorizationStatus.allowsSettingsNotifications ? "bell.badge.fill" : "bell.slash.fill"
    }

    private var statusTint: Color {
        authorizationStatus.allowsSettingsNotifications ? BrieflyTheme.accent : BrieflyTheme.secondaryText
    }
}

private extension UNAuthorizationStatus {
    var allowsSettingsNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

private struct NotificationToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(2)
            }

            Spacer(minLength: 10)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(16)
        .background(BrieflyTheme.cardBase.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.78), lineWidth: 1)
        }
    }
}

private struct AppliedJobsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var appliedJobs: [JobListing] = []
    private let jobsService = SavedJobsService()

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
        .task {
            await loadAppliedJobs()
        }
        .onChange(of: appState.session?.userID) {
            Task { await loadAppliedJobs() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotifications.appliedJobsDidChange)) { _ in
            Task { await loadAppliedJobs() }
        }
    }

    private var appliedJobsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.session == nil {
                AccountGateView(
                    title: "Sign in to track applications",
                    message: "Applied jobs are tied to your account so they restore when you sign in on any device.",
                    buttonTitle: "Sign In or Create Account"
                )
            } else if appliedJobs.isEmpty {
                Text("Open a job link from Jobs, close the in-app browser, then confirm that you applied. It will appear here.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(BrieflyTheme.cardBase.opacity(0.92))
                            .overlay {
                                BrieflyTheme.quietSurfaceGradient
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(BrieflyTheme.divider.opacity(0.82), lineWidth: 1)
                    }
            } else {
                VStack(spacing: 12) {
                    ForEach(appliedJobs) { job in
                        AppliedJobRow(job: job)
                    }
                }
            }
        }
    }

    private func loadAppliedJobs() async {
        guard let session = appState.session else {
            appliedJobs = []
            return
        }

        appliedJobs = (try? await jobsService.fetchAppliedJobs(session: session)) ?? []
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
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.94))
                .overlay {
                    LinearGradient(
                        colors: [tint.opacity(0.11), BrieflyTheme.elevatedCard.opacity(0.90)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
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
