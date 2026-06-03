import SwiftUI
import WidgetKit

private enum BrieflyWidgetStore {
    static let appGroupID = "group.com.furqan.briefly"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load<T: Decodable>(_ type: T.Type, fileName: String) -> T? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: containerURL.appendingPathComponent(fileName))
            return try decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }
}

private struct BrieflyWidgetArticle: Codable {
    let id: String
    let headline: String
    let source: String
    let summary: String
    let category: String
    let publishedAt: Date?
}

private struct BrieflyWidgetNewsSnapshot: Codable {
    let updatedAt: Date
    let articles: [BrieflyWidgetArticle]

    static let placeholder = BrieflyWidgetNewsSnapshot(
        updatedAt: .now,
        articles: [
            BrieflyWidgetArticle(
                id: "placeholder-news",
                headline: "Open Briefly to load your latest smart brief",
                source: "Briefly",
                summary: "Top headlines and short readable summaries will appear here after the app refreshes.",
                category: "News",
                publishedAt: nil
            )
        ]
    )
}

private struct BrieflyWidgetMarketItem: Codable {
    let id: String
    let ticker: String
    let name: String
    let priceText: String
    let changeText: String
    let isPositive: Bool
    let updatedAt: Date?
}

private struct BrieflyWidgetMarketSnapshot: Codable {
    let updatedAt: Date
    let items: [BrieflyWidgetMarketItem]

    static func placeholder(title: String) -> BrieflyWidgetMarketSnapshot {
        BrieflyWidgetMarketSnapshot(
            updatedAt: .now,
            items: [
                BrieflyWidgetMarketItem(
                    id: title,
                    ticker: title,
                    name: "Open Briefly",
                    priceText: "--",
                    changeText: "Waiting for data",
                    isPositive: true,
                    updatedAt: nil
                )
            ]
        )
    }
}

private struct BrieflyWidgetMatch: Codable {
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

    var displayScore: String {
        if let homeScore, let awayScore {
            return "\(homeScore) - \(awayScore)"
        }
        return scoreSummary ?? "Live"
    }
}

private struct BrieflyWidgetSportsSnapshot: Codable {
    let updatedAt: Date
    let match: BrieflyWidgetMatch?

    static let placeholder = BrieflyWidgetSportsSnapshot(updatedAt: .now, match: nil)
}

private struct TimelineEntryValue<Value>: TimelineEntry {
    let date: Date
    let value: Value
}

private struct SnapshotProvider<Value: Decodable>: TimelineProvider {
    let fileName: String
    let placeholderValue: Value

    func placeholder(in context: Context) -> TimelineEntryValue<Value> {
        TimelineEntryValue(date: .now, value: placeholderValue)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimelineEntryValue<Value>) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimelineEntryValue<Value>>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> TimelineEntryValue<Value> {
        TimelineEntryValue(
            date: .now,
            value: BrieflyWidgetStore.load(Value.self, fileName: fileName) ?? placeholderValue
        )
    }
}

struct BrieflyNewsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyNewsWidget",
            provider: SnapshotProvider(fileName: "news.json", placeholderValue: BrieflyWidgetNewsSnapshot.placeholder)
        ) { entry in
            NewsWidgetView(snapshot: entry.value)
        }
        .configurationDisplayName("Briefly News")
        .description("Read top headlines and short summaries from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct BrieflyMarketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyMarketWidget",
            provider: SnapshotProvider(fileName: "market.json", placeholderValue: BrieflyWidgetMarketSnapshot.placeholder(title: "Market"))
        ) { entry in
            MarketWidgetView(title: "Market", icon: "chart.line.uptrend.xyaxis", snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Market")
        .description("See stock and index moves without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BrieflyCryptoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyCryptoWidget",
            provider: SnapshotProvider(fileName: "crypto.json", placeholderValue: BrieflyWidgetMarketSnapshot.placeholder(title: "Crypto"))
        ) { entry in
            MarketWidgetView(title: "Crypto", icon: "bitcoinsign.circle.fill", snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Crypto")
        .description("Track crypto prices and movers from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BrieflySportsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflySportsWidget",
            provider: SnapshotProvider(fileName: "sports.json", placeholderValue: BrieflyWidgetSportsSnapshot.placeholder)
        ) { entry in
            SportsWidgetView(snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Live Match")
        .description("Keep the latest live match visible on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WidgetShell<Content: View>: View {
    let title: String
    let icon: String
    let updatedAt: Date
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text(updatedAt, style: .relative)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            content
        }
        .padding(14)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.13), Color(red: 0.13, green: 0.08, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "briefly://widget/\(title.lowercased())"))
    }
}

private struct NewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BrieflyWidgetNewsSnapshot

    var body: some View {
        WidgetShell(title: "News", icon: "newspaper.fill", updatedAt: snapshot.updatedAt) {
            if family == .systemSmall {
                let article = snapshot.articles.first ?? BrieflyWidgetNewsSnapshot.placeholder.articles[0]
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.headline)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                    Text(article.source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.articles.prefix(family == .systemLarge ? 4 : 2), id: \.id) { article in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.headline)
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(article.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(family == .systemLarge ? 2 : 1)
                        }
                    }
                }
            }
        }
    }
}

private struct MarketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let icon: String
    let snapshot: BrieflyWidgetMarketSnapshot

    var body: some View {
        WidgetShell(title: title, icon: icon, updatedAt: snapshot.updatedAt) {
            let items = Array(snapshot.items.prefix(family == .systemSmall ? 1 : 3))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.id) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.ticker)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.purple)
                                .lineLimit(1)
                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.priceText)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(item.changeText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(item.isPositive ? .green : .red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }
}

private struct SportsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BrieflyWidgetSportsSnapshot

    var body: some View {
        WidgetShell(title: "Sports", icon: "sportscourt.fill", updatedAt: snapshot.updatedAt) {
            if let match = snapshot.match {
                VStack(alignment: .leading, spacing: 10) {
                    Text(match.competitionName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        team(match.homeName, score: match.homeScore)
                        Text(match.displayScore)
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        team(match.awayName, score: match.awayScore)
                    }

                    HStack {
                        Text(match.liveBadge)
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                        Spacer(minLength: 0)
                        Text(match.sportName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No live match yet")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                    Text("Open Sports and refresh live scores to pin the latest match here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? 3 : 2)
                }
            }
        }
    }

    private func team(_ name: String, score: String?) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(score ?? "--")
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}
