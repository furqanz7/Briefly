import Foundation

struct BookItem: Identifiable, Equatable, Codable {
    enum Availability: String, Codable {
        case readable = "Readable"
        case preview = "Preview"
        case reference = "Reference"
    }

    let id: String
    let title: String
    let authors: [String]
    let genre: String
    let description: String
    let coverURL: URL?
    let rating: Double?
    let pageCount: Int?
    let publishedYear: String
    let publisher: String
    let source: String
    let availability: Availability
    let previewURL: URL?
    let downloadURL: URL?

    var authorLine: String {
        authors.isEmpty ? "Unknown author" : authors.joined(separator: ", ")
    }

    var readingMinutes: Int {
        max(12, (pageCount ?? 220) * 2)
    }
}
