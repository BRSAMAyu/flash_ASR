import Foundation
import AVFoundation
import CoreMedia

struct LectureImportReport {
    let mergedText: String
    let failedSegments: [Int]
    let totalSegments: Int
}

final class LectureImportService {
    struct Config {
        let segmentSeconds: Int
        let overlapSeconds: Int
        let concurrency: Int

        static let `default` = Config(segmentSeconds: 180, overlapSeconds: 10, concurrency: 2)
    }

    private let queue = DispatchQueue(label: "lecture.import.queue", qos: .userInitiated, attributes: .concurrent)
    private static let overlapIgnoredCharacterSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.punctuationCharacters)
        set.formUnion(.symbols)
        return set
    }()
    private let lock = NSLock()
    private var cancelled = false
    private var inFlightClients: [Int: FileASRStreamClient] = [:]

    private var lastSegments: [Data] = []
    private var lastResults: [Int: String] = [:]
    private var lastFailed: Set<Int> = []
    private var lastSettings: SettingsManager?

    func importAudio(
        from url: URL,
        settings: SettingsManager,
        config: Config = .default,
        onProgress: @escaping (_ progress: Double, _ stage: String) -> Void,
        onComplete: @escaping (Result<LectureImportReport, Error>) -> Void
    ) {
        queue.async {
            self.cancelled = false
            self.lastSettings = settings
            self.lastResults = [:]
            self.lastFailed = []
            onProgress(0.02, "正在解析音频...")

            do {
                let pcm = try self.decodeToPCM16Mono16k(url: url)
                let segments = self.makeSegments(pcm: pcm, config: config)
                self.lastSegments = segments
                if segments.isEmpty {
                    throw NSError(domain: "LectureImportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "音频内容为空"])
                }
                onProgress(0.08, "已切分为 \(segments.count) 段，开始转写...")
                self.processSegments(segments: segments, settings: settings, config: config, onProgress: onProgress) { report in
                    onComplete(.success(report))
                }
            } catch {
                onComplete(.failure(error))
            }
        }
    }

    func retrySegment(
        index: Int,
        onComplete: @escaping (Result<LectureImportReport, Error>) -> Void
    ) {
        queue.async {
            guard index >= 0, index < self.lastSegments.count else {
                onComplete(.failure(NSError(domain: "LectureImportService", code: -2, userInfo: [NSLocalizedDescriptionKey: "无效分段索引"])))
                return
            }
            guard let settings = self.lastSettings else {
                onComplete(.failure(NSError(domain: "LectureImportService", code: -3, userInfo: [NSLocalizedDescriptionKey: "未找到导入上下文"])))
                return
            }
            let result = self.transcribeSegment(self.lastSegments[index], index: index, settings: settings)
            switch result {
            case .success(let text):
                self.lastResults[index] = text
                self.lastFailed.remove(index)
                let report = LectureImportReport(
                    mergedText: self.mergeResults(total: self.lastSegments.count),
                    failedSegments: self.lastFailed.sorted(),
                    totalSegments: self.lastSegments.count
                )
                onComplete(.success(report))
            case .failure(let error):
                self.lastFailed.insert(index)
                onComplete(.failure(error))
            }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let clients = inFlightClients.values
        inFlightClients.removeAll()
        lock.unlock()
        for client in clients {
            client.cancel()
        }
    }

    private func processSegments(
        segments: [Data],
        settings: SettingsManager,
        config: Config,
        onProgress: @escaping (_ progress: Double, _ stage: String) -> Void,
        onDone: @escaping (LectureImportReport) -> Void
    ) {
        let total = segments.count
        var nextIndex = 0
        var finished = 0
        let group = DispatchGroup()
        let workers = max(1, min(config.concurrency, total))

        for _ in 0..<workers {
            group.enter()
            queue.async {
                while true {
                    self.lock.lock()
                    let idx = nextIndex
                    if idx < total {
                        nextIndex += 1
                    }
                    self.lock.unlock()

                    if idx >= total { break }
                    if self.isCancelled() { break }

                    var result = self.transcribeSegment(segments[idx], index: idx, settings: settings)
                    if case .failure = result, !self.isCancelled() {
                        // Auto-retry once without blocking delay to keep workers responsive.
                        result = self.transcribeSegment(segments[idx], index: idx, settings: settings)
                    }
                    self.lock.lock()
                    switch result {
                    case .success(let text):
                        self.lastResults[idx] = text
                        self.lastFailed.remove(idx)
                    case .failure:
                        self.lastFailed.insert(idx)
                    }
                    finished += 1
                    let progress = 0.08 + (Double(finished) / Double(max(1, total))) * 0.88
                    self.lock.unlock()
                    onProgress(progress, "课堂转写中 (\(finished)/\(total))")
                }
                group.leave()
            }
        }

        group.notify(queue: queue) {
            let merged = self.mergeResults(total: total)
            onProgress(1.0, "课堂转写完成")
            let report = LectureImportReport(
                mergedText: merged,
                failedSegments: self.lastFailed.sorted(),
                totalSegments: total
            )
            onDone(report)
        }
    }

    private func transcribeSegment(_ pcm: Data, index: Int, settings: SettingsManager) -> Result<String, Error> {
        if isCancelled() {
            return .failure(NSError(domain: "LectureImportService", code: -9, userInfo: [NSLocalizedDescriptionKey: "已取消"]))
        }
        let apiKey = settings.effectiveDashscopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return .failure(NSError(domain: "LectureImportService", code: -14, userInfo: [NSLocalizedDescriptionKey: "Dashscope API Key 为空，请先在设置中配置"]))
        }
        guard let endpoint = URL(string: settings.fileASRURL) else {
            return .failure(NSError(domain: "LectureImportService", code: -4, userInfo: [NSLocalizedDescriptionKey: "无效的 File ASR URL"]))
        }
        let wav = makeWav(pcm16Mono16k: pcm, sampleRate: Int(kSampleRate), channels: Int(kChannels))
        let base64 = wav.base64EncodedString()
        let semaphore = DispatchSemaphore(value: 0)
        var text = ""
        var err: Error?

        let client = FileASRStreamClient(
            apiKey: apiKey,
            endpoint: endpoint,
            model: settings.fileModel,
            language: settings.language,
            timeout: 120.0
        )
        lock.lock()
        inFlightClients[index] = client
        lock.unlock()

        client.onDelta = { delta in
            text += delta
        }
        client.onError = { message in
            if err == nil {
                err = NSError(domain: "LectureImportService", code: -5, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        client.onDone = {
            semaphore.signal()
        }
        client.start(base64Wav: base64)

        let timeoutResult = semaphore.wait(timeout: .now() + 140.0)
        lock.lock()
        inFlightClients[index] = nil
        lock.unlock()

        if timeoutResult == .timedOut {
            client.cancel()
            return .failure(NSError(domain: "LectureImportService", code: -6, userInfo: [NSLocalizedDescriptionKey: "第 \(index + 1) 段转写超时"]))
        }
        if let err {
            return .failure(err)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(NSError(domain: "LectureImportService", code: -7, userInfo: [NSLocalizedDescriptionKey: "第 \(index + 1) 段返回空结果"]))
        }
        return .success(trimmed)
    }

    private func makeSegments(pcm: Data, config: Config) -> [Data] {
        let bytesPerSecond = Int(kSampleRate) * MemoryLayout<Int16>.size
        let segmentBytes = config.segmentSeconds * bytesPerSecond
        let overlapBytes = config.overlapSeconds * bytesPerSecond
        guard segmentBytes > overlapBytes, !pcm.isEmpty else { return [] }
        let step = segmentBytes - overlapBytes
        var out: [Data] = []
        var offset = 0
        while offset < pcm.count {
            let end = min(offset + segmentBytes, pcm.count)
            out.append(pcm.subdata(in: offset..<end))
            if end >= pcm.count { break }
            offset += step
        }
        return out
    }

    private func mergeResults(total: Int) -> String {
        guard total > 0 else { return "" }
        var merged = ""
        for idx in 0..<total {
            guard let segment = lastResults[idx], !segment.isEmpty else { continue }
            if merged.isEmpty {
                merged = segment
            } else {
                merged = mergeWithOverlap(base: merged, next: segment)
            }
        }
        return merged
    }

    private func mergeWithOverlap(base: String, next: String) -> String {
        let baseText = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextText = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseText.isEmpty, !nextText.isEmpty else { return base + "\n" + next }

        let maxOverlap = min(260, baseText.count, nextText.count)
        guard maxOverlap >= 20 else { return baseText + "\n" + nextText }

        // 1) Prefer exact suffix-prefix match for deterministic merge.
        for size in stride(from: maxOverlap, through: 20, by: -1) {
            let suffix = String(baseText.suffix(size))
            let prefix = String(nextText.prefix(size))
            if suffix == prefix {
                return baseText + String(nextText.dropFirst(size))
            }
        }

        // 2) Relaxed exact match: ignore punctuation / whitespace differences.
        for size in stride(from: maxOverlap, through: 24, by: -2) {
            let suffix = String(baseText.suffix(size))
            let prefix = String(nextText.prefix(size))
            let normalizedSuffix = normalizeForOverlapMatch(suffix)
            if normalizedSuffix.count < 14 { continue }
            if normalizedSuffix == normalizeForOverlapMatch(prefix) {
                return baseText + String(nextText.dropFirst(size))
            }
        }

        // 3) Boundary-tolerant char match for minor ASR jitter near segment edges.
        if let drop = tolerantOverlapDrop(baseText: baseText, nextText: nextText, maxOverlap: maxOverlap) {
            return baseText + String(nextText.dropFirst(drop))
        }

        // 4) Final fallback: high-threshold positional fuzzy match with strict trim cap.
        var bestOverlap = 0
        var bestScore = 0.0
        for size in stride(from: maxOverlap, through: 40, by: -5) {
            let suffix = String(baseText.suffix(size))
            let prefix = String(nextText.prefix(size))
            let score = positionalSimilarity(suffix, prefix)
            if score > bestScore {
                bestScore = score
                bestOverlap = size
            }
        }
        guard bestScore >= 0.92, bestOverlap > 0, bestOverlap <= 80 else {
            return baseText + "\n" + nextText
        }
        return baseText + String(nextText.dropFirst(bestOverlap))
    }

    private func normalizeForOverlapMatch(_ text: String) -> String {
        let lower = text.lowercased()
        let scalars = lower.unicodeScalars.filter { !Self.overlapIgnoredCharacterSet.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func tolerantOverlapDrop(baseText: String, nextText: String, maxOverlap: Int) -> Int? {
        let nextChars = Array(nextText)
        guard !nextChars.isEmpty else { return nil }

        var bestDrop = 0
        var bestMatched = 0
        for size in stride(from: maxOverlap, through: 20, by: -1) {
            let suffixChars = Array(baseText.suffix(size))
            var i = 0
            var j = 0
            var consumed = 0
            var matchedCore = 0
            var mismatches = 0

            while i < suffixChars.count, j < nextChars.count {
                if isOverlapIgnorable(suffixChars[i]) {
                    i += 1
                    continue
                }
                if isOverlapIgnorable(nextChars[j]) {
                    j += 1
                    consumed += 1
                    continue
                }
                if normalizedOverlapChar(suffixChars[i]) == normalizedOverlapChar(nextChars[j]) {
                    matchedCore += 1
                    i += 1
                    j += 1
                    consumed += 1
                } else {
                    mismatches += 1
                    if mismatches > 2 { break }
                    i += 1
                    j += 1
                    consumed += 1
                }
            }

            while i < suffixChars.count, isOverlapIgnorable(suffixChars[i]) {
                i += 1
            }

            guard i == suffixChars.count else { continue }
            guard matchedCore >= 14, mismatches <= 2 else { continue }
            guard consumed > 0, consumed <= 120 else { continue }

            if matchedCore > bestMatched || (matchedCore == bestMatched && consumed > bestDrop) {
                bestMatched = matchedCore
                bestDrop = consumed
            }
        }

        return bestDrop > 0 ? bestDrop : nil
    }

    private func isOverlapIgnorable(_ ch: Character) -> Bool {
        for scalar in String(ch).unicodeScalars {
            if !Self.overlapIgnoredCharacterSet.contains(scalar) {
                return false
            }
        }
        return true
    }

    private func normalizedOverlapChar(_ ch: Character) -> Character {
        let lowered = String(ch).lowercased()
        return lowered.first ?? ch
    }

    private func positionalSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty, a.count == b.count else { return 0.0 }
        var same = 0
        for i in 0..<a.count where a[i] == b[i] {
            same += 1
        }
        return Double(same) / Double(a.count)
    }

    private func decodeToPCM16Mono16k(url: URL) throws -> Data {
        let asset = AVURLAsset(url: url)
        let tracks = try loadAudioTracks(asset: asset)
        guard let track = tracks.first else {
            throw NSError(domain: "LectureImportService", code: -10, userInfo: [NSLocalizedDescriptionKey: "文件无音轨"])
        }
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: kSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(domain: "LectureImportService", code: -11, userInfo: [NSLocalizedDescriptionKey: "无法读取音轨输出"])
        }
        reader.add(output)

        var pcm = Data()
        guard reader.startReading() else {
            throw NSError(domain: "LectureImportService", code: -12, userInfo: [NSLocalizedDescriptionKey: "无法开始读取音频"])
        }
        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { continue }
            if let block = CMSampleBufferGetDataBuffer(sample) {
                var length = 0
                var pointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
                if let pointer, length > 0 {
                    pcm.append(UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: length)
                }
            }
            CMSampleBufferInvalidate(sample)
        }
        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "LectureImportService", code: -13, userInfo: [NSLocalizedDescriptionKey: "读取音频失败"])
        }
        return pcm
    }

    private func loadAudioTracks(asset: AVURLAsset) throws -> [AVAssetTrack] {
        var output: Result<[AVAssetTrack], Error>?
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                output = .success(tracks)
            } catch {
                output = .failure(error)
            }
            sem.signal()
        }
        sem.wait()
        switch output {
        case .success(let tracks):
            return tracks
        case .failure(let error):
            throw error
        case .none:
            throw NSError(domain: "LectureImportService", code: -14, userInfo: [NSLocalizedDescriptionKey: "读取音轨失败"])
        }
    }

    private func isCancelled() -> Bool {
        lock.lock()
        let v = cancelled
        lock.unlock()
        return v
    }
}
