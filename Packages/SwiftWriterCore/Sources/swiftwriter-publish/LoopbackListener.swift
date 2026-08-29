import Foundation

/// Catches an OAuth redirect sent to http://localhost:<port>/… by being the thing it is sent to.
///
/// Replaces pasting the address by hand, which could not work: the redirect went to a custom
/// scheme, nothing on the machine was registered to handle it, and the browser silently gave up
/// rather than landing anywhere the address could be copied from. A loopback address is what
/// RFC 8252 recommends for exactly this - a command-line tool has no other way to be redirected to.
///
/// Deliberately not a general web server. It accepts one connection, reads one request line,
/// answers it, and stops.
struct LoopbackListener {
    let port: UInt16

    enum Failure: Error, LocalizedError {
        case cannotListen(port: UInt16, reason: String)
        case timedOut(seconds: Int)
        case noRequest

        var errorDescription: String? {
            switch self {
            case let .cannotListen(port, reason):
                "Could not listen on 127.0.0.1:\(port) - \(reason). "
                    + "Something else may be using the port."
            case let .timedOut(seconds):
                "Gave up after \(seconds)s waiting for the browser to come back."
            case .noRequest:
                "The browser connected but sent nothing."
            }
        }
    }

    /// - Returns: the full URL the browser asked for, so the caller can read `code` and `state`
    ///   from it exactly as it would from a pasted address.
    func waitForRedirect(timeoutSeconds: Int) throws -> URL {
        let listening = try openSocket()
        defer { close(listening) }

        // poll rather than a blocking accept, so a browser that never comes back is a clear
        // message rather than a tool that hangs - the failure this whole change exists to fix.
        var descriptor = pollfd(fd: listening, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Int32(timeoutSeconds * 1000))
        guard ready > 0 else { throw Failure.timedOut(seconds: timeoutSeconds) }

        let connection = accept(listening, nil, nil)
        guard connection >= 0 else { throw Failure.noRequest }
        defer { close(connection) }

        guard let target = Self.requestTarget(readFrom: connection) else { throw Failure.noRequest }
        respond(on: connection, success: target.contains("code="))

        // The browser sends only the path and query; the host is ours by definition.
        guard let url = URL(string: "http://localhost:\(port)\(target)") else { throw Failure.noRequest }
        return url
    }

    private func openSocket() throws -> Int32 {
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        guard handle >= 0 else {
            throw Failure.cannotListen(port: port, reason: String(cString: strerror(errno)))
        }
        // Without this a rerun within the TIME_WAIT window is refused, which would look like
        // the port is taken when it is only just finished with.
        var yes: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(handle, 1) == 0 else {
            let reason = String(cString: strerror(errno))
            close(handle)
            throw Failure.cannotListen(port: port, reason: reason)
        }
        return handle
    }

    /// The path and query out of "GET /callback?code=... HTTP/1.1".
    static func requestTarget(readFrom connection: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(connection, &buffer, buffer.count)
        guard count > 0 else { return nil }
        return requestTarget(inRequest: String(decoding: buffer[0..<count], as: UTF8.self))
    }

    static func requestTarget(inRequest request: String) -> String? {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private func respond(on connection: Int32, success: Bool) {
        // Careful not to claim more than is known: this page is written before the code has
        // been checked or exchanged, so it can only report that the redirect arrived. Saying
        // "authorised" here would show success in the browser while the terminal reports a
        // state mismatch.
        let message = success
            ? "<h1>Code received</h1><p>Back to the terminal - it will say whether the token was stored.</p>"
            : "<h1>No code</h1><p>WordPress did not send an authorisation code.</p>"
        let body = "<!doctype html><meta charset=utf-8><title>SwiftWriter</title>"
            + "<body style=\"font:16px -apple-system;padding:3em\">\(message)</body>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = Array(response.utf8).withUnsafeBufferPointer { write(connection, $0.baseAddress, $0.count) }
    }
}
