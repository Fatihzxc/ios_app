import CoreModels
import Foundation

public enum HealthCheckReminderInputError: Error, Equatable, Sendable {
    case missingName
}

public struct HealthCheckReminderInput: Equatable, Sendable {
    public let name: String
    public let dueDate: Date
    public let recurrence: HealthCheckRecurrence

    public init(
        name: String,
        dueDate: Date,
        recurrence: HealthCheckRecurrence
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw HealthCheckReminderInputError.missingName
        }
        self.name = normalizedName
        self.dueDate = dueDate
        self.recurrence = recurrence
    }
}

public enum HealthCheckDueState: Equatable, Sendable {
    case due
    case pending
    case done
}

public struct HealthCheckReminderSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let name: String
    public let dueDate: Date
    public let recurrence: HealthCheckRecurrence
    public let status: HealthCheckStatus

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        name: String,
        dueDate: Date,
        recurrence: HealthCheckRecurrence,
        status: HealthCheckStatus
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.dueDate = dueDate
        self.recurrence = recurrence
        self.status = status
    }

    public func dueState(
        at date: Date,
        calendar: Calendar
    ) -> HealthCheckDueState {
        guard status == .pending else { return .done }
        guard let startOfTomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) else {
            return dueDate <= date ? .due : .pending
        }
        return dueDate < startOfTomorrow ? .due : .pending
    }
}

public enum HealthCheckReminderOrdering {
    public static func dueFirst(
        _ lhs: HealthCheckReminderSnapshot,
        _ rhs: HealthCheckReminderSnapshot
    ) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public struct HealthCheckCompletionMutation: Equatable, Sendable {
    public let completed: HealthCheckReminderSnapshot
    public let successor: HealthCheckReminderSnapshot?

    public init(
        completed: HealthCheckReminderSnapshot,
        successor: HealthCheckReminderSnapshot?
    ) {
        self.completed = completed
        self.successor = successor
    }
}
