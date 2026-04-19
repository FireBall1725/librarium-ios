import Foundation

struct Shelf: Codable, Identifiable, Hashable {
    let id: String
    let libraryId: String
    let name: String
    let description: String
    let color: String
    let icon: String
    let displayOrder: Int
    let bookCount: Int
    let tags: [Tag]
    let createdAt: String
    let updatedAt: String
}
