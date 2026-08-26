import Foundation

public struct QuickEntryValidationIssue: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let fieldIdentifier: String?
    public let localizedMessage: String
    public let accessibilityAnnouncement: String

    public init(
        id: String,
        fieldIdentifier: String? = nil,
        localizedMessage: String,
        accessibilityAnnouncement: String
    ) {
        self.id = id
        self.fieldIdentifier = fieldIdentifier
        self.localizedMessage = localizedMessage
        self.accessibilityAnnouncement = accessibilityAnnouncement
    }
}
