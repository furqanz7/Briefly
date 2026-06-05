import Foundation

@MainActor
final class SportsViewModel: ObservableObject {
    private static let liveRefreshInterval: Duration = .seconds(60)

    enum Feed: String, CaseIterable, Identifiable {
        case live
        case upcoming
        case recent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live:
                return "Live"
            case .upcoming:
                return "Upcoming"
            case .recent:
                return "Recent"
            }
        }

        var icon: String {
            switch self {
            case .live:
                return "dot.radiowaves.left.and.right"
            case .upcoming:
                return "calendar"
            case .recent:
                return "clock.arrow.circlepath"
            }
        }

        var emptyTitle: String {
            switch self {
            case .live:
                return "No live matches"
            case .upcoming:
                return "No upcoming fixtures"
            case .recent:
                return "No recent results"
            }
        }

        var emptyMessage: String {
            switch self {
            case .live:
                return "Live scores will appear here as soon as a configured sports provider returns active matches."
            case .upcoming:
                return "Upcoming fixtures will appear here when the provider has scheduled matches to show."
            case .recent:
                return "Recent results will appear here after matches finish and the provider publishes scorecards."
            }
        }
    }

    @Published var sports: [LiveSportSection] = []
    @Published var upcomingSports: [LiveSportSection] = []
    @Published var recentSports: [LiveSportSection] = []
    @Published var selectedFeed: Feed = .live
    @Published var selectedSportID: String = "all"
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var providerMessage: String?
    @Published var providerConfigured = true
    @Published var lastUpdatedAt: Date?

    private let sportsService = SportsService()
    private var isFetching = false
    private let sportsCacheKey = "sports.live.feed.v2"
    private let sportsCacheMaxAge: TimeInterval = 6 * 60 * 60

    var feedTitle: String {
        selectedFeed.title
    }

    var currentSports: [LiveSportSection] {
        switch selectedFeed {
        case .live:
            return sports
        case .upcoming:
            return upcomingSports
        case .recent:
            return recentSports
        }
    }

    var visibleSports: [LiveSportSection] {
        let sportFiltered = selectedSportID == "all"
            ? currentSports
            : currentSports.filter { $0.id == selectedSportID }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sportFiltered }

        return sportFiltered.compactMap { sport in
            let competitions = sport.competitions.compactMap { competition -> LiveCompetition? in
                let competitionMatchesQuery = "\(competition.name) \(competition.country ?? "")".lowercased()
                let matches = competition.matches.filter { match in
                    if competitionMatchesQuery.contains(query) { return true }
                    return [
                        match.sportName,
                        match.competitionName,
                        match.country,
                        match.status,
                        match.statusDetail,
                        match.period,
                        match.homeName,
                        match.awayName,
                        match.homeScore,
                        match.awayScore,
                        match.scoreSummary,
                        match.venue,
                        match.note,
                    ]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(query) }
                }
                guard !matches.isEmpty else { return nil }
                return LiveCompetition(
                    id: competition.id,
                    name: competition.name,
                    country: competition.country,
                    matches: matches
                )
            }
            guard !competitions.isEmpty else { return nil }
            return LiveSportSection(
                id: sport.id,
                name: sport.name,
                icon: sport.icon,
                competitions: competitions
            )
        }
    }

    var totalLiveMatches: Int {
        sports.reduce(0) { $0 + $1.matchCount }
    }

    var hasLiveMatches: Bool {
        totalLiveMatches > 0
    }

    var currentMatchCount: Int {
        return currentSports.reduce(0) { $0 + $1.matchCount }
    }

    var hasCurrentFeedItems: Bool {
        currentMatchCount > 0
    }

    var hasVisibleFeedItems: Bool {
        visibleSports.reduce(0) { $0 + $1.matchCount } > 0
    }

    func load(force: Bool = false, showsLoading: Bool = true) async {
        if isFetching { return }
        isFetching = true
        hydrateCachedSportsIfNeeded()
        if showsLoading {
            isLoading = !hasCurrentFeedItems
            errorMessage = nil
        }

        defer {
            isFetching = false
            if showsLoading {
                isLoading = false
            }
        }

        do {
            let response = try await sportsService.fetchLiveScores(forceRefresh: force)
            sports = response.sports.filter { $0.matchCount > 0 }
            upcomingSports = response.upcomingSports.filter { $0.matchCount > 0 }
            recentSports = response.recentSports.filter { $0.matchCount > 0 }
            providerConfigured = response.providerConfigured
            providerMessage = nil
            lastUpdatedAt = response.generatedAt
            errorMessage = nil
            AppFeedCache.save(response, key: sportsCacheKey)
            WidgetSnapshotStore.saveSports(sports)

            if selectedSportID != "all",
               !currentSports.contains(where: { $0.id == selectedSportID }) {
                selectedSportID = "all"
            }
        } catch {
            if showsLoading || !hasCurrentFeedItems {
                errorMessage = error.localizedDescription
            }
        }
    }

    func startLiveUpdates() async {
        await load(force: true)

        while !Task.isCancelled {
            try? await Task.sleep(for: Self.liveRefreshInterval)
            if Task.isCancelled { break }
            await load(force: true, showsLoading: false)
        }
    }

    func selectFeed(_ feed: Feed) {
        selectedFeed = feed
        if selectedSportID != "all",
           !currentSports.contains(where: { $0.id == selectedSportID }) {
            selectedSportID = "all"
        }
    }

    private func hydrateCachedSportsIfNeeded() {
        guard sports.isEmpty,
              upcomingSports.isEmpty,
              recentSports.isEmpty,
              let cached = AppFeedCache.load(LiveScoresResponse.self, key: sportsCacheKey, maxAge: sportsCacheMaxAge) else {
            return
        }

        let response = cached.value
        sports = response.sports.filter { $0.matchCount > 0 }
        upcomingSports = response.upcomingSports.filter { $0.matchCount > 0 }
        recentSports = response.recentSports.filter { $0.matchCount > 0 }
        providerConfigured = response.providerConfigured
        providerMessage = "Showing saved scores while refreshing."
        lastUpdatedAt = cached.storedAt
        WidgetSnapshotStore.saveSports(sports)
    }
}
