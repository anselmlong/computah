import Foundation
@testable import Computah

/// Credential-free readiness and application-state fixture.
@MainActor
final class TestBrowserTransport: CodexComputerUseTransport {
    var connected = true
    var available: Bool { connected }

    func connect() async throws { if !available { throw CodexComputerUseError.unavailable } }
    func stop() { connected = false }
    func call(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        try await connect()
        return ["content": [["type": "text", "text": "Fixture application state"],
                            ["type": "image", "mimeType": "image/png", "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jCfoAAAAASUVORK5CYII="]]]
    }

}
