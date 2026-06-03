import Foundation

struct JobListing: Identifiable, Equatable, Codable {
    enum WorkMode: String, CaseIterable, Codable {
        case remote = "Remote"
        case hybrid = "Hybrid"
        case onsite = "On-site"
    }

    let id: String
    let title: String
    let company: String
    let location: String
    let workMode: WorkMode
    let salary: String
    let matchScore: Int
    let postedAt: String
    let companySummary: String
    let roleSummary: String
    let skills: [String]
    let perks: [String]
    let requirements: [String]
    let applyURL: URL?
}

extension JobListing {
    var postedDisplayText: String {
        let trimmed = postedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Recently" }

        if let date = Self.postedDateFormatter.date(from: trimmed) ?? Self.postedDateFormatterNoFraction.date(from: trimmed) {
            let elapsed = max(0, Date().timeIntervalSince(date))
            let minute: TimeInterval = 60
            let hour = minute * 60
            let day = hour * 24

            switch elapsed {
            case ..<minute:
                return "just now"
            case ..<hour:
                return "\(max(1, Int(elapsed / minute))) min ago"
            case ..<day:
                return "\(max(1, Int(elapsed / hour))) hr ago"
            default:
                return "\(max(1, Int(elapsed / day))) days ago"
            }
        }

        if trimmed.contains("T"), trimmed.contains("-") {
            return "Recently"
        }

        return trimmed
    }

    private static let postedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let postedDateFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
