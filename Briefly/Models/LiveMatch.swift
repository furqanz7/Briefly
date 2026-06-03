import Foundation

struct LiveScoresResponse: Decodable {
    let generatedAt: Date
    let cacheHit: Bool
    let providerConfigured: Bool
    let message: String?
    let sports: [LiveSportSection]
    let upcomingSports: [LiveSportSection]
    let recentSports: [LiveSportSection]

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case cacheHit
        case providerConfigured
        case message
        case sports
        case upcomingSports
        case recentSports
    }

    init(
        generatedAt: Date,
        cacheHit: Bool,
        providerConfigured: Bool,
        message: String?,
        sports: [LiveSportSection],
        upcomingSports: [LiveSportSection] = [],
        recentSports: [LiveSportSection] = []
    ) {
        self.generatedAt = generatedAt
        self.cacheHit = cacheHit
        self.providerConfigured = providerConfigured
        self.message = message
        self.sports = sports
        self.upcomingSports = upcomingSports
        self.recentSports = recentSports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        cacheHit = try container.decode(Bool.self, forKey: .cacheHit)
        providerConfigured = try container.decode(Bool.self, forKey: .providerConfigured)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        sports = try container.decodeIfPresent([LiveSportSection].self, forKey: .sports) ?? []
        upcomingSports = try container.decodeIfPresent([LiveSportSection].self, forKey: .upcomingSports) ?? []
        recentSports = try container.decodeIfPresent([LiveSportSection].self, forKey: .recentSports) ?? []
    }
}

struct LiveMatchDetailResponse: Decodable {
    let generatedAt: Date
    let match: LiveMatch
    let scoreboardSections: [ScoreboardSection]
}

struct LiveSportSection: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let competitions: [LiveCompetition]

    var matchCount: Int {
        competitions.reduce(0) { $0 + $1.matches.count }
    }
}

struct LiveCompetition: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let country: String?
    let matches: [LiveMatch]
}

struct LiveMatch: Decodable, Identifiable, Hashable {
    let id: String
    let providerID: String?
    let detailID: String?
    let sportID: String
    let sportName: String
    let competitionID: String
    let competitionName: String
    let country: String?
    let status: String
    let statusDetail: String?
    let clock: String?
    let period: String?
    let startsAt: Date?
    let homeName: String
    let awayName: String
    let homeScore: String?
    let awayScore: String?
    let scoreSummary: String?
    let homeLogoURL: URL?
    let awayLogoURL: URL?
    let venue: String?
    let note: String?
    let scoreboardSections: [ScoreboardSection]?

    var displayScore: String {
        if let homeScore, let awayScore {
            return "\(homeScore) - \(awayScore)"
        }
        return scoreSummary ?? "Live"
    }

    var liveBadgeText: String {
        if let clock, !clock.isEmpty {
            return clock
        }
        if let period, !period.isEmpty {
            return period
        }
        if !status.isEmpty {
            return status
        }
        return "Live"
    }
}

struct ScoreboardSection: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let columns: [String]
    let rows: [ScoreboardRow]
}

struct ScoreboardRow: Decodable, Identifiable, Hashable {
    let id: String
    let cells: [String]
    let note: String?
}
