import AppKit
import SwiftUI
import WebKit

/// Marketing capture harness. Uses native production views and explicit sample data.
/// It never loads credentials, starts audio, invokes an AI model, or submits a form.
@main
struct PitchPreviews {
    @MainActor static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent(".build/pitch-previews")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let model = AppModel(enableShortcuts: false, loadCredentials: false)
            model.expanded = true; model.settings = false
            model.active = true; model.state = .listening; model.level = 0.24
            model.seconds = 82
            model.captions = [
                ("You", "Help me plan my master's applications."),
                ("Computah", "Let's compare programs, check requirements, and prepare a draft for your review.")
            ]
            model.contextLabel = "Current display and circled region included"
            model.selected = true
            try await capture(IslandView(model: model, maximumHeight: 330), name: "masters-conversation", output: output)

            let fixture = try String(contentsOf: root.appendingPathComponent("scripts/fixtures/masters-application.html"), encoding: .utf8)
            let browser = BrowserWorkspace()
            let fixtureHost = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1024, height: 768), styleMask: [.borderless], backing: .buffered, defer: false)
            fixtureHost.isReleasedWhenClosed = false; fixtureHost.contentView = browser.webView
            fixtureHost.orderFrontRegardless()
            browser.webView.loadHTMLString(fixture, baseURL: nil)
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(100))
                if !browser.webView.isLoading, (try? await browser.webView.evaluateJavaScript("document.querySelector('#program') !== null")) as? Bool == true { break }
            }
            for (id, value) in [
                ("program", "MSc Human–Computer Interaction"),
                ("intake", "Autumn 2027 (sample)"),
                ("outline", "1. Why HCI: connect my computing background with human-centered research.\n2. Evidence: describe my own project and the questions it raised.\n3. Fit: verify relevant modules and faculty before finalizing.")
            ] {
                let point = try await browser.webView.evaluateJavaScript("(() => { const r = document.getElementById('\(id)').getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}; })()") as! [String: Double]
                _ = try await browser.perform(name: "browser_click", arguments: point)
                _ = try await browser.perform(name: "browser_type", arguments: ["text": value])
            }
            let values = try await browser.webView.evaluateJavaScript("[document.querySelector('#program').value, document.querySelector('#intake').value, document.querySelector('#outline').value]") as! [String]
            guard values.allSatisfy({ !$0.isEmpty }) else { throw NSError(domain: "PitchCapture", code: 1) }
            print("Verified three fields populated through production browser_click and browser_type tools.")

            let browserWorker = CodexWorker(browser: browser)
            browserWorker.status = "Prepared draft · sample workflow"
            let controller = BrowserWindowController(browser: browser, worker: browserWorker, taskTitle: "Prepare my master's application")
            controller.show()
            try await Task.sleep(for: .milliseconds(700))
            if let window = app.windows.first(where: { $0.title == controller.windowTitle }), let view = window.contentView {
                try await save(view, name: "masters-browser", output: output)
            }
            let submitPoint = try await browser.webView.evaluateJavaScript("(() => { const r=document.querySelector('button').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()") as! [String: Double]
            let response = try await browser.perform(name: "browser_click", arguments: submitPoint)
            guard String(describing: response).contains("MANUAL_REVIEW_REQUIRED") else { throw NSError(domain:"PitchCapture",code:2) }
            print("Verified submission control requests manual review; no submission performed.")
            controller.takeOver()
            try await Task.sleep(for: .milliseconds(350))
            if let window = app.windows.first(where: { $0.title == controller.windowTitle }), let view = window.contentView {
                try await save(view, name: "masters-review", output: output)
            }

            model.active = false; model.state = .stopped; model.seconds = 174
            model.captions = []
            model.contextLabel = "Sample master's application workflow"
            model.selected = false
            let shortlist = model.taskManager.createBrowsingSession(title: "Compare master's programs")
            shortlist.worker.status = "Sample research · ready for review"
            shortlist.worker.result = "Northbridge Institute · MSc HCI\nWesthaven University · MSc Interaction Design\n\nNext: verify course fit, entry requirements, costs, and deadlines on the official pages."
            let requirements = model.taskManager.createBrowsingSession(title: "Prepare the application checklist")
            requirements.worker.status = "Sample checklist · ready for review"
            requirements.worker.result = "Transcript · Statement of purpose · References\nConfirm the exact documents and deadline."
            try await capture(IslandView(model: model, maximumHeight: 860), name: "masters-plan", output: output)
            controller.close(); fixtureHost.close()
            print("Captured native UI with illustrative transcripts and fictional application data. No model session was run.")
        } catch {
            print("Capture failed: \(error)")
            exit(1)
        }
        exit(0)
    }

    @MainActor static func capture<V: View>(_ content: V, name: String, output: URL) async throws {
        let host = NSHostingView(rootView: content.padding(20).background(Color(red: 0.898, green: 0.925, blue: 0.961)))
        host.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 450, height: 950), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        window.setContentSize(host.fittingSize); host.frame = CGRect(origin: .zero, size: host.fittingSize)
        try await save(host, name: name, output: output)
        window.close()
    }

    @MainActor static func save(_ view: NSView, name: String, output: URL) async throws {
        try await Task.sleep(for: .milliseconds(250))
        view.layoutSubtreeIfNeeded(); view.window?.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain:"PitchCapture",code:3) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain:"PitchCapture",code:4) }
        try png.write(to: output.appendingPathComponent("\(name).png"))
        print("Captured \(name): \(bitmap.pixelsWide) x \(bitmap.pixelsHigh)")
    }
}
