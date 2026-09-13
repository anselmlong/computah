import Foundation
import XCTest
@testable import Computah

final class CodexComputerUseClientTests: XCTestCase {
    @MainActor
    private func fixture(mode: String, accessibilityTrusted: Bool = true) throws -> (CodexComputerUseClient, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("computah-cua-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("server.py")
        let source = """
        import json,sys,time
        mode=sys.argv[1]
        names=['list_apps','get_app_state','click','type_text','press_key','scroll']
        trace=sys.argv[2]
        for line in sys.stdin:
            msg=json.loads(line)
            assert msg.get('jsonrpc')=='2.0'
            if 'id' not in msg: continue
            method=msg.get('method')
            if method=='initialize': result={'protocolVersion':'2024-11-05','capabilities':{'tools':{}},'serverInfo':{'name':'fixture','version':'1'}}
            elif method=='tools/list': result={'tools':[{'name':n,'inputSchema':{'type':'object'}} for n in names]}
            elif method=='tools/call':
                name=msg['params']['name']
                with open(trace,'a') as log: log.write(name+' start\\n')
                if mode=='delay' and name=='click': time.sleep(0.1)
                if mode=='permission-delay' and name=='list_apps': time.sleep(20)
                with open(trace,'a') as log: log.write(name+' finish\\n')
                if mode=='timeout': time.sleep(5);continue
                if mode=='metadata': sys.exit(0)
                result={'isError':mode in ['error','auth'],'content':[{'type':'text','text':'Computer Use server error -10000: Sender process is not authenticated' if mode=='auth' else ('error text' if mode=='plaintext' else '[]')}]}
            else: result={}
            print(json.dumps({'jsonrpc':'2.0','id':msg['id'],'result':result}),flush=True)
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        let client = CodexComputerUseClient(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [script.path, mode, folder.appendingPathComponent("trace").path], environment: ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"], timeout: 8.0, accessibilityTrusted: { accessibilityTrusted })
        return (client, folder)
    }
    @MainActor
    func testLiveProbeRequiredAndErrorsRemainUnavailable() async throws {
        for mode in ["metadata", "error", "timeout", "plaintext"] {
            let (client, folder) = try fixture(mode: mode)
            defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
            XCTAssertFalse(client.available)
            do { try await client.connect(); XCTFail("Expected failed live readiness for \(mode)") }
            catch { XCTAssertTrue(error is CodexComputerUseError) }
            XCTAssertFalse(client.available)
            XCTAssertTrue(client.status.contains(mode == "error" ? "could not complete" : "not responding"))
        }
    }
    @MainActor
    func testAuthenticatedSenderRejectionIsSpecificAndDoesNotRetryOrRecommendPermissions() async throws {
        let (client, folder) = try fixture(mode: "auth", accessibilityTrusted: false)
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        for setup in [false, true] {
            do {
                if setup { try await client.connectForSetup() } else { try await client.connect() }
                XCTFail("Expected external sender rejection")
            } catch {
                XCTAssertEqual(error as? CodexComputerUseError, .externalCallerUnsupported)
            }
        }
        XCTAssertFalse(client.available)
        XCTAssertTrue(client.externalAccessDenied)
        XCTAssertTrue(client.status.contains("unauthenticated external app"))
        XCTAssertFalse(client.status.contains("Accessibility"))
        XCTAssertFalse(client.status.contains("not responding"))
        let trace = try String(contentsOf: folder.appendingPathComponent("trace"))
        XCTAssertEqual(trace.components(separatedBy: "list_apps start").count - 1, 1)
    }
    @MainActor
    func testInteractiveSetupAllowsPermissionDelayButOrdinaryCallerKeepsShortBudget() async throws {
        let (client, folder) = try fixture(mode: "permission-delay")
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        let setup = Task { try await client.connectForSetup() }
        try await Task.sleep(for: .milliseconds(30))
        do { try await client.connect(); XCTFail("Ordinary caller must not wait for the entire interactive setup") }
        catch { XCTAssertTrue(error is CodexComputerUseError) }
        XCTAssertFalse(client.available)
        try await setup.value
        XCTAssertTrue(client.available)
        let trace = try String(contentsOf: folder.appendingPathComponent("trace"))
        XCTAssertEqual(trace.components(separatedBy: "list_apps start").count - 1, 1)
    }
    @MainActor
    func testFailedConnectionReportsObservedMissingAccessibilityWithoutPrompting() async throws {
        let (client, folder) = try fixture(mode: "metadata", accessibilityTrusted: false)
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        do { try await client.connect(); XCTFail("Expected failed readiness") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Accessibility")) }
        XCTAssertFalse(client.available)
        XCTAssertTrue(client.status.contains("Accessibility"))
    }
    @MainActor
    func testSuccessfulProbeCoalescesConnectAndStopDisconnects() async throws {
        let (client, folder) = try fixture(mode: "success")
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        async let first: Void = client.connect()
        async let second: Void = client.connect()
        _ = try await (first, second)
        XCTAssertTrue(client.available)
        let result = try await client.call(name: "list_apps", arguments: [:])
        XCTAssertEqual(result["isError"] as? Bool, false)
        client.stop()
        XCTAssertFalse(client.available)
        XCTAssertTrue(client.status.contains("disconnected"))
    }
    @MainActor
    func testCancelledActionKeepsSerializationUntilRemoteCompletion() async throws {
        let (client, folder) = try fixture(mode: "delay")
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        try await client.connect()
        let action = Task { try await client.call(name: "click", arguments: ["app": "fixture"]) }
        try await Task.sleep(for: .milliseconds(30))
        action.cancel()
        let next = Task { try await client.call(name: "get_app_state", arguments: ["app": "fixture"]) }
        try await Task.sleep(for: .milliseconds(30))
        let early = try String(contentsOf: folder.appendingPathComponent("trace"))
        XCTAssertFalse(early.contains("get_app_state start"))
        do { _ = try await action.value; XCTFail("Expected cancelled result") } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await next.value
        let final = try String(contentsOf: folder.appendingPathComponent("trace"))
        XCTAssertLessThan(try XCTUnwrap(final.range(of: "click finish")?.lowerBound), try XCTUnwrap(final.range(of: "get_app_state start")?.lowerBound))
    }
    @MainActor
    func testStaleCallCannotInvalidateReconnectedChannel() async throws {
        let (client, folder) = try fixture(mode: "delay")
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        try await client.connect()
        let old = Task { try await client.call(name: "click", arguments: ["app": "fixture"]) }
        try await Task.sleep(for: .milliseconds(30))
        client.stop()
        try await client.connect()
        do { _ = try await old.value; XCTFail("Expected stale call cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(client.available)
        _ = try await client.call(name: "list_apps", arguments: [:])
    }
    @MainActor
    func testStopCancelsReadinessAndUnsupportedCallsAreRejected() async throws {
        let (client, folder) = try fixture(mode: "timeout")
        defer { client.stop(); try? FileManager.default.removeItem(at: folder) }
        let task = Task { try await client.connect() }
        try await Task.sleep(for: .milliseconds(30))
        client.stop()
        do { try await task.value; XCTFail("Expected cancellation") } catch {}
        XCTAssertFalse(client.available)
        do { _ = try await client.call(name: "arbitrary_code", arguments: [:]); XCTFail("Expected allowlist rejection") } catch { XCTAssertTrue(error is CodexComputerUseError) }
    }
}
