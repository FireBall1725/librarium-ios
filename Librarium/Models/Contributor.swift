import Foundation

// MARK: - Search / create (existing)

struct ContributorResult: Codable, Identifiable {
    let id: String
    let name: String
}

// MARK: - Library contributors browse

struct LibraryContributor: Decodable, Identifiable {
    let id: String
    let name: String
    let photoUrl: String?
    let bookCount: Int
    let nationality: String?
    let bornDate: String?
}

struct ContributorWork: Decodable, Identifiable {
    let id: String
    let contributorId: String
    let title: String
    let isbn13: String?
    let isbn10: String?
    let publishYear: Int?
    let coverUrl: String?
    let source: String?
    let inLibrary: Bool
    let libraryBookId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, source
        case contributorId  = "contributor_id"
        case isbn13         = "isbn_13"
        case isbn10         = "isbn_10"
        case publishYear    = "publish_year"
        case coverUrl       = "cover_url"
        case inLibrary      = "in_library"
        case libraryBookId  = "library_book_id"
    }
}

struct ContributorDetail: Decodable {
    let id: String
    let name: String
    let bio: String?
    let bornDate: String?
    let diedDate: String?
    let nationality: String?
    let photoUrl: String?
    let bookCount: Int
    let works: [ContributorWork]
    let books: [Book]
}
