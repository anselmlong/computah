import XCTest
import AppKit
@testable import Computah

final class CodexWorkerTests: XCTestCase {
    func testExecutableDiscoveryWithFinderPathAndUserInstall() {
        let expected = "/Users/test/.local/bin/codex"
        let result = CodexExecutable.resolve(environment: ["PATH": "/usr/bin:/bin"],
                                             home: URL(fileURLWithPath: "/Users/test"),
                                             isExecutable: { $0 == expected })
        XCTAssertEqual(result?.path, expected)
    }

    func testExecutableDiscoveryUsesPathAndFallsBackToHomebrew() {
        for expected in ["/custom/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            let result = CodexExecutable.resolve(environment: ["PATH": "/custom/bin:/usr/bin"],
                                                 isExecutable: { $0 == expected })
            XCTAssertEqual(result?.path, expected)
        }
    }

    func testExecutableDiscoveryRejectsRelativePathsAndMissingExecutables() {
        XCTAssertNil(CodexExecutable.resolve(environment: ["PATH": ":.:relative/bin"],
                                              isExecutable: { !$0.hasPrefix("/") }))
        XCTAssertNil(CodexExecutable.resolve(isExecutable: { _ in false }))
    }

    func testWorkerConfigurationExcludesInheritedCredentialsAndHostTools() throws {
        let directory = URL(fileURLWithPath: "/tmp/isolated-computah")
        let environment = CodexWorkerProtocol.environment(directory: directory, apiKey: "test-not-a-real-key")
        XCTAssertEqual(environment["HOME"], directory.path)
        XCTAssertEqual(environment["CODEX_HOME"], directory.path)
        XCTAssertEqual(environment["OPENAI_API_KEY"], "test-not-a-real-key")
        XCTAssertTrue(CodexWorkerProtocol.arguments.contains("web_search=\"live\""))
        XCTAssertTrue(CodexWorkerProtocol.arguments.contains("model_providers.computah_openai.supports_standalone_web_search=true"))
        XCTAssertNil(environment["CODEX_THREAD_ID"])
        XCTAssertNil(environment["HTTP_PROXY"])
        XCTAssertFalse(CodexWorkerProtocol.arguments.joined().contains("test-not-a-real-key"))
        let thread = CodexWorkerProtocol.thread(directory: directory, tools: [])
        XCTAssertEqual(thread["model"] as? String, "gpt-5.6-sol")
        XCTAssertEqual(thread["allowProviderModelFallback"] as? Bool, false)
        XCTAssertEqual((thread["environments"] as? [String])?.count, 0)
        XCTAssertEqual(thread["sandbox"] as? String, "read-only")
        XCTAssertEqual(thread["ephemeral"] as? Bool, true)
        XCTAssertEqual((CodexWorkerProtocol.turn(threadID: "t", task: "x", context: "y")["environments"] as? [String])?.count, 0)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: thread))
        for feature in ["shell_tool", "unified_exec", "computer_use", "browser_use", "apps", "multi_agent"] {
            XCTAssertTrue(CodexWorkerProtocol.arguments.contains("features.\(feature)=false"))
        }
    }

    func testAllApprovalResponsesDeclineAccess() {
        for method in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"] {
            XCTAssertEqual(CodexWorkerProtocol.deniedResponse(method: method)?["decision"] as? String, "decline")
        }
        let permissions = CodexWorkerProtocol.deniedResponse(method: "item/permissions/requestApproval")
        XCTAssertEqual((permissions?["permissions"] as? [String: String])?.count, 0)
        XCTAssertNil(CodexWorkerProtocol.deniedResponse(method: "account/chatgptAuthTokens/refresh"))
        XCTAssertNil(CodexWorkerProtocol.deniedResponse(method: "unexpectedTool"))
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
    func testInstalledCodexHandshakeUsesOnlyDummyCredential() async throws {
        guard let executable = CodexExecutable.resolve() else { throw XCTSkip("Codex CLI is not installed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("computah-worker-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let rpc = CodexRPC(executable: executable, arguments: CodexWorkerProtocol.arguments,
                           environment: CodexWorkerProtocol.environment(directory: directory, apiKey: "dummy-no-real-credentials"), directory: directory)
        defer { rpc.close() }
        try rpc.launch()
        _ = try await rpc.request("initialize", params: CodexWorkerProtocol.initialize)
        try rpc.notify("initialized")
        let spec: [String: Any] = ["type": "function", "name": "browser_observe", "description": "Inspect the embedded browser",
                                   "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]]
        let started = try await rpc.request("thread/start", params: CodexWorkerProtocol.thread(directory: directory, tools: [spec]))
        XCTAssertEqual(started["model"] as? String, CodexWorkerProtocol.model)
        XCTAssertEqual(started["modelProvider"] as? String, CodexWorkerProtocol.provider)
        XCTAssertNotNil((started["thread"] as? [String: Any])?["id"] as? String)
        XCTAssertEqual((started["instructionSources"] as? [String])?.count, 0)
        // No turn/start or account/login is sent. This probe makes no authenticated model call.
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        for file in files {
            let url = directory.appendingPathComponent(file)
            if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                XCTAssertFalse(text.contains("dummy-no-real-credentials"), "Credential was persisted")
            }
        }
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
            #"{"method":"item/tool/call","id":"tool-rpc","params":{"threadId":"thread-test","turnId":"turn-test","callId":"review-call","namespace":null,"tool":"browser_request_review","arguments":{"reason":"Check the prepared application before submitting."}}}"#,
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
        worker.takeOverForReview()
        XCTAssertEqual(worker.status, "You control the browser")
        XCTAssertFalse(worker.running)
    }

    @MainActor
    func testLiveWebSearchDoesNotStopBrowserWorker() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/started","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"webSearch","id":"search"}}}"#,
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"webSearch","id":"search"}}}"#,
            #"{"method":"item/completed","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"agentMessage","id":"answer","phase":"final_answer","text":"Found the official program."}}}"#,
            #"{"method":"turn/completed","params":{"threadId":"thread-test","turn":{"id":"turn-test","status":"completed"}}}"#
        ])
        try await worker.start(task: "find official program", context: "", apiKey: "dummy-no-real-credentials")
        XCTAssertEqual(worker.status, "Finished")
        XCTAssertEqual(worker.result, "Found the official program.")
    }

    @MainActor
    func testUnexpectedNativeToolEventStopsWorker() async throws {
        _ = NSApplication.shared
        let worker = fakeWorker(events: [
            #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
            #"{"method":"item/started","params":{"threadId":"thread-test","turnId":"turn-test","item":{"type":"commandExecution","id":"forbidden"}}}"#
        ])
        var results: [String] = []
        worker.onResult = { results.append($0) }
        try await worker.start(task: "test", context: "test", apiKey: "dummy-no-real-credentials")
        XCTAssertFalse(worker.running)
        XCTAssertEqual(worker.status, "Worker stopped")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(worker.result.contains("outside its browser workspace"))
    }

    @MainActor
    func testUnknownOrMissingCompletionStatusCannotReportSuccess() async throws {
        _ = NSApplication.shared
        for status in [",\"status\":\"unexpected\"", ""] {
            let worker = fakeWorker(events: [
                #"{"method":"turn/started","params":{"threadId":"thread-test","turn":{"id":"turn-test"}}}"#,
                "{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-test\",\"turn\":{\"id\":\"turn-test\"\(status)}}}"
            ])
            var results: [String] = []
            worker.onResult = { results.append($0) }
            try await worker.start(task: "test", context: "", apiKey: "dummy-no-real-credentials")
            XCTAssertFalse(worker.running)
            XCTAssertEqual(worker.status, "Worker unavailable")
            XCTAssertEqual(results.count, 1)
            XCTAssertTrue(worker.result.contains("unrecognized task status"))
        }
    }

    @MainActor
    private func fakeWorker(events: [String]) -> CodexWorker {
        // A deterministic subprocess speaks JSON-RPC without any model or network request.
        let eventPrints = events.map { "printf '%s\\n' '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: "\n")
        let script = """
        IFS= read -r fixture_line
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r fixture_line
        IFS= read -r fixture_line
        printf '%s\\n' '{"id":2,"result":{"model":"gpt-5.6-sol","modelProvider":"computah_openai","thread":{"id":"thread-test"}}}'
        IFS= read -r fixture_line
        \(eventPrints)
        while IFS= read -r fixture_line; do :; done
        """
        return CodexWorker(browser: BrowserWorkspace(), resolveExecutable: { URL(fileURLWithPath: "/bin/sh") }, rpcFactory: { _, _, environment, directory in
            CodexRPC(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: environment, directory: directory)
        })
    }

    @MainActor
    private func makeIdleRPC() -> CodexRPC {
        CodexRPC(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], environment: ["PATH": "/usr/bin:/bin"])
    }
}
