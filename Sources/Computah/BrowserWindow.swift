import AppKit
import Combine
import SwiftUI
import WebKit

/// The optional window presents the worker's existing private browser session.
@MainActor
final class BrowserWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var pageTitle = "Computah Browser"
    @Published private(set) var pageURL = "No page open"
    let browser: BrowserWorkspace
    let worker: CodexWorker
    let taskTitle: String
    var onTakeOver: (() -> Void)?
    var windowTitle: String { taskTitle.isEmpty ? pageTitle : "\(taskTitle) | \(pageTitle)" }
    private var window: BrowserWatchingWindow?
    private var observers: Set<AnyCancellable> = []

    init(browser: BrowserWorkspace, worker: CodexWorker, taskTitle: String = "") {
        self.browser = browser
        self.worker = worker
        self.taskTitle = String(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        super.init()
        browser.webView.publisher(for: \.title, options: [.initial, .new]).sink { [weak self] title in
            guard let self else { return }
            self.pageTitle = title?.isEmpty == false ? title! : "Computah Browser"
            self.window?.title = self.windowTitle
        }.store(in: &observers)
        browser.webView.publisher(for: \.url, options: [.initial, .new]).sink { [weak self] url in
            self?.pageURL = url?.absoluteString ?? "No page open"
        }.store(in: &observers)
    }

    func show() {
        if let window, isVisible {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 900)
        let size = CGSize(width: min(1000, visible.width - 48), height: min(720, visible.height - 48))
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        let window = self.window ?? BrowserWatchingWindow(contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        window.browser = browser
        window.title = windowTitle
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 640, height: 480)
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        browser.webView.removeFromSuperview()
        browser.setWindowPresentation(true)
        window.contentView = NSHostingView(rootView: BrowserWindowSurface(controller: self, browser: browser, worker: worker))
        isVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the presentation never ends the independent task.
    func close() {
        guard let window else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        browser.webView.removeFromSuperview()
        browser.setWindowPresentation(false)
        isVisible = false
    }

    func takeOver() {
        if let onTakeOver { onTakeOver() }
        else { worker.takeOverForReview() }
    }

    func reload() {
        guard browser.manualControl, !worker.running else { return }
        browser.webView.reload()
    }
}

/// Prevent keyboard events from reaching a page focused by a DOM tool while
/// the human is watching. The normal toolbar remains available.
@MainActor
private final class BrowserWatchingWindow: NSWindow {
    weak var browser: BrowserWorkspace?
    override func sendEvent(_ event: NSEvent) {
        if let browser, !browser.manualControl,
           [.keyDown, .keyUp].contains(event.type), let responder = firstResponder as? NSView,
           responder === browser.webView || responder.isDescendant(of: browser.webView) {
            return
        }
        super.sendEvent(event)
    }
}

private struct BrowserWindowSurface: View {
    @ObservedObject var controller: BrowserWindowController
    @ObservedObject var browser: BrowserWorkspace
    @ObservedObject var worker: CodexWorker

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        if !controller.taskTitle.isEmpty {
                            Text(controller.taskTitle).font(.system(size: 13, weight: .semibold))
                                .lineLimit(1).help(controller.taskTitle)
                        }
                        Text(browser.manualControl ? "You control the browser" : "Watching live")
                            .font(.system(size: 12, weight: controller.taskTitle.isEmpty ? .semibold : .regular))
                            .foregroundStyle(controller.taskTitle.isEmpty ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    Text(controller.pageURL).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if browser.manualControl {
                    Button("Reload page", action: controller.reload).disabled(worker.running)
                        .help("Enables website scripts. Reloading may clear prepared fields.")
                        .keyboardShortcut("r", modifiers: .command)
                } else {
                    Button("Take over", action: controller.takeOver)
                        .buttonStyle(.borderedProminent).tint(Color(red: 0.82, green: 0.95, blue: 0.55))
                        .help("Stop Codex before you interact with this page.")
                }
            }.padding(.horizontal, 18).padding(.vertical, 14)
            Divider()
            LiveBrowserPresentation(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Text(browser.manualControl
                     ? "Review before submitting. Reloading enables website scripts and may clear prepared fields."
                     : "Codex controls this page. Take over to click or type. Closing this window leaves the task running.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !browser.manualControl, worker.running {
                    ProgressView().controlSize(.small).accessibilityLabel("Browser task running")
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LiveBrowserPresentation: NSViewRepresentable {
    @ObservedObject var browser: BrowserWorkspace
    func makeNSView(context: Context) -> BrowserViewportView {
        let view = BrowserViewportView(browser: browser)
        view.updateMode()
        return view
    }
    func updateNSView(_ view: BrowserViewportView, context: Context) { view.updateMode() }
    static func dismantleNSView(_ view: BrowserViewportView, coordinator: ()) { view.detach() }
}

/// Watching keeps the browser at its tool viewport and scales its presentation.
/// Resizing the window therefore cannot invalidate the agent's coordinates.
@MainActor
final class BrowserViewportView: NSView {
    private let browser: BrowserWorkspace
    private let canvas = NSView()
    init(browser: BrowserWorkspace) {
        self.browser = browser
        super.init(frame: .zero)
        wantsLayer = true
        canvas.wantsLayer = true
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { !browser.manualControl }

    func updateMode() {
        if browser.webView.superview !== canvas {
            browser.webView.removeFromSuperview()
            canvas.addSubview(browser.webView)
        }
        if !browser.manualControl,
           let responder = window?.firstResponder as? NSView,
           responder === browser.webView || responder.isDescendant(of: browser.webView) {
            window?.makeFirstResponder(self)
        }
        needsLayout = true
    }
    func detach() {
        if browser.webView.superview === canvas { browser.webView.removeFromSuperview() }
    }
    override func layout() {
        super.layout()
        if browser.manualControl {
            canvas.frame = bounds
            canvas.bounds = CGRect(origin: .zero, size: bounds.size)
            browser.webView.frame = canvas.bounds
        } else {
            let viewport = CGSize(width: 1024, height: 768)
            let scale = max(0.01, min(bounds.width / viewport.width, bounds.height / viewport.height))
            let size = CGSize(width: viewport.width * scale, height: viewport.height * scale)
            canvas.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            canvas.bounds = CGRect(origin: .zero, size: viewport)
            browser.webView.frame = canvas.bounds
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !browser.manualControl { return bounds.contains(convert(point, from: superview)) ? self : nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) { if !browser.manualControl { window?.makeFirstResponder(self) } }
    override func scrollWheel(with event: NSEvent) { }
    override func keyDown(with event: NSEvent) { }
}
