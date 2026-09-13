import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--permission-diagnostics") {
            Task { @MainActor in
                await printPermissionDiagnostics()
                NSApp.terminate(nil)
            }
            return
        }
        let preview = CommandLine.arguments.contains("--render-preview")
        let model = AppModel(enableShortcuts: !preview, loadCredentials: !preview)
        self.model = model
        model.expanded = true; model.settings = true
        if preview {
            Task { @MainActor in
                await renderPreview(model)
                NSApp.terminate(nil)
            }
        } else { controller = PanelController(model: model) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.closeBrowser(); model?.stop(); model?.stopAllTasks(); model?.hotkey.uninstall(); model?.apiKey = ""
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Report authorization capability without capturing pixels or loading credentials.
    private func printPermissionDiagnostics() async {
        let status = Permissions.read()
        let hotkey = HotkeyController()
        let tapUsable = hotkey.install()
        let screen = await Permissions.checkScreenAccess()
        hotkey.uninstall()
        let functional: String
        switch screen {
        case .available: functional = "available"
        case .denied: functional = "denied"
        case .unavailable: functional = "unavailable"
        }
        let report: [String: Any] = [
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unbundled",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "microphoneAuthorized": status.microphoneAllowed,
            "screenPreflight": status.screenAllowed,
            "screenFunctional": functional,
            "inputMonitoringPreflight": status.inputMonitoringAllowed,
            "eventTapUsable": tapUsable
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let output = String(data: data, encoding: .utf8) { print(output) }
    }

    /// Capture the real hosting view, including AppKit-backed SecureField controls.
    private func renderPreview(_ model: AppModel) async {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/previews")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { print("Could not create the preview directory."); return }
        print("Rendering previews in \(directory.path)")
        for variant in ["settings", "ready", "conversation", "collapsed"] {
            model.settings = variant == "settings"; model.expanded = variant != "collapsed"
            model.active = variant == "conversation"
            model.state = variant == "conversation" ? .listening : .idle
            model.captions = variant == "conversation" ? [("You", "What is this button for?"), ("Computah", "Screen findings appear here during a connected conversation.")] : []
            model.contextLabel = variant == "conversation" ? "Circled region included" : "Screen context is off until you start"
            model.selected = variant == "conversation"
            let content = IslandView(model: model, maximumHeight: 700).padding(20).background(Color(white: 0.18))
            let host = NSHostingView(rootView: content)
            host.sizingOptions = [.intrinsicContentSize]
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 450, height: 740),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(160))
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            window.setContentSize(size); host.frame = CGRect(origin: .zero, size: size)
            try? await Task.sleep(for: .milliseconds(160))
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    do {
                        try data.write(to: directory.appendingPathComponent("\(variant).png"))
                        print("Rendered \(variant).png")
                    } catch { print("Could not save \(variant).png") }
                }
            } else { print("The \(variant) hosting view could not be captured.") }
            window.orderOut(nil); window.close()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
