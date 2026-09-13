import Foundation
import Combine

enum ComputerTaskState: String {
    case starting, working, review, manualReview, completed, failed, cancelled

    var isActive: Bool { self == .starting || self == .working || self == .review }
}

/// Each task retains its worker, application context and original voice delegation.
@MainActor
final class ComputerTaskSession: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let task: String
    let voiceSessionID: UUID?
    let createdAt = Date()
    let browser: BrowserWorkspace
    let worker: CodexWorker
    @Published private(set) var delegationIDs: Set<String>
    @Published private(set) var state: ComputerTaskState = .starting
    @Published private(set) var outcome: String?
    @Published private(set) var finishedAt: Date?
    var result: String { outcome ?? worker.result }
    var hasBrowserTab: Bool { browser.hasTaskTab }
    var approvalPending: Bool { worker.approvalPending }
    var approvalCanBeAccepted: Bool { worker.approvalCanBeAccepted }
    var pendingQuestion: CodexQuestionRequest? { worker.pendingQuestion }
    var pendingQuestions: [CodexQuestionRequest] { worker.pendingQuestions }

    fileprivate var onResult: ((ComputerTaskSession, String) -> Void)?
    fileprivate var onReview: ((ComputerTaskSession, String) -> Void)?
    fileprivate var onQuestion: ((ComputerTaskSession, CodexQuestionRequest) -> Void)?
    private var startupTask: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []
    private var notificationSent = false

    fileprivate init(task: String, title: String, delegationIDs: Set<String>, voiceSessionID: UUID?,
                     browser: BrowserWorkspace, worker: CodexWorker) {
        self.task = task
        self.title = title
        self.delegationIDs = delegationIDs
        self.voiceSessionID = voiceSessionID
        self.browser = browser
        self.worker = worker
        worker.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        browser.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observers)
        worker.onResult = { [weak self] text in self?.completed(text) }
        worker.onReview = { [weak self] text in self?.requestedReview(text) }
        worker.onQuestion = { [weak self] question in
            guard let self else { return }
            self.onQuestion?(self, question)
        }
    }

    func addDelegations(_ ids: Set<String>) { delegationIDs.formUnion(ids) }

    fileprivate func launch(context: String, apiKey: String) {
        _ = apiKey
        startupTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.state == .starting else { return }
            defer { self.startupTask = nil }
            do {
                try await self.worker.start(task: self.task, context: context, apiKey: "", title: self.title)
                guard !Task.isCancelled, self.state == .starting else { return }
                if self.worker.running { self.state = .working }
            } catch {
                guard self.state.isActive else { return }
                if error is CancellationError {
                    self.stop()
                } else {
                    self.state = .failed
                    self.finishedAt = Date()
                    let text = "Computer task could not start: \(error.localizedDescription)"
                    self.outcome = text
                    self.notifyResult(text)
                }
            }
        }
    }

    private func completed(_ text: String) {
        guard state.isActive, !notificationSent else { return }
        state = worker.status == "Finished" ? .completed : worker.status == "Stopped" ? .cancelled : .failed
        outcome = text
        finishedAt = Date()
        notifyResult(text)
    }

    private func requestedReview(_ text: String) {
        guard state.isActive, !notificationSent else { return }
        state = .review
        outcome = text
        finishedAt = worker.approvalPending ? nil : Date()
        if !worker.approvalPending { notificationSent = true }
        onReview?(self, text)
    }

    func allowPendingApproval() throws {
        try worker.approvePendingReview()
        state = .working
        outcome = nil
        finishedAt = nil
    }

    func declinePendingApproval() {
        worker.declinePendingReview()
        state = .working
        outcome = nil
        finishedAt = nil
    }

    func answerPendingQuestion(requestID: String, answers: [String: [String]]) throws {
        try worker.answerPendingQuestion(requestID: requestID, answers: answers)
    }

    private func notifyResult(_ text: String) {
        guard !notificationSent else { return }
        notificationSent = true
        onResult?(self, text)
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        // Completed and review results remain available when Quit cancels active work.
        if state == .review, !worker.approvalPending, !worker.running { return }
        guard state.isActive else {
            if worker.running { worker.stop() }
            return
        }
        state = .cancelled
        worker.stop()
        let text = "The user stopped this computer task. Work was not completed."
        outcome = text
        finishedAt = Date()
        notifyResult(text)
    }

    @discardableResult
    func showBrowser() async throws -> Bool {
        throw ComputahError.message("Codex uses your existing apps and does not create a separate task browser tab.")
    }

    func review() async throws {
        try await takeOver()
    }

    func takeOver() async throws {
        startupTask?.cancel()
        startupTask = nil
        try await worker.takeOverForReview()
        state = .manualReview
        if !notificationSent {
            let text = "The user stopped this task's agent for manual review. No submission was made by the agent."
            outcome = text
            finishedAt = Date()
            notificationSent = true
            onReview?(self, text)
        }
    }

    func detach() async { await browser.detach() }

    fileprivate func makeBrowsingSession() {
        state = .manualReview
        notificationSent = true
    }
}

/// Starting work appends a new independent session. Existing tasks keep running.
@MainActor
final class ComputerTaskManager: ObservableObject {
    @Published private(set) var sessions: [ComputerTaskSession] = []
    var onResult: ((ComputerTaskSession, String) -> Void)?
    var onReview: ((ComputerTaskSession, String) -> Void)?
    var onQuestion: ((ComputerTaskSession, CodexQuestionRequest) -> Void)?
    private let browserFactory: @MainActor () -> BrowserWorkspace
    private let workerFactory: @MainActor (BrowserWorkspace) -> CodexWorker
    private var sessionObservers: [UUID: AnyCancellable] = [:]

    init(browserFactory: @escaping @MainActor () -> BrowserWorkspace = { BrowserWorkspace() },
         workerFactory: @escaping @MainActor (BrowserWorkspace) -> CodexWorker = { CodexWorker(browser: $0) }) {
        self.browserFactory = browserFactory
        self.workerFactory = workerFactory
    }

    @discardableResult
    func start(task: String, context: String, apiKey: String, delegationIDs: Set<String> = [],
               voiceSessionID: UUID? = nil) -> ComputerTaskSession {
        let compactTitle = task.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let session = makeSession(task: task, title: compactTitle.isEmpty ? "Computer task" : String(compactTitle.prefix(90)),
                                  delegationIDs: delegationIDs, voiceSessionID: voiceSessionID)
        session.launch(context: context, apiKey: apiKey)
        return session
    }

    @discardableResult
    func createBrowsingSession(title: String = "Browser") -> ComputerTaskSession {
        let session = makeSession(task: "", title: title, delegationIDs: [], voiceSessionID: nil)
        session.makeBrowsingSession()
        return session
    }

    private func makeSession(task: String, title: String, delegationIDs: Set<String>, voiceSessionID: UUID?) -> ComputerTaskSession {
        var uniqueTitle = title
        var suffix = 2
        while sessions.contains(where: { $0.title == uniqueTitle }) {
            uniqueTitle = "\(title) (\(suffix))"
            suffix += 1
        }
        let browser = browserFactory()
        let session = ComputerTaskSession(task: task, title: uniqueTitle, delegationIDs: delegationIDs, voiceSessionID: voiceSessionID,
                                          browser: browser, worker: workerFactory(browser))
        session.onResult = { [weak self] session, text in self?.onResult?(session, text) }
        session.onReview = { [weak self] session, text in self?.onReview?(session, text) }
        session.onQuestion = { [weak self] session, question in self?.onQuestion?(session, question) }
        sessionObservers[session.id] = session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        sessions.append(session)
        return session
    }

    func stopAll() {
        for session in sessions {
            session.stop()
            Task { await session.detach() }
        }
    }
}
