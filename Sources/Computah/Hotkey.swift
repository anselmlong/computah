import AppKit
import ApplicationServices

/// Device masks come from the macOS SDK's IOLLEvent.h.
enum HotkeyModifier: String, CaseIterable, Identifiable {
    case rightShift, rightCommand, rightOption, rightControl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightShift: return "Right Shift"
        case .rightCommand: return "Right Command"
        case .rightOption: return "Right Option"
        case .rightControl: return "Right Control"
        }
    }
    var keyCode: Int64 {
        switch self {
        case .rightShift: return 60
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        }
    }
    var deviceMask: UInt64 {
        switch self {
        case .rightShift: return 0x04
        case .rightCommand: return 0x10
        case .rightOption: return 0x40
        case .rightControl: return 0x2000
        }
    }
    private var aggregateMask: CGEventFlags {
        switch self {
        case .rightShift: return .maskShift
        case .rightCommand: return .maskCommand
        case .rightOption: return .maskAlternate
        case .rightControl: return .maskControl
        }
    }
    func isPressed(flags: CGEventFlags) -> Bool { flags.rawValue & deviceMask != 0 }
    func isSoloPress(flags: CGEventFlags) -> Bool {
        let deviceModifiers: UInt64 = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000
        let aggregateModifiers: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl]
        return isPressed(flags: flags) && flags.rawValue & (deviceModifiers & ~deviceMask) == 0
            && flags.intersection(aggregateModifiers).subtracting(aggregateMask).isEmpty
    }
}

enum HotkeyAction: Equatable { case none, armHold, hold, tap, release, cancel }

struct HotkeyGesture {
    private enum State { case idle, pressed, held, suppressed }
    private var state: State = .idle

    mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags, modifier: HotkeyModifier) -> HotkeyAction {
        let pressed = modifier.isPressed(flags: flags)
        guard keyCode == modifier.keyCode else {
            if state == .pressed || state == .held {
                if !pressed || !modifier.isSoloPress(flags: flags) {
                    state = pressed ? .suppressed : .idle
                    return .cancel
                }
            }
            return .none
        }
        if !pressed {
            let previous = state; state = .idle
            if previous == .pressed { return .tap }
            if previous == .held { return .release }
            return .none
        }
        guard modifier.isSoloPress(flags: flags) else {
            let active = state == .pressed || state == .held
            state = .suppressed
            return active ? .cancel : .none
        }
        guard state == .idle else { return .none }
        state = .pressed; return .armHold
    }

    mutating func holdElapsed() -> HotkeyAction {
        guard state == .pressed else { return .none }
        state = .held; return .hold
    }
    mutating func keyDown() -> HotkeyAction {
        guard state == .pressed || state == .held else { return .none }
        state = .suppressed; return .cancel
    }
    mutating func reset() { state = .idle }
}

@MainActor
final class HotkeyController {
    var modifier: HotkeyModifier = .rightShift {
        didSet { if oldValue != modifier { cancel() } }
    }
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = HotkeyGesture()
    private var holdTask: Task<Void, Never>?
    private var observedEventMask: CGEventMask = 0
    static let requiredEvents: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

    static func containsRequiredEvents(_ mask: CGEventMask) -> Bool { mask & requiredEvents == requiredEvents }

    private func keyboardMaskAvailable() -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return Self.containsRequiredEvents(observedEventMask) }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else { return Self.containsRequiredEvents(observedEventMask) }
        return taps.prefix(Int(count)).contains {
            $0.tappingProcess == ProcessInfo.processInfo.processIdentifier && $0.enabled
                && $0.tapPoint == .cgSessionEventTap && Self.containsRequiredEvents($0.eventsOfInterest)
        }
    }

    func install() -> Bool {
        if let tap {
            if CFMachPortIsValid(tap) {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
                if CGEvent.tapIsEnabled(tap: tap) && keyboardMaskAvailable() { onAvailability?(true); return true }
            }
            uninstall()
        }
        guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else { onAvailability?(false); return false }
        let mask = Self.requiredEvents
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HotkeyController>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { controller.receive(type, event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: opaque) else { onAvailability?(false); return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        let usable = CGEvent.tapIsEnabled(tap: port) && keyboardMaskAvailable()
        onAvailability?(usable)
        return usable
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel(); onDiagnostic?("Shortcut monitor restarted")
            _ = install(); return
        }
        observedEventMask |= 1 << type.rawValue
        if Self.containsRequiredEvents(observedEventMask) { onAvailability?(true) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown {
            if key == 53 { cancel() }
            else { dispatch(gesture.keyDown()) }
            return
        }
        if key == modifier.keyCode {
            onDiagnostic?("\(modifier.title) flags 0x\(String(event.flags.rawValue, radix: 16))")
        }
        dispatch(gesture.flagsChanged(keyCode: key, flags: event.flags, modifier: modifier))
    }

    private func dispatch(_ action: HotkeyAction) {
        switch action {
        case .none: break
        case .armHold:
            holdTask?.cancel()
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled, let self else { return }
                self.dispatch(self.gesture.holdElapsed())
            }
        case .hold: onDiagnostic?("\(modifier.title) held. Drag to circle."); onHold?()
        case .tap: holdTask?.cancel(); onDiagnostic?("\(modifier.title) tapped"); onTap?()
        case .release: holdTask?.cancel(); onDiagnostic?("\(modifier.title) released"); onRelease?()
        case .cancel: holdTask?.cancel(); onDiagnostic?("Circle gesture cancelled by another key"); onCancel?()
        }
    }

    func uninstall() {
        cancel()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; observedEventMask = 0
        onAvailability?(false)
    }

    private func cancel() { gesture.reset(); holdTask?.cancel(); onCancel?() }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SelectionController {
    private var window: NSWindow?
    private var canvas: LassoView?
    private var screen: NSScreen?
    var onSelection: ((NSScreen, CGRect) -> Void)?

    func show() {
        cancel()
        guard let display = ScreenContext.currentScreen else { return }
        screen = display
        let window = SelectionPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = .screenSaver; window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = LassoView(frame: CGRect(origin: .zero, size: display.frame.size))
        view.onComplete = { [weak self] in self?.finish() }
        window.contentView = view
        canvas = view; self.window = window; window.orderFrontRegardless()
        window.makeFirstResponder(view)
    }

    func finish() {
        let bounds = canvas?.selectionBounds
        let display = screen
        cancel()
        if let bounds, let display, bounds.width >= 8, bounds.height >= 8 { onSelection?(display, bounds) }
    }

    func cancel() { window?.orderOut(nil); window = nil; canvas = nil; screen = nil }
}

final class LassoView: NSView {
    var onComplete: (() -> Void)?
    private var points: [CGPoint] = []
    var selectionBounds: CGRect? {
        guard let first = points.first, points.count > 2 else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, p in
            CGRect(x: min(rect.minX, p.x), y: min(rect.minY, p.y),
                   width: max(rect.maxX, p.x) - min(rect.minX, p.x),
                   height: max(rect.maxY, p.y) - min(rect.minY, p.y))
        }
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) { points = [convert(event.locationInWindow, from: nil)]; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { points.append(convert(event.locationInWindow, from: nil)); needsDisplay = true }
    override func mouseUp(with event: NSEvent) { points.append(convert(event.locationInWindow, from: nil)); onComplete?() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill(); bounds.fill()
        let hint = "Circle something, then ask. Esc to cancel."
        hint.draw(at: CGPoint(x: 32, y: bounds.height - 80), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white])
        guard let first = points.first else { return }
        let path = NSBezierPath(); path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round
        NSColor(calibratedRed: 0.82, green: 0.95, blue: 0.55, alpha: 1).setStroke(); path.stroke()
    }
}
