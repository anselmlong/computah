import AppKit
import WebKit

/// Explicit opt-in live test. Uses the saved Computah key without printing it.
/// Sends only the supplied public research request; never submits applications.
@main struct BrowserResearchSmoke {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let question = CommandLine.arguments.dropFirst().first ?? "Find the official NUS Master of Computing General Track admissions requirements. Open the official program page in your browser and summarize the entry requirements with source URLs. Do not submit anything."
        do {
            print("Loading saved Computah credential…")
            guard let key = try KeychainCredentialStore().load() else {
                throw ComputahError.message("Save an API key in Computah Settings first.")
            }
            print("Classifying public research request…")
            let decision = try await RouteService.classify(question: question, history: "", key: key)
            print("Route: \(decision.route.rawValue); task: \(decision.task)")
            guard decision.route == .task else { throw ComputahError.message("Request did not route to browser work.") }
            let browser = BrowserWorkspace()
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1024, height: 768), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = browser.webView
            window.orderFrontRegardless()
            let worker = CodexWorker(browser: browser)
            try await worker.start(task: decision.task, context: "", apiKey: key)
            let deadline = Date().addingTimeInterval(240)
            var lastURL = ""
            var lastStatus = ""
            while worker.running && Date() < deadline {
                if worker.status != lastStatus { print("Status: \(worker.status)"); lastStatus = worker.status }
                let url = browser.webView.url?.absoluteString ?? ""
                if url != lastURL { print("Browser URL: \(url)"); lastURL = url }
                try await Task.sleep(for: .seconds(1))
            }
            if worker.running { worker.stop(); throw ComputahError.message("Live browser research exceeded 240 seconds.") }
            print("Status: \(worker.status)\nResult:\n\(worker.result)")
            if worker.status != "Finished" && !worker.reviewRequested { exit(1) }
            window.close()
        } catch { print("Live test failed: \(error.localizedDescription)"); exit(1) }
        exit(0)
    }
}
