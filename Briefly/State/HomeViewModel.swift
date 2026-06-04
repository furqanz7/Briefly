import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var allArticles: [Article] = []
    @Published var featuredArticles: [Article] = []
    @Published var searchText = ""
    @Published var savedIDs = Set<String>()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchResult: SearchResult = .articles([])
    @Published var activeCategories = Set<NewsCategory>()
    @Published var lastUpdatedAt: Date?
    @Published private(set) var activeDayWindow = DayWindow.current()
    @Published var marketSnapshots: [MarketSnapshot] = []
    @Published var marketStatusMessage: String?
    @Published var marketUpdatedAt: Date?
    @Published var cryptoSnapshots: [MarketSnapshot] = []
    @Published var cryptoStatusMessage: String?
    @Published var cryptoUpdatedAt: Date?
    @Published var trendingCryptoSnapshots: [MarketSnapshot] = []
    @Published var trendingCryptoStatusMessage: String?
    @Published var cryptoStats: CryptoStats?
    @Published var cryptoStatsStatusMessage: String?
    @Published var cryptoGainers: [MarketSnapshot] = []
    @Published var cryptoLosers: [MarketSnapshot] = []
    @Published var cryptoMoversStatusMessage: String?
    @Published var cryptoSearchSnapshots: [MarketSnapshot] = []
    @Published var cryptoSearchStatusMessage: String?
    private let newsService = NewsService()
    private let marketService = MarketService()
    private let savedService = SavedArticlesService()
    private let searchService = SearchService()
    private var searchTask: Task<Void, Never>?
    private let desiredFeedCount = 48
    private let autoRefreshInterval: TimeInterval = 600

    var availableCategories: [NewsCategory] {
        NewsCategory.allCases
    }

    var filteredPicks: [Article] {
        let defaultPicks = defaultPickSource
        switch searchResult {
        case .articles(let articles):
            return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? applyCategoryFilter(defaultPicks)
                : articles
        case .aiFallback:
            return []
        }
    }

    var displayedAllArticles: [Article] {
        switch searchResult {
        case .articles(let articles):
            return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? applyCategoryFilter(allArticles)
                : articles
        case .aiFallback:
            return []
        }
    }

    var dailyBriefArticles: [Article] {
        let source = allArticles
        let ranked = source.sorted { lhs, rhs in
            let lhsScore = briefScore(lhs)
            let rhsScore = briefScore(rhs)
            if lhsScore == rhsScore {
                return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
            return lhsScore > rhsScore
        }

        var chosen: [Article] = []
        var categoryCounts: [NewsCategory: Int] = [:]

        for article in ranked {
            let primary = article.categories.first ?? .world
            if categoryCounts[primary, default: 0] >= 2 && chosen.count >= 3 {
                continue
            }

            chosen.append(article)
            categoryCounts[primary, default: 0] += 1

            if chosen.count == 5 { break }
        }

        return chosen
    }

    var liveNowArticles: [Article] {
        let cutoff = Date().addingTimeInterval(-6 * 60 * 60)
        let source = allArticles
        let fresh = source.filter { ($0.publishedAt ?? .distantPast) >= cutoff }
        return Array(fresh.prefix(8))
    }

    var searchFallbackAnswer: String? {
        guard case .aiFallback(_, let answer) = searchResult else { return nil }
        return answer
    }

    var searchFallbackQuery: String? {
        guard case .aiFallback(let query, _) = searchResult else { return nil }
        return query
    }

    var searchMatchedArticles: [Article] {
        guard case .articles(let articles) = searchResult else { return [] }
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : articles
    }

    var hasCryptoSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !cryptoSearchSnapshots.isEmpty
    }

    func load(session: UserSession?, force: Bool = false, desiredCount: Int = 20) async {
        activeDayWindow = DayWindow.current()

        if session == nil {
            savedIDs = []
        }

        if !force,
           !allArticles.isEmpty,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < autoRefreshInterval {
            return
        }

        if isLoading {
            guard force else { return }
            while isLoading {
                await Task.yield()
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let previousIDs = Set(allArticles.map(\.id))
            let articles = try await newsService.fetchArticles(
                forceRefresh: force,
                desiredCount: desiredCount,
                excludingIDs: force ? previousIDs : []
            )

            if force, !previousIDs.isEmpty {
                let incomingIDs = Set(articles.map(\.id))
                let retained = allArticles.filter { !incomingIDs.contains($0.id) }
                allArticles = Array((articles + retained).prefix(desiredCount))
            } else {
                allArticles = articles
            }

            featuredArticles = Array(applyCategoryFilter(allArticles).prefix(3))
            lastUpdatedAt = .now
            WidgetSnapshotStore.saveNews(allArticles)
            if marketSnapshots.isEmpty {
                marketSnapshots = MarketSnapshot.placeholders
                WidgetSnapshotStore.saveMarket(marketSnapshots)
            }
            Task {
                await loadMarketSnapshotsIfNeeded()
                await loadCryptoSnapshotsIfNeeded()
                await loadCryptoStatsIfNeeded()
                await loadTrendingCryptoSnapshotsIfNeeded()
                await loadCryptoMoversIfNeeded()
            }
            await loadSavedIDsIfNeeded(session: session)
            errorMessage = nil
            await refreshSearchResults()
        } catch {
            if isCancellation(error) {
                errorMessage = nil
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    func handleSearchTextChange() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            // Debounce typing to avoid kicking off expensive ranking / remote search on every keystroke.
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await refreshSearchResults()
        }
    }

    func toggleCategory(_ category: NewsCategory) {
        if activeCategories.contains(category) {
            activeCategories.remove(category)
        } else {
            activeCategories.insert(category)
        }

        let filteredArticles = applyCategoryFilter(allArticles)
        featuredArticles = Array(filteredArticles.prefix(3))
        handleSearchTextChange()

        if filteredArticles.isEmpty, activeCategories.count == 1, activeCategories.contains(category) {
            Task {
                await loadCategoryFallback(category)
            }
        }
    }

    func toggleSave(article: Article, session: UserSession?) async {
        guard let session else { return }
        do {
            if savedIDs.contains(article.id) {
                try await savedService.delete(article: article, session: session)
                savedIDs.remove(article.id)
            } else {
                try await savedService.save(article: article, session: session)
                savedIDs.insert(article.id)
            }
            NotificationCenter.default.post(name: AppNotifications.savedArticlesDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        searchText = ""
        searchTask?.cancel()
        searchResult = .articles(applyCategoryFilter(defaultPickSource))
        cryptoSearchSnapshots = []
        cryptoSearchStatusMessage = nil
    }

    func handleHeartbeat(session: UserSession?) async {
        let currentWindow = DayWindow.current()

        if !currentWindow.isSameDay(as: activeDayWindow) {
            activeDayWindow = currentWindow
            allArticles = []
            featuredArticles = []
            searchResult = .articles([])
            lastUpdatedAt = nil
            errorMessage = nil
            await load(session: session, force: true, desiredCount: desiredFeedCount)
            return
        }

        guard !isLoading else { return }

        if shouldAutoRefresh(now: .now) {
            await load(session: session, force: true, desiredCount: desiredFeedCount)
        }
    }

    private var defaultPickSource: [Article] {
        let base = Array(applyCategoryFilter(allArticles).dropFirst(min(3, applyCategoryFilter(allArticles).count)))
        return base.isEmpty ? applyCategoryFilter(allArticles) : base
    }

    private func refreshSearchResults() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchResult = .articles(applyCategoryFilter(defaultPickSource))
            cryptoSearchSnapshots = []
            cryptoSearchStatusMessage = nil
            return
        }

        async let articleResult = searchService.search(
            query: query,
            in: allArticles,
            preferredCategories: activeCategories
        )
        async let cryptoResult = searchCrypto(query: query)

        searchResult = await articleResult
        await cryptoResult
    }

    private func searchCrypto(query: String) async {
        guard query.count >= 2 else {
            cryptoSearchSnapshots = []
            cryptoSearchStatusMessage = nil
            return
        }

        do {
            let response = try await marketService.searchCryptoSnapshots(query: query)
            cryptoSearchSnapshots = response.snapshots
            cryptoSearchStatusMessage = response.providerStatusMessage
        } catch {
            cryptoSearchSnapshots = []
            cryptoSearchStatusMessage = error.localizedDescription
        }
    }

    private func applyCategoryFilter(_ articles: [Article]) -> [Article] {
        guard !activeCategories.isEmpty else { return articles }
        return articles.filter { !activeCategories.isDisjoint(with: Set($0.categories)) }
    }

    private func loadCategoryFallback(_ category: NewsCategory) async {
        let query = category.queryHint ?? category.displayName
        let articles = await newsService.searchArticles(
            query: query,
            preferredCategories: Set([category]),
            desiredCount: 30
        )
        guard activeCategories.contains(category), !articles.isEmpty else { return }

        allArticles = dedupeArticles(articles + allArticles)
        featuredArticles = Array(applyCategoryFilter(allArticles).prefix(3))
        lastUpdatedAt = .now
        await refreshSearchResults()
    }

    private func dedupeArticles(_ articles: [Article]) -> [Article] {
        var byID: [String: Article] = [:]

        for article in articles {
            if let existing = byID[article.id] {
                let mergedCategories = mergeCategories(existing.categories + article.categories)
                if (existing.publishedAt ?? .distantPast) < (article.publishedAt ?? .distantPast) {
                    byID[article.id] = article.withCategories(mergedCategories)
                } else {
                    byID[article.id] = existing.withCategories(mergedCategories)
                }
            } else {
                byID[article.id] = article
            }
        }

        return byID.values.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private func mergeCategories(_ categories: [NewsCategory]) -> [NewsCategory] {
        var seen = Set<NewsCategory>()
        var merged: [NewsCategory] = []

        for category in categories {
            guard !seen.contains(category) else { continue }
            seen.insert(category)
            merged.append(category)
        }

        return merged
    }

    private func briefScore(_ article: Article) -> Int {
        var score = 0
        let text = article.searchText

        let highSignalTerms = [
            "war", "attack", "strike", "ceasefire", "election", "poll", "trump", "iran",
            "israel", "gaza", "pakistan", "china", "russia", "oil", "bitcoin", "stock",
            "market", "nvidia", "openai", "fed", "inflation", "ipl", "cricket"
        ]

        score += highSignalTerms.reduce(0) { partial, term in
            partial + (text.contains(term) ? 7 : 0)
        }

        if article.categories.contains(.conflict) || article.categories.contains(.politics) || article.categories.contains(.world) {
            score += 10
        }

        if let publishedAt = article.publishedAt {
            let age = Date().timeIntervalSince(publishedAt)
            if age <= 3 * 60 * 60 {
                score += 14
            } else if age <= 12 * 60 * 60 {
                score += 8
            } else if age <= 24 * 60 * 60 {
                score += 4
            }
        }

        let summaryLength = article.plainSummary.split(separator: " ").count
        if summaryLength >= 18 {
            score += 4
        }

        return score
    }

    private func shouldAutoRefresh(now: Date) -> Bool {
        guard let lastUpdatedAt else { return true }
        return now.timeIntervalSince(lastUpdatedAt) >= autoRefreshInterval
    }

    private func loadMarketSnapshotsIfNeeded() async {
        if let marketUpdatedAt,
           !marketSnapshots.isEmpty,
           Date().timeIntervalSince(marketUpdatedAt) < autoRefreshInterval {
            return
        }

        do {
            let response = try await marketService.fetchSnapshots()
            marketSnapshots = response.snapshots
            marketStatusMessage = response.providerStatusMessage
            marketUpdatedAt = response.updatedAt ?? response.generatedAt
            WidgetSnapshotStore.saveMarket(marketSnapshots)
        } catch let error as MarketServiceError {
            if marketSnapshots.isEmpty {
                marketSnapshots = MarketSnapshot.placeholders
            }
            marketStatusMessage = error.localizedDescription
            marketUpdatedAt = nil
            WidgetSnapshotStore.saveMarket(marketSnapshots)
        } catch {
            if marketSnapshots.isEmpty {
                marketSnapshots = MarketSnapshot.placeholders
            }
            marketStatusMessage = error.localizedDescription
            marketUpdatedAt = nil
            WidgetSnapshotStore.saveMarket(marketSnapshots)
        }
    }

    private func loadCryptoSnapshotsIfNeeded() async {
        if let cryptoUpdatedAt,
           !cryptoSnapshots.isEmpty,
           Date().timeIntervalSince(cryptoUpdatedAt) < autoRefreshInterval {
            return
        }

        do {
            let response = try await marketService.fetchCryptoSnapshots()
            cryptoSnapshots = response.snapshots
            cryptoStatusMessage = response.providerStatusMessage
            cryptoUpdatedAt = response.updatedAt ?? response.generatedAt
            WidgetSnapshotStore.saveCrypto(cryptoSnapshots)
        } catch {
            cryptoStatusMessage = error.localizedDescription
            cryptoUpdatedAt = nil
            WidgetSnapshotStore.saveCrypto(cryptoSnapshots)
        }
    }

    private func loadTrendingCryptoSnapshotsIfNeeded() async {
        guard !cryptoSnapshots.isEmpty else { return }
        if let cryptoUpdatedAt,
           !trendingCryptoSnapshots.isEmpty,
           Date().timeIntervalSince(cryptoUpdatedAt) < autoRefreshInterval {
            return
        }

        do {
            let response = try await marketService.fetchTrendingCryptoSnapshots()
            trendingCryptoSnapshots = response.snapshots
            trendingCryptoStatusMessage = response.providerStatusMessage
        } catch {
            trendingCryptoStatusMessage = error.localizedDescription
        }
    }

    private func loadCryptoStatsIfNeeded() async {
        guard !cryptoSnapshots.isEmpty else { return }

        do {
            let response = try await marketService.fetchCryptoStats()
            cryptoStats = response.stats
            cryptoStatsStatusMessage = response.providerStatusMessage
        } catch {
            cryptoStatsStatusMessage = error.localizedDescription
        }
    }

    private func loadCryptoMoversIfNeeded() async {
        guard !cryptoSnapshots.isEmpty else { return }

        do {
            let response = try await marketService.fetchCryptoMovers()
            cryptoGainers = response.gainers
            cryptoLosers = response.losers
            cryptoMoversStatusMessage = response.providerStatusMessage
        } catch {
            cryptoMoversStatusMessage = error.localizedDescription
        }
    }

    private func loadSavedIDsIfNeeded(session: UserSession?) async {
        guard let session else {
            savedIDs = []
            return
        }

        do {
            let saved = try await savedService.fetchSavedArticles(session: session)
            savedIDs = Set(saved.map(\.id))
        } catch {
            // Saved state should never block or fail the main feed.
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            errorMessage = nil
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
