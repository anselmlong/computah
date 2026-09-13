import XCTest
import AppKit
@testable import Computah

final class CodexWorkerTests: XCTestCase {
    func testWorkerConfigurationUsesNormalCodexHomeAndRemovesParentTaskIdentity() throws {
        let directory = URL(fileURLWithPath: "/Users/tester")
        let environment = CodexWorkerProtocol.environment(from: [
            "HOME": directory.path, "CODEX_HOME": "/Users/tester/.codex",
            "HTTP_PROXY": "http://localhost:8080", "CODEX_THREAD_ID": "parent",
            "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "parent-origin", "CODEX_ENGINE_STATE": "private",
            "OPENAI_API_KEY": "not-for-the-worker", "PATH": "/usr/bin"
        ])
        XCTAssertEqual(environment["HOME"], directory.path)
        XCTAssertEqual(environment["CODEX_HOME"], "/Users/tester/.codex")
        XCTAssertNil(environment["CODEX_THREAD_ID"])
        XCTAssertNil(environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"])
        XCTAssertNil(environment["CODEX_ENGINE_STATE"])
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertEqual(environment["HTTP_PROXY"], "http://localhost:8080")
        XCTAssertEqual(CodexWorkerProtocol.arguments, ["app-server", "--listen", "stdio://"])
        let thread = CodexWorkerProtocol.thread(directory: directory)
        XCTAssertEqual(thread["model"] as? String, "gpt-6-astra")
        XCTAssertEqual(thread["allowProviderModelFallback"] as? Bool, false)
        XCTAssertEqual(thread["sandbox"] as? String, "read-only")
        XCTAssertEqual(thread["ephemeral"] as? Bool, true)
        XCTAssertNil(thread["modelProvider"])
        XCTAssertNil(thread["dynamicTools"])
        XCTAssertNil(thread["environments"])
        let turn = CodexWorkerProtocol.turn(threadID: "t", task: "x", context: "y")
        XCTAssertEqual(turn["effort"] as? String, "high")
        XCTAssertNil(turn["environments"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: thread))
    }

    func testReviewRequestsBecomeActionableSummaries() {
        let summary = CodexWorkerProtocol.reviewSummary(method: "item/tool/requestUserInput", params: [
            "questions": [["question": "Review the prepared form before submission."]]
        ])
        XCTAssertEqual(summary, "Review the prepared form before submission.")
        XCTAssertNotNil(CodexWorkerProtocol.reviewSummary(method: "item/permissions/requestApproval", params: [:]))
        XCTAssertNil(CodexWorkerProtocol.reviewSummary(method: "unexpectedTool", params: [:]))
    }

    @MainActor
    func testFramingHandlesSplitUnicodeAndMultipleMessages() throws {
        let rpc = makeIdleRPC()
        var values: [String] = []
        rpc.onMessage = { values.append($0["method"] as? String ?? "") }
        let frames = Data("{\"method\":\"消息\"}\n{\"method\":\"second\"}\n".utf8)
        for byte in frames { rpc.receive(Data([byte])) }
        XCTAssertEqual(values, ["消息", "second"])
        rpc.close()
    }

    @MainActor
    func testInvalidAndOversizedFramesFailWithoutDisplayingPayload() {
        for frame in [Data("secret-key-is-not-json\n".utf8), Data(repeating: 65, count: CodexRPC.maximumFrameBytes + 1)] {
            let rpc = makeIdleRPC()
            var failure: String?
            rpc.onFailure = { failure = $0.localizedDescription }
            rpc.receive(frame)
            XCTAssertNotNil(failure)
            XCTAssertFalse(failure?.contains("secret-key") ?? true)
        }
    }

    @MainActor
    func testPendingRequestsFailOnShutdownAndTimeout() async throws {
        let rpc = makeIdleRPC()
        try rpc.launch()
        let pending = Task { try await rpc.request("neverResponds", params: [:], timeout: 5) }
        await Task.yield()
        rpc.close()
        do { _ = try await pending.value; XCTFail("Shutdown must fail a pending request") }
        catch { }

        let timed = makeIdleRPC()
        try timed.launch()
        defer { timed.close() }
        do { _ = try await timed.request("neverResponds", params: [:], timeout: 0.03); XCTFail("Request must time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("in time")) }
    }

    @MainActor
    func testClosingRPCNeverDeletesItsWorkingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("computah-cwd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentinel = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let rpc = CodexRPC(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                           environment: ["PATH": "/usr/bin:/bin"], directory: directory)
        try rpc.launch()
        rpc.close()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @MainActor
    func testRequestCancellationAndLateReplyDoNotResolveAnotherRequest() async throws {
        let rpc = makeIdleRPC()
        try rpc.launch()
        defer { rpc.close() }
        let canceled = Task { try await rpc.request("one", params: [:]) }
        await Task.yield()
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Cancellation must end the request") }
        catch { XCTAssertTrue(error is CancellationError) }
        rpc.receive(Data("{\"id\":1,\"result\":{\"stale\":true}}\n".utf8))
        let next = Task { try await rpc.request("two", params: [:]) }
        await Task.yield()
        rpc.receive(Data("{\"id\":2,\"result\":{\"ok\":true}}\n".utf8))
        let result = try await next.value
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertNil(result["stale"])
    }

    @MainActor
    func testInstalledCodexHandshakeUsesNormalUserConfigurationWithoutModelCall() async throws {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw XCTSkip("Codex CLI is not installed") }
        let environment = CodexWorkerProtocol.environment()
        let directory = URL(fileURLWithPath: environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path)
        let rpc = CodexRPC(executable: executable, arguments: CodexWorkerProtocol.arguments,
                           environment: environment, directory: directory)
        defer { rpc.close() }
        try rpc.launch()
        _ = try await rpc.request("initialize", params: CodexWorkerProtocol.initialize)
        try rpc.notify("initialized")
        let started = try await rpc.request("thread/start", params: CodexWorkerProtocol.thread(directory: directory))
        XCTAssertEqual(started["model"] as? String, CodexWorkerProtocol.model)
        XCTAssertNotNil((started["thread"] as? [String: Any])?["id"] as? String)
    }

    @MainActor
    func testImmediateCompletionWhileTurnStartIsPendingReportsExactlyOnce() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/agentMessage/delta","params":{"threadId":"thread-test","turnId":"turn-test","itemId":"message-test","delta":"Prepared the page."}}"#,
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"agentMessage","id":"message-test","phase":"final_answer","text":"Prepared the page."}}}"#,
            #"{"method":"turn/completed","params":{"threadId":"thread-test","turn":{"id":"turn-test","status":"completed"}}}"#
        ])
        var results: [String] = []
        worker.onResult = { results.append($0) }
        try await worker.start(task: "prepare a page", context: "test", apiKey: "dummy-no-real-credentials")
        XCTAssertEqual(results, ["Prepared the page."])
        XCTAssertEqual(worker.result, "Prepared the page.")
        XCTAssertFalse(worker.running)
        XCTAssertEqual(worker.status, "Finished")
    }

    @MainActor
    func testReviewToolStopsWorkerBeforeManualTakeoverAndIgnoresLateEvents() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/tool/requestUserInput","id":"tool-rpc","params":{"threadId":"thread-test","turnId":"turn-test","itemId":"review-call","isBlocking":true,"questions":[{"header":"Review","id":"review","question":"Check the prepared application before submitting."}]}}"#,
            #"{"method":"item/completed","params":{"threadId":"old-thread","turnId":"old-turn","item":{"type":"agentMessage","id":"late","phase":"final_answer","text":"I submitted it."}}}"#
        ])
        var reviews: [String] = []
        var results: [String] = []
        worker.onReview = { reason in
            XCTAssertFalse(worker.running)
            reviews.append(reason)
        }
        worker.onResult = { results.append($0) }
        try await worker.start(task: "prepare application", context: "test", apiKey: "dummy-no-real-credentials")
        XCTAssertEqual(reviews, ["Check the prepared application before submitting."])
        XCTAssertEqual(results, [])
        XCTAssertTrue(worker.reviewRequested)
        XCTAssertFalse(worker.result.contains("submitted it"))
        XCTAssertFalse(worker.running)
    }

    @MainActor
    func testNativeAppApprovalKeepsWorkerAliveAndCanResume() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"mcpServer/elicitation/request","id":"approval-rpc","params":{"threadId":"thread-test","turnId":"turn-test","serverName":"computer-use","mode":"form","message":"Allow Calculator for this task?","requestedSchema":{"type":"object","properties":{},"required":[]},"_meta":{"codex_approval_kind":"mcp_tool_call"}}}"#
        ], respondBeforeEvents: true)
        var reviews: [String] = []
        worker.onReview = { reviews.append($0) }
        try await worker.start(task: "read Calculator", context: "test", apiKey: "")
        for _ in 0..<50 where !worker.approvalPending { await Task.yield() }
        XCTAssertTrue(worker.running)
        XCTAssertTrue(worker.approvalPending)
        XCTAssertTrue(worker.approvalCanBeAccepted)
        XCTAssertEqual(reviews, ["Allow Calculator for this task?"])
        try worker.approvePendingReview()
        XCTAssertTrue(worker.running)
        XCTAssertFalse(worker.approvalPending)
        XCTAssertEqual(worker.status, "Working with Codex")
        worker.stop()
    }

    @MainActor
    func testNativeToolEventsRemainOwnedByCodex() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/started","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"commandExecution","id":"forbidden"}}}"#
        ], respondBeforeEvents: true)
        var results: [String] = []
        worker.onResult = { results.append($0) }
        try await worker.start(task: "test", context: "test", apiKey: "dummy-no-real-credentials")
        XCTAssertTrue(worker.running)
        XCTAssertEqual(worker.status, "Working with Codex")
        XCTAssertEqual(results.count, 0)
        worker.stop()
    }

    @MainActor
    private func fakeWorker(events: [String], respondBeforeEvents: Bool = false) -> CodexWorker {
        // A deterministic subprocess speaks JSON-RPC without any model or network request.
        let eventPrints = events.map { "printf '%s\\n' '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: "\n")
        let turnResponse = "printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-test\"}}}'"
        let turnExchange = respondBeforeEvents ? "\(turnResponse)\n\(eventPrints)" : "\(eventPrints)"
        let script = """
        IFS= read -r fixture_line
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r fixture_line
        IFS= read -r fixture_line
        printf '%s\\n' '{"id":2,"result":{"model":"gpt-6-astra","modelProvider":"openai","thread":{"id":"thread-test"}}}'
        IFS= read -r fixture_line
        \(turnExchange)
        while IFS= read -r fixture_line; do :; done
        """
        return CodexWorker(browser: BrowserWorkspace(transport: TestBrowserTransport()), rpcFactory: { _, _, environment, directory in
            CodexRPC(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: environment, directory: directory)
        })
    }

    @MainActor
    private func makeIdleRPC() -> CodexRPC {
        CodexRPC(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], environment: ["PATH": "/usr/bin:/bin"])
    }
}
