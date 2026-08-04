import CoreModels
import XCTest

final class ReminderScheduleCodecTests: XCTestCase {
    func testOneTimeEncodesDeterministicallyAndRoundTrips() throws {
        let schedule = ReminderSchedule.oneTime(Date(timeIntervalSince1970: 1_704_067_200.123))

        let json = try ReminderScheduleCodec.encode(schedule)

        XCTAssertEqual(json, #"{"date":1704067200123,"schemaVersion":1,"type":"oneTime"}"#)
        XCTAssertEqual(try ReminderScheduleCodec.decode(json), schedule)
    }

    func testDailyEncodesDeterministicallyAndRoundTrips() throws {
        let schedule = ReminderSchedule.daily(hour: 7, minute: 5)

        let json = try ReminderScheduleCodec.encode(schedule)

        XCTAssertEqual(json, #"{"hour":7,"minute":5,"schemaVersion":1,"type":"daily"}"#)
        XCTAssertEqual(try ReminderScheduleCodec.decode(json), schedule)
    }

    func testWeeklyEncodesSortedWeekdaysAndRoundTrips() throws {
        let schedule = ReminderSchedule.weekly(
            weekdays: [.friday, .monday, .sunday],
            hour: 18,
            minute: 30
        )

        let json = try ReminderScheduleCodec.encode(schedule)

        XCTAssertEqual(json, #"{"hour":18,"minute":30,"schemaVersion":1,"type":"weekly","weekdays":[1,2,6]}"#)
        XCTAssertEqual(try ReminderScheduleCodec.decode(json), schedule)
    }

    func testIntervalDaysEncodesDeterministicallyAndRoundTrips() throws {
        let schedule = ReminderSchedule.intervalDays(count: 3, hour: 9, minute: 45)

        let json = try ReminderScheduleCodec.encode(schedule)

        XCTAssertEqual(json, #"{"count":3,"hour":9,"minute":45,"schemaVersion":1,"type":"intervalDays"}"#)
        XCTAssertEqual(try ReminderScheduleCodec.decode(json), schedule)
    }

    func testDecodeRejectsUnsupportedSchemaVersion() {
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"hour":9,"minute":0,"schemaVersion":2,"type":"daily"}"#)
        )
    }

    func testDecodeRejectsMalformedJSON() {
        XCTAssertThrowsError(try ReminderScheduleCodec.decode("not json"))
    }

    func testCodecRejectsInvalidHoursAndMinutes() {
        XCTAssertThrowsError(try ReminderScheduleCodec.encode(.daily(hour: -1, minute: 0)))
        XCTAssertThrowsError(try ReminderScheduleCodec.encode(.daily(hour: 24, minute: 0)))
        XCTAssertThrowsError(try ReminderScheduleCodec.decode(#"{"hour":12,"minute":60,"schemaVersion":1,"type":"daily"}"#))
    }

    func testCodecAcceptsHourAndMinuteUpperBounds() throws {
        let schedule = ReminderSchedule.daily(hour: 23, minute: 59)

        XCTAssertEqual(try ReminderScheduleCodec.decode(ReminderScheduleCodec.encode(schedule)), schedule)
    }

    func testCodecRejectsEmptyOrDuplicateWeeklyWeekdays() {
        XCTAssertThrowsError(try ReminderScheduleCodec.encode(.weekly(weekdays: [], hour: 8, minute: 0)))
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"hour":8,"minute":0,"schemaVersion":1,"type":"weekly","weekdays":[2,2]}"#)
        )
    }

    func testDecodeRejectsEmptyOrOutOfRangeWeeklyWeekdays() {
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"hour":8,"minute":0,"schemaVersion":1,"type":"weekly","weekdays":[]}"#)
        )
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"hour":8,"minute":0,"schemaVersion":1,"type":"weekly","weekdays":[8]}"#)
        )
    }

    func testCodecRejectsIntervalCountsBelowOne() {
        XCTAssertThrowsError(try ReminderScheduleCodec.encode(.intervalDays(count: 0, hour: 8, minute: 0)))
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"count":0,"hour":8,"minute":0,"schemaVersion":1,"type":"intervalDays"}"#)
        )
    }

    func testDecodeRejectsFieldsFromAnotherScheduleKind() {
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"date":0,"hour":8,"minute":0,"schemaVersion":1,"type":"daily"}"#)
        )
    }

    func testDecodeRejectsUnknownSchemaV1Keys() {
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"hour":8,"minute":0,"schemaVersion":1,"type":"daily","unexpected":true}"#)
        )
    }

    func testDecodeRejectsPresentButNullForeignKeys() {
        XCTAssertThrowsError(
            try ReminderScheduleCodec.decode(#"{"date":null,"hour":8,"minute":0,"schemaVersion":1,"type":"daily"}"#)
        )
    }
}
