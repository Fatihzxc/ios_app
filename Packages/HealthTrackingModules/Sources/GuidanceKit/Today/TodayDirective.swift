import Foundation

public enum TodayDirective {
    public struct Session: Equatable, Sendable {
        public enum Status: Equatable, Sendable {
            case planned
            case inProgress
            case completed
            case skipped
        }

        public let id: UUID
        public let templateID: UUID
        public let date: Date
        public let status: Status

        public init(id: UUID, templateID: UUID, date: Date, status: Status) {
            self.id = id
            self.templateID = templateID
            self.date = date
            self.status = status
        }
    }

    public struct Input: Equatable, Sendable {
        public let templates: [WorkoutRotation.Template]
        public let sessions: [Session]
        public let weeklyWorkoutTarget: Int
        public let overrideRest: Bool

        public init(
            templates: [WorkoutRotation.Template],
            sessions: [Session],
            weeklyWorkoutTarget: Int,
            overrideRest: Bool
        ) {
            self.templates = templates
            self.sessions = sessions
            self.weeklyWorkoutTarget = weeklyWorkoutTarget
            self.overrideRest = overrideRest
        }
    }

    public enum RestReason: Equatable, Sendable {
        case completedToday
        case completedPreviousCalendarDay
        case weeklyTargetReached(completed: Int, target: Int)
    }

    public enum TrainReason: Equatable, Sendable {
        case scheduled
        case restOverride(RestReason)
    }

    public enum DataError: Error, Equatable, Sendable {
        case rotation(WorkoutRotation.DataError)
        case invalidWeeklyWorkoutTarget(Int)
        case multipleInProgressSessions(count: Int)
        case unknownInProgressTemplate(UUID)
        case calendarCalculationFailed
    }

    public enum Outcome: Equatable, Sendable {
        case resume(sessionID: UUID, templateID: UUID)
        case train(templateID: UUID, reason: TrainReason)
        case rest(reason: RestReason, nextTemplateID: UUID)
        case invalid(DataError)
    }

    public static func resolve(
        input: Input,
        now: Date,
        calendar: Calendar
    ) -> Outcome {
        let templateValidation = WorkoutRotation.resolve(
            templates: input.templates,
            completions: []
        )
        if case let .invalid(error) = templateValidation {
            return .invalid(.rotation(error))
        }

        let inProgressSessions = input.sessions.filter { $0.status == .inProgress }
        guard inProgressSessions.count <= 1 else {
            return .invalid(.multipleInProgressSessions(count: inProgressSessions.count))
        }
        if let inProgress = inProgressSessions.first {
            guard input.templates.contains(where: { $0.id == inProgress.templateID }) else {
                return .invalid(.unknownInProgressTemplate(inProgress.templateID))
            }
            return .resume(sessionID: inProgress.id, templateID: inProgress.templateID)
        }

        guard input.weeklyWorkoutTarget > 0 else {
            return .invalid(.invalidWeeklyWorkoutTarget(input.weeklyWorkoutTarget))
        }

        let completedSessions = input.sessions.filter { $0.status == .completed }
        let rotation = WorkoutRotation.resolve(
            templates: input.templates,
            completions: completedSessions.map {
                WorkoutRotation.Completion(
                    id: $0.id,
                    templateID: $0.templateID,
                    completedAt: $0.date
                )
            }
        )
        let nextTemplate: WorkoutRotation.Template
        switch rotation {
        case let .next(template):
            nextTemplate = template
        case let .invalid(error):
            return .invalid(.rotation(error))
        }

        let restReason: RestReason?
        if completedSessions.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            restReason = .completedToday
        } else {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: now),
                  let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
            else {
                return .invalid(.calendarCalculationFailed)
            }
            if completedSessions.contains(where: {
                calendar.isDate($0.date, inSameDayAs: previousDay)
            }) {
                restReason = .completedPreviousCalendarDay
            } else {
                let completedThisWeek = completedSessions.filter {
                    currentWeek.contains($0.date)
                }.count
                restReason = completedThisWeek >= input.weeklyWorkoutTarget
                    ? .weeklyTargetReached(
                        completed: completedThisWeek,
                        target: input.weeklyWorkoutTarget
                    )
                    : nil
            }
        }

        if let restReason {
            if input.overrideRest {
                return .train(
                    templateID: nextTemplate.id,
                    reason: .restOverride(restReason)
                )
            }
            return .rest(reason: restReason, nextTemplateID: nextTemplate.id)
        }
        return .train(templateID: nextTemplate.id, reason: .scheduled)
    }
}
