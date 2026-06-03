import Foundation

struct CombinedNewsService {
    let providers: [NewsProvider]

    func fetchFeed(
        categories: [NewsCategory],
        desiredCount: Int,
        forceRefresh: Bool,
        excludingIDs: Set<String> = []
    ) async throws -> [Article] {
        guard !providers.isEmpty else { return [] }

        let requestGroups = max(categories.count * providers.count, 1)
        let pageSize = max(4, Int(ceil(Double(desiredCount) / Double(requestGroups))) + 2)
        let batches = await withTaskGroup(of: ProviderFetchResult.self) { group in
            for category in categories {
                for provider in providers {
                    let providerName = provider.diagnosticsName
                    group.addTask {
                        do {
                            let articles = try await fetchArticles(
                                provider: provider,
                                category: category,
                                pageSize: pageSize,
                                forceRefresh: forceRefresh,
                                excludingIDs: excludingIDs
                            )
                            return ProviderFetchResult(
                                providerName: providerName,
                                category: category,
                                articles: articles,
                                errorDescription: nil
                            )
                        } catch {
                            return ProviderFetchResult(
                                providerName: providerName,
                                category: category,
                                articles: [],
                                errorDescription: String(describing: error)
                            )
                        }
                    }
                }
            }

            var results: [ProviderFetchResult] = []
            for await result in group {
                results.append(result)
            }

            logProviderDiagnostics(results)
            return results.map(\.articles)
        }
        .flatMap { $0 }

        let deduped = dedupe(articles: batches)
        let sorted = balanceSources(rankTodayFirst(articles: deduped), desiredCount: desiredCount)
        logFinalSourceDistribution(sorted, desiredCount: desiredCount)

        if !excludingIDs.isEmpty {
            let unseen = sorted.filter { !excludingIDs.contains($0.id) }
            if !unseen.isEmpty {
                return Array(unseen.prefix(desiredCount))
            }
        }

        return Array(sorted.prefix(desiredCount))
    }

    private struct ProviderFetchResult {
        let providerName: String
        let category: NewsCategory
        let articles: [Article]
        let errorDescription: String?
    }

    private func fetchArticles(
        provider: NewsProvider,
        category: NewsCategory,
        pageSize: Int,
        forceRefresh: Bool,
        excludingIDs: Set<String>
    ) async throws -> [Article] {
        var collected: [Article] = []
        var pageToken: String?
        let maxPages = excludingIDs.isEmpty ? 1 : 2

        for _ in 0..<maxPages {
            let batch = try await provider.fetch(
                category: category,
                pageToken: pageToken,
                pageSize: pageSize,
                forceRefresh: forceRefresh
            )
            collected.append(contentsOf: batch.articles)
            pageToken = batch.nextPageToken
            if pageToken == nil || collected.count >= pageSize * maxPages {
                break
            }
        }

        return collected
    }

    private func dedupe(articles: [Article]) -> [Article] {
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
        return Array(byID.values)
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

    private func rankTodayFirst(articles: [Article]) -> [Article] {
        let today = DayWindow.current()

        return articles.sorted { lhs, rhs in
            let lhsDate = lhs.publishedAt ?? .distantPast
            let rhsDate = rhs.publishedAt ?? .distantPast
            let lhsIsToday = today.contains(lhsDate)
            let rhsIsToday = today.contains(rhsDate)

            if lhsIsToday != rhsIsToday {
                return lhsIsToday && !rhsIsToday
            }

            return lhsDate > rhsDate
        }
    }

    private func balanceSources(_ articles: [Article], desiredCount: Int) -> [Article] {
        guard desiredCount > 0, articles.count > 1 else { return articles }

        var buckets = Dictionary(grouping: articles, by: \.source)
            .mapValues { sourceArticles in
                sourceArticles.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            }
        var sourceOrder = buckets.keys.sorted {
            let lhsDate = buckets[$0]?.first?.publishedAt ?? .distantPast
            let rhsDate = buckets[$1]?.first?.publishedAt ?? .distantPast
            return lhsDate > rhsDate
        }

        guard sourceOrder.count > 1 else { return articles }

        var balanced: [Article] = []

        while !sourceOrder.isEmpty, balanced.count < articles.count {
            var exhaustedSources: [String] = []

            for source in sourceOrder {
                guard var sourceArticles = buckets[source], !sourceArticles.isEmpty else {
                    exhaustedSources.append(source)
                    continue
                }

                balanced.append(sourceArticles.removeFirst())
                buckets[source] = sourceArticles

                if sourceArticles.isEmpty {
                    exhaustedSources.append(source)
                }
            }

            if !exhaustedSources.isEmpty {
                let exhausted = Set(exhaustedSources)
                sourceOrder.removeAll { exhausted.contains($0) }
            }
        }

        return balanced
    }

    private func logProviderDiagnostics(_ results: [ProviderFetchResult]) {
        #if DEBUG
        let sortedResults = results.sorted {
            if $0.providerName == $1.providerName {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.providerName < $1.providerName
        }

        print("Briefly News Diagnostics: provider fetch results")
        for result in sortedResults {
            if let errorDescription = result.errorDescription {
                print("  \(result.providerName) / \(result.category.displayName): 0 articles, error: \(errorDescription)")
            } else {
                print("  \(result.providerName) / \(result.category.displayName): \(result.articles.count) articles")
            }
        }
        #endif
    }

    private func logFinalSourceDistribution(_ articles: [Article], desiredCount: Int) {
        #if DEBUG
        let visibleArticles = Array(articles.prefix(desiredCount))
        let counts = Dictionary(grouping: visibleArticles, by: \.source)
            .mapValues(\.count)
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }

        print("Briefly News Diagnostics: final visible source distribution")
        for (source, count) in counts {
            print("  \(source): \(count)")
        }
        #endif
    }
}
