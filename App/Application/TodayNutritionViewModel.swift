import Foundation
import NutritionKit
import Observation
import TrainingKit

@MainActor
@Observable
final class TodayNutritionViewModel {
    private(set) var state: TodayNutritionViewState = .loading
    private(set) var selectedDay: NutritionDayKey

    @ObservationIgnored
    private let repository: any NutritionQuickAddRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private var loadGeneration = 0

    init(
        repository: any NutritionQuickAddRepository,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
        guard let day = try? NutritionDayKey(containing: now(), calendar: calendar) else {
            preconditionFailure("The injected calendar cannot resolve Today nutrition.")
        }
        selectedDay = day
    }

    func load() async {
        await load(at: now())
    }

    func load(at date: Date) async {
        guard let day = try? NutritionDayKey(containing: date, calendar: calendar) else {
            state = .error
            return
        }
        selectedDay = day
        loadGeneration &+= 1
        let generation = loadGeneration
        state = .loading
        do {
            let context = try await repository.fetchQuickAddContext(containing: day.start)
            guard generation == loadGeneration, selectedDay == day else { return }
            guard context.daySnapshot.day == day else {
                throw TodayNutritionMappingError.invalidDay
            }
            try publish(snapshot: context.daySnapshot, targets: context.targets)
        } catch {
            guard generation == loadGeneration, selectedDay == day else { return }
            state = .error
        }
    }

    func apply(
        snapshot: NutritionDayEntriesSnapshot,
        targets: NutritionMacroTargets?
    ) {
        guard snapshot.day == selectedDay else { return }
        loadGeneration &+= 1
        do {
            try publish(snapshot: snapshot, targets: targets)
        } catch {
            state = .error
        }
    }

    private func publish(
        snapshot: NutritionDayEntriesSnapshot,
        targets: NutritionMacroTargets?
    ) throws {
        let effectiveTargets = targets ?? NutritionMacroTargets(
            calories: nil,
            proteinG: nil,
            carbG: nil,
            fatG: nil
        )
        let summary = try NutritionTargetSummary(
            consumed: snapshot.totalMacros,
            targets: effectiveTargets
        )
        let presentation = TodayNutritionPresentation(
            calories: metric(summary.calories),
            protein: metric(summary.proteinG),
            carbG: metric(summary.carbG),
            fatG: metric(summary.fatG)
        )
        state = snapshot.entries.isEmpty ? .empty(presentation) : .content(presentation)
    }

    private func metric(
        _ value: NutritionTargetPresentation
    ) -> TodayNutritionMetricPresentation {
        switch value {
        case let .total(consumed):
            TodayNutritionMetricPresentation(
                consumed: consumed,
                target: nil,
                remaining: nil,
                clampedProgress: nil
            )
        case let .targeted(consumed, target, remaining, progress):
            TodayNutritionMetricPresentation(
                consumed: consumed,
                target: target,
                remaining: remaining,
                clampedProgress: min(max(progress, 0), 1)
            )
        }
    }
}

private enum TodayNutritionMappingError: Error {
    case invalidDay
}
