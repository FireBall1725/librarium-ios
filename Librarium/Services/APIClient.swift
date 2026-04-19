import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(Int, String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid server URL — check your server settings."
        case .unauthorized:         return "Invalid credentials."
        case .notFound:             return "Resource not found."
        case .serverError(let c, let m): return m ?? "Server error (\(c))."
        case .decodingError(let e): return "Unexpected server response: \(e.localizedDescription)"
        case .networkError(let e):  return e.localizedDescription
        }
    }
}

final class APIClient {
    let baseURL: String
    var token: String?

    /// Called when any request gets a 401. Should refresh auth and return the new
    /// access token, or nil if refresh failed (triggers logout upstream).
    var onUnauthorized: (() async -> String?)?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(baseURL: String, token: String? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
    }

    // MARK: - Public (with response body)

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await raw(path, method: "GET", body: nil as Data?)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await raw(path, method: "POST", body: try encoder.encode(body))
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await raw(path, method: "PUT", body: try encoder.encode(body))
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await raw(path, method: "PATCH", body: try encoder.encode(body))
    }

    // MARK: - Public (void — no response body expected)

    func postVoid<B: Encodable>(_ path: String, body: B) async throws {
        try await voidRequest(path, method: "POST", body: try encoder.encode(body))
    }

    func postVoid(_ path: String) async throws {
        try await voidRequest(path, method: "POST", body: nil as Data?)
    }

    func delete(_ path: String) async throws {
        try await voidRequest(path, method: "DELETE", body: nil as Data?)
    }

    // MARK: - Multipart upload (for covers, etc.)

    func uploadMultipart(
        _ path: String,
        method: String = "PUT",
        fieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        retried: Bool = false
    ) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw APIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299: return
        case 401:
            if !retried, let refresh = onUnauthorized, let newToken = await refresh() {
                token = newToken
                return try await uploadMultipart(path, method: method, fieldName: fieldName,
                                                 fileData: fileData, fileName: fileName,
                                                 mimeType: mimeType, retried: true)
            }
            throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            throw APIError.serverError(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Private

    private struct Envelope<T: Decodable>: Decodable {
        let data: T
    }

    private func buildRequest(_ path: String, method: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        return req
    }

    private func raw<T: Decodable>(_ path: String, method: String, body: Data?, retried: Bool = false) async throws -> T {
        let req = try buildRequest(path, method: method, body: body)
        #if DEBUG
        let _t0 = Date()
        #endif
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw APIError.networkError(error) }
        #if DEBUG
        let _ms = Int(Date().timeIntervalSince(_t0) * 1000)
        let _status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("⏱️ [APIClient] \(method) \(_status) \(_ms)ms \(data.count)B \(path)")
        #endif

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299:
            do { return try decoder.decode(Envelope<T>.self, from: data).data }
            catch {
                #if DEBUG
                let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
                print("🔴 [APIClient] Decode failure for \(T.self) at \(path)\n\(raw)\n\(error)")
                #endif
                throw APIError.decodingError(error)
            }
        case 401:
            if !retried, let refresh = onUnauthorized, let newToken = await refresh() {
                token = newToken
                return try await raw(path, method: method, body: body, retried: true)
            }
            throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            throw APIError.serverError(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    private func voidRequest(_ path: String, method: String, body: Data?, retried: Bool = false) async throws {
        let req = try buildRequest(path, method: method, body: body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw APIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200...299: return
        case 401:
            if !retried, let refresh = onUnauthorized, let newToken = await refresh() {
                token = newToken
                return try await voidRequest(path, method: method, body: body, retried: true)
            }
            throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            throw APIError.serverError(http.statusCode, String(data: data, encoding: .utf8))
        }
    }
}
