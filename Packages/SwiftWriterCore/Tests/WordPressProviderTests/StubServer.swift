import Foundation
import WordPressProvider

/// Answers requests from a table of canned replies and remembers what it was asked.
///
/// Everything in this target is built against it: the term lookups, the two media calls, the
/// scheduled date, the pull. None of them needs a network, which is what makes them worth
/// running on every build.
final class StubServer: @unchecked Sendable {
    /// Not Sendable: it holds a parsed JSON body. It never leaves the stub's own thread.
    struct Call {
        let method: String
        let path: String
        let query: String?
        let json: [String: Any]?
        let bodyBytes: Int
        let headers: [String: String]
    }

    private(set) var calls: [Call] = []
    private var replies: [String: (Int, String)] = [:]

    /// `key` is "METHOD /path", matched without the query string.
    func reply(_ key: String, status: Int = 200, body: String) {
        replies[key] = (status, body)
    }

    var transport: Transport {
        { [self] request in
            let url = request.url!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let path = components.path.replacingOccurrences(of: "/wp/v2/sites/174606693/", with: "")
            let method = request.httpMethod ?? "GET"
            let body = request.httpBody ?? Data()
            calls.append(Call(
                method: method,
                path: path,
                query: components.query,
                json: (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                bodyBytes: body.count,
                headers: request.allHTTPHeaderFields ?? [:]
            ))
            let (status, text) = replies["\(method) \(path)"] ?? (404, #"{"message":"no stub"}"#)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(text.utf8), response)
        }
    }

    func call(_ method: String, _ path: String) -> Call? {
        calls.first { $0.method == method && $0.path == path }
    }
}

