import AppKit
import AVFoundation
import ApplicationServices
import ScreenCaptureKit

enum ScreenAccessStatus: Equatable, Sendable {
    case available
    case denied
    case unavailable(String)
}

// ScreenCaptureKit can take several seconds to answer, and a stalled service must not
// leave the permission row checking forever. Its late callback cannot finish twice.
private final class ScreenAccessCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ScreenAccessStatus, Never>?

    init(_ continuation: CheckedContinuation<ScreenAccessStatus, Never>) {
        self.continuation = continuation
    }

    func finish(_ status: ScreenAccessStatus) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: status)
    }
}

struct PermissionStatus {
    let microphoneAllowed: Bool
    let screenAllowed: Bool
    let inputMonitoringAllowed: Bool
    let accessibilityAllowed: Bool
}

@MainActor
enum Permissions {
    private static var lastScreenAccess: ScreenAccessStatus?
    private static var screenProbeTask: Task<ScreenAccessStatus, Never>?
    static let screenRecordingHelp = "Allow Computah in System Settings → Privacy & Security → Screen & System Audio Recording, then return to Computah and refresh permissions. If macOS asks you to quit and reopen Computah, reopen it to apply access."
    static func read() -> PermissionStatus {
        .init(microphoneAllowed: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              screenAllowed: CGPreflightScreenCaptureAccess(),
              inputMonitoringAllowed: CGPreflightListenEventAccess(),
              accessibilityAllowed: AXIsProcessTrusted())
    }

    static func refresh() -> PermissionStatus { read() }

    static func checkScreenAccess(allowPrompt: Bool = false) async -> ScreenAccessStatus {
        await checkScreenAccess(allowPrompt: allowPrompt, preflight: CGPreflightScreenCaptureAccess(),
                                probe: probeScreenAccess)
    }

    static func checkScreenAccess(allowPrompt: Bool, preflight: Bool,
                                  probe: @escaping @MainActor () async -> ScreenAccessStatus) async -> ScreenAccessStatus {
        // Enumerating shareable content can display consent. Foreground notifications,
        // Refresh, and diagnostics must never initiate that request.
        guard allowPrompt else {
            if preflight { lastScreenAccess = .available; return .available }
            return lastScreenAccess ?? .unavailable("Screen access is not confirmed. Choose Allow to check it once.")
        }
        // Multiple clicks share one consent-producing operation.
        if let screenProbeTask { return await screenProbeTask.value }
        let task = Task { await probe() }
        screenProbeTask = task
        let status = await task.value
        recordScreenAccess(status)
        screenProbeTask = nil
        return status
    }

    static func recordScreenAccess(_ status: ScreenAccessStatus) {
        lastScreenAccess = status
    }

    static func canAttemptScreenCapture(preflight: Bool? = nil) -> Bool {
        // A denied grant remains latched until Settings preflight confirms a new grant
        // or the user explicitly chooses Allow. Automatic voice captures cannot re-prompt.
        if preflight ?? CGPreflightScreenCaptureAccess() { lastScreenAccess = .available; return true }
        return lastScreenAccess == .available
    }

    private static func probeScreenAccess() async -> ScreenAccessStatus {
        // Check the API used by capture itself. The CoreGraphics preflight result can
        // remain false while ScreenCaptureKit already has usable access. This only
        // enumerates metadata: it never captures, encodes, saves, or sends screen pixels.
        await withCheckedContinuation { continuation in
            let check = ScreenAccessCheck(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
                check.finish(.unavailable("Screen access check timed out. Try Refresh permissions again."))
            }
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                check.finish(screenAccessStatus(error: error, displayCount: content?.displays.count ?? 0))
            }
        }
    }

    nonisolated static func screenAccessStatus(error: Error?, displayCount: Int) -> ScreenAccessStatus {
        if let error {
            if isScreenAccessDenied(error) { return .denied }
            return .unavailable("Screen capture is temporarily unavailable. Try Refresh permissions again.")
        }
        guard displayCount > 0 else {
            return .unavailable("No display is available for screen capture. Try Refresh permissions again.")
        }
        return .available
    }

    nonisolated static func isScreenAccessDenied(_ error: Error) -> Bool {
        var platform = error as NSError
        for _ in 0..<8 {
            if platform.domain == SCStreamErrorDomain && platform.code == SCStreamError.Code.userDeclined.rawValue {
                return true
            }
            guard let underlying = platform.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            platform = underlying
        }
        return false
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            if !allowed { openMicrophoneSettings() }
            return allowed
        case .denied, .restricted:
            openMicrophoneSettings()
            return false
        @unknown default:
            openMicrophoneSettings()
            return false
        }
    }

    @discardableResult
    static func requestScreenRecording() async -> ScreenAccessStatus {
        // ScreenCaptureKit performs its own permission request when needed. Open the
        // privacy pane only for a confirmed denial, not a stale preflight or service error.
        let status = await checkScreenAccess(allowPrompt: true)
        if status == .denied { openScreenRecordingSettings() }
        return status
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        _ = CGRequestListenEventAccess()
        let allowed = CGPreflightListenEventAccess()
        if !allowed { openInputMonitoringSettings() }
        return allowed
    }

    static func openScreenRecordingSettings() { openPrivacyPane("Privacy_ScreenCapture") }
    static func openMicrophoneSettings() { openPrivacyPane("Privacy_Microphone") }
    static func openInputMonitoringSettings() { openPrivacyPane("Privacy_ListenEvent") }
    static func openAccessibilitySettings() { openPrivacyPane("Privacy_Accessibility") }

    private static func openPrivacyPane(_ pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        if !NSWorkspace.shared.open(url) {
            // Privacy deep links vary between macOS releases. Open System Settings as a fallback.
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                                               configuration: .init()) { _, _ in }
        }
    }
}
