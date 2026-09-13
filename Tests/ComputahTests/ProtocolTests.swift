import XCTest
@testable import Computah

final class ProtocolTests: XCTestCase {
    func testClientDelegationUsesLiveContract() throws {
        let json = LiveProtocol.start()
        XCTAssertEqual(json["type"] as? String, "session.start")
        let session = try XCTUnwrap(json["session"] as? [String: Any])
        XCTAssertEqual(session["model"] as? String, "gpt-live-1")
        XCTAssertEqual((session["delegation"] as? [String: String])?["type"], "client")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: json))
        let context = LiveProtocol.append("context")
        XCTAssertTrue(context["delegation_id"] is NSNull)
        let result = LiveProtocol.append("result", delegation: "opaque-original-id", speak: true)
        XCTAssertEqual(result["delegation_id"] as? String, "opaque-original-id")
        XCTAssertEqual(result["type"] as? String, "session.commentary.append")
    }

    func testLateTranscriptFragmentsAreOrderedAndDeduplicated() {
        var ledger = TranscriptLedger()
        let later: [String: Any] = ["type": "session.input_transcript.delta", "event_id": "2", "delta": "this?", "start_ms": 200.0, "end_ms": 300.0]
        XCTAssertTrue(ledger.ingest(later))
        XCTAssertFalse(ledger.ingest(later))
        XCTAssertTrue(ledger.ingest(["type": "session.input_transcript.delta", "event_id": "1", "delta": "What is ", "start_ms": 0.0, "end_ms": 200.0]))
        XCTAssertEqual(ledger.captions.first?.text, "What is this?")
        XCTAssertFalse(ledger.context(through: 100).contains("this?"))
    }

    func testRetinaSelectionFlipsYAndClipsToDisplay() {
        let rect = SelectionGeometry.pixelRect(selection: CGRect(x: 100, y: 700, width: 200, height: 100),
            displaySize: CGSize(width: 1440, height: 900), pixelSize: CGSize(width: 2880, height: 1800))
        XCTAssertEqual(rect, CGRect(x: 200, y: 200, width: 400, height: 200))
        let clipped = SelectionGeometry.pixelRect(selection: CGRect(x: -20, y: -10, width: 120, height: 60),
            displaySize: CGSize(width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200))
        XCTAssertEqual(clipped, CGRect(x: 0, y: 100, width: 200, height: 100))
        XCTAssertEqual(SelectionGeometry.pixelRect(selection: .zero, displaySize: .zero, pixelSize: .zero), .zero)
    }

    func testAppendsPreserveUnicodeAndDelegationWithinConservativeLimit() throws {
        let text = String(repeating: "你好 👩🏽‍💻 screen text\n", count: 100)
        let events = LiveProtocol.appends(content: text, delegation: "original", speak: true)
        XCTAssertGreaterThan(events.count, 1)
        XCTAssertEqual(events.compactMap { $0["content"] as? String }.joined(), text)
        for event in events {
            let part = try XCTUnwrap(event["content"] as? String)
            XCTAssertLessThanOrEqual(part.utf8.count, 480)
            XCTAssertEqual(event["delegation_id"] as? String, "original")
            XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: event))
        }
    }

    func testLatestUserTextSplitsTimelineGapsAndIncludesLateFragments() {
        var ledger = TranscriptLedger()
        func input(_ id: String, _ text: String, _ start: Double, _ end: Double) -> [String: Any] {
            ["type": "session.input_transcript.delta", "event_id": id, "delta": text, "start_ms": start, "end_ms": end]
        }
        XCTAssertTrue(ledger.ingest(input("old", "Hello", 0, 500)))
        XCTAssertTrue(ledger.ingest(input("late", "page?", 2500, 3000)))
        XCTAssertTrue(ledger.ingest(input("early", "What is this ", 2200, 2700)))
        XCTAssertEqual(ledger.latestUserText, "What is this page?")
        XCTAssertTrue(ledger.ingest(["type": "session.output_transcript.delta", "event_id": "answer", "delta": "A page", "start_ms": 3100.0, "end_ms": 3500.0]))
        XCTAssertTrue(ledger.ingest(input("new", "Read it", 3700, 4100)))
        XCTAssertEqual(ledger.latestUserText, "Read it")
        XCTAssertFalse(ledger.ingest(input("bad", "Invalid", 5000, 4000)))
    }

    func testRoutingRejectsIncompleteRefusedAndInconsistentResults() throws {
        func response(_ text: String, status: String = "completed") -> [String: Any] {
            ["status": status, "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        }
        let result = try RouteService.parse(response("{\"route\":\"task\",\"task\":\"Find jobs related to this page\",\"requiresScreen\":true}"))
        XCTAssertEqual(result.kind, .task)
        XCTAssertTrue(result.requiresScreen)
        XCTAssertThrowsError(try RouteService.parse(response("{\"route\":\"screen\",\"task\":\"Read this\",\"requiresScreen\":false}")))
        XCTAssertThrowsError(try RouteService.parse(response("{\"route\":\"direct\",\"task\":\"Talk\",\"requiresScreen\":true}")))
        XCTAssertThrowsError(try RouteService.parse(response("{}", status: "incomplete")))
        XCTAssertThrowsError(try RouteService.parse(["status": "completed", "output": [["content": [["type": "refusal", "refusal": "No"]]]]]))
    }

    func testShowBrowserRouteIsDistinctFromWebsiteNavigation() throws {
        func response(_ route: String, _ task: String, screen: Bool) -> [String: Any] {
            let payload: [String: Any] = ["route": route, "task": task, "requiresScreen": screen]
            let data = try! JSONSerialization.data(withJSONObject: payload)
            return ["status": "completed", "output": [["content": [["type": "output_text", "text": String(decoding: data, as: UTF8.self)]]]]]
        }
        let show = try RouteService.parse(response("show_browser", "Show your current browser", screen: false))
        XCTAssertEqual(show.kind, .showBrowser)
        XCTAssertFalse(show.requiresScreen)
        let navigation = try RouteService.parse(response("task", "Open https://example.com", screen: false))
        XCTAssertEqual(navigation.kind, .task)
        XCTAssertThrowsError(try RouteService.parse(response("show_browser", "Show the browser", screen: true)))
        XCTAssertThrowsError(try RouteService.parse(response("hide_browser", "Hide the browser", screen: false)))
    }

    func testConcurrentTasksAndNamedBrowserTargetArePreserved() throws {
        func response(_ payload: [String: Any]) throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: payload)
            return ["status": "completed", "output": [["content": [["type": "output_text", "text": String(decoding: data, as: UTF8.self)]]]]]
        }
        let jobs = ["Find Swift jobs in Singapore", "Find Swift jobs in New Zealand"]
        let batch = try RouteService.parse(response(["route": "task", "task": "Find jobs in both countries", "requiresScreen": false, "tasks": jobs, "targetTask": NSNull()]))
        XCTAssertEqual(batch.tasks, jobs)
        XCTAssertNil(batch.targetTask)
        let show = try RouteService.parse(response(["route": "show_browser", "task": "Show Singapore jobs", "requiresScreen": false, "tasks": [], "targetTask": "Singapore jobs"]))
        XCTAssertEqual(show.kind, .showBrowser)
        XCTAssertEqual(show.targetTask, "Singapore jobs")
        let legacy = try RouteService.parse(response(["route": "task", "task": "Find jobs", "requiresScreen": false]))
        XCTAssertEqual(legacy.tasks, ["Find jobs"])
        XCTAssertThrowsError(try RouteService.parse(response(["route": "task", "task": "Find jobs", "requiresScreen": false, "tasks": [], "targetTask": NSNull()])))
        XCTAssertThrowsError(try RouteService.parse(response(["route": "task", "task": "Find jobs", "requiresScreen": false, "tasks": [" "], "targetTask": NSNull()])))
    }
}
