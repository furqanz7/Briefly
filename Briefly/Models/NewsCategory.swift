import Foundation

enum NewsCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case world
    case politics
    case conflict
    case technology
    case business
    case sports

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .world:
            return "World"
        case .politics:
            return "Politics"
        case .conflict:
            return "War / Conflict"
        case .technology:
            return "Technology"
        case .business:
            return "Business"
        case .sports:
            return "Sports"
        }
    }

    var providerCategory: String {
        switch self {
        case .conflict:
            return "world"
        default:
            return rawValue
        }
    }

    var queryHint: String? {
        switch self {
        case .conflict:
            return "war OR conflict OR military OR strike OR attack OR missile OR troops OR ceasefire"
        case .politics:
            return "politics OR election OR senate OR parliament OR government OR vote"
        case .sports:
            return "IPL OR cricket OR football OR sports OR match OR score OR tournament"
        case .technology:
            return "AI OR Nvidia OR OpenAI OR software OR chips OR devices OR internet"
        case .business:
            return "business OR markets OR stock OR startup OR founder OR company OR earnings"
        case .world:
            return "world OR global OR international OR Middle East OR Pakistan OR Iran"
        }
    }

    init?(providerValue: String) {
        let normalized = providerValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "world", "top":
            self = .world
        case "politics":
            self = .politics
        case "conflict", "war":
            self = .conflict
        case "technology", "tech", "science":
            self = .technology
        case "business", "economy":
            self = .business
        case "sports", "sport":
            self = .sports
        default:
            return nil
        }
    }
}
