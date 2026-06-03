import SafariServices
import SwiftUI
import UIKit

struct JobsView: View {
    @StateObject private var viewModel = JobsViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showControls = false
    @State private var authPrompt: AuthPrompt?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let horizontalPadding: CGFloat = 20
                let contentWidth = max(proxy.size.width - horizontalPadding * 2, 0)
                let bottomReserve: CGFloat = 20
                let deckHeight = max(470, min(660, proxy.size.height - bottomReserve - 130))

                VStack(alignment: .leading, spacing: 14) {
                    header
                    compactControls
                    deckSection(width: contentWidth, height: deckHeight)
                }
                .frame(width: contentWidth, height: proxy.size.height, alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, bottomReserve)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .navigationBarHidden(true)
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.load()
            }
            .sheet(item: $viewModel.selectedJob) { job in
                JobDetailView(
                    job: job,
                    isSaved: viewModel.savedJobs.contains(job),
                    hasApplied: viewModel.hasApplied(job),
                    isLoadingDetail: viewModel.isLoadingDetail,
                    onToggleSave: {
                        if viewModel.savedJobs.contains(job) {
                            viewModel.removeSaved(job)
                        } else {
                            viewModel.save(job)
                        }
                    },
                    onMarkApplied: { viewModel.markApplied(job) }
                )
                .environmentObject(appState)
            }
            .sheet(isPresented: $showControls) {
                controlsSheet
                    .presentationDetents([.fraction(0.78)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30)
            }
            .sheet(item: $authPrompt) { prompt in
                AccountGateView(
                    title: prompt.title,
                    message: prompt.message,
                    buttonTitle: prompt.buttonTitle
                )
                .environmentObject(appState)
                .padding(20)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
            }
        }
        .background {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Jobs")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("\(viewModel.deckJobs.count) matches  •  \(viewModel.selectedCountry.rawValue)  •  \(viewModel.selectedFilter.rawValue)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                Button {
                    showControls = true
                } label: {
                    JobsIconButton(icon: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Job filters")

                Button {
                    Task { await viewModel.search() }
                } label: {
                    JobsIconButton(icon: "arrow.clockwise", isLoading: viewModel.isLoading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh jobs")
            }
        }
    }

    private var compactControls: some View {
        searchBar
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)

            TextField("Search role, company, skill", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(BrieflyTheme.primaryText)
                .tint(BrieflyTheme.accent)
                .onSubmit {
                    Task { await viewModel.search() }
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(BrieflyTheme.cardBase)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }

    private var controlsSheet: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Job Preferences")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text("Search, market, and deck mode")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.secondaryText)
                    }

                    searchBar

                    JobsControlGroup(title: "Quick search") {
                        quickSearchRow
                    }

                    JobsControlGroup(title: "Market") {
                        countryRow
                    }

                    JobsControlGroup(title: "Deck") {
                        filterChoiceRow
                    }

                    Button {
                        showControls = false
                        Task { await viewModel.search() }
                    } label: {
                        Text("Apply")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(BrieflyTheme.actionGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .frame(minHeight: proxy.size.height - 26, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
        }
    }

    private var quickSearchRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(viewModel.quickSearches, id: \.self) { query in
                Button {
                    viewModel.chooseQuickSearch(query)
                } label: {
                    JobPreferenceChip(
                        title: query,
                        icon: query == "Remote" ? "wifi" : "bolt.fill",
                        isSelected: viewModel.searchText == query,
                        selectedTint: BrieflyTheme.accent
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var countryRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(JobsViewModel.Country.allCases) { country in
                Button {
                    viewModel.selectedCountry = country
                } label: {
                    JobPreferenceChip(
                        title: country.rawValue,
                        icon: country == .remote ? "wifi" : "globe",
                        isSelected: viewModel.selectedCountry == country,
                        selectedTint: BrieflyTheme.accentBlue
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filterChoiceRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(JobsViewModel.Filter.allCases) { filter in
                Button {
                    viewModel.selectedFilter = filter
                } label: {
                    JobPreferenceChip(
                        title: filter.rawValue,
                        icon: filter == .saved ? "bookmark.fill" : filter == .remote ? "wifi" : "sparkles",
                        isSelected: viewModel.selectedFilter == filter,
                        selectedTint: BrieflyTheme.accent
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func deckSection(width: CGFloat, height: CGFloat) -> some View {
        if viewModel.isLoading {
            JobsMessageCard(icon: "briefcase.fill", title: "Loading matches", message: "Finding roles that fit your profile.")
                .frame(height: height)
        } else if let errorMessage = viewModel.errorMessage {
            JobsMessageCard(
                icon: "magnifyingglass",
                title: viewModel.searchText.isEmpty ? "Jobs unavailable" : "No matches yet",
                message: errorMessage
            )
                .frame(height: height)
        } else if viewModel.selectedFilter == .saved {
            savedList
                .frame(height: height)
        } else if viewModel.visibleJobs.isEmpty {
            JobsMessageCard(
                icon: "sparkles",
                title: viewModel.deckJobs.isEmpty ? "Deck cleared" : "No visible jobs",
                message: viewModel.searchText.isEmpty ? "Restore passed jobs or change filters to keep swiping." : "Try a broader role, another market, or one of the quick searches above."
            )
                .frame(height: height)
        } else {
            let cardHeight = min(max(430, height - 128), 462)
            VStack(spacing: 16) {

                ZStack {
                    ForEach(Array(viewModel.visibleJobs.prefix(3).enumerated()).reversed(), id: \.element.id) { index, job in
                        if index == 0 {
                            JobSwipeCard(
                                job: job,
                                isTopCard: true,
                                cardWidth: width,
                                cardHeight: cardHeight,
                                onSave: {
                                    requireAccount(
                                        title: "Sign in to save jobs",
                                        message: "Sign in before saving roles so Briefly can keep your job list tied to your account.",
                                        action: viewModel.saveCurrent
                                    )
                                },
                                onPass: {
                                    requireAccount(
                                        title: "Sign in to pass jobs",
                                        message: "Sign in before passing roles so your job deck can stay consistent.",
                                        action: viewModel.passCurrent
                                    )
                                },
                                onOpen: { viewModel.open(job) }
                            )
                            .allowsHitTesting(true)
                        } else {
                            JobCardBackPlate(cardWidth: width, cardHeight: cardHeight, depth: index)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: cardHeight + 34)

                HStack(spacing: 22) {
                    JobsActionButton(icon: "xmark", tint: .red) {
                        requireAccount(
                            title: "Sign in to pass jobs",
                            message: "Sign in before passing roles so your job deck can stay consistent."
                        ) {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                viewModel.passCurrent()
                            }
                        }
                    }

                    JobsActionButton(icon: "info.circle.fill", tint: BrieflyTheme.accentBlue) {
                        if let job = viewModel.currentJob {
                            viewModel.open(job)
                        }
                    }

                    JobsActionButton(icon: "checkmark", tint: .green) {
                        requireAccount(
                            title: "Sign in to save jobs",
                            message: "Sign in before saving roles so Briefly can keep your job list tied to your account."
                        ) {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                viewModel.saveCurrent()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: height, alignment: .top)
        }
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.savedJobs.isEmpty {
                JobsMessageCard(icon: "bookmark.fill", title: "No saved jobs yet", message: "Swipe right on a role to save it here.")
            } else {
                SavedJobsHeader(
                    count: viewModel.visibleJobs.count,
                    bestMatch: viewModel.visibleJobs.map(\.matchScore).max() ?? 0
                )

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.visibleJobs) { job in
                            SavedJobRow(
                                job: job,
                                onOpen: { viewModel.open(job) },
                                onRemove: { viewModel.removeSaved(job) }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func requireAccount(title: String, message: String, action: () -> Void) {
        guard appState.session != nil else {
            authPrompt = AuthPrompt(title: title, message: message)
            return
        }

        action()
    }
}

private struct JobSwipeCard: View {
    let job: JobListing
    let isTopCard: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onSave: () -> Void
    let onPass: () -> Void
    let onOpen: () -> Void

    @State private var dragOffset: CGSize = .zero

    private var matchedSkills: String {
        let skills = job.skills.prefix(3).joined(separator: ", ")
        return skills.isEmpty ? "Role, company, and market fit" : skills
    }

    private var decisionText: String? {
        if dragOffset.width > 52 { return "SAVE" }
        if dragOffset.width < -52 { return "PASS" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CompanyMark(company: job.company)

                VStack(alignment: .leading, spacing: 9) {
                    Text(job.company.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.accent)
                        .tracking(0.6)

                    Text(job.title)
                        .font(.system(size: 24, weight: .heavy))
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .lineLimit(3)

                    Text(job.location)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(spacing: 4) {
                    Text("\(job.matchScore)")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                    Text("match")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [BrieflyTheme.accent.opacity(0.32), BrieflyTheme.accent.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 12) {
                JobBadge(title: job.salary, icon: "banknote.fill")
                JobBadge(title: job.workMode.rawValue, icon: "location.fill")
                JobBadge(title: job.postedDisplayText, icon: "clock.fill")
            }

            Text(job.roleSummary)
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(BrieflyTheme.primaryText.opacity(0.92))
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.accent)
                    Text("Matched for \(matchedSkills)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 9)], alignment: .leading, spacing: 9) {
                    ForEach(job.skills.prefix(4), id: \.self) { skill in
                        Text(skill)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(BrieflyTheme.elevatedCard.opacity(0.86))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrieflyTheme.backgroundBase.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BrieflyTheme.divider.opacity(0.75), lineWidth: 1)
            }

            HStack(spacing: 10) {
                JobCardGesturePill(icon: "arrow.left", title: "Pass", tint: .red)
                JobCardGesturePill(icon: "hand.tap.fill", title: "Open", tint: BrieflyTheme.accentBlue)
                JobCardGesturePill(icon: "arrow.right", title: "Save", tint: .green)
            }
            .accessibilityLabel("Swipe left to pass, tap the card to open, swipe right to save")
        }
        .padding(22)
        .frame(width: cardWidth, height: cardHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(BrieflyTheme.cardBase)
                .overlay {
                    LinearGradient(
                        colors: [
                            BrieflyTheme.accent.opacity(0.22),
                            BrieflyTheme.accentBlue.opacity(0.10),
                            BrieflyTheme.cardBase.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(BrieflyTheme.accent.opacity(0.18))
                        .blur(radius: 34)
                        .frame(width: 130, height: 130)
                        .offset(x: 30, y: -36)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
        .overlay(alignment: dragOffset.width >= 0 ? .topLeading : .topTrailing) {
            if let decisionText {
                Text(decisionText)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(dragOffset.width > 0 ? .green : .red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(BrieflyTheme.backgroundBase.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(20)
                    .rotationEffect(.degrees(dragOffset.width > 0 ? -10 : 10))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    guard isTopCard, abs(dragOffset.width) < 8, abs(dragOffset.height) < 8 else { return }
                    onOpen()
                }
        )
        .offset(dragOffset)
        .rotationEffect(.degrees(Double(dragOffset.width / 24)))
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isTopCard else { return }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    guard isTopCard else { return }
                    if value.translation.width > 120 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            dragOffset = CGSize(width: 520, height: value.translation.height)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            dragOffset = .zero
                            onSave()
                        }
                    } else if value.translation.width < -120 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            dragOffset = CGSize(width: -520, height: value.translation.height)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            dragOffset = .zero
                            onPass()
                        }
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.title) at \(job.company), \(job.salary), \(job.workMode.rawValue). Swipe left to pass, right to save, or tap to open.")
    }
}

private struct JobCardGesturePill: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .lineLimit(1)
    }
}

private struct JobCardBackPlate: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let depth: Int

    private var scale: CGFloat {
        1 - CGFloat(depth) * 0.035
    }

    private var yOffset: CGFloat {
        CGFloat(depth) * 14
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(BrieflyTheme.cardBase.opacity(max(0.46, 0.72 - CGFloat(depth) * 0.12)))
            .overlay {
                LinearGradient(
                    colors: [
                        BrieflyTheme.accent.opacity(0.14),
                        BrieflyTheme.accentBlue.opacity(0.06),
                        BrieflyTheme.backgroundBase.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(BrieflyTheme.divider.opacity(0.80), lineWidth: 1)
            }
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 8)
            .accessibilityHidden(true)
    }
}

private struct JobsIconButton: View {
    let icon: String
    var isLoading = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BrieflyTheme.elevatedCard)
                .frame(width: 46, height: 46)
                .overlay {
                    Circle().stroke(BrieflyTheme.divider, lineWidth: 1)
                }

            if isLoading {
                ProgressView()
                    .tint(BrieflyTheme.primaryText)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText.opacity(0.86))
            }
        }
    }
}

private struct JobPreferenceChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let selectedTint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .frame(width: 15)

            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .foregroundStyle(isSelected ? BrieflyTheme.primaryText : BrieflyTheme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 42)
        .padding(.horizontal, 12)
        .background(isSelected ? selectedTint.opacity(0.28) : BrieflyTheme.cardBase)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(isSelected ? selectedTint.opacity(0.55) : BrieflyTheme.divider, lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct JobsControlGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.6)

            content
        }
    }
}

private struct JobDetailView: View {
    let job: JobListing
    let isSaved: Bool
    let hasApplied: Bool
    let isLoadingDetail: Bool
    let onToggleSave: () -> Void
    let onMarkApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var browserURL: URL?
    @State private var authPrompt: AuthPrompt?
    @State private var shouldAskAppliedAfterApply = false
    @State private var isShowingAppliedPrompt = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        CompanyMark(company: job.company)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(job.company.uppercased())
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.accent)
                            Text(job.title)
                                .font(.system(size: 32, weight: .heavy))
                                .lineSpacing(2)
                                .foregroundStyle(BrieflyTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(job.company)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BrieflyTheme.secondaryText)
                        }
                    }

                    detailMetricGrid

                    NativeAdCard(
                        slot: NativeAdSlot(
                            id: "job-detail-\(job.id)",
                            placement: .jobs
                        )
                    )

                    if isLoadingDetail {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(BrieflyTheme.primaryText)
                            Text("Loading full details")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.secondaryText)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BrieflyTheme.cardBase)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(BrieflyTheme.divider, lineWidth: 1)
                        }
                    }

                    DetailTagBlock(title: "Skills", items: job.skills, icon: "sparkle")
                    DetailBlock(title: "Company", text: job.companySummary)
                    DetailBlock(title: "Role", text: job.roleSummary)
                    DetailListBlock(title: "Requirements", items: job.requirements)
                    DetailListBlock(title: "Perks", items: job.perks)
                    applyButton
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        requireAccount(
                            title: "Sign in to save jobs",
                            message: "Sign in before saving roles so Briefly can keep your job list tied to your account.",
                            action: onToggleSave
                        )
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                    }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { browserURL != nil },
                set: { if !$0 { browserURL = nil } }
            ),
            onDismiss: {
                if shouldAskAppliedAfterApply {
                    shouldAskAppliedAfterApply = false
                    isShowingAppliedPrompt = true
                }
            }
        ) {
            if let browserURL {
                JobSafariSheet(url: browserURL)
            }
        }
        .sheet(item: $authPrompt) { prompt in
            AccountGateView(
                title: prompt.title,
                message: prompt.message,
                buttonTitle: prompt.buttonTitle
            )
            .environmentObject(appState)
            .padding(20)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
        .confirmationDialog(
            "Did you apply for this job?",
            isPresented: $isShowingAppliedPrompt,
            titleVisibility: .visible
        ) {
            Button("Yes, mark applied") {
                onMarkApplied()
                Haptics.success()
            }
            Button("No", role: .cancel) {}
        } message: {
            Text("Applied jobs appear in Profile so you can track them later.")
        }
    }

    private var detailMetricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            JobDetailMetric(icon: "banknote.fill", title: "Salary", value: job.salary)
            JobDetailMetric(icon: "target", title: "Match", value: "\(job.matchScore)%")
            JobDetailMetric(icon: "location.fill", title: "Location", value: job.location)
            JobDetailMetric(icon: "clock.fill", title: "Posted", value: job.postedDisplayText)
            JobDetailMetric(icon: "briefcase.fill", title: "Mode", value: job.workMode.rawValue)
            JobDetailMetric(icon: "link", title: "Apply", value: job.browserApplyURL == nil ? "Unavailable" : "Ready")
        }
    }

    @ViewBuilder
    private var applyButton: some View {
        if let applyURL = job.browserApplyURL {
            Button {
                requireAccount(
                    title: "Sign in to apply",
                    message: "Sign in before opening job links so Briefly can track applications in your profile."
                ) {
                    shouldAskAppliedAfterApply = true
                    browserURL = applyURL
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 16, weight: .heavy))
                    Text(hasApplied ? "Applied" : "Apply in Briefly")
                        .font(.system(size: 18, weight: .heavy))
                }
                .foregroundStyle(BrieflyTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(BrieflyTheme.actionGradient)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 16, weight: .heavy))
                Text("Apply link unavailable")
                    .font(.system(size: 17, weight: .heavy))
            }
            .foregroundStyle(BrieflyTheme.secondary(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(BrieflyTheme.elevatedCard)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BrieflyTheme.divider, lineWidth: 1)
            }
        }
    }

    private func requireAccount(title: String, message: String, action: () -> Void) {
        guard appState.session != nil else {
            authPrompt = AuthPrompt(title: title, message: message)
            return
        }

        action()
    }
}

private struct JobSafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(BrieflyTheme.accent)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct JobDetailMetric: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(BrieflyTheme.secondaryText)

            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct JobBadge: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(BrieflyTheme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(Capsule())
    }
}

private struct JobsActionButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 62, height: 62)
                .background(BrieflyTheme.elevatedCard)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(tint.opacity(0.32), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct CompanyMark: View {
    let company: String

    private var initials: String {
        company
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(BrieflyTheme.actionGradient)
            Text(initials)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
        }
        .frame(width: 58, height: 58)
        .overlay {
            Circle().stroke(BrieflyTheme.primaryText.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct SavedJobsHeader: View {
    let count: Int
    let bestMatch: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved roles")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("Shortlist worth revisiting")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }

                Spacer(minLength: 12)

                Text("\(count)")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 9) {
                SavedSummaryPill(icon: "bookmark.fill", text: "\(count) saved", tint: BrieflyTheme.accent)
                SavedSummaryPill(icon: "target", text: "\(bestMatch)% best", tint: .green)
            }
        }
    }
}

private struct SavedSummaryPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
            Text(text)
                .font(.system(size: 12, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(BrieflyTheme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.16))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.30), lineWidth: 1)
        }
    }
}

private struct SavedJobRow: View {
    let job: JobListing
    var onOpen: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            CompanyMark(company: job.company)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(job.title)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)

                        Text(job.company)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    SavedMatchBadge(score: job.matchScore)
                }

                HStack(spacing: 7) {
                    SavedJobMetaPill(icon: "mappin.and.ellipse", text: job.location)
                    SavedJobMetaPill(icon: job.workMode == .remote ? "wifi" : "building.2.fill", text: job.workMode.rawValue)
                }
            }

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(BrieflyTheme.backgroundBase.opacity(0.38))
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(BrieflyTheme.divider.opacity(0.90), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove saved job")
            }
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.86))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(BrieflyTheme.actionGradient)
                        .frame(width: 4)
                        .padding(.vertical, 18)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(BrieflyTheme.accentBlue.opacity(0.10))
                        .blur(radius: 22)
                        .frame(width: 84, height: 84)
                        .offset(x: 24, y: -24)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            onOpen?()
        }
    }
}

private struct SavedMatchBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)%")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.green.opacity(0.12))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.green.opacity(0.25), lineWidth: 1)
            }
    }
}

private struct SavedJobMetaPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(BrieflyTheme.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(BrieflyTheme.elevatedCard.opacity(0.74))
        .clipShape(Capsule())
    }
}

private struct JobsMessageCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(BrieflyTheme.accent)
            Text(title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(BrieflyTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(22)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct DetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(BrieflyTheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct DetailListBlock: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                    Text(item)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct DetailTagBlock: View {
    let title: String
    let items: [String]
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)

            if items.isEmpty {
                Text("No skills listed yet.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 7) {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .heavy))
                            Text(item)
                                .font(.system(size: 12, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)
                        }
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(BrieflyTheme.elevatedCard)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

#Preview {
    JobsView()
}
