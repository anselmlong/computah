import SwiftUI
import AppKit
import WebKit

private let leaf = Color(red: 0.82, green: 0.95, blue: 0.55)
private let secondaryInk = Color(white: 0.7)

struct CompanionFace: View {
    let state: CompanionState
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let blink = !reduceMotion && t.truncatingRemainder(dividingBy: 5.8) < 0.14
            let busy = state == .looking || state == .connecting
            let gaze = busy && !reduceMotion ? sin(t * 2) * 2 : 0
            Canvas { context, size in
                let scale = min(size.width / 76, size.height / 46)
                context.scaleBy(x: scale, y: scale)
                let color = state == .failed ? Color(red: 1, green: 0.65, blue: 0.5) : leaf
                for x in [CGFloat(22), 48] {
                    let rect = CGRect(x: x + gaze, y: blink ? 22 : 12, width: 10, height: blink ? 2 : 17)
                    context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color))
                }
                if state == .speaking {
                    let opening = reduceMotion ? 5.0 : 4 + abs(sin(t * 13)) * 5
                    context.fill(Path(ellipseIn: CGRect(x: 33, y: 33, width: 11, height: opening)), with: .color(color))
                } else {
                    var mouth = Path(); mouth.move(to: CGPoint(x: 33, y: 34))
                    mouth.addQuadCurve(to: CGPoint(x: 43, y: 34), control: CGPoint(x: 38, y: 39))
                    context.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if state == .listening {
                    for i in 0..<3 {
                        let h = 3 + CGFloat(level) * CGFloat(8 + i * 5)
                        context.fill(Path(roundedRect: CGRect(x: CGFloat(i * 4 + 3), y: 23 - h / 2, width: 2, height: h), cornerRadius: 1), with: .color(color.opacity(0.7)))
                    }
                }
            }
        }
        .frame(width: 76, height: 46)
        .accessibilityLabel("Computah, \(state.rawValue)")
    }
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    var notchWidth: CGFloat = 190
    var notchHeight: CGFloat = 32
    var collapsedHeight: CGFloat = 32
    var maximumHeight: CGFloat = 760
    var reviewWidth: CGFloat = 880
    var onResize: (() -> Void)?
    var revealSize: CGSize?
    var revealProgress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faceHovered = false
    @State private var suppressHoverUntilExit = false
    @State private var hoverOpenTask: Task<Void, Never>?
    var compactWidth: CGFloat { notchWidth + (model.active || model.runningTaskCount > 0 ? 192 : 88) }

    var body: some View {
        let width = model.reviewing && !model.settings ? reviewWidth : max(410, notchWidth + 192)
        let visibleSize = revealSize ?? CGSize(width: model.expanded ? width : compactWidth, height: model.expanded ? contentHeight + notchHeight + 8 : collapsedHeight)
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight + 8)

            if model.active {
                liveSubtitles
                    .padding(.horizontal, 24)
                    .frame(height: liveSubtitleHeight)
            }
            VStack(spacing: 0) {
                expandedTitlebar.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.settings { settings }
                        else { conversation }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 18)
                }
                if !model.settings {
                    conversationAction.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 20)
                        .background(.black)
                }
            }
            .frame(height: max(120, contentHeight - liveSubtitleHeight))
        }
        .frame(width: width, height: contentHeight + notchHeight + 8, alignment: .top)
        .offset(y: -18 * (1 - (model.expanded || revealSize != nil ? revealProgress : 0)))
        .opacity(model.expanded || revealSize != nil ? max(0, (revealProgress - 0.6) / 0.4) : 0)
        .allowsHitTesting(model.expanded)
        .accessibilityHidden(!model.expanded)
        .frame(width: visibleSize.width, height: visibleSize.height, alignment: .top)
        .clipped()
        .foregroundStyle(.white)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 25, bottomTrailingRadius: 25))
        .overlay(alignment: .bottom) { if model.active && model.expanded { Capsule().fill(leaf).frame(width: 28, height: 2).padding(.bottom, 6) } }
        .contentShape(Rectangle())
        .overlay(alignment: .top) { shoulderHeader(height: min(notchHeight + 8, visibleSize.height)) }
        .preferredColorScheme(.dark)
        .onChange(of: model.expanded) { _, _ in onResize?() }
        .onChange(of: model.active) { _, _ in onResize?() }
        .onChange(of: model.runningTaskCount) { _, _ in onResize?() }
        .onChange(of: model.settings) { _, _ in onResize?() }
        .onChange(of: model.reviewing) { _, _ in onResize?() }
        .onChange(of: model.captions.count) { _, _ in onResize?() }
        .onChange(of: model.error) { _, _ in onResize?() }
        .onChange(of: model.audioNotice) { _, _ in onResize?() }
        .onReceive(model.taskManager.objectWillChange) { _ in onResize?() }
    }

    private func shoulderHeader(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button {
                hoverOpenTask?.cancel()
                suppressHoverUntilExit = model.expanded
                model.expanded.toggle()
            } label: {
                CompanionFace(state: model.state, level: model.level)
                    .scaleEffect(faceHovered && !reduceMotion ? 0.67 : 0.62)
                    .offset(x: 26)
                    .frame(width: 96, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
            .onHover { hovering in
                faceHovered = hovering
                hoverOpenTask?.cancel()
                if !hovering { suppressHoverUntilExit = false }
                guard hovering, !model.expanded, !suppressHoverUntilExit else { return }
                hoverOpenTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    guard !Task.isCancelled, faceHovered else { return }
                    model.expanded = true
                }
            }
            .onDisappear { hoverOpenTask?.cancel() }
            .accessibilityLabel(model.expanded ? "Collapse Computah" : "Open Computah")
            // The physical camera cutout contains no status, controls, or text.
            Color.clear.frame(width: notchWidth, height: height)
                .allowsHitTesting(false)
            if model.expanded || model.active || model.runningTaskCount > 0 {
            Button { model.expanded.toggle() } label: {
                HStack(spacing: 6) {
                    if model.active || model.runningTaskCount > 0 {
                    Image(systemName: model.runningTaskCount > 0 ? "desktopcomputer" : model.active ? "mic.fill" : "circle.fill")
                        .font(.system(size: model.active || model.runningTaskCount > 0 ? 11 : 5))
                        .foregroundStyle(leaf)
                    Text(model.runningTaskCount > 0 ? "\(model.runningTaskCount) \(model.runningTaskCount == 1 ? "task" : "tasks")" : model.active ? "Live" : "")
                        .font(.system(size: 10, weight: .medium))
                    }
                    Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 96, height: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
            .accessibilityLabel(model.expanded ? "Collapse Computah" : "Expand Computah")
            } else { Color.clear.frame(width: 96, height: height).allowsHitTesting(false) }
        }
        .frame(width: notchWidth + 192, height: height)
    }

    var contentHeight: CGFloat {
        let desired: CGFloat
        if model.reviewing && !model.settings { desired = maximumHeight }
        else if model.settings { desired = 570 }
        else {
            let hasTask = !model.tasks.isEmpty
            desired = (model.captions.isEmpty ? 330 : 470) + (hasTask ? 210 : 0)
                + (model.audioNotice == nil ? 0 : 44) + (model.error == nil ? 0 : 64)
        }
        return max(180, min(desired, maximumHeight - notchHeight - 8))
    }

    private var expandedTitlebar: some View {
        HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Computah").font(.system(size: 23, weight: .semibold, design: .rounded))
                            Text(model.state.rawValue).font(.system(size: 13)).foregroundStyle(secondaryInk)
                        }
                        Spacer()
                        Button { model.expanded = false } label: {
                            Label("Hide", systemImage: "chevron.up")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8).frame(height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(IslandButtonStyle())
                        .accessibilityLabel("Hide Computah")
                        .help("Collapse to the compact bar")
                        Button { model.settings.toggle() } label: {
                            Image(systemName: model.settings ? "xmark" : "gearshape")
                                .frame(width: 32, height: 32).contentShape(Rectangle())
                        }.buttonStyle(IslandButtonStyle()).accessibilityLabel(model.settings ? "Close settings" : "Open settings")
                        Button { model.quit() } label: {
                            Image(systemName: "power")
                                .frame(width: 32, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(IslandButtonStyle())
                        .accessibilityLabel("Quit Computah and stop all tasks")
                        .help("Quit Computah and stop all tasks")
                    }
    }

    private var liveSubtitleHeight: CGFloat { model.active ? 90 : 0 }

    private var liveSubtitles: some View {
        VStack(alignment: .leading, spacing: 8) {
            subtitleRow("You", text: model.liveUserSubtitle.isEmpty ? "Listening for your words…" : model.liveUserSubtitle,
                        color: secondaryInk)
            subtitleRow("Computah", text: model.liveAssistantSubtitle.isEmpty ? "Waiting for assistant subtitles…" : model.liveAssistantSubtitle,
                        color: leaf)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private func subtitleRow(_ speaker: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(speaker).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                .frame(width: 52, alignment: .leading).padding(.top, 2)
            Text(text).font(.system(size: 12)).foregroundStyle(.white)
                .lineLimit(speaker == "You" ? 1 : 2).truncationMode(.head).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("\(speaker): \(text)")
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.active && model.captions.isEmpty {
                Text("What's on your mind?").font(.system(size: 18, weight: .medium))
                Text("Tap \(model.shortcut.title) to talk. Hold it and circle something to ask about your screen.")
                    .font(.system(size: 13)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            } else if !model.active {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(model.captions.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.speaker).font(.system(size: 11, weight: .semibold)).foregroundStyle(row.speaker == "You" ? secondaryInk : leaf)
                                Text(row.text).font(.system(size: 14)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.trailing, 6)
                }.frame(height: model.active ? 100 : 180)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.selected ? "lasso" : "display").foregroundStyle(leaf)
                Text(model.contextLabel).font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.selected {
                    Button("Clear") { model.clearSelection() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(leaf)
                }
            }
            if let notice = model.audioNotice {
                Label(notice, systemImage: "headphones").font(.system(size: 12)).foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.error { errorView(error) }
            if model.tasks.isEmpty {
                Text("Ask me to research or prepare tasks. Independent agents can work at the same time.")
                    .font(.system(size: 11)).foregroundStyle(secondaryInk)
            } else {
                Text("Computer tasks · \(model.runningTaskCount) running")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(secondaryInk)
                ForEach(model.tasks) { session in
                    WorkerCard(session: session, worker: session.worker,
                        onStop: { model.stopTask(session) }, onReview: { model.reviewTask(session) },
                        onAllow: { model.allowTaskApproval(session) },
                        onDecline: { model.declineTaskApproval(session) })
                }
            }
        }
    }

    private var conversationAction: some View {
        HStack {
                Button { model.toggle() } label: {
                    Label(model.active ? "End conversation" : "Start talking", systemImage: model.active ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                        .foregroundStyle(.black).background(leaf, in: Capsule())
                }.buttonStyle(IslandButtonStyle())
                Spacer()
                if model.seconds > 0 { Text(duration).font(.system(size: 11, design: .monospaced)).foregroundStyle(secondaryInk) }
            }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenAI API key").font(.system(size: 13, weight: .medium))
            SecureField("Paste your API key", text: $model.apiKey)
                .textFieldStyle(.roundedBorder).disabled(model.credentialsInUse)
                .accessibilityLabel("OpenAI API key, save in macOS Keychain")
            Text("Save your key in macOS Keychain to load it when Computah opens. Voice and screen reading use your OpenAI API account.")
                .font(.system(size: 12)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.keySaved ? "Replace saved key" : "Save to Keychain") { model.saveAPIKey() }
                    .disabled(model.credentialsInUse || model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove saved key") { model.removeAPIKey() }.disabled(model.credentialsInUse)
            }.controlSize(.small)
            if let notice = model.credentialNotice {
                Text(notice).font(.system(size: 11)).foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Color.white.opacity(0.15))
            Label(model.codexInstalled ? "Codex installed" : "Codex unavailable",
                  systemImage: model.codexInstalled ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 12)).foregroundStyle(model.codexInstalled ? leaf : secondaryInk)
            Text(model.codexInstallationStatus)
                .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            if !model.codexInstalled {
                Button("Check again") { model.refreshCodexStatus() }.controlSize(.small)
            }
            Divider().overlay(Color.white.opacity(0.15))
            Picker("Conversation key", selection: $model.shortcut) {
                ForEach(HotkeyModifier.allCases) { key in Text(key.title).tag(key) }
            }.pickerStyle(.menu).font(.system(size: 12))
            Text("Tap to start or end conversation. Hold and drag to circle. Your conversation key choice is saved.")
                .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            permissionRow("Microphone", allowed: model.microphoneAllowed,
                action: model.requestMicrophoneAccess, openSettings: Permissions.openMicrophoneSettings)
            permissionRow("Screen Recording", allowed: model.screenAllowed,
                checking: model.screenPermissionChecking, unavailable: model.screenPermissionUnavailable,
                action: model.requestScreenAccess, openSettings: Permissions.openScreenRecordingSettings)
            permissionRow("Input Monitoring", allowed: model.inputMonitoringAllowed,
                action: model.requestShortcutAccess, openSettings: Permissions.openInputMonitoringSettings)
            permissionRow("Accessibility (optional)", allowed: model.accessibilityAllowed,
                action: model.requestAccessibilityAccess, openSettings: Permissions.openAccessibilitySettings)
            if !model.inputMonitoringAllowed {
                Button("Renew Input Monitoring") { model.requestShortcutAccess() }.controlSize(.small)
                Text("Refresh only checks access. Choose Allow or Renew, then enable Computah in Input Monitoring. If it is missing, add the built Computah.app with the + button.")
                    .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            if !model.screenAllowed && !model.screenPermissionChecking && !model.screenPermissionUnavailable {
                Text("macOS has not granted this build screen access. A grant from an earlier build may need renewal. Choose Allow to request access, or open Screen Recording settings.")
                    .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                Button("Open Screen Recording settings", action: Permissions.openScreenRecordingSettings)
                    .controlSize(.small)
            }
            if let notice = model.screenPermissionNotice {
                Text(notice).font(.system(size: 11)).foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Refresh permissions") { model.refreshPermissions() }.controlSize(.small)
                Spacer()
                Button("Reopen Computah") { model.relaunch() }.controlSize(.small)
            }
            if let error = model.error { errorView(error) }
            HStack {
                Button("Done") { model.settings = false }.disabled(model.apiKey.isEmpty)
                Spacer()
                Button("Quit Computah") { model.quit() }.buttonStyle(.plain).foregroundStyle(secondaryInk)
            }
            Text(model.buildLabel).font(.system(size: 10)).foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ title: String, allowed: Bool, checking: Bool = false,
                               unavailable: Bool = false, action: @escaping () -> Void,
                               openSettings: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle").foregroundStyle(allowed ? leaf : secondaryInk)
            Text(title).font(.system(size: 12))
            Spacer()
            if checking {
                ProgressView().controlSize(.small)
                Text("Checking").font(.system(size: 11)).foregroundStyle(secondaryInk)
            } else if allowed {
                Text("Allowed").font(.system(size: 11)).foregroundStyle(secondaryInk)
                Button("Settings", action: openSettings).controlSize(.small)
                    .accessibilityLabel("Open \(title) settings")
                    .accessibilityIdentifier("permission.settings.\(title)")
            } else if unavailable {
                Button("Allow", action: action).controlSize(.small)
                    .accessibilityLabel("Allow \(title)")
                    .accessibilityIdentifier("permission.allow.\(title)")
                Button("Settings", action: openSettings).controlSize(.small)
                    .accessibilityLabel("Open \(title) settings")
                    .accessibilityIdentifier("permission.settings.\(title)")
            } else {
                Button("Allow", action: action).controlSize(.small)
                    .accessibilityLabel("Allow \(title)")
                    .accessibilityIdentifier("permission.allow.\(title)")
            }
        }
    }
    private func errorView(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.72, blue: 0.61))
            .fixedSize(horizontal: false, vertical: true)
    }
    private var duration: String { String(format: "%d:%02d", Int(model.seconds) / 60, Int(model.seconds) % 60) }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    let panel: IslandPanel
    let model: AppModel
    private var host: NSHostingView<IslandView>!
    private var observers: [NSObjectProtocol] = []
    private var resizePending = false
    private var display: NSScreen?
    private var revealTimer: Timer?
    private var currentReveal: CGFloat = 1
    private var targetSize: CGSize = .zero
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        host = NSHostingView(rootView: IslandView(model: model, onResize: { [weak self] in self?.resize() }))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.refreshPermissions(); self?.resize() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                Task { @MainActor in
                    guard let self else { return }
                    if let activatedPID, activatedPID != ProcessInfo.processInfo.processIdentifier {
                        self.model.expanded = false
                    }
                    self.model.refreshPermissions()
                    self.resize()
                }
            })
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Clicks in native popovers/menus owned by Computah stay inside its workflow.
                if event.window == nil || event.window === self.panel || event.window?.parent === self.panel { return }
                self.collapseIfOutside()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.collapseIfOutside() }
        }
        resize(); panel.orderFrontRegardless()
    }

    private func collapseIfOutside() {
        guard model.expanded, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        model.expanded = false
    }

    deinit {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
    }

    func resize() {
        guard !resizePending else { return }
        resizePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizePending = false
            guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
            self.display = screen
            let geometry = NotchGeometry(screen: screen)
            let maximumHeight = min(760, screen.frame.height - 48)
            let reviewWidth = min(880, screen.frame.width - 48)
            let content = IslandView(model: self.model, notchWidth: geometry.notchWidth,
                notchHeight: geometry.notchHeight, collapsedHeight: geometry.collapsedHeight,
                maximumHeight: maximumHeight,
                reviewWidth: reviewWidth, onResize: { [weak self] in self?.resize() })
            let width = self.model.reviewing && !self.model.settings ? reviewWidth : max(410, geometry.notchWidth + 192)
            let target = self.model.expanded
                ? CGSize(width: width, height: content.contentHeight + geometry.notchHeight + 8)
                : CGSize(width: content.compactWidth, height: geometry.collapsedHeight)
            let endReveal: CGFloat = self.model.expanded ? 1 : 0
            guard target != self.targetSize else { return }
            self.targetSize = target
            self.panel.hasShadow = self.model.expanded
            self.revealTimer?.invalidate()
            let startSize = self.panel.frame.size
            let startReveal = self.currentReveal
            let animate = self.panel.isVisible && startSize.width > 0
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            @MainActor func present(_ size: CGSize, reveal: CGFloat) {
                self.currentReveal = reveal
                var view = content
                view.revealSize = size
                view.revealProgress = reveal
                // A single driver updates both the clipping viewport and window. Content keeps
                // its final width throughout the reveal, so text never reflows during opening.
                self.host.rootView = view
                self.panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2,
                    y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: false)
                self.host.layoutSubtreeIfNeeded()
                self.panel.displayIfNeeded()
            }
            guard animate else { present(target, reveal: endReveal); return }
            let began = ProcessInfo.processInfo.systemUptime
            self.revealTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    let fraction = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.32)
                    let eased = CGFloat(1 - pow(1 - fraction, 3))
                    present(CGSize(width: startSize.width + (target.width - startSize.width) * eased,
                        height: startSize.height + (target.height - startSize.height) * eased),
                        reveal: startReveal + (endReveal - startReveal) * eased)
                    if fraction >= 1 { timer.invalidate(); self.revealTimer = nil }
                }
            }
        }
    }
}

private struct WorkerCard: View {
    @ObservedObject var session: ComputerTaskSession
    @ObservedObject var worker: CodexWorker
    let onStop: () -> Void
    let onReview: () -> Void
    let onAllow: () -> Void
    let onDecline: () -> Void
    @State private var showFullResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.title).font(.system(size: 13, weight: .semibold)).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(session.state == .starting ? "Starting agent" : worker.status)
                    .font(.system(size: 11)).foregroundStyle(secondaryInk)
                Spacer()
                if session.state.isActive { Button("Stop", action: onStop).controlSize(.small) }
                if !session.approvalPending && (session.state == .review || session.state == .manualReview) {
                    Button("Review", action: onReview).controlSize(.small).tint(leaf)
                }
            }
            if session.approvalPending {
                HStack {
                    if session.approvalCanBeAccepted {
                        Button("Allow once", action: onAllow).controlSize(.small).tint(leaf)
                            .accessibilityLabel("Allow once for \(session.title)")
                    }
                    Button("Don't allow", action: onDecline).controlSize(.small)
                        .accessibilityLabel("Don't allow for \(session.title)")
                }
            }
            if !session.result.isEmpty {
                Text(showFullResult ? session.result : String(session.result.prefix(300)))
                    .font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if session.result.count > 300 {
                    Button(showFullResult ? "Show less" : "Full result") { showFullResult.toggle() }
                        .buttonStyle(IslandButtonStyle()).font(.system(size: 11)).foregroundStyle(leaf)
                }
            }
        }
        .padding(12).background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Keep native button semantics while making the island's plain controls respond to the pointer.
private struct IslandButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : hovered ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
    }
}
