import Foundation

struct SegmentedProgressSnapshot {
    let pipelineID: UUID
    let sessionID: UUID
    let totalSegments: Int
    let completedSegments: Int
    let failedSegments: [Int]
    let mergedText: String
    let stageText: String
    let progress: Double
    let recordingStopped: Bool
    let recovering: Bool
}

struct SegmentedFinalizeReport {
    let pipelineID: UUID
    let sessionID: UUID
    let mergedText: String
    let failedSegments: [Int]
    let totalSegments: Int
    let recovering: Bool
}

struct SegmentJob: Codable {
    enum Status: String, Codable {
        case pending
        case processing
        case succeeded
        case failed
    }

    let index: Int
    let wavFileName: String
    var status: Status
    var attempts: Int
    var nextRetryAt: Date?
    var text: String?
    var lastError: String?
}

struct SegmentedRecoveryManifest: Codable {
    let pipelineID: UUID
    let sessionID: UUID
    let createdAt: Date
    var updatedAt: Date
    var segmentSeconds: Int
    var overlapSeconds: Int
    var recordingStopped: Bool
    var mergedText: String
    var jobs: [SegmentJob]
}

final class SegmentedRecordingPipeline {
    static let defaultSegmentSeconds = 180
    static let defaultOverlapSeconds = 10
    static let maxConcurrency = 2
    static let maxAttempts = 3

    private let queue: DispatchQueue
    private let settings: SettingsManager
    private let pipelineDir: URL
    private let manifestURL: URL
    private let recovering: Bool

    private var manifest: SegmentedRecoveryManifest
    private var livePCM = Data()
    private var inFlight: [Int: FileASRStreamClient] = [:]
    private var retryWork: [Int: DispatchWorkItem] = [:]
    private var finished = false

    private var onSnapshot: ((SegmentedProgressSnapshot) -> Void)?
    private var onFinished: ((SegmentedFinalizeReport) -> Void)?

    private var segmentBytes: Int {
        manifest.segmentSeconds * Int(kSampleRate) * MemoryLayout<Int16>.size
    }

    private var overlapBytes: Int {
        manifest.overlapSeconds * Int(kSampleRate) * MemoryLayout<Int16>.size
    }

    private var stepBytes: Int {
        max(1, segmentBytes - overlapBytes)
    }

    private init(
        settings: SettingsManager,
        pipelineDir: URL,
        manifestURL: URL,
        manifest: SegmentedRecoveryManifest,
        recovering: Bool,
        onSnapshot: ((SegmentedProgressSnapshot) -> Void)?,
        onFinished: ((SegmentedFinalizeReport) -> Void)?
    ) {
        self.settings = settings
        self.pipelineDir = pipelineDir
        self.manifestURL = manifestURL
        self.manifest = manifest
        self.recovering = recovering
        self.onSnapshot = onSnapshot
        self.onFinished = onFinished
        self.queue = DispatchQueue(label: "segmented.recording.pipeline.\(manifest.pipelineID.uuidString)", qos: .userInitiated)
    }

    static func create(
        sessionID: UUID,
        settings: SettingsManager,
        onSnapshot: ((SegmentedProgressSnapshot) -> Void)?,
        onFinished: ((SegmentedFinalizeReport) -> Void)?
    ) throws -> SegmentedRecordingPipeline {
        let root = try ensureRecoveryRootDirectory()
        let pipelineID = UUID()
        let pipelineDir = root.appendingPathComponent(pipelineID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pipelineDir, withIntermediateDirectories: true)
        let manifestURL = pipelineDir.appendingPathComponent("manifest.json")
        let now = Date()
        let manifest = SegmentedRecoveryManifest(
            pipelineID: pipelineID,
            sessionID: sessionID,
            createdAt: now,
            updatedAt: now,
            segmentSeconds: defaultSegmentSeconds,
            overlapSeconds: defaultOverlapSeconds,
            recordingStopped: false,
            mergedText: "",
            jobs: []
        )
        let pipeline = SegmentedRecordingPipeline(
            settings: settings,
            pipelineDir: pipelineDir,
            manifestURL: manifestURL,
            manifest: manifest,
            recovering: false,
            onSnapshot: onSnapshot,
            onFinished: onFinished
        )
        try pipeline.persistManifestSync()
        return pipeline
    }

    static func openExisting(
        pipelineID: UUID,
        settings: SettingsManager,
        recovering: Bool,
        onSnapshot: ((SegmentedProgressSnapshot) -> Void)?,
        onFinished: ((SegmentedFinalizeReport) -> Void)?
    ) throws -> SegmentedRecordingPipeline {
        let root = try ensureRecoveryRootDirectory()
        let pipelineDir = root.appendingPathComponent(pipelineID.uuidString, isDirectory: true)
        let manifestURL = pipelineDir.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(SegmentedRecoveryManifest.self, from: data)
        return SegmentedRecordingPipeline(
            settings: settings,
            pipelineDir: pipelineDir,
            manifestURL: manifestURL,
            manifest: manifest,
            recovering: recovering,
            onSnapshot: onSnapshot,
            onFinished: onFinished
        )
    }

    static func recoverablePipelineIDs() -> [UUID] {
        guard let root = try? ensureRecoveryRootDirectory() else { return [] }
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return dirs.compactMap { UUID(uuidString: $0.lastPathComponent) }
    }

    static func diagnosticsSummary() -> String {
        let ids = recoverablePipelineIDs()
        return "segmentedPipelineRecoveryCount=\(ids.count), ids=\(ids.map { $0.uuidString }.joined(separator: ","))"
    }

    func pipelineID() -> UUID {
        manifest.pipelineID
    }

    func sessionID() -> UUID {
        manifest.sessionID
    }

    func appendFrame(_ frame: Data) {
        queue.async {
            guard !self.manifest.recordingStopped else { return }
            self.livePCM.append(frame)
            self.cutReadySegmentsIfNeeded()
        }
    }

    func stopRecording() {
        queue.async {
            guard !self.manifest.recordingStopped else { return }
            self.manifest.recordingStopped = true
            self.emitTailSegmentIfNeeded()
            self.persistManifest()
            self.schedulePendingIfNeeded()
            self.tryFinishIfPossible()
            self.emitSnapshot(stageText: "分段收尾中...")
        }
    }

    func beginRecovery(retryFailedSegments: Bool) {
        queue.async {
            self.manifest.recordingStopped = true
            for idx in self.manifest.jobs.indices {
                switch self.manifest.jobs[idx].status {
                case .processing:
                    self.manifest.jobs[idx].status = .pending
                case .failed where retryFailedSegments:
                    self.manifest.jobs[idx].status = .pending
                    self.manifest.jobs[idx].attempts = 0
                    self.manifest.jobs[idx].nextRetryAt = Date()
                default:
                    break
                }
            }
            self.persistManifest()
            self.schedulePendingIfNeeded()
            self.tryFinishIfPossible()
            self.emitSnapshot(stageText: "恢复中...")
        }
    }

    func retryFailedSegment(_ index: Int) {
        retryFailedSegments([index])
    }

    func retryFailedSegments(_ indices: [Int]) {
        queue.async {
            guard !indices.isEmpty else { return }
            var changed = false
            for target in indices {
                guard let idx = self.manifest.jobs.firstIndex(where: { $0.index == target }) else { continue }
                guard self.manifest.jobs[idx].status == .failed else { continue }
                self.manifest.jobs[idx].status = .pending
                self.manifest.jobs[idx].attempts = 0
                self.manifest.jobs[idx].nextRetryAt = Date()
                self.manifest.jobs[idx].lastError = nil
                changed = true
            }
            guard changed else { return }
            self.finished = false
            self.manifest.recordingStopped = true
            self.persistManifest()
            self.schedulePendingIfNeeded()
            self.emitSnapshot(stageText: "失败分段重试中...")
        }
    }

    func cancel() {
        queue.async {
            self.finished = true
            let clients = self.inFlight.values
            self.inFlight.removeAll()
            for client in clients {
                client.cancel()
            }
            for work in self.retryWork.values {
                work.cancel()
            }
            self.retryWork.removeAll()
        }
    }

    private func cutReadySegmentsIfNeeded() {
        guard segmentBytes > overlapBytes else { return }
        while livePCM.count >= segmentBytes {
            let segmentPCM = Data(livePCM.prefix(segmentBytes))
            enqueueSegment(pcm: segmentPCM)
            livePCM.removeFirst(stepBytes)
        }
    }

    private func emitTailSegmentIfNeeded() {
        guard !livePCM.isEmpty else { return }
        let shouldEmit = manifest.jobs.isEmpty || livePCM.count > overlapBytes
        if shouldEmit {
            enqueueSegment(pcm: livePCM)
        }
        livePCM.removeAll(keepingCapacity: false)
    }

    private func enqueueSegment(pcm: Data) {
        let index = (manifest.jobs.map { $0.index }.max() ?? -1) + 1
        let filename = "segment-\(index).wav"
        let url = pipelineDir.appendingPathComponent(filename)
        let wav = makeWav(pcm16Mono16k: pcm, sampleRate: Int(kSampleRate), channels: Int(kChannels))
        do {
            try wav.write(to: url, options: .atomic)
            let job = SegmentJob(index: index, wavFileName: filename, status: .pending, attempts: 0, nextRetryAt: Date(), text: nil, lastError: nil)
            manifest.jobs.append(job)
            manifest.updatedAt = Date()
            persistManifest()
            schedulePendingIfNeeded()
            emitSnapshot(stageText: "分段录音中...")
        } catch {
            Console.line("Failed to persist segment \(index): \(error.localizedDescription)")
        }
    }

    private func schedulePendingIfNeeded() {
        guard !finished else { return }
        while inFlight.count < Self.maxConcurrency {
            guard let idx = nextRunnablePendingIndex() else { break }
            manifest.jobs[idx].status = .processing
            manifest.jobs[idx].attempts += 1
            manifest.jobs[idx].nextRetryAt = nil
            manifest.jobs[idx].lastError = nil
            let job = manifest.jobs[idx]
            persistManifest()
            startTranscription(job: job)
        }
    }

    private func nextRunnablePendingIndex() -> Int? {
        let now = Date()
        return manifest.jobs.firstIndex {
            $0.status == .pending && ($0.nextRetryAt == nil || $0.nextRetryAt! <= now)
        }
    }

    private func startTranscription(job: SegmentJob) {
        let segmentURL = pipelineDir.appendingPathComponent(job.wavFileName)
        guard let wav = try? Data(contentsOf: segmentURL), !wav.isEmpty else {
            markFailure(index: job.index, message: "分段音频不存在或为空")
            return
        }

        let endpointString = settings.fileASRURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: endpointString) else {
            markFailure(index: job.index, message: "无效的 File ASR URL")
            return
        }
        let apiKey = settings.effectiveDashscopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            markFailure(index: job.index, message: "Dashscope API Key 为空")
            return
        }

        let client = FileASRStreamClient(
            apiKey: apiKey,
            endpoint: endpoint,
            model: settings.fileModel,
            language: settings.language,
            timeout: 140.0
        )

        var text = ""
        var errorMessage: String?

        inFlight[job.index] = client

        client.onDelta = { delta in
            text += delta
        }
        client.onError = { msg in
            if errorMessage == nil {
                errorMessage = msg
            }
        }
        client.onDone = { [weak self] in
            self?.queue.async {
                guard let self else { return }
                self.inFlight[job.index] = nil
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self.markSuccess(index: job.index, text: trimmed)
                } else {
                    self.markFailure(index: job.index, message: errorMessage ?? "分段返回空结果")
                }
            }
        }
        client.start(base64Wav: wav.base64EncodedString())
    }

    private func markSuccess(index: Int, text: String) {
        guard let idx = manifest.jobs.firstIndex(where: { $0.index == index }) else { return }
        manifest.jobs[idx].status = .succeeded
        manifest.jobs[idx].text = text
        manifest.jobs[idx].lastError = nil
        manifest.jobs[idx].nextRetryAt = nil
        updateMergedTextCheckpoint()
        persistManifest()
        schedulePendingIfNeeded()
        emitSnapshot(stageText: manifest.recordingStopped ? "分段转写收敛中..." : "分段转写中...")
        tryFinishIfPossible()
    }

    private func markFailure(index: Int, message: String) {
        guard let idx = manifest.jobs.firstIndex(where: { $0.index == index }) else { return }
        let attempts = manifest.jobs[idx].attempts
        manifest.jobs[idx].lastError = message

        if attempts < Self.maxAttempts {
            manifest.jobs[idx].status = .pending
            let delay = pow(2.0, Double(max(0, attempts - 1)))
            manifest.jobs[idx].nextRetryAt = Date().addingTimeInterval(delay)
            retryWork[index]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.queue.async {
                    self?.retryWork[index] = nil
                    self?.schedulePendingIfNeeded()
                    self?.tryFinishIfPossible()
                }
            }
            retryWork[index] = work
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            manifest.jobs[idx].status = .failed
            manifest.jobs[idx].nextRetryAt = nil
        }

        updateMergedTextCheckpoint()
        persistManifest()
        schedulePendingIfNeeded()
        emitSnapshot(stageText: "分段失败，正在重试...")
        tryFinishIfPossible()
    }

    private func updateMergedTextCheckpoint() {
        let pairs: [(Int, String)] = manifest.jobs.compactMap { job in
            guard job.status == .succeeded, let text = job.text, !text.isEmpty else { return nil }
            return (job.index, text)
        }
        let map = Dictionary(uniqueKeysWithValues: pairs)
        manifest.mergedText = OverlapTextMerger.mergeOrderedSegments(map, total: manifest.jobs.count)
        manifest.updatedAt = Date()
    }

    private func tryFinishIfPossible() {
        guard manifest.recordingStopped else { return }
        guard inFlight.isEmpty else { return }
        guard !manifest.jobs.contains(where: { $0.status == .pending || $0.status == .processing }) else { return }

        if finished { return }
        finished = true

        updateMergedTextCheckpoint()
        persistManifest()

        let failed = manifest.jobs.filter { $0.status == .failed }.map { $0.index }.sorted()
        let merged = manifest.mergedText.trimmingCharacters(in: .whitespacesAndNewlines)
        emitSnapshot(stageText: failed.isEmpty ? "分段转写完成" : "分段转写完成（存在失败段）")

        if failed.isEmpty {
            cleanupArtifacts()
        }

        let report = SegmentedFinalizeReport(
            pipelineID: manifest.pipelineID,
            sessionID: manifest.sessionID,
            mergedText: merged,
            failedSegments: failed,
            totalSegments: manifest.jobs.count,
            recovering: recovering
        )
        onFinished?(report)
    }

    private func emitSnapshot(stageText: String) {
        let failed = manifest.jobs.filter { $0.status == .failed }.map { $0.index }.sorted()
        let completed = manifest.jobs.filter { $0.status == .succeeded || $0.status == .failed }.count
        let total = manifest.jobs.count
        let progress = total == 0 ? 0 : min(1.0, max(0.0, Double(completed) / Double(total)))
        let snap = SegmentedProgressSnapshot(
            pipelineID: manifest.pipelineID,
            sessionID: manifest.sessionID,
            totalSegments: total,
            completedSegments: completed,
            failedSegments: failed,
            mergedText: manifest.mergedText,
            stageText: stageText,
            progress: progress,
            recordingStopped: manifest.recordingStopped,
            recovering: recovering
        )
        onSnapshot?(snap)
    }

    private func persistManifest() {
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            Console.line("Persist segmented manifest failed: \(error.localizedDescription)")
        }
    }

    private func persistManifestSync() throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func cleanupArtifacts() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        retryWork.values.forEach { $0.cancel() }
        retryWork.removeAll()
        try? FileManager.default.removeItem(at: pipelineDir)
    }

    private static func ensureRecoveryRootDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let root = appSupport
            .appendingPathComponent("FlashASR", isDirectory: true)
            .appendingPathComponent("segment-recovery", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
