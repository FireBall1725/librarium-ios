import Foundation

struct ISBNLookupResult: Codable {
    let provider: String
    let providerDisplay: String
    let title: String
    let subtitle: String
    let authors: [String]
    let publisher: String
    let publishDate: String
    let isbn10: String
    let isbn13: String
    let description: String
    let coverUrl: String
    let language: String
    let pageCount: Int?
    let categories: [String]?
}

extension ISBNLookupResult: Identifiable {
    var id: String { "\(provider)-\(isbn13.isEmpty ? isbn10 : isbn13)" }
}

struct SeriesLookupResult: Codable {
    let provider: String
    let providerDisplay: String
    let name: String
    let description: String
    let totalCount: Int?
    let isComplete: Bool
    let coverUrl: String
    let externalId: String
    let status: String
    let originalLanguage: String
    let publicationYear: Int?
    let demographic: String
    let genres: [String]
    let url: String
    let externalSource: String
}

extension SeriesLookupResult: Identifiable {
    var id: String { "\(provider)-\(externalId)" }
}
