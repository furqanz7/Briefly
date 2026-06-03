import Foundation
import WidgetKit

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.furqan.briefly"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let fileManager = FileManager.default

    static func saveNews(_ articles: [Article]) {
        let items = articles.prefix(4).map {
            BrieflyWidgetArticle(
                id: $0.id,
                headline: $0.headline,
                source: $0.source,
                summary: $0.summaryCards.first ?? $0.plainSummary,
                category: $0.category,
                publishedAt: $0.publishedAt
            )
        }
        save(BrieflyWidgetNewsSnapshot(updatedAt: .now, articles: items), named: "news.json")
        WidgetCenter.shared.reloadTimelines(ofKind: "BrieflyNewsWidget")
    }

    static func saveMarket(_ snapshots: [MarketSnapshot]) {
        let items = snapshots.prefix(4).map {
            BrieflyWidgetMarketItem(
                id: $0.id,
                ticker: $0.ticker,
                name: $0.name,
                priceText: $0.priceText,
                changeText: $0.changeText,
                isPositive: $0.isPositive,
                updatedAt: $0.updatedAt
            )
        }
        save(BrieflyWidgetMarketSnapshot(updatedAt: .now, items: items), named: "market.json")
        WidgetCenter.shared.reloadTimelines(ofKind: "BrieflyMarketWidget")
    }

    static func saveCrypto(_ snapshots: [MarketSnapshot]) {
        let items = snapshots.prefix(4).map {
            BrieflyWidgetMarketItem(
                id: $0.id,
                ticker: $0.ticker,
                name: $0.name,
                priceText: $0.priceText,
                changeText: $0.changeText,
                isPositive: $0.isPositive,
                updatedAt: $0.updatedAt
            )
        }
        save(BrieflyWidgetMarketSnapshot(updatedAt: .now, items: items), named: "crypto.json")
        WidgetCenter.shared.reloadTimelines(ofKind: "BrieflyCryptoWidget")
    }

    static func saveSports(_ sports: [LiveSportSection]) {
        let matches = sports
            .flatMap(\.competitions)
            .flatMap(\.matches)

        let pinnedMatch = load(BrieflyWidgetMatch.self, named: "pinned-match.json")
        let match = pinnedMatch
            .flatMap { pinned in
                matches.first(where: { $0.id == pinned.id }).map(BrieflyWidgetMatch.init(match:))
            }
            ?? matches.first.map(BrieflyWidgetMatch.init(match:))

        save(BrieflyWidgetSportsSnapshot(updatedAt: .now, match: match), named: "sports.json")
        WidgetCenter.shared.reloadTimelines(ofKind: "BrieflySportsWidget")
    }

    static func pinMatch(_ match: LiveMatch) {
        let widgetMatch = BrieflyWidgetMatch(match: match)
        save(widgetMatch, named: "pinned-match.json")
        save(BrieflyWidgetSportsSnapshot(updatedAt: .now, match: widgetMatch), named: "sports.json")
        WidgetCenter.shared.reloadTimelines(ofKind: "BrieflySportsWidget")
    }

    private static func load<T: Decodable>(_ type: T.Type, named fileName: String) -> T? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: containerURL.appendingPathComponent(fileName))
            return try decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T, named fileName: String) {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }

        do {
            let data = try encoder.encode(value)
            try data.write(to: containerURL.appendingPathComponent(fileName), options: [.atomic])
        } catch {
            #if DEBUG
            print("[WidgetSnapshotStore] Failed saving \(fileName): \(error)")
            #endif
        }
    }
}

struct BrieflyWidgetArticle: Codable {
    let id: String
    let headline: String
    let source: String
    let summary: String
    let category: String
    let publishedAt: Date?
}

struct BrieflyWidgetNewsSnapshot: Codable {
    let updatedAt: Date
    let articles: [BrieflyWidgetArticle]
}

struct BrieflyWidgetMarketItem: Codable {
    let id: String
    let ticker: String
    let name: String
    let priceText: String
    let changeText: String
    let isPositive: Bool
    let updatedAt: Date?
}

struct BrieflyWidgetMarketSnapshot: Codable {
    let updatedAt: Date
    let items: [BrieflyWidgetMarketItem]
}

struct BrieflyWidgetMatch: Codable {
    let id: String
    let sportName: String
    let competitionName: String
    let status: String
    let homeName: String
    let awayName: String
    let homeScore: String?
    let awayScore: String?
    let scoreSummary: String?
    let liveBadge: String

    init(match: LiveMatch) {
        id = match.id
        sportName = match.sportName
        competitionName = match.competitionName
        status = match.status
        homeName = match.homeName
        awayName = match.awayName
        homeScore = match.homeScore
        awayScore = match.awayScore
        scoreSummary = match.scoreSummary
        liveBadge = match.liveBadgeText
    }
}

struct BrieflyWidgetSportsSnapshot: Codable {
    let updatedAt: Date
    let match: BrieflyWidgetMatch?
}
