import Foundation

public enum ReminderScheduleCodec {
    public static func encode(_ schedule: ReminderSchedule) throws -> String {
        try validate(schedule)

        let envelope = envelope(for: schedule)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ReminderScheduleCodecError.encodingFailed
        }
        return json
    }

    public static func decode(_ json: String) throws -> ReminderSchedule {
        guard let data = json.data(using: .utf8) else {
            throw ReminderScheduleCodecError.malformedPayload
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw ReminderScheduleCodecError.malformedPayload
        }

        guard envelope.schemaVersion == 1 else {
            throw ReminderScheduleCodecError.unsupportedSchemaVersion
        }

        let schedule = try schedule(from: envelope)
        try validate(schedule)
        return schedule
    }

    private static func envelope(for schedule: ReminderSchedule) -> Envelope {
        switch schedule {
        case let .oneTime(date):
            Envelope(schemaVersion: 1, type: .oneTime, date: date)
        case let .daily(hour, minute):
            Envelope(schemaVersion: 1, type: .daily, hour: hour, minute: minute)
        case let .weekly(weekdays, hour, minute):
            Envelope(
                schemaVersion: 1,
                type: .weekly,
                hour: hour,
                minute: minute,
                weekdays: weekdays.map(\.rawValue).sorted()
            )
        case let .intervalDays(count, hour, minute):
            Envelope(schemaVersion: 1, type: .intervalDays, hour: hour, minute: minute, count: count)
        }
    }

    private static func schedule(from envelope: Envelope) throws -> ReminderSchedule {
        switch envelope.type {
        case .oneTime:
            guard let date = envelope.date,
                  envelope.hour == nil,
                  envelope.minute == nil,
                  envelope.weekdays == nil,
                  envelope.count == nil else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            return .oneTime(date)
        case .daily:
            guard let hour = envelope.hour,
                  let minute = envelope.minute,
                  envelope.date == nil,
                  envelope.weekdays == nil,
                  envelope.count == nil else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            return .daily(hour: hour, minute: minute)
        case .weekly:
            guard let rawWeekdays = envelope.weekdays,
                  rawWeekdays.count == Set(rawWeekdays).count,
                  let hour = envelope.hour,
                  let minute = envelope.minute,
                  envelope.date == nil,
                  envelope.count == nil else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            let weekdays = Set(rawWeekdays.compactMap(ReminderWeekday.init(rawValue:)))
            guard weekdays.count == rawWeekdays.count else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            return .weekly(weekdays: weekdays, hour: hour, minute: minute)
        case .intervalDays:
            guard let count = envelope.count,
                  let hour = envelope.hour,
                  let minute = envelope.minute,
                  envelope.date == nil,
                  envelope.weekdays == nil else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            return .intervalDays(count: count, hour: hour, minute: minute)
        }
    }

    private static func validate(_ schedule: ReminderSchedule) throws {
        switch schedule {
        case let .oneTime(date):
            guard date.timeIntervalSince1970.isFinite else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
        case let .daily(hour, minute):
            try validate(hour: hour, minute: minute)
        case let .weekly(weekdays, hour, minute):
            guard !weekdays.isEmpty else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            try validate(hour: hour, minute: minute)
        case let .intervalDays(count, hour, minute):
            guard count >= 1 else {
                throw ReminderScheduleCodecError.invalidSchedule
            }
            try validate(hour: hour, minute: minute)
        }
    }

    private static func validate(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ReminderScheduleCodecError.invalidSchedule
        }
    }
}

private enum ReminderScheduleCodecError: Error {
    case malformedPayload
    case unsupportedSchemaVersion
    case invalidSchedule
    case encodingFailed
}

private struct Envelope: Codable {
    let schemaVersion: Int
    let type: ScheduleType
    let date: Date?
    let hour: Int?
    let minute: Int?
    let weekdays: [Int]?
    let count: Int?

    init(
        schemaVersion: Int,
        type: ScheduleType,
        date: Date? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        weekdays: [Int]? = nil,
        count: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.type = type
        self.date = date
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.count = count
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case type
        case date
        case hour
        case minute
        case weekdays
        case count
    }

    init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(keyedBy: AnyCodingKey.self).allKeys
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let type = try container.decode(ScheduleType.self, forKey: .type)

        let expectedKeys: Set<String>
        switch type {
        case .oneTime:
            expectedKeys = ["schemaVersion", "type", "date"]
        case .daily:
            expectedKeys = ["schemaVersion", "type", "hour", "minute"]
        case .weekly:
            expectedKeys = ["schemaVersion", "type", "hour", "minute", "weekdays"]
        case .intervalDays:
            expectedKeys = ["schemaVersion", "type", "hour", "minute", "count"]
        }

        guard Set(allKeys.map(\.stringValue)) == expectedKeys else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid reminder schedule key shape")
            )
        }

        self.schemaVersion = schemaVersion
        self.type = type
        self.date = try container.decodeIfPresent(Date.self, forKey: .date)
        self.hour = try container.decodeIfPresent(Int.self, forKey: .hour)
        self.minute = try container.decodeIfPresent(Int.self, forKey: .minute)
        self.weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays)
        self.count = try container.decodeIfPresent(Int.self, forKey: .count)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(hour, forKey: .hour)
        try container.encodeIfPresent(minute, forKey: .minute)
        try container.encodeIfPresent(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(count, forKey: .count)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum ScheduleType: String, Codable {
    case oneTime
    case daily
    case weekly
    case intervalDays
}
