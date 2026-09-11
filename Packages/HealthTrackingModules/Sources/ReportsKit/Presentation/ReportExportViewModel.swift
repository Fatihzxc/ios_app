import Foundation
import Observation

public enum ReportExportViewState: Equatable, Sendable {
    case idle
    case generating
    case ready
    case failed
}

@MainActor
@Observable
public final class ReportExportViewModel {
    public private(set) var selectedPreset: ReportDateRangePreset
    public private(set) var selectedModules: Set<ExportModuleV1>
    public private(set) var format: ReportExportFormat
    public private(set) var includesPhotos = false
    public private(set) var state: ReportExportViewState = .idle
    public private(set) var interval: ReportDateInterval?
    public private(set) var failure: (any Error)?
    public private(set) var isProgressVisible = false
    public private(set) var token: ExportArtifactToken?

    @ObservationIgnored private let generator: any ReportExportGenerating
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let progressDelay: @Sendable () async throws -> Void
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var activeGenerationID: UUID?
    @ObservationIgnored private var lastReferenceDate: Date?
    @ObservationIgnored private var cleanupTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        generator: any ReportExportGenerating,
        calendar: Calendar,
        selectedPreset: ReportDateRangePreset = .oneMonth,
        selectedModules: Set<ExportModuleV1> = Set(ExportModuleV1.allCases),
        format: ReportExportFormat = .csv,
        progressDelay: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(nanoseconds: 400_000_000)
        }
    ) {
        self.generator = generator
        self.calendar = calendar
        self.selectedPreset = selectedPreset
        self.selectedModules = selectedModules
        self.format = format
        self.progressDelay = progressDelay
    }

    public var shareURLs: [URL] { token?.shareURLs ?? [] }
    public var canRetry: Bool { state == .failed && lastReferenceDate != nil }
    public var canGenerate: Bool { !selectedModules.isEmpty && state != .generating }

    public func setPreset(_ preset: ReportDateRangePreset) {
        guard selectedPreset != preset else { return }
        selectedPreset = preset
        selectionDidChange()
    }

    public func toggleModule(_ module: ExportModuleV1) {
        if selectedModules.contains(module) {
            selectedModules.remove(module)
        } else {
            selectedModules.insert(module)
        }
        selectionDidChange()
    }

    public func setFormat(_ newFormat: ReportExportFormat) {
        guard format != newFormat else { return }
        format = newFormat
        if newFormat != .bothZip { includesPhotos = false }
        selectionDidChange()
    }

    public func setIncludesPhotos(_ included: Bool) {
        let normalized = format == .bothZip ? included : false
        guard includesPhotos != normalized else { return }
        includesPhotos = normalized
        selectionDidChange()
    }

    public func generate(referenceDate: Date) {
        lastReferenceDate = referenceDate
        startGeneration(referenceDate: referenceDate)
    }

    public func retry() {
        guard let lastReferenceDate else { return }
        startGeneration(referenceDate: lastReferenceDate)
    }

    public func cancel() {
        activeGenerationID = nil
        activeTask?.cancel()
        activeTask = nil
        stopProgress()
        cleanupCurrentToken()
        failure = nil
        state = .idle
    }

    public func shareDidFinish(completed: Bool) {
        _ = completed
        cleanupCurrentToken()
        failure = nil
        state = .idle
    }

    public func viewDidDisappear() {
        cancel()
    }

    public func waitForCurrentGeneration() async {
        let task = activeTask
        await task?.value
    }

    private func startGeneration(referenceDate: Date) {
        activeTask?.cancel()
        stopProgress()
        cleanupCurrentToken()

        let resolvedInterval: ReportDateInterval
        do {
            resolvedInterval = try ReportDateRangeResolver.resolve(
                selectedPreset,
                referenceDate: referenceDate,
                calendar: calendar
            )
        } catch {
            interval = nil
            failure = error
            state = .failed
            return
        }
        interval = resolvedInterval
        failure = nil
        state = .generating
        let generationID = UUID()
        activeGenerationID = generationID
        let request = ReportExportRequest(
            interval: resolvedInterval,
            modules: selectedModules,
            format: format,
            includesPhotos: includesPhotos
        )

        let delay = progressDelay
        progressTask = Task { [weak self] in
            do { try await delay() } catch { return }
            guard !Task.isCancelled,
                  let self,
                  self.activeGenerationID == generationID,
                  self.state == .generating else { return }
            self.isProgressVisible = true
        }

        let generator = self.generator
        activeTask = Task { [weak self] in
            do {
                let generatedToken = try await generator.generate(request)
                guard let self else {
                    _ = await generatedToken.beginCleanup().value
                    return
                }
                guard !Task.isCancelled, self.activeGenerationID == generationID else {
                    self.scheduleCleanup(generatedToken)
                    return
                }
                self.stopProgress()
                self.token = generatedToken
                self.failure = nil
                self.state = .ready
                self.activeGenerationID = nil
                self.activeTask = nil
            } catch is CancellationError {
                guard let self, self.activeGenerationID == generationID else { return }
                self.stopProgress()
                self.state = .idle
                self.activeGenerationID = nil
                self.activeTask = nil
            } catch {
                guard let self, self.activeGenerationID == generationID else { return }
                self.stopProgress()
                guard !Task.isCancelled else {
                    self.state = .idle
                    self.activeGenerationID = nil
                    self.activeTask = nil
                    return
                }
                self.failure = error
                self.state = .failed
                self.activeGenerationID = nil
                self.activeTask = nil
            }
        }
    }

    private func stopProgress() {
        progressTask?.cancel()
        progressTask = nil
        isProgressVisible = false
    }

    private func selectionDidChange() {
        activeGenerationID = nil
        activeTask?.cancel()
        activeTask = nil
        stopProgress()
        cleanupCurrentToken()
        interval = nil
        lastReferenceDate = nil
        failure = nil
        state = .idle
    }

    private func cleanupCurrentToken() {
        guard let current = token else { return }
        token = nil
        scheduleCleanup(current)
    }

    private func scheduleCleanup(_ token: ExportArtifactToken) {
        guard cleanupTasks[token.id] == nil else { return }
        let operation = token.beginCleanup()
        cleanupTasks[token.id] = Task { [weak self, token] in
            let succeeded = await operation.value
            guard let self else { return }
            self.cleanupTasks[token.id] = nil
            _ = succeeded
        }
    }
}
