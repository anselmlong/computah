import Foundation

struct LiveDiagnostics {
    var sessionStarted = false
    var inputChunks = 0
    var inputBytes = 0
    var outputChunks = 0
    var outputBytes = 0
    var lastEventType = "Not connected"
}

@MainActor
final class LiveConnection {
    var onEvent: (([String: Any]) -> Void)?
    var onFailure: ((String) -> Void)?
    var onDiagnostics: ((LiveDiagnostics) -> Void)?
    private(set) var diagnostics = LiveDiagnostics()
    private var lastDiagnosticUpdate = Date.distantPast
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .ephemeral)
    private var receiver: Task<Void, Never>?
    private var closeTimeout: Task<Void, Never>?
    private var sendTail: Task<Void, Never>?
    private var generation = UUID()
    private(set) var ready = false
    private var closing = false
    private var queuedAudio = 0
    private var queuedAudioBytes = 0
    private var pendingPCMByte = Data()
    private var queuedMessages = 0

    func connect(key: String) {
        disconnect()
        diagnostics = LiveDiagnostics(); publishDiagnostics(force: true)
        let token = generation
        var request = URLRequest(url: LiveProtocol.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 8 * 1024 * 1024
        socket = task
        task.resume()
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard let self, self.generation == token else { return }
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self.diagnostics.lastEventType = event["type"] as? String ?? "Unknown event"
                    if event["type"] as? String == "session.output_audio.delta",
                       let delta = event["delta"] as? String, let bytes = Data(base64Encoded: delta) {
                        self.diagnostics.outputChunks += 1; self.diagnostics.outputBytes += bytes.count
                    }
                    if event["type"] as? String == "session.started" {
                        self.ready = true; self.closeTimeout?.cancel(); self.closeTimeout = nil
                        self.diagnostics.sessionStarted = true
                    }
                    self.publishDiagnostics(force: event["type"] as? String == "session.started")
                    self.onEvent?(event)
                    if event["type"] as? String == "session.closed" { self.disconnect(); return }
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.onFailure?("Voice connection ended. Check your API key, model access, and network, then retry.")
                self.disconnect()
            }
        }
        enqueue(LiveProtocol.start())
        closeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.generation == token, !self.ready else { return }
            self.onFailure?("GPT-Live did not start within 20 seconds. Check model access and retry.")
            self.disconnect()
        }
    }

    func send(_ event: [String: Any]) { guard ready, !closing else { return }; enqueue(event) }

    @discardableResult
    func askWorkerQuestion(_ question: WorkerQuestionEnvelope) -> Bool {
        guard ready, !closing, question.isValid else { return false }
        for event in LiveProtocol.workerQuestionContext(question) { enqueue(event) }
        return true
    }

    func audio(_ data: Data) {
        guard ready, !closing else { return }
        var bytes = pendingPCMByte
        bytes.append(data)
        let count = bytes.count - bytes.count % 2
        pendingPCMByte = Data(bytes.suffix(bytes.count - count))
        guard count > 0 else { return }
        let complete = Data(bytes.prefix(count))
        // Do not silently drop chunks or let a slow connection accumulate unlimited microphone audio.
        guard queuedAudio < 120, queuedAudioBytes + complete.count <= 24000 * 2 * 5 else {
            onFailure?("The connection cannot keep up with microphone audio. Please reconnect.")
            disconnect(); return
        }
        queuedAudio += 1
        queuedAudioBytes += complete.count
        enqueue(["type": "session.input_audio.append", "audio": complete.base64EncodedString()], audioBytes: complete.count)
    }

    private func enqueue(_ event: [String: Any], audioBytes: Int = 0) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        guard queuedMessages < 256 else {
            onFailure?("Voice context is arriving faster than the connection can send it. Please reconnect.")
            disconnect(); return
        }
        queuedMessages += 1
        let previous = sendTail
        let token = generation
        sendTail = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.generation == token else { return }
            do {
                try await socket.send(.string(text))
                if audioBytes > 0, self.generation == token {
                    self.diagnostics.inputChunks += 1; self.diagnostics.inputBytes += audioBytes
                    self.publishDiagnostics()
                }
            }
            catch {
                if self.generation == token {
                    self.onFailure?("Could not send audio or context. Reconnect to try again.")
                    self.disconnect()
                }
            }
            if self.generation == token {
                self.queuedMessages -= 1
                if audioBytes > 0 { self.queuedAudio -= 1; self.queuedAudioBytes -= audioBytes }
            }
        }
    }

    private func publishDiagnostics(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastDiagnosticUpdate) >= 1 else { return }
        lastDiagnosticUpdate = Date()
        onDiagnostics?(diagnostics)
    }

    func close() {
        guard !closing else { return }
        guard ready else { disconnect(); return }
        closing = true
        closeTimeout?.cancel()
        enqueue(["type": "session.close"])
        let token = generation
        closeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.onFailure?("Voice stopped, but final session usage could not be confirmed.")
            self.disconnect()
        }
    }

    func disconnect() {
        generation = UUID(); ready = false; closing = false; queuedAudio = 0
        queuedAudioBytes = 0; queuedMessages = 0; pendingPCMByte = Data()
        receiver?.cancel(); receiver = nil
        closeTimeout?.cancel(); closeTimeout = nil
        sendTail?.cancel(); sendTail = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
    }
}
