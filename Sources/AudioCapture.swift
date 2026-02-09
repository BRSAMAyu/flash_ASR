import Foundation
import AVFoundation

let kSampleRate: Double = 16_000
let kChannels: AVAudioChannelCount = 1
let kFrameMS = 20
let kFrameBytes = Int(kSampleRate * Double(kFrameMS) / 1000.0) * MemoryLayout<Int16>.size
let kSilenceThreshold: Int32 = 220

final class AudioCapture {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "audio.capture.queue", qos: .userInitiated)

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var pending = Data()
    private var running = false
    private var dropSilenceFrames = true
    private var frameHandler: ((Data) -> Void)?

    /// v4: audio level callback (0.0 - 1.0), called on audio queue
    var onAudioLevel: ((Float) -> Void)?

    func start(dropSilenceFrames: Bool = true, frameHandler: @escaping (Data) -> Void) throws {
        guard !running else { return }
        running = true
        self.dropSilenceFrames = dropSilenceFrames
        self.frameHandler = frameHandler
        pending.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: kSampleRate,
                                         channels: kChannels,
                                         interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            running = false
            throw NSError(domain: "AudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio format init failed"])
        }

        self.converter = converter
        self.targetFormat = target

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async {
                self?.process(buffer: buffer)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        targetFormat = nil
        pending.removeAll(keepingCapacity: false)
        frameHandler = nil
        onAudioLevel = nil
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard running,
              let converter,
              let targetFormat,
              let frameHandler
        else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var fed = false
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil else { return }
        guard status == .haveData, out.frameLength > 0 else { return }
        guard let ch = out.int16ChannelData else { return }

        let count = Int(out.frameLength)
        let data = Data(bytes: ch[0], count: count * MemoryLayout<Int16>.size)
        pending.append(data)

        while pending.count >= kFrameBytes {
            let frame = pending.prefix(kFrameBytes)
            pending.removeFirst(kFrameBytes)
            let frameData = Data(frame)

            // Calculate and emit audio level
            let level = calculateRMS(frameData)
            onAudioLevel?(level)

            if !dropSilenceFrames || isVoice(frameData) {
                frameHandler(frameData)
            }
        }
    }

    private func calculateRMS(_ frame: Data) -> Float {
        return frame.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0.0 }
            var sumSquares: Float = 0.0
            for sample in samples {
                let f = Float(sample) / Float(Int16.max)
                sumSquares += f * f
            }
            let rms = sqrt(sumSquares / Float(samples.count))
            // Normalize: typical speech RMS ~0.02-0.15, amplify for UI
            return min(rms * 5.0, 1.0)
        }
    }

    private func isVoice(_ frame: Data) -> Bool {
        return frame.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            if samples.isEmpty { return false }
            var peak: Int32 = 0
            var i = 0
            while i < samples.count {
                let s = Int32(samples[i])
                let v = s >= 0 ? s : -s
                if v > peak { peak = v }
                if peak >= kSilenceThreshold { return true }
                i += 4
            }
            return false
        }
    }
}
