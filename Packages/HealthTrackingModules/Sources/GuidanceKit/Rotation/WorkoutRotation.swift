import Foundation

public enum WorkoutRotation {
    public struct Template: Equatable, Sendable {
        public let id: UUID
        public let orderIndex: Int

        public init(id: UUID, orderIndex: Int) {
            self.id = id
            self.orderIndex = orderIndex
        }
    }

    public struct Completion: Equatable, Sendable {
        public let id: UUID
        public let templateID: UUID
        public let completedAt: Date

        public init(id: UUID, templateID: UUID, completedAt: Date) {
            self.id = id
            self.templateID = templateID
            self.completedAt = completedAt
        }
    }

    public enum DataError: Error, Equatable, Sendable {
        case missingTemplates
        case duplicateTemplateID(UUID)
        case duplicateOrderIndex(Int)
        case unknownCompletedTemplate(UUID)
    }

    public enum Outcome: Equatable, Sendable {
        case next(Template)
        case invalid(DataError)
    }

    public static func resolve(
        templates: [Template],
        completions: [Completion]
    ) -> Outcome {
        guard !templates.isEmpty else {
            return .invalid(.missingTemplates)
        }

        var templateIDs: Set<UUID> = []
        var orderIndexes: Set<Int> = []
        for template in templates {
            guard templateIDs.insert(template.id).inserted else {
                return .invalid(.duplicateTemplateID(template.id))
            }
            guard orderIndexes.insert(template.orderIndex).inserted else {
                return .invalid(.duplicateOrderIndex(template.orderIndex))
            }
        }

        let unknownTemplateIDs = Set(completions.map(\.templateID))
            .subtracting(templateIDs)
            .sorted { $0.uuidString < $1.uuidString }
        if let unknownTemplateID = unknownTemplateIDs.first {
            return .invalid(.unknownCompletedTemplate(unknownTemplateID))
        }

        let orderedTemplates = templates.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let latestCompletion = completions.max(by: completionIsEarlier) else {
            return .next(orderedTemplates[0])
        }
        guard let completedIndex = orderedTemplates.firstIndex(where: {
            $0.id == latestCompletion.templateID
        }) else {
            return .invalid(.unknownCompletedTemplate(latestCompletion.templateID))
        }

        let nextIndex = orderedTemplates.index(after: completedIndex)
        return .next(nextIndex == orderedTemplates.endIndex ? orderedTemplates[0] : orderedTemplates[nextIndex])
    }

    private static func completionIsEarlier(_ lhs: Completion, _ rhs: Completion) -> Bool {
        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt < rhs.completedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
