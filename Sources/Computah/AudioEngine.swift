import AVFoundation

final class AudioEngine {
    var onAudio: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onPlaybackState: ((Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    private(set) var voiceProcessingEnabled = false
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let wire = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    private let playback = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
    private var tapped = false
    private var playbackGeneration = UUID()
    private var queuedFrames = 0
    var isPlaying: Bool { queuedFrames > 0 }
    private let captureLock = NSLock()
    private var captureGeneration = UUID()
    private var queuedCaptureBytes = 0
    private var captureOverloaded = false

    func start() throws {
        stop()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw ComputahError.message("Allow Microphone access in macOS settings, then start again.")
        }
        do {
            try configure(voiceProcessing: true)
            voiceProcessingEnabled = true
            onNotice?("")
        } catch {
            let voiceError = error as NSError
            stop()
            do {
                try configure(voiceProcessing: false)
                onNotice?("Echo cancellation could not start (audio error \(voiceError.code)). Use headphones to prevent the assistant hearing its own voice.")
            } catch {
                let plainError = error as NSError
                stop()
                throw ComputahError.message("Audio devices could not initialize (voice processing: \(voiceError.code), ordinary audio: \(plainError.code)). Check the input and output devices in macOS Sound settings, close other apps using the microphone, then retry.")
            }
        }
    }

    private func configure(voiceProcessing: Bool) throws {
        // Failed or stopped VoiceProcessingIO graphs must not leak their formats into a retry.
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        let input = engine.inputNode
        let output = engine.outputNode
        if voiceProcessing { try input.setVoiceProcessingEnabled(true) }
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let converter = Self.microphoneConverter(source: source, target: wire) else {
            throw ComputahError.message("No usable microphone was found. Choose a microphone in macOS Sound settings.")
        }
        let hardwareOutput = output.outputFormat(forBus: 0)
        guard hardwareOutput.sampleRate > 0, hardwareOutput.channelCount > 0 else {
            throw ComputahError.message("No usable speaker device was found. Choose an output in macOS Sound settings.")
        }
        engine.attach(player)
        let mixer = engine.mainMixerNode
        engine.connect(player, to: mixer, format: playback)
        // Apple requires the two I/O client formats to match with VoiceProcessingIO.
        // The mixer resamples 24 kHz API playback to this device-rate format.
        engine.connect(mixer, to: output, format: voiceProcessing ? source : hardwareOutput)
        let captureToken = captureGeneration
        input.installTap(onBus: 0, bufferSize: 1024, format: source) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24000 / source.sampleRate) + 16)
            guard let converted = AVAudioPCMBuffer(pcmFormat: self.wire, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData?[0] else { return }
            let count = Int(converted.frameLength)
            var energy: Float = 0
            for index in 0..<count { let value = Float(samples[index]) / 32768; energy += value * value }
            self.deliver(Data(bytes: samples, count: count * 2),
                         level: min(1, sqrt(energy / Float(count)) * 7), token: captureToken)
        }
        tapped = true
        do { engine.prepare(); try engine.start(); player.play() }
        catch { stop(); throw error }
    }

    static func microphoneConverter(source: AVAudioFormat, target: AVAudioFormat) -> AVAudioConverter? {
        guard source.sampleRate > 0, source.channelCount > 0, target.channelCount == 1,
              let converter = AVAudioConverter(from: source, to: target) else { return nil }
        // VoiceProcessingIO can expose a multichannel aggregate input. Automatic layout
        // downmixing produced silent PCM despite nonzero source samples on this Mac.
        converter.channelMap = [0]
        return converter
    }

    private func deliver(_ data: Data, level: Float, token: UUID) {
        captureLock.lock()
        guard captureGeneration == token, !captureOverloaded else { captureLock.unlock(); return }
        guard queuedCaptureBytes + data.count <= 24000 * 2 * 5 else {
            captureOverloaded = true; captureLock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureLock.lock()
                let current = self.captureGeneration == token
                self.captureLock.unlock()
                if current { self.onFailure?("Microphone processing cannot keep up. Please reconnect.") }
            }
            return
        }
        queuedCaptureBytes += data.count
        captureLock.unlock()
        // Dispatching from the single input tap preserves PCM order on the main queue.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.captureLock.lock()
            let current = self.captureGeneration == token
            if current { self.queuedCaptureBytes -= data.count }
            self.captureLock.unlock()
            guard current else { return }
            self.onLevel?(level)
            self.onAudio?(data)
        }
    }

    func play(_ data: Data) {
        guard engine.isRunning, data.count % 2 == 0, data.count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playback, frameCapacity: AVAudioFrameCount(data.count / 2)),
              let output = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameCapacity)
        guard queuedFrames + frames <= 24000 * 30 else {
            onFailure?("Speaker playback cannot keep up. Please reconnect.")
            return
        }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { raw in
            for i in 0..<Int(buffer.frameLength) {
                output[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768
            }
        }
        let token = playbackGeneration
        let wasPlaying = isPlaying
        queuedFrames += frames
        if !wasPlaying { onPlaybackState?(true) }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // AVAudioPlayerNode callbacks run outside the UI thread. Device playback completion
            // marks speech ending; transcript arrival and network quiet do not.
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == token else { return }
                self.queuedFrames = max(0, self.queuedFrames - frames)
                if !self.isPlaying { self.onPlaybackState?(false) }
            }
        }
    }

    func stop() {
        captureLock.lock()
        captureGeneration = UUID(); queuedCaptureBytes = 0; captureOverloaded = false
        captureLock.unlock()
        playbackGeneration = UUID()
        let wasPlaying = isPlaying
        queuedFrames = 0
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        player.stop(); engine.stop()
        engine.reset()
        voiceProcessingEnabled = false
        if wasPlaying { onPlaybackState?(false) }
    }
}
