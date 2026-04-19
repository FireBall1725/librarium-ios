import Foundation

struct BookFingerprint: Codable, Equatable {
    let total: Int
    let maxUpdatedAt: String?

    var cacheToken: String { "\(total)|\(maxUpdatedAt ?? "")" }
}
