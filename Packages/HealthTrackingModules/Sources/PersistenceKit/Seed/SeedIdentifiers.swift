import Foundation

public enum SeedIdentifiers {
    public static let profile = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let program = UUID(uuidString: "00000000-0000-4000-8000-000000000100")!
    public static let phase1 = UUID(uuidString: "00000000-0000-4000-8000-000000000111")!
    public static let phase2 = UUID(uuidString: "00000000-0000-4000-8000-000000000112")!
    public static let phase3 = UUID(uuidString: "00000000-0000-4000-8000-000000000113")!
    public static let phase4 = UUID(uuidString: "00000000-0000-4000-8000-000000000114")!
    public static let dayA = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
    public static let dayB = UUID(uuidString: "00000000-0000-4000-8000-000000000202")!
    public static let dayC = UUID(uuidString: "00000000-0000-4000-8000-000000000203")!

    public static let gobletSquat = UUID(uuidString: "00000000-0000-4000-8000-000000000301")!
    public static let chinUp = UUID(uuidString: "00000000-0000-4000-8000-000000000302")!
    public static let dbFloorPress = UUID(uuidString: "00000000-0000-4000-8000-000000000303")!
    public static let dbRomanianDeadlift = UUID(uuidString: "00000000-0000-4000-8000-000000000304")!
    public static let proneYTW = UUID(uuidString: "00000000-0000-4000-8000-000000000305")!
    public static let facePull = UUID(uuidString: "00000000-0000-4000-8000-000000000306")!
    public static let singleLegCalfRaise = UUID(uuidString: "00000000-0000-4000-8000-000000000307")!
    public static let plankPallof = UUID(uuidString: "00000000-0000-4000-8000-000000000308")!

    public static let doubleDBRDL = UUID(uuidString: "00000000-0000-4000-8000-000000000401")!
    public static let singleArmDBRow = UUID(uuidString: "00000000-0000-4000-8000-000000000402")!
    public static let pushUp = UUID(uuidString: "00000000-0000-4000-8000-000000000403")!
    public static let dbOverheadPress = UUID(uuidString: "00000000-0000-4000-8000-000000000404")!
    public static let bulgarianSplitSquat = UUID(uuidString: "00000000-0000-4000-8000-000000000405")!
    public static let gluteBridgeHipThrust = UUID(uuidString: "00000000-0000-4000-8000-000000000406")!
    public static let wallSlide = UUID(uuidString: "00000000-0000-4000-8000-000000000407")!
    public static let deadBug = UUID(uuidString: "00000000-0000-4000-8000-000000000408")!
    public static let copenhagenPlank = UUID(uuidString: "00000000-0000-4000-8000-000000000409")!

    public static let reverseLunge = UUID(uuidString: "00000000-0000-4000-8000-000000000501")!
    public static let nordicHamstringCurl = UUID(uuidString: "00000000-0000-4000-8000-000000000502")!
    public static let pullUpBanded = UUID(uuidString: "00000000-0000-4000-8000-000000000503")!
    public static let bandedSingleArmRow = UUID(uuidString: "00000000-0000-4000-8000-000000000504")!
    public static let halfKneelingDBPress = UUID(uuidString: "00000000-0000-4000-8000-000000000505")!
    public static let dbLateralRaise = UUID(uuidString: "00000000-0000-4000-8000-000000000506")!
    public static let farmersCarry = UUID(uuidString: "00000000-0000-4000-8000-000000000507")!
    public static let curl = UUID(uuidString: "00000000-0000-4000-8000-000000000508")!
    public static let triceps = UUID(uuidString: "00000000-0000-4000-8000-000000000509")!
    public static let sidePlankPallof = UUID(uuidString: "00000000-0000-4000-8000-000000000510")!
    public static let curlTricepsSuperset = UUID(uuidString: "00000000-0000-4000-8000-000000000599")!

    public static let warmupDayA = identifiers(in: 601...609)
    public static let warmupDayB = identifiers(in: 610...621)
    public static let warmupDayC = identifiers(in: 622...630)
    public static let cooldownDayA = identifiers(in: 701...703)
    public static let cooldownDayB = identifiers(in: 704...706)
    public static let cooldownDayC = identifiers(in: 707...709)

    public static let ferritinReminder = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!
    public static let vitaminDReminder = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!
    public static let generalCheckupReminder = UUID(uuidString: "00000000-0000-4000-8000-000000000803")!
    public static let programState = UUID(uuidString: "00000000-0000-4000-8000-000000000901")!

    private static func identifiers(in range: ClosedRange<Int>) -> [UUID] {
        range.map { value in
            UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
        }
    }
}
