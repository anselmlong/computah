import AVFoundation
import Foundation

@main
struct AudioSmokeTest {
    static func main() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            print("Skipped audio startup check. Existing microphone authorization is required; no permission request was made.")
            return
        }
        let audio = AudioEngine()
        audio.onNotice = { if !$0.isEmpty { print($0) } }
        var chunks = 0
        var bytes = 0
        var samples = 0
        var energy = 0.0
        audio.onAudio = { data in
            chunks += 1; bytes += data.count
            data.withUnsafeBytes { raw in
                for offset in stride(from: 0, to: raw.count, by: 2) {
                    let value = Double(raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32768
                    energy += value * value; samples += 1
                }
            }
        }
        // Only aggregate counts and RMS are reported. No samples are saved or transmitted.
        for attempt in 1...3 {
            do {
                try audio.start()
                print("Audio start \(attempt) passed; echo cancellation=\(audio.voiceProcessingEnabled)")
                if attempt == 1 { RunLoop.current.run(until: Date().addingTimeInterval(2)) }
                audio.stop()
            } catch {
                print("Audio start \(attempt) failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        print("Microphone stream: \(chunks) chunks, \(bytes) PCM bytes, RMS \(sqrt(energy / Double(max(1, samples))))")
        if bytes < 48000 || energy == 0 {
            print("Microphone PCM did not flow or remained entirely silent. Check the microphone input and mute settings.")
            exit(1)
        }
    }
}
