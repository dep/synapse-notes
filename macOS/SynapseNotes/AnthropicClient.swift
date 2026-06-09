import Foundation

/// Streams text deltas from the Anthropic /v1/messages SSE endpoint.
/// The URLSession is injectable for testing; defaults to .shared.
struct AnthropicClient {
    enum ClientError: Error, Equatable {
        case invalidKey
        case server(status: Int)
        case badResponse
    }

    let apiKey: String
    var urlSession: URLSession = .shared

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Streams `text_delta` strings. The async sequence finishes on `message_stop`
    /// or end of stream, and throws `ClientError` on a non-2xx status.
    func stream(body: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let httpBody: Data
            do {
                httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = httpBody

                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.badResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        if http.statusCode == 401 { throw ClientError.invalidKey }
                        throw ClientError.server(status: http.statusCode)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if json["type"] as? String == "message_stop" { break }
                        if json["type"] as? String == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
