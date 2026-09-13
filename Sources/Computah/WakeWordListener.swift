import AVFoundation
import Speech

enum WakePhrase {
    static func matches(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }
        return zip(words, words.dropFirst()).contains { first, second in
            // Accept the standard spelling too: speech recognition can render Computah as computer.
            first == "hey" && (second == "computer" || second == "computah")
        }
    }
}

/// Owns the microphone only between conversations. Recognition never falls back to a server.
@MainActor
final class WakeWordListener {
    var onWake: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var renewal: Task<Void, Never>?
    private var generation = UUID()
    private var wanted = false
    private var retryDelay: Double = 2

    func start() {
        guard !wanted else { return }
        wanted = true
        beginRecognition()
    }

    func stop() {
        wanted = false
        tearDown()
    }

    private func tearDown() {
        generation = UUID()
        renewal?.cancel(); renewal = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); request = nil
        recognition?.cancel(); recognition = nil
    }

    private func beginRecognition() {
        tearDown()
        guard wanted else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            wanted = false
            onStatus?("Allow Microphone and Speech Recognition to use Hey, computah.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else {
            wanted = false
            onStatus?("On-device English speech recognition is unavailable on this Mac. Use Start talking.")
            return
        }
        guard recognizer.isAvailable else {
            scheduleRetry(); return
        }
        let token = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = ["Hey computah"]
        self.request = request
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            scheduleRetry(); return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        self.engine = engine
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.wanted, self.generation == token else { return }
                if let text, WakePhrase.matches(text) {
                    self.stop()
                    self.onWake?()
                } else if failed {
                    self.scheduleRetry()
                } else if finished {
                    self.retryDelay = 2
                    self.beginRecognition()
                }
            }
        }
        do {
            try engine.start()
            onStatus?("Listening for Hey, computah on this Mac.")
            // Rotate before the speech service's per-request limit, including during silence.
            renewal = Task { [weak self] in
                try? await Task.sleep(for: .seconds(50))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.retryDelay = 2
                self.beginRecognition()
            }
        } catch { scheduleRetry() }
    }

    private func scheduleRetry() {
        tearDown()
        guard wanted else { return }
        onStatus?("Wake listening is unavailable. Retrying; you can use Start talking.")
        let token = generation
        let delay = retryDelay
        retryDelay = min(30, retryDelay * 2)
        renewal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.beginRecognition()
        }
    }
}
