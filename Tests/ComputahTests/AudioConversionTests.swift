import XCTest
import AVFoundation
@testable import Computah

final class AudioConversionTests: XCTestCase {
    func testMultichannelMicrophoneConvertsFirstChannelToNonSilentMonoPCM() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 9))
        let source = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layout)
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true))
        let converter = try XCTUnwrap(AudioEngine.microphoneConverter(source: source, target: target))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 8192))
        input.frameLength = input.frameCapacity
        let channels = try XCTUnwrap(input.floatChannelData)
        for channel in 0..<9 {
            for frame in 0..<8192 { channels[channel][frame] = channel == 0 ? 0.25 : -0.8 }
        }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4112))
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        XCTAssertNil(error)
        XCTAssertNotEqual(status, .error)
        XCTAssertGreaterThan(output.frameLength, 4000)
        let samples = try XCTUnwrap(output.int16ChannelData?[0])
        // Ignore the resampler's startup edge, and verify correct source-channel routing.
        let mean = (100..<Int(output.frameLength)).reduce(0.0) { $0 + Double(samples[$1]) / 32768 } / Double(Int(output.frameLength) - 100)
        XCTAssertEqual(mean, 0.25, accuracy: 0.01)
    }
}
