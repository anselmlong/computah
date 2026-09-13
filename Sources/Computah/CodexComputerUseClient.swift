import Foundation
import Combine
import ApplicationServices

@MainActor
protocol CodexComputerUseTransport: AnyObject {
    var available: Bool { get }
    func connect() async throws
    func call(name: String, arguments: [String: Any]) async throws -> [String: Any]
    func stop()
}

enum CodexComputerUseError: LocalizedError, Equatable {
    case missingHelper, unavailable, accessibilityRequired, externalCallerUnsupported, rejected, invalidArguments
    var errorDescription: String? {
        switch self {
        case .missingHelper: return "The Codex Computer Use helper was not found. Check that Computer Use is installed in Codex."
        case .unavailable: return "Codex Computer Use is not responding. Open Codex and check Computer Use availability, then retry."
        case .accessibilityRequired: return "Codex Computer Use is unavailable. Enable Accessibility for Computah in System Settings, then retry."
        case .externalCallerUnsupported: return "Codex Computer Use rejected Computah as an unauthenticated external app. This installed helper does not currently provide Computah an authorized connection."
        case .rejected: return "Codex Computer Use could not complete this action. Check the application and retry."
        case .invalidArguments: return "This computer action is unsupported or contains invalid arguments."
        }
    }
}

/// Uses the installed Computer Use helper's MCP stdio interface.
/// It does not borrow the desktop thread's credentials or private connection context.
@MainActor
final class CodexComputerUseClient: ObservableObject, CodexComputerUseTransport {
    static let shared = CodexComputerUseClient()
    @Published private(set) var available = false
    @Published private(set) var externalAccessDenied = false
    @Published private(set) var status = "Computer Use availability has not been checked."
    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let accessibilityTrusted: @MainActor () -> Bool
    private var rpc: CodexRPC?
    private var connecting: Task<Void, Error>?
    private var generation = UUID()
    private var discoveredTools: Set<String> = []
    private var busy = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    nonisolated static let allowedTools: Set<String> = ["list_apps", "get_app_state", "click", "drag", "perform_secondary_action", "press_key", "scroll", "select_text", "set_value", "type_text"]

    init(executable: URL? = nil, arguments: [String] = ["mcp"], environment: [String: String]? = nil, timeout: TimeInterval = 5,
         accessibilityTrusted: (@MainActor () -> Bool)? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.executable = executable ?? home.appendingPathComponent(".codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient")
        self.arguments = arguments
        self.environment = environment ?? ["HOME": home.path, "CODEX_HOME": home.appendingPathComponent(".codex").path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        self.timeout = timeout
        self.accessibilityTrusted = accessibilityTrusted ?? { AXIsProcessTrusted() }
    }
    func connect() async throws {
        try await connect(readinessTimeout: timeout, callerWaitTimeout: timeout)
    }
    /// An explicit setup check gives the user time to answer macOS permission dialogs.
    func connectForSetup() async throws {
        try await connect(readinessTimeout: 30, callerWaitTimeout: 30)
    }
    private func connect(readinessTimeout: TimeInterval, callerWaitTimeout: TimeInterval) async throws {
        if available { return }
        if externalAccessDenied { throw CodexComputerUseError.externalCallerUnsupported }
        if let connecting { try await waitForConnection(connecting, timeout: callerWaitTimeout); try Task.checkCancellation(); return }
        let token = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CodexComputerUseError.unavailable }
            try await self.establish(token, readinessTimeout: readinessTimeout)
        }
        connecting = task
        do {
            try await task.value
            if generation == token { connecting = nil }
            try Task.checkCancellation()
        } catch {
            if generation == token { connecting = nil }
            throw error
        }
    }
    private final class ConnectionWaiter {
        var continuation: CheckedContinuation<Void, Error>?
        var timer: Task<Void, Never>?
        func finish(_ result: Result<Void, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel()
            continuation.resume(with: result)
        }
    }
    private func waitForConnection(_ task: Task<Void, Error>, timeout: TimeInterval) async throws {
        try Task.checkCancellation()
        let waiter = ConnectionWaiter()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                waiter.timer = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    waiter.finish(.failure(CodexComputerUseError.unavailable))
                }
                Task { @MainActor in
                    do { try await task.value; waiter.finish(.success(())) }
                    catch { waiter.finish(.failure(error)) }
                }
            }
        }, onCancel: { Task { @MainActor in waiter.finish(.failure(CancellationError())) } })
    }
    private var connectionFailure: CodexComputerUseError {
        accessibilityTrusted() ? .unavailable : .accessibilityRequired
    }
    private func establish(_ token: UUID, readinessTimeout: TimeInterval) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            status = CodexComputerUseError.missingHelper.localizedDescription
            throw CodexComputerUseError.missingHelper
        }
        status = "Checking Codex Computer Use with a live readiness request…"
        let channel = CodexRPC(executable: executable, arguments: arguments, environment: environment, includeJSONRPCVersion: true)
        rpc = channel
        channel.onMessage = { [weak channel] message in
            if let id = message["id"], message["method"] != nil { channel?.reject(id: id) }
        }
        channel.onFailure = { [weak self] _ in
            guard let self, self.generation == token else { return }
            self.available = false
            self.status = self.connectionFailure.localizedDescription
        }
        do {
            try channel.launch()
            _ = try await channel.request("initialize", params: ["protocolVersion": "2024-11-05", "capabilities": [:], "clientInfo": ["name": "Computah", "version": "1.0"]], timeout: timeout)
            try channel.notify("notifications/initialized")
            let inventory = try await channel.request("tools/list", params: [:], timeout: timeout)
            guard let tools = inventory["tools"] as? [[String: Any]] else { throw CodexComputerUseError.unavailable }
            let names = Set(tools.compactMap { $0["name"] as? String })
            guard names.isSuperset(of: ["list_apps", "get_app_state", "click", "type_text", "press_key", "scroll"]) else { throw CodexComputerUseError.unavailable }
            // Metadata alone never proves that desktop control is available.
            if readinessTimeout > timeout { status = "Checking Codex Computer Use. Answer any macOS permission dialog, then wait for this check." }
            let probe = try await channel.request("tools/call", params: ["name": "list_apps", "arguments": [:]], timeout: readinessTimeout)
            if Self.isSenderAuthenticationFailure(probe) { throw CodexComputerUseError.externalCallerUnsupported }
            if probe["isError"] as? Bool == true { throw CodexComputerUseError.rejected }
            guard probe["isError"] as? Bool != true,
                  let content = probe["content"] as? [[String: Any]],
                  content.contains(where: { item in
                      guard item["type"] as? String == "text", let text = item["text"] as? String,
                            let data = text.data(using: .utf8) else { return false }
                      return (try? JSONSerialization.jsonObject(with: data)) is [Any]
                  }) else { throw CodexComputerUseError.unavailable }
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            discoveredTools = names
            externalAccessDenied = false
            available = true
            status = "Codex Computer Use is available."
        } catch {
            channel.close()
            let safe = error as? CodexComputerUseError
            let failure: CodexComputerUseError = safe == .externalCallerUnsupported || safe == .rejected ? safe! : connectionFailure
            if generation == token {
                rpc = nil; available = false
                externalAccessDenied = failure == .externalCallerUnsupported
                status = failure.localizedDescription
            }
            if error is CancellationError { throw error }
            throw failure
        }
    }
    /// Match the observed helper error without exposing arbitrary helper output.
    private nonisolated static func isSenderAuthenticationFailure(_ result: [String: Any]) -> Bool {
        guard result["isError"] as? Bool == true, let content = result["content"] as? [[String: Any]] else { return false }
        return content.contains { item in
            guard item["type"] as? String == "text", let text = item["text"] as? String else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines) == "Computer Use server error -10000: Sender process is not authenticated"
        }
    }
    func call(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        guard Self.allowedTools.contains(name), JSONSerialization.isValidJSONObject(arguments), let data = try? JSONSerialization.data(withJSONObject: arguments), data.count <= 65536 else { throw CodexComputerUseError.invalidArguments }
        try await connect()
        let token = generation
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        guard generation == token, available, discoveredTools.contains(name), let channel = rpc else { throw CodexComputerUseError.unavailable }
        // A cancelled caller cannot prove that the helper stopped a desktop action.
        // Keep the shared slot until that action completes or its request times out.
        let remote = Task { @MainActor in
            try await channel.request("tools/call", params: ["name": name, "arguments": arguments], timeout: timeout)
        }
        do {
            let result = try await remote.value
            try Task.checkCancellation()
            guard generation == token, rpc === channel, available else { throw CancellationError() }
            if Self.isSenderAuthenticationFailure(result) {
                available = false; externalAccessDenied = true
                status = CodexComputerUseError.externalCallerUnsupported.localizedDescription
                throw CodexComputerUseError.externalCallerUnsupported
            }
            guard result["isError"] as? Bool != true else { throw CodexComputerUseError.rejected }
            return result
        } catch {
            guard generation == token, rpc === channel else { throw CancellationError() }
            if error is CancellationError { throw error }
            if let safe = error as? CodexComputerUseError {
                if safe == .externalCallerUnsupported { channel.close(); rpc = nil }
                throw safe
            }
            available = false
            status = connectionFailure.localizedDescription
            channel.close()
            throw connectionFailure
        }
    }
    private func acquire() async throws {
        try Task.checkCancellation()
        if !busy { busy = true; return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in waiters.append((id, continuation)) }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, let index = self.waiters.firstIndex(where: { $0.0 == id }) else { return }
                self.waiters.remove(at: index).1.resume(throwing: CancellationError())
            }
        })
    }
    private func release() {
        if !waiters.isEmpty { waiters.removeFirst().1.resume() }
        else { busy = false }
    }
    func stop() {
        generation = UUID()
        connecting?.cancel(); connecting = nil
        rpc?.close(); rpc = nil
        available = false
        discoveredTools.removeAll()
        status = "Codex Computer Use is disconnected."
        for (_, continuation) in waiters { continuation.resume(throwing: CancellationError()) }
        waiters.removeAll()
    }
}
