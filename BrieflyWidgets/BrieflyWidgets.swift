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

private struct BrieflyWidgetJobItem: Codable {
    let id: String
    let title: String
    let company: String
    let location: String
    let workMode: String
    let matchScore: Int
}

private struct BrieflyWidgetJobsSnapshot: Codable {
    let updatedAt: Date
    let savedCount: Int
    let appliedCount: Int
    let jobs: [BrieflyWidgetJobItem]

    static let placeholder = BrieflyWidgetJobsSnapshot(
        updatedAt: .now,
        savedCount: 0,
        appliedCount: 0,
        jobs: []
    )
}

private struct BrieflyWidgetBooksSnapshot: Codable {
    let updatedAt: Date
    let todaySeconds: Int
    let weekSeconds: Int
    let monthSeconds: Int
    let overallSeconds: Int
    let dailyGoalMinutes: Int
    let hasCustomGoal: Bool
    let savedCount: Int
    let downloadedCount: Int

    static let placeholder = BrieflyWidgetBooksSnapshot(
        updatedAt: .now,
        todaySeconds: 0,
        weekSeconds: 0,
        monthSeconds: 0,
        overallSeconds: 0,
        dailyGoalMinutes: 30,
        hasCustomGoal: false,
        savedCount: 0,
        downloadedCount: 0
    )

    var todayMinutes: Int { minutes(todaySeconds) }
    var weekMinutes: Int { minutes(weekSeconds) }
    var monthMinutes: Int { minutes(monthSeconds) }
    var overallMinutes: Int { minutes(overallSeconds) }
    var goalLabel: String { hasCustomGoal ? "\(dailyGoalMinutes)m goal" : "Set goal" }
    var progress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(Double(max(todaySeconds, 0)) / Double(dailyGoalMinutes * 60), 1)
    }

    private func minutes(_ seconds: Int) -> Int {
        Int(ceil(Double(max(seconds, 0)) / 60))
    }
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
        .configurationDisplayName("Briefly")
        .description("See your latest brief from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct BrieflyMarketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyMarketWidget",
            provider: SnapshotProvider(fileName: "market.json", placeholderValue: BrieflyWidgetMarketSnapshot.placeholder(title: "Market"))
        ) { entry in
            MarketWidgetView(title: "Market", icon: "chart.line.uptrend.xyaxis", slug: "market", snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Market")
        .description("Track market movers from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct BrieflyCryptoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyCryptoWidget",
            provider: SnapshotProvider(fileName: "crypto.json", placeholderValue: BrieflyWidgetMarketSnapshot.placeholder(title: "Crypto"))
        ) { entry in
            MarketWidgetView(title: "Crypto", icon: "bitcoinsign.circle.fill", slug: "crypto", snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Crypto")
        .description("Track crypto movers from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
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
        .configurationDisplayName("Briefly Sports")
        .description("Keep a pinned live match visible on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct BrieflyJobsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyJobsWidget",
            provider: SnapshotProvider(fileName: "jobs.json", placeholderValue: BrieflyWidgetJobsSnapshot.placeholder)
        ) { entry in
            JobsWidgetView(snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Jobs")
        .description("View saved roles and application progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct BrieflyBooksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "BrieflyBooksWidget",
            provider: SnapshotProvider(fileName: "books.json", placeholderValue: BrieflyWidgetBooksSnapshot.placeholder)
        ) { entry in
            BooksWidgetView(snapshot: entry.value)
        }
        .configurationDisplayName("Briefly Books")
        .description("Track reading time, goal progress, and your library.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private enum WidgetPalette {
    static let background = Color(red: 0.018, green: 0.020, blue: 0.034)
    static let surface = Color.white.opacity(0.070)
    static let surfaceStrong = Color.white.opacity(0.105)
    static let divider = Color.white.opacity(0.105)
    static let primary = Color(red: 0.965, green: 0.960, blue: 1.000)
    static let secondary = Color(red: 0.680, green: 0.650, blue: 0.760)
    static let muted = Color(red: 0.465, green: 0.450, blue: 0.545)
    static let accent = Color(red: 0.510, green: 0.245, blue: 1.000)
    static let blue = Color(red: 0.195, green: 0.515, blue: 1.000)
    static let green = Color(red: 0.225, green: 0.875, blue: 0.410)
    static let red = Color(red: 1.000, green: 0.300, blue: 0.410)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct WidgetBackdrop: View {
    var body: some View {
        ZStack {
            WidgetPalette.background
            LinearGradient(
                colors: [
                    Color(red: 0.120, green: 0.070, blue: 0.230).opacity(0.82),
                    Color(red: 0.028, green: 0.036, blue: 0.070).opacity(0.95),
                    Color(red: 0.020, green: 0.065, blue: 0.125).opacity(0.72)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
}

private struct WidgetShell<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let subtitle: String
    let icon: String
    let slug: String
    let updatedAt: Date
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 11) {
            header
            content
        }
        .padding(shellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            WidgetBackdrop()
        }
        .widgetURL(URL(string: "briefly://widget/\(slug)"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(WidgetPalette.surfaceStrong)
                Image(systemName: icon)
                    .font(.system(size: family == .systemSmall ? 12 : 13, weight: .black))
                    .foregroundStyle(WidgetPalette.accentGradient)
            }
            .frame(width: family == .systemSmall ? 24 : 28, height: family == .systemSmall ? 24 : 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if family != .systemSmall {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if family != .systemSmall {
                Text(updatedAt, style: .relative)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var shellPadding: EdgeInsets {
        switch family {
        case .systemSmall:
            EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        case .systemLarge:
            EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        default:
            EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        }
    }
}

private struct NewsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BrieflyWidgetNewsSnapshot

    private var articles: [BrieflyWidgetArticle] {
        snapshot.articles.isEmpty ? BrieflyWidgetNewsSnapshot.placeholder.articles : snapshot.articles
    }

    var body: some View {
        WidgetShell(
            title: "Briefly",
            subtitle: "Your smart brief",
            icon: "sparkles",
            slug: "home",
            updatedAt: snapshot.updatedAt
        ) {
            switch family {
            case .systemSmall:
                small
            case .systemLarge:
                large
            default:
                medium
            }
        }
    }

    private var small: some View {
        let article = articles[0]
        return VStack(alignment: .leading, spacing: 8) {
            BrieflyTag(text: article.category, tint: WidgetPalette.accent)

            Text(article.headline)
                .font(.headline.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.74)

            Spacer(minLength: 0)

            WidgetFooter(text: article.source, icon: "newspaper.fill")
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 9) {
            FeaturedHeadline(article: articles[0], lineLimit: 2)

            WidgetDivider()

            ForEach(articles.dropFirst().prefix(2), id: \.id) { article in
                NewsMiniRow(article: article)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 11) {
            FeaturedHeadline(article: articles[0], lineLimit: 3, showSummary: true)

            WidgetDivider()

            ForEach(articles.dropFirst().prefix(4), id: \.id) { article in
                NewsMiniRow(article: article)
            }
        }
    }
}

private struct MarketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let icon: String
    let slug: String
    let snapshot: BrieflyWidgetMarketSnapshot

    private var items: [BrieflyWidgetMarketItem] {
        snapshot.items.isEmpty ? BrieflyWidgetMarketSnapshot.placeholder(title: title).items : snapshot.items
    }

    var body: some View {
        WidgetShell(
            title: title,
            subtitle: title == "Crypto" ? "Digital assets" : "Live movers",
            icon: icon,
            slug: slug,
            updatedAt: snapshot.updatedAt
        ) {
            if family == .systemSmall {
                marketSmall(items[0])
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items.prefix(4), id: \.id) { item in
                        MarketRow(item: item)
                    }
                }
            }
        }
    }

    private func marketSmall(_ item: BrieflyWidgetMarketItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            Text(item.ticker)
                .font(.title3.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(item.priceText)
                .font(.title2.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            BrieflyTag(text: item.changeText, tint: item.isPositive ? WidgetPalette.green : WidgetPalette.red)
        }
    }
}

private struct SportsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BrieflyWidgetSportsSnapshot

    var body: some View {
        WidgetShell(
            title: "Sports",
            subtitle: "Pinned match",
            icon: "sportscourt.fill",
            slug: "sports",
            updatedAt: snapshot.updatedAt
        ) {
            if let match = snapshot.match {
                if family == .systemSmall {
                    SportsSmall(match: match)
                } else {
                    SportsMedium(match: match)
                }
            } else {
                EmptyWidgetState(
                    icon: "pin.fill",
                    title: "Pin a match",
                    message: "Open Sports and pin a live match for this widget."
                )
            }
        }
    }
}

private struct JobsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BrieflyWidgetJobsSnapshot

    private var jobs: [BrieflyWidgetJobItem] {
        snapshot.jobs
    }

    var body: some View {
        WidgetShell(
            title: "Jobs",
            subtitle: "Saved and applied",
            icon: "briefcase.fill",
            slug: "jobs",
            updatedAt: snapshot.updatedAt
        ) {
            if jobs.isEmpty {
                EmptyWidgetState(
                    icon: "bookmark.fill",
                    title: "Save roles",
                    message: "Saved and applied jobs will appear here."
                )
            } else if family == .systemSmall {
                jobsSmall
            } else {
                jobsMedium
            }
        }
    }

    private var jobsSmall: some View {
        let job = jobs[0]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                StatPill(value: "\(snapshot.savedCount)", label: "saved", icon: "bookmark.fill", tint: WidgetPalette.accent)
                StatPill(value: "\(snapshot.appliedCount)", label: "applied", icon: "checkmark.seal.fill", tint: WidgetPalette.green)
            }

            Spacer(minLength: 0)

            Text(job.title)
                .font(.headline.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(job.company)
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)

            WidgetFooter(text: "\(job.workMode) - \(job.location)", icon: "mappin.and.ellipse")
        }
    }

    private var jobsMedium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MetricTile(title: "Saved", value: "\(snapshot.savedCount)", icon: "bookmark.fill", tint: WidgetPalette.accent)
                MetricTile(title: "Applied", value: "\(snapshot.appliedCount)", icon: "checkmark.seal.fill", tint: WidgetPalette.green)
            }

            ForEach(jobs.prefix(2), id: \.id) { job in
                JobRow(job: job)
            }
        }
    }
}

private struct BooksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: BrieflyWidgetBooksSnapshot

    var body: some View {
        WidgetShell(
            title: "Books",
            subtitle: "Reading progress",
            icon: "books.vertical.fill",
            slug: "books",
            updatedAt: snapshot.updatedAt
        ) {
            switch family {
            case .systemSmall:
                booksSmall
            case .systemLarge:
                booksLarge
            default:
                booksMedium
            }
        }
    }

    private var booksSmall: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.todayMinutes)")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("m")
                    .font(.title3.weight(.black))
                    .foregroundStyle(WidgetPalette.secondary)
            }

            Text(snapshot.hasCustomGoal ? "of \(snapshot.dailyGoalMinutes)m goal" : "Tap to set a goal")
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ProgressCapsule(value: snapshot.progress)

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                StatPill(value: "\(snapshot.savedCount)", label: "saved", icon: "bookmark.fill", tint: WidgetPalette.accent)
                StatPill(value: "\(snapshot.downloadedCount)", label: "kept", icon: "arrow.down.circle.fill", tint: WidgetPalette.blue)
            }
        }
    }

    private var booksMedium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily reading")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetPalette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(snapshot.todayMinutes)")
                            .font(.title.weight(.black))
                            .foregroundStyle(WidgetPalette.primary)
                            .lineLimit(1)
                        Text("min")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }

                Spacer(minLength: 8)

                BrieflyTag(text: snapshot.goalLabel, tint: WidgetPalette.accent)
            }

            ProgressCapsule(value: snapshot.progress)

            HStack(spacing: 8) {
                MetricTile(title: "Week", value: "\(snapshot.weekMinutes)m", icon: "calendar", tint: WidgetPalette.blue)
                MetricTile(title: "Saved", value: "\(snapshot.savedCount)", icon: "bookmark.fill", tint: WidgetPalette.accent)
                MetricTile(title: "Kept", value: "\(snapshot.downloadedCount)", icon: "arrow.down.circle.fill", tint: WidgetPalette.green)
            }
        }
    }

    private var booksLarge: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetPalette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(snapshot.todayMinutes)")
                            .font(.system(size: 46, weight: .black))
                            .foregroundStyle(WidgetPalette.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("min")
                            .font(.title3.weight(.black))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(snapshot.progress * 100))%")
                        .font(.title3.weight(.black))
                        .foregroundStyle(WidgetPalette.green)
                    Text(snapshot.goalLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            }

            ProgressCapsule(value: snapshot.progress)

            HStack(spacing: 8) {
                MetricTile(title: "Week", value: "\(snapshot.weekMinutes)m", icon: "calendar", tint: WidgetPalette.blue)
                MetricTile(title: "Month", value: "\(snapshot.monthMinutes)m", icon: "calendar.circle.fill", tint: WidgetPalette.accent)
            }

            HStack(spacing: 8) {
                MetricTile(title: "Overall", value: "\(snapshot.overallMinutes)m", icon: "clock.fill", tint: WidgetPalette.green)
                MetricTile(title: "Saved", value: "\(snapshot.savedCount)", icon: "bookmark.fill", tint: WidgetPalette.accent)
                MetricTile(title: "Kept", value: "\(snapshot.downloadedCount)", icon: "arrow.down.circle.fill", tint: WidgetPalette.blue)
            }
        }
    }
}

private struct FeaturedHeadline: View {
    let article: BrieflyWidgetArticle
    let lineLimit: Int
    var showSummary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                BrieflyTag(text: article.category, tint: WidgetPalette.accent)
                Spacer(minLength: 0)
                Text(article.source)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
            }

            Text(article.headline)
                .font(.headline.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.74)

            if showSummary {
                Text(article.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(3)
            }
        }
    }
}

private struct NewsMiniRow: View {
    let article: BrieflyWidgetArticle

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(WidgetPalette.accentGradient)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.headline)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(article.source)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
            }
        }
    }
}

private struct MarketRow: View {
    let item: BrieflyWidgetMarketItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.ticker)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(item.name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.priceText)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                Text(item.changeText)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(item.isPositive ? WidgetPalette.green : WidgetPalette.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WidgetPalette.divider, lineWidth: 1)
        }
    }
}

private struct SportsSmall: View {
    let match: BrieflyWidgetMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BrieflyTag(text: match.liveBadge, tint: WidgetPalette.green)

            Text(match.competitionName)
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)

            Text(match.displayScore)
                .font(.title.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text("\(match.homeName) vs \(match.awayName)")
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct SportsMedium: View {
    let match: BrieflyWidgetMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                BrieflyTag(text: match.liveBadge, tint: WidgetPalette.green)
                Text(match.competitionName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                TeamScore(name: match.homeName, score: match.homeScore)
                Text(match.displayScore)
                    .font(.title2.weight(.black))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                TeamScore(name: match.awayName, score: match.awayScore)
            }

            WidgetFooter(text: match.sportName, icon: "sportscourt.fill")
        }
    }
}

private struct TeamScore: View {
    let name: String
    let score: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(score ?? "--")
                .font(.headline.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)

            Text(name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct JobRow: View {
    let job: BrieflyWidgetJobItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(WidgetPalette.accentGradient)
                Text(initials)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.title)
                    .font(.caption.weight(.black))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("\(job.company) - \(job.workMode)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            MatchPill(score: job.matchScore)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WidgetPalette.divider, lineWidth: 1)
        }
    }

    private var initials: String {
        let parts = job.company
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "B" : value
    }
}

private struct MatchPill: View {
    let score: Int

    var body: some View {
        Text("\(score)%")
            .font(.caption.weight(.black))
            .foregroundStyle(WidgetPalette.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(WidgetPalette.green.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(WidgetPalette.green.opacity(0.34), lineWidth: 1)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.subheadline.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(WidgetPalette.divider, lineWidth: 1)
        }
    }
}

private struct StatPill: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
            Text(value)
                .font(.caption.weight(.black))
            Text(label)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.13), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.30), lineWidth: 1)
        }
    }
}

private struct BrieflyTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.30), lineWidth: 1)
            }
    }
}

private struct ProgressCapsule: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.22))

                Capsule()
                    .fill(WidgetPalette.accentGradient)
                    .frame(width: max(4, proxy.size.width * max(0, min(value, 1))))
            }
        }
        .frame(height: 8)
    }
}

private struct WidgetFooter: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(WidgetPalette.secondary)
    }
}

private struct WidgetDivider: View {
    var body: some View {
        Rectangle()
            .fill(WidgetPalette.divider)
            .frame(height: 1)
    }
}

private struct EmptyWidgetState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.title3.weight(.black))
                .foregroundStyle(WidgetPalette.accentGradient)

            Text(title)
                .font(.headline.weight(.black))
                .foregroundStyle(WidgetPalette.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(3)
        }
    }
}
