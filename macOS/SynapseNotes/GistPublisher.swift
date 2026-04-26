import Foundation
import Combine
import AppKit

/// Represents a note to be published to a gist
struct NoteContent {
    let filename: String
    let content: String

    init(filename: String, content: String) {
        self.filename = filename
        self.content = content
    }
}

/// Handles publishing notes to GitHub Gists
class GistPublisher: ObservableObject {
    enum PublishState: Equatable {
        case idle
        case publishing
        case success(url: String)
        case failed(error: String)
    }

    @Published var state: PublishState = .idle

    /// Injected for testing; defaults to the shared session in production.
    var urlSession: URLSession = .shared
    
    /// Injected for testing; defaults to NSWorkspace.shared.open in production.
    var onOpenExternalURL: ((URL) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    /// Publishes a note to a new GitHub public gist
    /// - Parameters:
    ///   - note: The note content to publish
    ///   - pat: GitHub Personal Access Token with 'gist' scope
    func publish(_ note: NoteContent, pat: String) {
        // Validate inputs
        let trimmedPAT = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPAT.isEmpty else {
            state = .failed(error: "GitHub Personal Access Token is required")
            return
        }

        guard !note.content.isEmpty else {
            state = .failed(error: "Note content cannot be empty")
            return
        }

        guard !note.filename.isEmpty else {
            state = .failed(error: "Filename cannot be empty")
            return
        }

        state = .publishing

        // Create the gist payload
        let payload: [String: Any] = [
            "public": true,
            "files": [
                note.filename: [
                    "content": note.content
                ]
            ]
        ]

        guard let url = URL(string: "https://api.github.com/gists"),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            state = .failed(error: "Failed to create request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(trimmedPAT)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        urlSession.dataTaskPublisher(for: request)
            .tryMap { data, response -> String in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                switch httpResponse.statusCode {
                case 201:
                    // Parse the response to get the gist URL
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let gistUrl = json["html_url"] as? String {
                        return gistUrl
                    } else {
                        throw NSError(domain: "GistPublisher", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse gist URL"])
                    }
                case 401:
                    throw NSError(domain: "GistPublisher", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub token. Please check your Personal Access Token."])
                case 403:
                    throw NSError(domain: "GistPublisher", code: 403, userInfo: [NSLocalizedDescriptionKey: "GitHub API rate limit exceeded or insufficient permissions"])
                case 422:
                    throw NSError(domain: "GistPublisher", code: 422, userInfo: [NSLocalizedDescriptionKey: "Invalid request. Please check your note content."])
                default:
                    throw NSError(domain: "GistPublisher", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API error (HTTP \(httpResponse.statusCode))"])
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.state = .failed(error: error.localizedDescription)
                    }
                },
                receiveValue: { [weak self] gistUrl in
                    self?.state = .success(url: gistUrl)
                    // Open the gist URL in the default browser
                    if let url = URL(string: gistUrl) {
                        // Use injected callback if available, otherwise fall back to NSWorkspace
                        if let onOpenExternalURL = self?.onOpenExternalURL {
                            onOpenExternalURL(url)
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    /// Resets the publisher state to idle
    func reset() {
        state = .idle
    }
}
