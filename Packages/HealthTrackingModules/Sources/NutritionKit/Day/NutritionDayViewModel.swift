import CoreModels
import Foundation
import Observation

public struct NutritionDayRetryContext: Equatable, Sendable {
    public let day: NutritionDayKey

    public init(day: NutritionDayKey) {
        self.day = day
    }
}

public struct NutritionMealSectionPresentation: Equatable, Sendable, Identifiable {
    public let category: MealCategory
    public let entries: [MealEntrySnapshot]
    public let subtotal: NutritionMacros

    public var id: MealCategory { category }

    public init(
        category: MealCategory,
        entries: [MealEntrySnapshot],
        subtotal: NutritionMacros
    ) {
        self.category = category
        self.entries = entries
        self.subtotal = subtotal
    }
}

public struct NutritionDayPresentation: Equatable, Sendable {
    public let day: NutritionDayKey
    public let totalMacros: NutritionMacros
    public let targets: NutritionTargetSummary
    public let sections: [NutritionMealSectionPresentation]

    public init(
        day: NutritionDayKey,
        totalMacros: NutritionMacros,
        targets: NutritionTargetSummary,
        sections: [NutritionMealSectionPresentation]
    ) {
        self.day = day
        self.totalMacros = totalMacros
        self.targets = targets
        self.sections = sections
    }
}

public enum NutritionDayViewState: Equatable, Sendable {
    case loading
    case empty(NutritionDayPresentation)
    case content(NutritionDayPresentation)
    case error(NutritionDayRetryContext)
}

public enum NutritionDayMutationState: Equatable, Sendable {
    case idle
    case deleting(entryID: UUID)
    case deleteError(entryID: UUID)
}

@MainActor
@Observable
public final class NutritionDayViewModel {
    public private(set) var state: NutritionDayViewState = .loading
    public private(set) var mutationState: NutritionDayMutationState = .idle
    public private(set) var selectedDay: NutritionDayKey

    @ObservationIgnored
    private let repository: any NutritionDayViewRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private var loadGeneration = 0
    @ObservationIgnored
    private var currentSnapshot: NutritionDayEntriesSnapshot?
    @ObservationIgnored
    private var currentTargets: NutritionMacroTargets?

    public init(
        repository: any NutritionDayViewRepository,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        guard let day = try? NutritionDayKey(
            containing: now(),
            calendar: calendar
        ) else {
            preconditionFailure("The injected calendar cannot resolve its current local day.")
        }
        selectedDay = day
    }

    public func load() async {
        await load(day: selectedDay, showsLoadingState: true)
    }

    public func retry() async {
        // Keep the day-scoped retry context visible until the reload completes
        // instead of removing its control subtree during the button action.
        await load(day: selectedDay, showsLoadingState: false)
    }

    public func selectPreviousDay() async {
        await moveSelectedDay(by: -1)
    }

    public func selectNextDay() async {
        await moveSelectedDay(by: 1)
    }

    public func selectDay(containing date: Date) async {
        guard let day = try? NutritionDayKey(containing: date, calendar: calendar) else {
            state = .error(NutritionDayRetryContext(day: selectedDay))
            return
        }
        selectedDay = day
        await load(day: day, showsLoadingState: true)
    }

    public func adjacentDay(by value: Int) -> NutritionDayKey? {
        guard let destination = calendar.date(
            byAdding: .day,
            value: value,
            to: selectedDay.start
        ) else {
            return nil
        }
        return try? NutritionDayKey(containing: destination, calendar: calendar)
    }

    public func deleteEntry(id: UUID) async {
        guard canBeginDelete(id: id),
              let originalSnapshot = currentSnapshot,
              originalSnapshot.entries.contains(where: { $0.id == id }) else {
            return
        }
        let mutationDay = selectedDay
        let mutationGeneration = loadGeneration
        let targets = currentTargets
        mutationState = .deleting(entryID: id)

        do {
            let optimisticSnapshot = try NutritionDayEntriesSnapshot(
                day: originalSnapshot.day,
                log: originalSnapshot.log,
                entries: originalSnapshot.entries.filter { $0.id != id }
            )
            currentSnapshot = optimisticSnapshot
            try publish(snapshot: optimisticSnapshot, targets: targets)

            let repositorySnapshot = try await repository.deleteMealEntry(id: id)
            guard loadGeneration == mutationGeneration,
                  selectedDay == mutationDay else { return }
            try validate(repositorySnapshot, belongsTo: mutationDay)
            currentSnapshot = repositorySnapshot
            try publish(snapshot: repositorySnapshot, targets: targets)
            mutationState = .idle
        } catch {
            guard loadGeneration == mutationGeneration,
                  selectedDay == mutationDay else { return }
            currentSnapshot = originalSnapshot
            try? publish(snapshot: originalSnapshot, targets: targets)
            mutationState = .deleteError(entryID: id)
        }
    }

    public func retryDelete() async {
        guard case let .deleteError(entryID) = mutationState else { return }
        await deleteEntry(id: entryID)
    }

    public func dismissMutationError() {
        if case .deleteError = mutationState {
            mutationState = .idle
        }
    }

    private func canBeginDelete(id: UUID) -> Bool {
        switch mutationState {
        case .idle:
            return true
        case let .deleteError(failedID):
            return failedID == id
        case .deleting:
            return false
        }
    }

    private func moveSelectedDay(by value: Int) async {
        guard let destination = adjacentDay(by: value) else {
            state = .error(NutritionDayRetryContext(day: selectedDay))
            return
        }
        selectedDay = destination
        await load(day: destination, showsLoadingState: true)
    }

    private func load(
        day: NutritionDayKey,
        showsLoadingState: Bool
    ) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        if showsLoadingState {
            state = .loading
        }
        mutationState = .idle

        do {
            let targets = try await repository.fetchNutritionTargets()
            let snapshot = try await repository.fetchMealEntries(containing: day.start)
            guard generation == loadGeneration, selectedDay == day else { return }
            try validate(snapshot, belongsTo: day)
            currentSnapshot = snapshot
            currentTargets = targets
            try publish(snapshot: snapshot, targets: targets)
        } catch {
            guard generation == loadGeneration, selectedDay == day else { return }
            currentSnapshot = nil
            currentTargets = nil
            state = .error(NutritionDayRetryContext(day: day))
        }
    }

    private func validate(
        _ snapshot: NutritionDayEntriesSnapshot,
        belongsTo day: NutritionDayKey
    ) throws {
        guard snapshot.day == day else {
            throw NutritionDayPresentationError.repositoryReturnedDifferentDay
        }
    }

    private func publish(
        snapshot: NutritionDayEntriesSnapshot,
        targets: NutritionMacroTargets?
    ) throws {
        let presentation = try Self.presentation(snapshot: snapshot, targets: targets)
        state = snapshot.entries.isEmpty
            ? .empty(presentation)
            : .content(presentation)
    }

    private static func presentation(
        snapshot: NutritionDayEntriesSnapshot,
        targets: NutritionMacroTargets?
    ) throws -> NutritionDayPresentation {
        let categories = try standardCategories() + customCategories(in: snapshot.entries)
        let sections = try categories.map { category in
            NutritionMealSectionPresentation(
                category: category,
                entries: snapshot.entries.filter { $0.category == category },
                subtotal: try snapshot.totalMacros(for: category)
            )
        }
        let effectiveTargets = targets ?? NutritionMacroTargets(
            calories: nil,
            proteinG: nil,
            carbG: nil,
            fatG: nil
        )
        return NutritionDayPresentation(
            day: snapshot.day,
            totalMacros: snapshot.totalMacros,
            targets: try NutritionTargetSummary(
                consumed: snapshot.totalMacros,
                targets: effectiveTargets
            ),
            sections: sections
        )
    }

    private static func standardCategories() throws -> [MealCategory] {
        try [
            MealCategory.Kind.breakfast,
            .lunch,
            .dinner,
            .snack,
        ].map { try MealCategory(kind: $0) }
    }

    private static func customCategories(
        in entries: [MealEntrySnapshot]
    ) -> [MealCategory] {
        Array(Set(entries.map(\.category).filter { $0.kind == .custom }))
            .sorted { lhs, rhs in
                let leftName = lhs.customName ?? ""
                let rightName = rhs.customName ?? ""
                let leftKey = customSortKey(leftName)
                let rightKey = customSortKey(rightName)
                if leftKey != rightKey { return leftKey < rightKey }
                return leftName < rightName
            }
    }

    private static func customSortKey(_ value: String) -> String {
        let locale = Locale(identifier: "tr_TR")
        return value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }
}

private enum NutritionDayPresentationError: Error {
    case repositoryReturnedDifferentDay
}
