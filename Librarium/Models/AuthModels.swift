import Foundation

struct LoginRequest: Encodable {
    let identifier: String
    let password: String
}

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
}
