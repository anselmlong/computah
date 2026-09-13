import AppKit
import WebKit
import XCTest
@testable import Computah

final class BrowserWorkspaceTests: XCTestCase {
    @MainActor
    func testConcurrentBrowserSessionsKeepFormsCookiesAndTakeoverSeparate() async throws {
        _ = NSApplication.shared
        let first = BrowserWorkspace()
        let second = BrowserWorkspace()
        XCTAssertFalse(first.webView === second.webView)
        XCTAssertFalse(first.webView.configuration.websiteDataStore === second.webView.configuration.websiteDataStore)
        // Install local HTML at the same document origin without making a network
        // request. This test-only setup bypasses the agent navigation policy.
        first.webView.navigationDelegate = nil
        second.webView.navigationDelegate = nil
        let origin = URL(string: "https://example.com/isolation-fixture")!
        first.webView.loadHTMLString("<body><input aria-label='Name' value='first prepared form'></body>", baseURL: origin)
        second.webView.loadHTMLString("<body><input aria-label='Name' value='second prepared form'></body>", baseURL: origin)
        try await waitForDocument(first.webView)
        try await waitForDocument(second.webView)
        first.webView.navigationDelegate = first
        second.webView.navigationDelegate = second
        _ = try await first.webView.evaluateJavaScript("sessionStorage.setItem('task','first')")
        _ = try await second.webView.evaluateJavaScript("sessionStorage.setItem('task','second')")
        let firstStorage = try await first.webView.evaluateJavaScript("sessionStorage.getItem('task')") as? String
        let secondStorage = try await second.webView.evaluateJavaScript("sessionStorage.getItem('task')") as? String
        XCTAssertEqual(firstStorage, "first")
        XCTAssertEqual(secondStorage, "second")
        let firstCookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "task", .value: "first"]))
        let secondCookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "task", .value: "second"]))
        await withCheckedContinuation { continuation in
            first.webView.configuration.websiteDataStore.httpCookieStore.setCookie(firstCookie) { continuation.resume() }
        }
        await withCheckedContinuation { continuation in
            second.webView.configuration.websiteDataStore.httpCookieStore.setCookie(secondCookie) { continuation.resume() }
        }
        let firstCookies = await withCheckedContinuation { continuation in
            first.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let secondCookies = await withCheckedContinuation { continuation in
            second.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(firstCookies.first { $0.name == "task" }?.value, "first")
        XCTAssertEqual(secondCookies.first { $0.name == "task" }?.value, "second")
        let firstController = BrowserWindowController(browser: first, worker: CodexWorker(browser: first), taskTitle: "Research first company")
        let secondController = BrowserWindowController(browser: second, worker: CodexWorker(browser: second), taskTitle: "Research second company")
        XCTAssertTrue(firstController.windowTitle.contains("Research first company"))
        XCTAssertTrue(secondController.windowTitle.contains("Research second company"))
        firstController.takeOver()
        XCTAssertTrue(first.manualControl)
        XCTAssertFalse(second.manualControl)
        let result = try await second.perform(name: "browser_observe", arguments: [:])
        XCTAssertTrue((result.first?["text"] as? String ?? "").contains("second prepared form"))
        XCTAssertFalse((result.first?["text"] as? String ?? "").contains("first prepared form"))
        first.reset()
        let secondValue = try await second.webView.evaluateJavaScript("document.querySelector('input').value") as? String
        XCTAssertEqual(secondValue, "second prepared form")
        firstController.close()
        XCTAssertFalse(second.presentedInWindow)
    }

    @MainActor
    func testLiveWindowViewportPreservesAgentCoordinatesAndRequiresTakeover() async throws {
        _ = NSApplication.shared
        let browser = BrowserWorkspace()
        browser.webView.loadHTMLString("<body><input aria-label='Prepared' value='same session'></body>", baseURL: nil)
        try await waitForDocument(browser.webView)
        let host = BrowserViewportView(browser: browser)
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        host.updateMode()
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(browser.webView.frame.size, CGSize(width: 1024, height: 768))
        let viewport = try await browser.webView.evaluateJavaScript("({width:innerWidth,height:innerHeight})") as? [String: Int]
        XCTAssertEqual(viewport?["width"], 1024)
        XCTAssertEqual(viewport?["height"], 768)
        XCTAssertTrue(host.hitTest(NSPoint(x: 100, y: 100)) === host, "Watching must intercept human input before the live web view.")
        host.frame.size = CGSize(width: 1200, height: 850)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(browser.webView.frame.size, CGSize(width: 1024, height: 768))
        XCTAssertFalse(browser.manualControl)
        browser.enableManualReview()
        host.updateMode()
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(browser.manualControl)
        XCTAssertEqual(browser.webView.frame.size, host.bounds.size)
        XCTAssertFalse(host.hitTest(NSPoint(x: 100, y: 100)) === host)
        let value = try await browser.webView.evaluateJavaScript("document.querySelector('input').value") as? String
        XCTAssertEqual(value, "same session")
        host.detach()
        XCTAssertNil(browser.webView.superview)
    }

    @MainActor
    func testPrivateBrowserReadsFillsAndBlocksSubmission() async throws {
        _ = NSApplication.shared
        let browser = BrowserWorkspace()
        XCTAssertFalse(browser.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(browser.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        browser.webView.loadHTMLString("""
        <!doctype html><html><head><title>Preparation fixture</title></head>
        <body style="background:#fff;color:#000;font:24px system-ui;margin:40px">
          <h1>Private preparation</h1>
          <form action="https://example.com/submit" method="post">
            <input aria-label="Name" name="name" style="display:block;width:300px;height:40px">
            <button style="display:block;width:300px;height:40px;margin-top:20px">Send application</button>
          </form>
          <script>document.body.dataset.pageScriptExecuted = 'yes'; fetch('https://example.com/write',{method:'POST',body:'unsafe'});</script>
        </body></html>
        """, baseURL: nil)
        try await waitForDocument(browser.webView)
        let ran = try await browser.webView.evaluateJavaScript("document.body.dataset.pageScriptExecuted || 'no'") as? String
        XCTAssertEqual(ran, "no", "Website-authored scripts must not execute during preparation.")

        let observed = try await browser.perform(name: "browser_observe", arguments: [:])
        XCTAssertTrue((observed.first?["text"] as? String ?? "").contains("Private preparation"))
        XCTAssertTrue((observed.last?["imageUrl"] as? String ?? "").hasPrefix("data:image/png;base64,"))
        XCTAssertNotNil(browser.preview)
        let imageURL = try XCTUnwrap(observed.last?["imageUrl"] as? String)
        let png = try XCTUnwrap(Data(base64Encoded: String(imageURL.dropFirst("data:image/png;base64,".count))))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        var opaqueDarkPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.5, color.redComponent < 0.5 {
                    opaqueDarkPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(opaqueDarkPixels, 50, "The unattached browser screenshot must contain actual page text, rather than a blank image.")
        let point = try await center(of: "input", in: browser.webView)
        _ = try await browser.perform(name: "browser_click", arguments: point)
        _ = try await browser.perform(name: "browser_type", arguments: ["text": "Ada \"review\" Lovelace\nNo Enter"])
        let value = try await browser.webView.evaluateJavaScript("document.querySelector('input').value") as? String
        XCTAssertEqual(value, "Ada \"review\" LovelaceNo Enter")

        var reviewReason: String?
        browser.onReviewRequested = { reviewReason = $0 }
        let submit = try await center(of: "button", in: browser.webView)
        let blocked = try await browser.perform(name: "browser_click", arguments: submit)
        XCTAssertNotNil(reviewReason)
        XCTAssertTrue((blocked.first?["text"] as? String ?? "").contains("MANUAL_REVIEW_REQUIRED"))
        XCTAssertNil(browser.webView.url?.host)
        do {
            _ = try await browser.perform(name: "browser_type", arguments: ["text": "late agent write"])
            XCTFail("Agent tools must stay locked after review is requested.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("manual review")) }
        browser.enableManualReview()
        XCTAssertTrue(browser.status.contains("Manual review"))
        let reviewHost = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        reviewHost.addSubview(browser.webView)
        browser.webView.frame = reviewHost.bounds
        XCTAssertTrue(browser.webView.superview === reviewHost)
        let after = try await browser.webView.evaluateJavaScript("document.querySelector('input').value") as? String
        XCTAssertEqual(after, value, "Opening review must preserve prepared values without reloading or submitting.")
        browser.webView.removeFromSuperview()
        browser.reset()
        XCTAssertEqual(browser.webView.frame.size, CGSize(width: 1024, height: 768))
    }

    @MainActor
    func testNativeDelegateBlocksDirectFormSubmission() async throws {
        _ = NSApplication.shared
        let browser = BrowserWorkspace()
        browser.webView.loadHTMLString("<form method='post' action='https://example.com/'><input name='x' value='prepared'></form>", baseURL: nil)
        try await waitForDocument(browser.webView)
        let review = expectation(description: "Native navigation delegate blocks submission")
        browser.onReviewRequested = { _ in review.fulfill() }
        // The direct evaluation is test-only. There is no corresponding agent tool.
        _ = try await browser.webView.evaluateJavaScript("document.forms[0].submit(); null")
        await fulfillment(of: [review], timeout: 3)
        XCTAssertNil(browser.webView.url?.host)
        XCTAssertTrue(browser.status.contains("blocked"))
    }

    @MainActor
    func testFormCannotBypassReviewWithPopupTarget() async throws {
        _ = NSApplication.shared
        let browser = BrowserWorkspace()
        browser.webView.loadHTMLString("<form target='_blank' method='post' action='https://example.com/'><input name='x' value='prepared'></form>", baseURL: nil)
        try await waitForDocument(browser.webView)
        let review = expectation(description: "Popup submission requires review")
        browser.onReviewRequested = { _ in review.fulfill() }
        _ = try await browser.webView.evaluateJavaScript("document.forms[0].submit(); null")
        await fulfillment(of: [review], timeout: 3)
        XCTAssertNil(browser.webView.url?.host)
        XCTAssertTrue(browser.status.contains("blocked"))
    }

    func testPublicURLPolicyRejectsPrivateAndNonWebDestinations() async {
        for address in ["file:///etc/passwd", "http://localhost/", "http://127.0.0.1/", "http://10.0.0.1/", "http://[::1]/", "http://192.168.1.1/", "http://203.0.113.1/", "https://example.com:8443/", "https://user:password@example.com/"] {
            do {
                try await BrowserWorkspace.validatePublicURL(URL(string: address)!)
                XCTFail("Should reject \(address)")
            } catch { }
        }
    }

    @MainActor
    private func waitForDocument(_ webView: WKWebView) async throws {
        for _ in 0..<100 {
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript("document.readyState")) as? String == "complete" { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Fixture document did not finish loading")
    }

    @MainActor
    private func center(of selector: String, in webView: WKWebView) async throws -> [String: Any] {
        let result = try await webView.evaluateJavaScript("(() => {const r=document.querySelector('\(selector)').getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};})()")
        return try XCTUnwrap(result as? [String: Any])
    }
}
