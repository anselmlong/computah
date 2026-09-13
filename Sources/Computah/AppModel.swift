import SwiftUI
import AVFoundation
import ApplicationServices
import Combine

enum CompanionState: String {
    case idle = "Ready when you are"
    case connecting = "Connecting"
    case listening = "I'm listening"
    case speaking = "Speaking"
    case looking = "Reading your screen"
    case stopped = "Conversation ended"
    case failed = "Needs attention"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: CompanionState = .idle
    @Published var expanded = false
    @Published var settings = false
    @Published var reviewing = false
    @Published var apiKey = ""
    @Published var keySaved = false
    @Published var credentialNotice: String?
    @Published var level: Float = 0
    @Published var captions: [(speaker: String, text: String)] = []
    @Published var error: String?
    @Published var audioNotice: String?
    @Published var voiceDiagnostics = ""
    @Published var gestureDiagnostics = ""
    @Published var contextLabel = "Screen context is off until you start"
    @Published var findings = ""
    @Published var selected = false
    @Published var shortcutAvailable = false
    @Published var inputMonitoringAllowed = Permissions.hasInputMonitoringAccess()
    @Published var accessibilityAllowed = AXIsProcessTrusted()
    @Published var shortcut: HotkeyModifier = .rightShift {
        didSet {
            hotkey.modifier = shortcut
            UserDefaults.standard.set(shortcut.rawValue, forKey: "conversationShortcut")
        }
    }
    @Published var screenAllowed = CGPreflightScreenCaptureAccess()
    @Published var screenPermissionChecking = false
    @Published var screenPermissionUnavailable = false
    @Published var screenPermissionNotice: String?
    @Published var microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var seconds: Double = 0
    @Published var active = false
    @Published var reading = false
    let live = LiveConnection()
    let audio = AudioEngine()
    let hotkey = HotkeyController()
    let selection = SelectionController()
    let taskManager = ComputerTaskManager()
    var codexInstalled: Bool { CodexWorkerProtocol.isInstalled }
    var codexInstallationStatus: String { CodexWorkerProtocol.installationStatus }
    var tasks: [ComputerTaskSession] { taskManager.sessions }
    var runningTaskCount: Int { tasks.filter { $0.state.isActive }.count }
    var credentialsInUse: Bool { active }
    private var ledger = TranscriptLedger()
    private var generation = UUID()
    private var captureTask: Task<ScreenSnapshot, Error>?
    private var analysisTask: Task<Void, Never>?
    private var pendingStart: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var lastInputEnd = -Double.infinity
    private var lastUserArrival = Date.distantPast
    private var snapshot: ScreenSnapshot?
    private var selectedCrop: Data?
    private var handled: Set<String> = []
    private var pendingDelegations: Set<String> = []
    private var lastRoutedText = ""
    private var lastRoutedKind: QuestionRoute?
    private struct TaskBatch {
        let voiceSessionID: UUID
        var delegationIDs: Set<String>
        var sessionIDs: Set<UUID> = []
        var reported = false
    }
    private var batches: [UUID: TaskBatch] = [:]
    private var sessionBatches: [UUID: UUID] = [:]
    private var lastBatchID: UUID?
    private var lastBrowserAcknowledgment = ""
    private struct WorkerRequestKey: Hashable {
        let taskID: UUID
        let requestID: String
    }
    private var workerQuestionQueue: [WorkerQuestionEnvelope] = []
    private var activeWorkerQuestion: WorkerQuestionEnvelope?
    private var workerQuestionAnswers: [WorkerRequestKey: [String: [String]]] = [:]
    private var workerQuestionOutputObserved = false
    private var workerQuestionAnswerReady = false
    private var workerQuestionArmTask: Task<Void, Never>?
    private var managerObservation: AnyCancellable?
    private let credentialStore: any CredentialStore
    private var savedKey: String?
    private let enableShortcuts: Bool
    private var permissionTask: Task<Void, Never>?
    private var permissionGeneration = UUID()
    private var shortcutRetryTask: Task<Void, Never>?

    init(enableShortcuts: Bool = true, loadCredentials: Bool = true,
         credentialStore: any CredentialStore = KeychainCredentialStore()) {
        self.enableShortcuts = enableShortcuts
        self.credentialStore = credentialStore
        managerObservation = taskManager.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        taskManager.onResult = { [weak self] session, result in self?.taskFinished(session, result: result, review: false) }
        taskManager.onReview = { [weak self] session, result in self?.taskFinished(session, result: result, review: true) }
        taskManager.onQuestion = { [weak self] session, request in self?.taskAskedQuestion(session, request: request) }
        if loadCredentials {
            do {
                if let key = try credentialStore.load() { apiKey = key; savedKey = key; keySaved = true }
            } catch { credentialNotice = error.localizedDescription }
        }
        live.onEvent = { [weak self] in self?.receive($0) }
        live.onFailure = { [weak self] text in self?.fail(text) }
        live.onDiagnostics = { [weak self] diagnostic in
            self?.voiceDiagnostics = "Sent \(diagnostic.inputChunks) chunks, \(diagnostic.inputBytes) bytes. Received \(diagnostic.outputChunks) chunks, \(diagnostic.outputBytes) bytes. Last event: \(diagnostic.lastEventType)"
        }
        audio.onAudio = { [weak self] data in MainActor.assumeIsolated { self?.live.audio(data) } }
        audio.onLevel = { [weak self] level in MainActor.assumeIsolated { self?.level = level } }
        audio.onPlaybackState = { [weak self] speaking in
            guard let self, self.active else { return }
            self.state = speaking ? .speaking : (self.reading ? .looking : .listening)
            if !speaking, self.workerQuestionOutputObserved, self.activeWorkerQuestion != nil {
                self.workerQuestionAnswerReady = true
                self.workerQuestionArmTask?.cancel()
            }
        }
        audio.onFailure = { [weak self] in self?.fail($0) }
        audio.onNotice = { [weak self] notice in self?.audioNotice = notice.isEmpty ? nil : notice }
        hotkey.onAvailability = { [weak self] usable in
            guard let self, self.shortcutAvailable != usable else { return }
            self.shortcutAvailable = usable
        }
        hotkey.onDiagnostic = { [weak self] text in self?.gestureDiagnostics = text }
        hotkey.onTap = { [weak self] in self?.toggle() }
        hotkey.onHold = { [weak self] in self?.selection.show() }
        hotkey.onRelease = { [weak self] in self?.selection.finish() }
        hotkey.onCancel = { [weak self] in self?.selection.cancel() }
        selection.onSelection = { [weak self] screen, rect in self?.circle(screen: screen, rect: rect) }
        shortcut = HotkeyModifier(rawValue: UserDefaults.standard.string(forKey: "conversationShortcut") ?? "") ?? .rightShift
        hotkey.modifier = shortcut
        shortcutAvailable = enableShortcuts ? hotkey.install() : false
        inputMonitoringAllowed = Permissions.read().inputMonitoringAllowed
        if enableShortcuts { refreshPermissions() }
    }

    var buildLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return "Development build"
        }
        let date = Bundle.main.object(forInfoDictionaryKey: "ComputahBuildDate") as? String ?? ""
        return date.isEmpty ? "Build \(version)" : "Build \(version). \(date)"
    }

    var liveUserSubtitle: String { captions.last(where: { $0.speaker == "You" })?.text ?? "" }
    var liveAssistantSubtitle: String { captions.last(where: { $0.speaker == "Computah" })?.text ?? "" }

    func toggle() {
        expanded = true
        if active { stop(); return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { settings = true; return }
        if savedKey != apiKey.trimmingCharacters(in: .whitespacesAndNewlines), !persistCurrentKey() {
            settings = true; return
        }
        active = true; state = .connecting; error = nil; audioNotice = nil; voiceDiagnostics = "Starting voice connection"; findings = ""; seconds = 0
        ledger = TranscriptLedger(); captions = []; handled = []; pendingDelegations = []
        lastInputEnd = -.infinity; lastUserArrival = .distantPast; lastRoutedText = ""
        generation = UUID()
        let token = generation
        pendingStart = Task { [weak self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.microphoneAllowed = allowed
            guard allowed else { self.fail("Allow Microphone access in macOS settings, then start again."); return }
            self.live.connect(key: self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Ending the voice session leaves independent computer work running.
    func stop() {
        generation = UUID(); active = false; reading = false
        pendingStart?.cancel(); analysisTask?.cancel(); captureTask?.cancel()
        selectionTask?.cancel(); selection.cancel()
        audio.stop(); live.close(); level = 0; state = .stopped
        snapshot = nil; selected = false; selectedCrop = nil; contextLabel = "Screen context is off until you start"
        pendingDelegations.removeAll(); lastBatchID = nil
        workerQuestionQueue.removeAll(); activeWorkerQuestion = nil
        workerQuestionOutputObserved = false; workerQuestionAnswerReady = false
        workerQuestionArmTask?.cancel(); workerQuestionArmTask = nil
    }

    func stopTask(_ session: ComputerTaskSession) { session.stop() }
    func stopAllTasks() { taskManager.stopAll() }

    @discardableResult
    func showBrowser(target: String? = nil) async -> String {
        guard !Task.isCancelled else { return "The task request was cancelled." }
        guard codexInstalled else { return codexInstallationStatus }
        let session: ComputerTaskSession
        if let target, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let exact = tasks.filter { $0.title.caseInsensitiveCompare(target) == .orderedSame }
            let matches = exact.isEmpty ? tasks.filter { $0.title.localizedCaseInsensitiveContains(target) } : exact
            guard matches.count == 1, let match = matches.first else {
                return matches.isEmpty ? "No task named \(target) was found. Ask which task's browser to show." : "Several tasks match \(target). Ask the user to choose one in the task list."
            }
            session = match
        } else {
            guard let latest = tasks.last else { return "There is no Codex task to show yet." }
            session = latest
        }
        reviewing = false
        do {
            let focused = try await session.showBrowser()
            return focused ? "Opened the task workspace for \(session.title). Existing work continues." : "The task workspace could not be opened."
        } catch { return error.localizedDescription }
    }

    func openBrowser(_ session: ComputerTaskSession) {
        reviewing = false
        Task {
            do { _ = try await session.showBrowser() }
            catch { self.error = error.localizedDescription; self.expanded = true }
        }
    }
    func reviewTask(_ session: ComputerTaskSession) {
        reviewing = false; settings = false; expanded = true
        Task {
            do { try await session.review() }
            catch { self.error = error.localizedDescription }
        }
    }

    func allowTaskApproval(_ session: ComputerTaskSession) {
        do {
            try session.allowPendingApproval()
            error = nil
        } catch {
            self.error = error.localizedDescription
            expanded = true
        }
    }

    func declineTaskApproval(_ session: ComputerTaskSession) {
        session.declinePendingApproval()
    }

    func answerTaskQuestion(_ session: ComputerTaskSession, requestID: String,
                            answers: [String: [String]]) {
        do {
            try session.answerPendingQuestion(requestID: requestID, answers: answers)
            clearVoiceQuestions(taskID: session.id, requestID: requestID)
            error = nil
            presentNextWorkerQuestion()
        } catch {
            self.error = error.localizedDescription
            expanded = true
        }
    }

    func refreshCodexStatus() { objectWillChange.send() }

    private func taskAskedQuestion(_ session: ComputerTaskSession, request: CodexQuestionRequest) {
        expanded = true
        enqueueVoiceQuestions(session: session, request: request)
        presentNextWorkerQuestion()
    }

    private func enqueueVoiceQuestions(session: ComputerTaskSession, request: CodexQuestionRequest) {
        // Keep mixed requests together in the local form so a private answer never
        // causes the user to repeat answers already spoken for the same request.
        guard !request.questions.contains(where: \.isSecret) else { return }
        let key = WorkerRequestKey(taskID: session.id, requestID: request.id)
        let answered = workerQuestionAnswers[key] ?? [:]
        for question in request.questions where !question.isSecret && answered[question.id] == nil {
            let envelope = WorkerQuestionEnvelope(taskID: session.id, taskTitle: session.title,
                requestID: request.id, questionID: question.id, prompt: question.prompt,
                options: question.options.map(\.label))
            guard envelope.isValid, activeWorkerQuestion != envelope,
                  !workerQuestionQueue.contains(envelope) else { continue }
            workerQuestionQueue.append(envelope)
        }
    }

    private func rebuildWorkerQuestionQueue() {
        workerQuestionQueue.removeAll()
        activeWorkerQuestion = nil
        workerQuestionOutputObserved = false
        workerQuestionAnswerReady = false
        let currentKeys = Set(tasks.flatMap { session in
            session.pendingQuestions.map { WorkerRequestKey(taskID: session.id, requestID: $0.id) }
        })
        workerQuestionAnswers = workerQuestionAnswers.filter { currentKeys.contains($0.key) }
        for session in tasks {
            for request in session.pendingQuestions { enqueueVoiceQuestions(session: session, request: request) }
        }
    }

    private func presentNextWorkerQuestion() {
        guard active, activeWorkerQuestion == nil else { return }
        while !workerQuestionQueue.isEmpty {
            let next = workerQuestionQueue.removeFirst()
            guard pendingQuestion(next) != nil else { continue }
            activeWorkerQuestion = next
            workerQuestionOutputObserved = false
            workerQuestionAnswerReady = false
            if live.askWorkerQuestion(next) { return }
            activeWorkerQuestion = nil
            workerQuestionQueue.insert(next, at: 0)
            return
        }
    }

    private func observeWorkerQuestionOutput() {
        guard activeWorkerQuestion != nil, !workerQuestionAnswerReady else { return }
        workerQuestionOutputObserved = true
        workerQuestionArmTask?.cancel()
        workerQuestionArmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.activeWorkerQuestion != nil,
                  self.workerQuestionOutputObserved else { return }
            self.workerQuestionAnswerReady = true
        }
    }

    private func pendingQuestion(_ envelope: WorkerQuestionEnvelope) -> CodexQuestion? {
        tasks.first(where: { $0.id == envelope.taskID })?.pendingQuestions
            .first(where: { $0.id == envelope.requestID })?.questions
            .first(where: { $0.id == envelope.questionID })
    }

    private func clearVoiceQuestions(taskID: UUID, requestID: String) {
        let key = WorkerRequestKey(taskID: taskID, requestID: requestID)
        workerQuestionAnswers.removeValue(forKey: key)
        workerQuestionQueue.removeAll { $0.taskID == taskID && $0.requestID == requestID }
        if activeWorkerQuestion?.taskID == taskID && activeWorkerQuestion?.requestID == requestID {
            activeWorkerQuestion = nil
            workerQuestionOutputObserved = false
            workerQuestionAnswerReady = false
            workerQuestionArmTask?.cancel()
        }
    }

    private func clearVoiceQuestions(taskID: UUID) {
        workerQuestionAnswers = workerQuestionAnswers.filter { $0.key.taskID != taskID }
        workerQuestionQueue.removeAll { $0.taskID == taskID }
        if activeWorkerQuestion?.taskID == taskID {
            activeWorkerQuestion = nil
            workerQuestionOutputObserved = false
            workerQuestionAnswerReady = false
            workerQuestionArmTask?.cancel()
            presentNextWorkerQuestion()
        }
    }

    private func routeWorkerAnswer(_ utterance: String, token: UUID) async -> Bool {
        guard workerQuestionAnswerReady, let question = activeWorkerQuestion,
              pendingQuestion(question) != nil else { return false }
        do {
            let decision = try await WorkerAnswerService.classify(utterance: utterance,
                question: question, key: apiKey)
            guard !Task.isCancelled, generation == token, activeWorkerQuestion == question else { return true }
            switch decision.kind {
            case .answer:
                acceptWorkerVoiceAnswer(decision.answer, for: question)
                return true
            case .ambiguous:
                workerQuestionAnswerReady = false
                workerQuestionOutputObserved = false
                if !live.askWorkerQuestion(question) {
                    activeWorkerQuestion = nil
                    workerQuestionQueue.insert(question, at: 0)
                }
                return true
            case .unrelated:
                return false
            }
        } catch is CancellationError {
            return true
        } catch {
            self.error = error.localizedDescription
            append("I couldn't safely match that response to the waiting Codex question. Please repeat the answer, or type it in the task card.", speak: true)
            return true
        }
    }

    private func acceptWorkerVoiceAnswer(_ answer: String, for question: WorkerQuestionEnvelope) {
        guard let session = tasks.first(where: { $0.id == question.taskID }),
              let request = session.pendingQuestions.first(where: { $0.id == question.requestID }),
              request.questions.contains(where: { $0.id == question.questionID }) else {
            clearVoiceQuestions(taskID: question.taskID, requestID: question.requestID)
            presentNextWorkerQuestion()
            return
        }
        let key = WorkerRequestKey(taskID: question.taskID, requestID: question.requestID)
        workerQuestionAnswers[key, default: [:]][question.questionID] = [answer]
        activeWorkerQuestion = nil
        workerQuestionOutputObserved = false
        workerQuestionAnswerReady = false
        workerQuestionArmTask?.cancel()
        let answers = workerQuestionAnswers[key] ?? [:]
        if request.questions.allSatisfy({ answers[$0.id] != nil }) {
            answerTaskQuestion(session, requestID: request.id, answers: answers)
        } else {
            enqueueVoiceQuestions(session: session, request: request)
            presentNextWorkerQuestion()
        }
    }

    func saveAPIKey() {
        guard !credentialsInUse else { return }
        _ = persistCurrentKey()
    }
    @discardableResult
    private func persistCurrentKey() -> Bool {
        do {
            let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try credentialStore.save(normalized)
            apiKey = normalized
            savedKey = apiKey; keySaved = true; credentialNotice = "Saved in macOS Keychain."
            return true
        } catch { credentialNotice = error.localizedDescription; return false }
    }

    func removeAPIKey() {
        guard !credentialsInUse else { return }
        do { try credentialStore.remove(); apiKey = ""; savedKey = nil; keySaved = false; credentialNotice = "Removed from macOS Keychain." }
        catch { credentialNotice = error.localizedDescription }
    }

    func quit() { shortcutRetryTask?.cancel(); permissionTask?.cancel(); stop(); taskManager.stopAll(); apiKey = ""; NSApp.terminate(nil) }

    private func fail(_ message: String) { stop(); error = message; state = .failed; expanded = true }

    func requestMicrophoneAccess() {
        Task { [weak self] in
            _ = await Permissions.requestMicrophone()
            self?.refreshPermissions()
        }
    }
    func requestScreenAccess() {
        Task { [weak self] in
            _ = await Permissions.requestScreenRecording()
            self?.refreshPermissions()
        }
    }
    func requestShortcutAccess() {
        _ = Permissions.requestInputMonitoring()
        refreshPermissions()
    }
    func requestAccessibilityAccess() {
        _ = Permissions.requestAccessibility()
        refreshPermissions()
    }
    func refreshPermissions() {
        let status = Permissions.read()
        microphoneAllowed = status.microphoneAllowed
        accessibilityAllowed = status.accessibilityAllowed
        shortcutAvailable = enableShortcuts ? hotkey.install() : false
        inputMonitoringAllowed = status.inputMonitoringAllowed
        retryShortcutIfNeeded()
        permissionTask?.cancel(); permissionGeneration = UUID()
        let token = permissionGeneration
        screenPermissionChecking = true
        permissionTask = Task { [weak self] in
            let access = await Permissions.checkScreenAccess()
            guard !Task.isCancelled, let self, self.permissionGeneration == token else { return }
            self.screenPermissionChecking = false
            self.screenPermissionUnavailable = false; self.screenPermissionNotice = nil
            switch access {
            case .available: self.screenAllowed = true
            case .denied: self.screenAllowed = false
            case .unavailable(let message):
                self.screenPermissionUnavailable = true; self.screenPermissionNotice = message
            }
        }
    }

    private func retryShortcutIfNeeded() {
        shortcutRetryTask?.cancel()
        guard enableShortcuts, !shortcutAvailable else { return }
        shortcutRetryTask = Task { [weak self] in
            for delay in [200, 800] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                let current = Permissions.read()
                self.inputMonitoringAllowed = current.inputMonitoringAllowed
                guard current.inputMonitoringAllowed || current.accessibilityAllowed else { continue }
                if self.hotkey.install() { self.shortcutAvailable = true; return }
                self.shortcutAvailable = false
            }
        }
    }

    func relaunch() {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else {
            error = "Quit and reopen the built Computah.app to refresh macOS permissions."; return
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "sleep 1; exec /usr/bin/open -n \"$1\"", "computah-relaunch", bundle.path]
        helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
        do { try helper.run(); quit() }
        catch { self.error = "Computah could not reopen itself. Quit and open it again manually." }
    }

    func clearSelection() {
        invalidateScreenAnalysis()
        selectionTask?.cancel()
        selected = false; selectedCrop = nil; snapshot = nil; findings = ""
        contextLabel = active ? "Your current display is included with each question" : "Screen context is off until you start"
    }

    private func circle(screen: NSScreen, rect: CGRect) {
        invalidateScreenAnalysis()
        selected = true; expanded = true; contextLabel = "Capturing your selection"; error = nil
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            do {
                let shot = try await ScreenContext.capture(screen: screen, selection: rect)
                guard let self, !Task.isCancelled else { return }
                self.selectedCrop = shot.crop
                self.snapshot = shot; self.contextLabel = "Circled region ready. Ask about it."
                self.findings = ""
                if !self.active { self.toggle() }
                else { self.live.send(LiveProtocol.append("The user circled a new region. Screen questions require fresh findings from the client.")) }
            } catch {
                guard !Task.isCancelled else { return }
                self?.selected = false; self?.error = error.localizedDescription
            }
        }
    }

    private func invalidateScreenAnalysis() {
        analysisTask?.cancel(); captureTask?.cancel(); captureTask = nil
        lastRoutedText = ""; reading = false
        if active && state == .looking { state = .listening }
    }

    private func receive(_ event: [String: Any]) {
        let type = event["type"] as? String ?? ""
        if type == "session.closed" {
            if let usage = event["usage"] as? [String: Any] { seconds = usage["seconds"] as? Double ?? seconds }
            if active { stop() }; return
        }
        guard active else { return }
        switch type {
        case "session.started":
            do {
                try audio.start(); state = .listening
                contextLabel = selected ? "Circled region ready. Ask about it." : "Your current display is included with each question"
                live.send(LiveProtocol.append("Screen reading is available when screen permission is granted. Answer simple questions directly. Delegate screen questions or computer tasks. Computer tasks use the normal installed Codex CLI and the user’s signed-in Codex account: \(codexInstalled ? "Codex is installed." : codexInstallationStatus) Never claim an action occurred when unavailable. Never submit applications; wait for explicit user review."))
                if runningTaskCount > 0 { append("Independent computer tasks are running:\n" + taskContext) }
                rebuildWorkerQuestionQueue()
                presentNextWorkerQuestion()
            } catch { fail("Microphone could not start: \(error.localizedDescription)") }
        case "session.output_audio.delta":
            observeWorkerQuestionOutput()
            if let encoded = event["delta"] as? String, let data = Data(base64Encoded: encoded) {
                audio.play(data)
            }
        case "session.input_transcript.delta", "session.output_transcript.delta":
            guard ledger.ingest(event) else { return }
            captions = ledger.captions
            if type == "session.input_transcript.delta" { userSpoke(event) }
            else { observeWorkerQuestionOutput() }
        case "session.delegation.created":
            guard let delegation = event["delegation"] as? [String: Any],
                  delegation["target"] as? String == "client",
                  let id = delegation["id"] as? String, handled.insert(id).inserted else { return }
            pendingDelegations.insert(id)
            scheduleAnalysis()
        case "session.usage.updated":
            if let usage = event["usage"] as? [String: Any] { seconds = usage["seconds"] as? Double ?? seconds }
        case "error":
            let server = event["error"] as? [String: Any]
            let code = server?["code"] as? String ?? "unknown_error"
            fail("GPT-Live rejected a request (\(code)). Check your API access, then reconnect.")
        default: break
        }
    }

    private func userSpoke(_ event: [String: Any]) {
        let start = event["start_ms"] as? Double ?? lastInputEnd
        let end = event["end_ms"] as? Double ?? start
        let newUtterance = start - lastInputEnd > 1000 || Date().timeIntervalSince(lastUserArrival) > 1.5
        lastInputEnd = max(lastInputEnd, end); lastUserArrival = Date()
        if newUtterance {
            lastRoutedText = ""; findings = ""
            snapshot = nil; captureTask?.cancel()
            contextLabel = "Capturing your current display"
            let display = ScreenContext.currentScreen
            let crop = selected ? selectedCrop : nil
            captureTask = Task {
                let fresh = try await ScreenContext.capture(screen: display)
                return ScreenSnapshot(jpeg: fresh.jpeg, crop: crop, capturedAt: fresh.capturedAt, displayName: fresh.displayName)
            }
        }
        scheduleAnalysis()
    }

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        let token = generation
        analysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled, let self, self.active, self.generation == token else { return }
            defer {
                if !Task.isCancelled, self.generation == token {
                    self.reading = false
                    if self.active && self.state != .speaking { self.state = .listening }
                }
            }
            let question = self.ledger.latestUserText
            guard !question.isEmpty else { return }
            if await self.routeWorkerAnswer(question, token: token) {
                self.lastRoutedText = question
                return
            }
            if question == self.lastRoutedText {
                if self.lastRoutedKind == .showBrowser {
                    self.finishDelegations(self.lastBrowserAcknowledgment.isEmpty ? "No task browser focus was confirmed." : self.lastBrowserAcknowledgment)
                } else if self.lastRoutedKind == .task, let batch = self.lastBatchID {
                    self.linkDelegations(self.pendingDelegations, to: batch); self.pendingDelegations.removeAll()
                } else if !self.findings.isEmpty { self.finishDelegations(self.findings) }
                else { self.finishDelegations("Answer the user's simple question directly. No computer action was needed.") }
                return
            }
            do {
                let routeSnapshot: ScreenSnapshot?
                if let selectedShot = self.snapshot, self.selected { routeSnapshot = selectedShot }
                else if let capture = self.captureTask { routeSnapshot = try? await capture.value }
                else { routeSnapshot = nil }
                guard !Task.isCancelled, self.generation == token else { return }
                if let routeSnapshot {
                    self.snapshot = routeSnapshot
                    self.contextLabel = self.selected ? "Current display and circled region included" : "\(routeSnapshot.displayName) included"
                } else { self.contextLabel = "Screen recording unavailable. Voice still works." }
                let route = try await RouteService.classify(question: question, history: self.ledger.context() + "\nComputer tasks:\n" + self.taskContext, key: self.apiKey, snapshot: routeSnapshot)
                guard !Task.isCancelled, self.generation == token else { return }
                self.lastRoutedKind = route.kind
                switch route.kind {
                case .direct:
                    self.lastRoutedText = question
                    self.finishDelegations("Answer this conversational question directly. No screen reading or computer action was performed.")
                case .showBrowser:
                    let result = await self.showBrowser(target: route.targetTask)
                    guard !Task.isCancelled, self.generation == token else { return }
                    self.lastRoutedText = question
                    self.lastBrowserAcknowledgment = result
                    if self.pendingDelegations.isEmpty { self.append(result) }
                    else { self.finishDelegations(result) }
                case .screen:
                    let context = try await self.readScreen(question: question, token: token)
                    guard !Task.isCancelled, self.generation == token else { return }
                    self.lastRoutedText = question
                    if self.pendingDelegations.isEmpty { self.append(context) }
                    else { self.finishDelegations(context) }
                case .task:
                    guard self.codexInstalled else {
                        self.settings = true; self.expanded = true
                        self.lastBatchID = nil
                        self.lastRoutedText = question
                        let message = self.codexInstallationStatus + " Voice can continue. No computer task was started."
                        self.findings = message
                        if self.pendingDelegations.isEmpty { self.append(message, speak: true) }
                        else { self.finishDelegations(message) }
                        return
                    }
                    var context = self.ledger.context()
                    if route.requiresScreen { context += "\n" + (try await self.readScreen(question: question, token: token)) }
                    guard !Task.isCancelled, self.generation == token else { return }
                    self.lastRoutedText = question
                    let requested = route.tasks.isEmpty ? [route.task.isEmpty ? question : route.task] : route.tasks
                    let batchID = UUID()
                    self.lastBatchID = batchID
                    self.batches[batchID] = TaskBatch(voiceSessionID: token, delegationIDs: self.pendingDelegations)
                    let ids = self.pendingDelegations; self.pendingDelegations.removeAll()
                    for task in requested {
                        let session = self.taskManager.start(task: task, context: context, apiKey: self.apiKey,
                            delegationIDs: ids, voiceSessionID: token)
                        self.batches[batchID]?.sessionIDs.insert(session.id)
                        self.sessionBatches[session.id] = batchID
                    }
                    self.append("Started \(requested.count) computer task\(requested.count == 1 ? "" : "s") using your normal Codex installation and account. Existing tasks continue. You can keep talking. Manual review is required before submission.", speak: true)

                }
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.error = error.localizedDescription
                self.finishDelegations("Client routing or screen reading failed. Tell the user the task did not start, and ask them to check permissions and API access.")
            }
        }
    }

    private func readScreen(question: String, token: UUID) async throws -> String {
        reading = true; state = .looking
        let shot: ScreenSnapshot
        if let snapshot { shot = snapshot }
        else if let captureTask { shot = try await captureTask.value }
        else {
            let display = ScreenContext.currentScreen
            let capture = Task { try await ScreenContext.capture(screen: display) }
            captureTask = capture; shot = try await capture.value
        }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        snapshot = shot; contextLabel = selected ? "Reading the circled region" : "Reading \(shot.displayName)"
        let result = try await VisionService.describe(snapshot: shot, question: question, key: apiKey)
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        findings = result; contextLabel = selected ? "Circled region included" : "\(shot.displayName) included"
        return "Verified screen observations captured \(shot.capturedAt.formatted(date: .omitted, time: .standard)): \(result)"
    }

    private func append(_ text: String, delegation: String? = nil, speak: Bool = false) {
        for event in LiveProtocol.appends(content: text, delegation: delegation, speak: speak) { live.send(event) }
    }

    private func resolve(_ ids: Set<String>, with text: String) {
        guard active else { return }
        for id in ids { append(text, delegation: id, speak: true) }
    }
    private func finishDelegations(_ text: String) { resolve(pendingDelegations, with: text); pendingDelegations.removeAll() }
    private var taskContext: String {
        tasks.map { "\($0.title): \($0.state.rawValue), \($0.worker.status)" }.joined(separator: "\n")
    }

    private func taskFinished(_ session: ComputerTaskSession, result: String, review: Bool) {
        expanded = true
        if !session.state.isActive { clearVoiceQuestions(taskID: session.id) }
        guard let batchID = sessionBatches[session.id] else { return }
        if review && active && session.voiceSessionID == generation {
            if session.approvalPending {
                append("Task \(session.title) needs your approval. Choose Allow once or Don't allow in its task card. Other tasks continue.", speak: true)
            } else {
                append("Task \(session.title) needs your review. Choose its Review button. Other tasks continue. No submission was made.", speak: true)
            }
        }
        reportBatchIfReady(batchID)
    }

    private func linkDelegations(_ ids: Set<String>, to batchID: UUID) {
        guard var batch = batches[batchID], batch.voiceSessionID == generation else { return }
        if batch.reported {
            resolve(ids, with: batchSummary(batch))
            return
        }
        batch.delegationIDs.formUnion(ids); batches[batchID] = batch
        for session in tasks where batch.sessionIDs.contains(session.id) { session.addDelegations(ids) }
        reportBatchIfReady(batchID)
    }

    private func reportBatchIfReady(_ batchID: UUID) {
        guard var batch = batches[batchID], !batch.reported, !batch.sessionIDs.isEmpty else { return }
        let sessions = tasks.filter { batch.sessionIDs.contains($0.id) }
        guard sessions.count == batch.sessionIDs.count, sessions.allSatisfy({ !$0.state.isActive }) else { return }
        batch.reported = true; batches[batchID] = batch
        guard active, batch.voiceSessionID == generation else { return }
        let summary = batchSummary(batch)
        if batch.delegationIDs.isEmpty { append(summary, speak: true) }
        else { resolve(batch.delegationIDs, with: summary) }
    }

    private func batchSummary(_ batch: TaskBatch) -> String {
        let summaries = tasks.filter { batch.sessionIDs.contains($0.id) }.map { session in
            "Task \(session.title), \(session.state.rawValue): \(String(session.result.prefix(240)))"
        }
        // Keep the live audio queue bounded even when many task results arrive together.
        return String((summaries.joined(separator: "\n") + "\nFull results are in each task card. Review is required before submission.").prefix(2200))
    }
}
