import Charts
import SwiftUI

struct MarketDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: MarketSnapshot

    @State private var detail: MarketDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let service = MarketService()

    private var resolvedSnapshot: MarketSnapshot {
        detail?.snapshot ?? snapshot
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrieflyTheme.background(colorScheme)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        chartSection
                        statsSection
                        fundamentalsSection
                        analystStatsSection
                        technicalIndicatorsSection
                        newsSection
                        marketExtrasFallbackSection
                        providerSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                        .frame(width: 34, height: 34)
                        .background(BrieflyTheme.card(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(resolvedSnapshot.ticker)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text(resolvedSnapshot.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(resolvedSnapshot.priceText)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text(resolvedSnapshot.changeText)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(resolvedSnapshot.isPositive ? Color.green : Color.red)
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("30-Day Close")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
            } else if let detail, !detail.chart.isEmpty {
                Chart(detail.chart) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Close", point.close)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(resolvedSnapshot.isPositive ? Color.green : BrieflyTheme.accent)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Close", point.close)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle((resolvedSnapshot.isPositive ? Color.green : BrieflyTheme.accent).opacity(0.16))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .frame(height: 210)
            } else {
                Text(isLoading ? "Loading chart" : "No chart points available")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
            }
        }
        .padding(18)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statsSection: some View {
        let quote = resolvedSnapshot
        let rows: [(String, String)] = quote.assetType == "crypto"
            ? [
                ("Rank", quote.rank.map { "#\(Int($0))" } ?? "--"),
                ("Market Cap", currency(quote.marketCap)),
                ("24h Volume", currency(quote.dailyVolume)),
                ("Markets", compactNumber(quote.marketCount)),
                ("Change", quote.changeText),
                ("Source", quote.exchange ?? "--")
            ]
            : [
                ("Open", currency(quote.open)),
                ("High", currency(quote.high)),
                ("Low", currency(quote.low)),
                ("Previous Close", currency(quote.previousClose)),
                ("Volume", compactNumber(quote.volume)),
                ("Exchange", quote.exchange ?? "--"),
                ("Currency", quote.currency ?? "USD")
            ]

        return VStack(alignment: .leading, spacing: 14) {
            Text("Quote Details")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.55))

                        Text(row.1)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(BrieflyTheme.elevatedCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let provider = detail?.provider {
                Text("Source: \(provider)")
            }

            if let updatedAt = detail?.updatedAt ?? resolvedSnapshot.updatedAt {
                Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }

            if let message = detail?.message {
                Text(message)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.6))
    }

    private var fundamentalsSection: some View {
        Group {
            if resolvedSnapshot.assetType != "crypto",
               let fundamentals = detail?.fundamentals {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Company")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    if let description = fundamentals.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13, weight: .medium))
                            .lineSpacing(3)
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.68))
                            .lineLimit(5)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(fundamentalRows(fundamentals), id: \.0) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.0)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.55))

                                Text(row.1)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(BrieflyTheme.elevatedCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var newsSection: some View {
        Group {
            if resolvedSnapshot.assetType != "crypto",
               let news = detail?.news,
               !news.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Market News")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    VStack(spacing: 10) {
                        ForEach(news) { item in
                            if let url = item.url {
                                Link(destination: url) {
                                    newsCard(item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                newsCard(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func newsCard(_ item: MarketNewsItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .lineLimit(3)

            HStack(spacing: 6) {
                if let publisher = item.publisher, !publisher.isEmpty {
                    Text(publisher)
                }

                if let publishedAt = item.publishedAt {
                    Text(publishedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.54))

            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.66))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var technicalIndicatorsSection: some View {
        Group {
            if resolvedSnapshot.assetType != "crypto",
               let indicators = detail?.technicalIndicators,
               !indicators.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Technical Indicators")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(indicators) { indicator in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(indicator.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.55))

                                Text(ratio(indicator.value))
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                                if let signal = indicator.signal, !signal.isEmpty {
                                    Text(signal)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(indicatorSignalColor(signal))
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(BrieflyTheme.elevatedCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var analystStatsSection: some View {
        Group {
            if resolvedSnapshot.assetType != "crypto",
               let stats = detail?.analystStats {
                let rows = analystRows(stats)
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Analyst & Key Stats")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(rows, id: \.0) { row in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.0)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.55))

                                    Text(row.1)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(BrieflyTheme.elevatedCard)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        if let website = stats.website {
                            Link(destination: website) {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(website.host() ?? website.absoluteString)
                                        .font(.system(size: 13, weight: .bold))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(BrieflyTheme.accent)
                                .padding(14)
                                .background(BrieflyTheme.elevatedCard)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var marketExtrasFallbackSection: some View {
        Group {
            if resolvedSnapshot.assetType != "crypto",
               !isLoading,
               errorMessage == nil,
               detail != nil,
               detail?.analystStats == nil,
               detail?.technicalIndicators?.isEmpty != false,
               detail?.news?.isEmpty != false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Market Extras")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    Text("Analyst stats, technical indicators, and market news are temporarily unavailable. The quote and chart can still use cached market data.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(BrieflyTheme.card(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            detail = try await service.fetchDetail(for: snapshot)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currency(_ value: Double?) -> String {
        guard let value else { return "--" }
        return MarketDetailFormatters.currency.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func compactNumber(_ value: Double?) -> String {
        guard let value else { return "--" }
        let absValue = abs(value)
        if absValue >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func fundamentalRows(_ fundamentals: StockFundamentals) -> [(String, String)] {
        [
            ("Sector", fundamentals.sector ?? "--"),
            ("Industry", fundamentals.industry ?? "--"),
            ("Market Cap", currency(fundamentals.marketCapitalization)),
            ("P/E", ratio(fundamentals.peRatio)),
            ("EPS", ratio(fundamentals.eps)),
            ("Dividend", percent(fundamentals.dividendYield)),
            ("52W High", currency(fundamentals.fiftyTwoWeekHigh)),
            ("52W Low", currency(fundamentals.fiftyTwoWeekLow)),
        ]
    }

    private func analystRows(_ stats: AnalystStats) -> [(String, String)] {
        [
            ("Recommendation", stats.recommendation?.capitalized ?? "--"),
            ("Target Mean", currency(stats.targetMeanPrice)),
            ("Target High", currency(stats.targetHighPrice)),
            ("Target Low", currency(stats.targetLowPrice)),
            ("Analysts", compactNumber(stats.numberOfAnalystOpinions)),
            ("Revenue Growth", percent(stats.revenueGrowth)),
            ("Gross Margin", percent(stats.grossMargins)),
            ("Operating Margin", percent(stats.operatingMargins)),
            ("Return on Equity", percent(stats.returnOnEquity)),
            ("Forward P/E", ratio(stats.forwardPE)),
            ("Trailing P/E", ratio(stats.trailingPE)),
            ("Price/Book", ratio(stats.priceToBook)),
            ("EV/Revenue", ratio(stats.enterpriseToRevenue)),
            ("EV/EBITDA", ratio(stats.enterpriseToEbitda)),
            ("Employees", compactNumber(stats.fullTimeEmployees)),
        ].filter { $0.1 != "--" }
    }

    private func ratio(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.2f%%", value * 100)
    }

    private func indicatorSignalColor(_ signal: String) -> Color {
        let lowercased = signal.lowercased()
        if lowercased.contains("above") || lowercased.contains("oversold") {
            return .green
        }
        if lowercased.contains("below") || lowercased.contains("overbought") {
            return .red
        }
        return BrieflyTheme.text(colorScheme).opacity(0.58)
    }
}

private enum MarketDetailFormatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
