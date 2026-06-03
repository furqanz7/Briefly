import Foundation

struct MarketSnapshot: Identifiable, Equatable, Decodable {
    let id: String
    let ticker: String
    let name: String
    let assetType: String?
    let detailID: String?
    let priceText: String
    let changeText: String
    let isPositive: Bool
    let updatedAt: Date?
    let price: Double?
    let change: Double?
    let changePercent: Double?
    let open: Double?
    let high: Double?
    let low: Double?
    let previousClose: Double?
    let volume: Double?
    let currency: String?
    let exchange: String?
    let rank: Double?
    let marketCap: Double?
    let marketCount: Double?
    let dailyVolume: Double?
    let iconURL: URL?

    init(
        id: String,
        ticker: String,
        name: String,
        assetType: String? = nil,
        detailID: String? = nil,
        priceText: String,
        changeText: String,
        isPositive: Bool,
        updatedAt: Date?,
        price: Double? = nil,
        change: Double? = nil,
        changePercent: Double? = nil,
        open: Double? = nil,
        high: Double? = nil,
        low: Double? = nil,
        previousClose: Double? = nil,
        volume: Double? = nil,
        currency: String? = nil,
        exchange: String? = nil,
        rank: Double? = nil,
        marketCap: Double? = nil,
        marketCount: Double? = nil,
        dailyVolume: Double? = nil,
        iconURL: URL? = nil
    ) {
        self.id = id
        self.ticker = ticker
        self.name = name
        self.assetType = assetType
        self.detailID = detailID
        self.priceText = priceText
        self.changeText = changeText
        self.isPositive = isPositive
        self.updatedAt = updatedAt
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.open = open
        self.high = high
        self.low = low
        self.previousClose = previousClose
        self.volume = volume
        self.currency = currency
        self.exchange = exchange
        self.rank = rank
        self.marketCap = marketCap
        self.marketCount = marketCount
        self.dailyVolume = dailyVolume
        self.iconURL = iconURL
    }

    static let placeholders: [MarketSnapshot] = [
        MarketSnapshot(id: "AAPL", ticker: "AAPL", name: "Apple", priceText: "--", changeText: "Waiting for data", isPositive: true, updatedAt: nil),
        MarketSnapshot(id: "NVDA", ticker: "NVDA", name: "Nvidia", priceText: "--", changeText: "Waiting for data", isPositive: true, updatedAt: nil),
        MarketSnapshot(id: "MSFT", ticker: "MSFT", name: "Microsoft", priceText: "--", changeText: "Waiting for data", isPositive: true, updatedAt: nil)
    ]
}

struct MarketChartPoint: Identifiable, Equatable, Decodable {
    let id: String
    let date: Date
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double
    let volume: Double?
}

struct MarketDetail: Equatable, Decodable {
    let generatedAt: Date
    let source: MarketSnapshotSource
    let provider: String
    let cacheHit: Bool
    let stale: Bool
    let updatedAt: Date?
    let expiresAt: Date?
    let message: String?
    let snapshot: MarketSnapshot
    let chart: [MarketChartPoint]
    let fundamentals: StockFundamentals?
    let news: [MarketNewsItem]?
    let technicalIndicators: [TechnicalIndicator]?
    let analystStats: AnalystStats?
}

struct StockFundamentals: Equatable, Decodable {
    let name: String?
    let description: String?
    let sector: String?
    let industry: String?
    let country: String?
    let marketCapitalization: Double?
    let peRatio: Double?
    let pegRatio: Double?
    let dividendYield: Double?
    let eps: Double?
    let beta: Double?
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?
    let profitMargin: Double?
}

struct MarketNewsItem: Identifiable, Equatable, Decodable {
    let id: String
    let title: String
    let publisher: String?
    let url: URL?
    let publishedAt: Date?
    let summary: String?
    let imageURL: URL?
}

struct TechnicalIndicator: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
    let value: Double?
    let signal: String?
    let updatedAt: Date?
}

struct AnalystStats: Equatable, Decodable {
    let recommendation: String?
    let targetMeanPrice: Double?
    let targetHighPrice: Double?
    let targetLowPrice: Double?
    let numberOfAnalystOpinions: Double?
    let revenueGrowth: Double?
    let grossMargins: Double?
    let operatingMargins: Double?
    let returnOnEquity: Double?
    let forwardPE: Double?
    let trailingPE: Double?
    let priceToBook: Double?
    let enterpriseToRevenue: Double?
    let enterpriseToEbitda: Double?
    let website: URL?
    let fullTimeEmployees: Double?
}
