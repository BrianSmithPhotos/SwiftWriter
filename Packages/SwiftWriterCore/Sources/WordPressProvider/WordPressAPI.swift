import Foundation
import BlogPublishing

/// One HTTP round trip.
///
/// A closure rather than a protocol so a test can answer a request with a canned response in
/// a line, and so nothing in this module depends on URLSession being reachable.
public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public enum WordPressTransport {
    /// The real one. `ephemeral` because the only state worth keeping is the token, and that
    /// lives in the Keychain rather than in a cookie jar.
    public static func urlSession() -> Transport {
        let session = URLSession(configuration: .ephemeral)
        return { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PublishError.providerRefused("The response was not HTTP")
            }
            return (data, http)
        }
    }
}

/// Builds requests against `/wp/v2/sites/<id>`.
///
/// v2 rather than WordPress.com's older v1.1: it is what WordPress.com points new code at,
/// and the same requests work against a self-hosted site, which is the point of keeping the
/// publishing layer provider-neutral. The cost is that tags and categories are term ids here
/// rather than names, which is what `TermResolver` exists to bridge.
struct WordPressAPI: Sendable {
    static let host = URL(string: "https://public-api.wordpress.com")!

    let siteID: String
    let token: @Sendable () async throws -> String
    let transport: Transport

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(
            url: Self.host.appending(path: "wp/v2/sites/\(siteID)/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    /// A GET returning a decoded body.
    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = "GET"
        return try await send(request)
    }

    /// A POST with a JSON body. WordPress uses POST for updates too, not PATCH or PUT.
    func post<Response: Decodable>(_ path: String, json body: [String: Any]) async throws -> Response {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return try await send(request)
    }

    /// A POST of raw file bytes, which is how wp/v2 takes an upload: the file name travels in
    /// Content-Disposition rather than in a multipart envelope.
    func upload<Response: Decodable>(
        _ path: String, data: Data, fileName: String, mimeType: String
    ) async throws -> Response {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("attachment; filename=\"\(fileName)\"", forHTTPHeaderField: "Content-Disposition")
        request.httpBody = data
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        var request = request
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await transport(request)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, statusCode: http.statusCode)
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw PublishError.providerRefused("Could not read the response: \(error)")
        }
    }

    /// WordPress reports failures as `{"code":…,"message":…,"data":{…}}`. Surfacing its message
    /// beats a bare status code, because that message is usually the actionable half - and the
    /// `data` object is kept with it, since that is where WordPress puts the detail that lets a
    /// caller recover. A `term_exists` refusal, for one, names the id it clashed with there and
    /// nowhere else.
    static func error(from data: Data, statusCode: Int) -> PublishError {
        if statusCode == 401 || statusCode == 403 { return .notAuthenticated }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = body?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
        var text = "HTTP \(statusCode): \(message)"
        if let detail = body?["data"],
           let encoded = try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]),
           let json = String(data: encoded, encoding: .utf8) {
            text += " \(json)"
        }
        // 404 keeps its message but gets its own case, because "this is not there" is the one
        // failure a caller can act on rather than only report.
        if statusCode == 404 { return .notFound(text) }
        return .providerRefused(text)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
