import Foundation

enum SearchResult: Equatable {
    case articles([Article])
    case aiFallback(query: String, answer: String)
}
