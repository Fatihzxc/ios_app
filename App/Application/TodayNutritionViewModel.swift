import Foundation
import NutritionKit
import Observation
import TrainingKit

enum TodayNutritionMapper {
    static func presentation(
        snapshot: NutritionDayEntriesSnapshot,
        targets: NutritionMacroTargets?
    ) -> TodayNutritionPresentation {
        let targets = targets ?? NutritionMacroTargets(
            calories: nil,
            proteinG: nil,
            carbG: nil,
            fatG: nil
        )
        return TodayNutritionPresentation(
            calories: metric(
                consumed: snapshot.totalMacros.calories,
                target: targets.calories
            ),
            protein: metric(
                consumed: snapshot.totalMacros.proteinG,
                target: targets.proteinG
            ),
            carbs: metric(
                consumed: snapshot.totalMacros.carbG,
                target: targets.carbG
            ),
            fat: metric(
                consumed: snapshot.totalMacros.fatG,
                target: targets.fatG
            )
        )
    }

    private static func metric(
        consumed: Decimal,
        target: Decimal?
    ) -> TodayNutritionMetricPresentation {
        guard let target, target.isFinite, target > 0 else {
            return TodayNutritionMetricPresentation(
                consumed: consumed,
                target: nil,
                remaining: nil,
                progress: nil
            )
        }
        let consumedNumber = NSDecimalNumber(decimal: consumed)
        let targetNumber = NSDecimalNumber(decimal: target)
        return TodayNutritionMetricPresentation(
            consumed: consumed,
            target: target,
            remaining: targetNumber
                .subtracting(consumedNumber)
                .decimalValue,
            progress: consumedNumber
                .dividing(by: targetNumber)
                .decimalValue
        )
    }
}

@MainActor
@Observable
final class TodayNutritionViewModel {
    private(set) var state: TodayNutritionViewState = .loading

    @ObservationIgnored
    private let repository: any NutritionDayViewRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private var currentDay: NutritionDayKey?
    @ObservationIgnored
    private var currentTargets: NutritionMacroTargets?
    @ObservationIgnored
    private var loadGeneration = 0

    init(
        repository: any NutritionDayViewRepository,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        state = .loading
        do {
            let date = now()
            let day = try NutritionDayKey(containing: date, calendar: calendar)
            let targets = try await repository.fetchNutritionTargets()
            let snapshot = try await repository.fetchMealEntries(containing: date)
            guard generation == loadGeneration, snapshot.day == day else { return }
            currentDay = day
            currentTargets = targets
            publish(snapshot)
        } catch {
            guard generation == loadGeneration else { return }
            state = .error
        }
    }

    func retry() async {
        await load()
    }

    func apply(snapshot: NutritionDayEntriesSnapshot) {
        guard let today = try? NutritionDayKey(
            containing: now(),
            calendar: calendar
        ), snapshot.day == today else {
            return
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        currentDay = today
        publish(snapshot)
        if currentTargets == nil {
            Task { [weak self] in
                await self?.reconcileTargetsIfNeeded(
                    snapshot: snapshot,
                    generation: generation
                )
            }
        }
    }

    private func reconcileTargetsIfNeeded(
        snapshot: NutritionDayEntriesSnapshot,
        generation: Int
    ) async {
        do {
            let targets = try await repository.fetchNutritionTargets()
            guard generation == loadGeneration,
                  currentDay == snapshot.day else {
                return
            }
            currentTargets = targets
            publish(snapshot)
        } catch {
            // Preserve the valid meal total. A later explicit load can retry
            // target retrieval without blocking the workout or quick-add path.
        }
    }

    private func publish(_ snapshot: NutritionDayEntriesSnapshot) {
        let presentation = TodayNutritionMapper.presentation(
            snapshot: snapshot,
            targets: currentTargets
        )
        state = snapshot.entries.isEmpty
            ? .empty(presentation)
            : .content(presentation)
    }
}
