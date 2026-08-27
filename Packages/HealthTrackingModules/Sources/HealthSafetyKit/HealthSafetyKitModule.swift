import Foundation

public enum HealthSafetyKitModule {
    public static let name = "HealthSafetyKit"
}

public struct MedicalDisclaimerPresentation: Equatable, Sendable {
    public let text: String
    public let isAlwaysVisible: Bool

    public static let permanent = MedicalDisclaimerPresentation(
        text: "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
        isAlwaysVisible: true
    )

    public init(text: String, isAlwaysVisible: Bool) {
        self.text = text
        self.isAlwaysVisible = isAlwaysVisible
    }
}

public enum CervicalRedFlag: String, CaseIterable, Equatable, Hashable, Sendable {
    case armOrLegWeaknessOrNumbness
    case handDexterityLoss
    case balanceOrWalkingChange
    case bladderOrBowelChange
}

public enum MedicalSafetyTrigger: Equatable, Hashable, Sendable {
    case overheadPressSymptom
    case increasingSymptom
    case cervicalRedFlags(Set<CervicalRedFlag>)
}

public enum MedicalSafetyNoticeKind: Equatable, Sendable {
    case stopAndProfessionalAssessment
    case urgentAssessmentInformation
}

public struct MedicalSafetyNotice: Equatable, Sendable {
    public let kind: MedicalSafetyNoticeKind
    public let message: String
    public let requiresUrgentAssessment: Bool

    public init(
        kind: MedicalSafetyNoticeKind,
        message: String,
        requiresUrgentAssessment: Bool
    ) {
        self.kind = kind
        self.message = message
        self.requiresUrgentAssessment = requiresUrgentAssessment
    }
}

public struct MedicalSafetyPresentation: Equatable, Sendable {
    public let disclaimer: MedicalDisclaimerPresentation
    public let levelTwo: MedicalSafetyNotice?

    public init(
        disclaimer: MedicalDisclaimerPresentation,
        levelTwo: MedicalSafetyNotice?
    ) {
        self.disclaimer = disclaimer
        self.levelTwo = levelTwo
    }

    public static func resolve(
        triggers: Set<MedicalSafetyTrigger>
    ) -> MedicalSafetyPresentation {
        let redFlags = triggers.reduce(into: Set<CervicalRedFlag>()) { result, trigger in
            guard case let .cervicalRedFlags(flags) = trigger else { return }
            result.formUnion(flags)
        }

        if !redFlags.isEmpty {
            return MedicalSafetyPresentation(
                disclaimer: .permanent,
                levelTwo: MedicalSafetyNotice(
                    kind: .urgentAssessmentInformation,
                    message: urgentMessage,
                    requiresUrgentAssessment: true
                )
            )
        }

        if triggers.contains(.overheadPressSymptom)
            || triggers.contains(.increasingSymptom) {
            return MedicalSafetyPresentation(
                disclaimer: .permanent,
                levelTwo: MedicalSafetyNotice(
                    kind: .stopAndProfessionalAssessment,
                    message: generalStopMessage,
                    requiresUrgentAssessment: false
                )
            )
        }

        return MedicalSafetyPresentation(disclaimer: .permanent, levelTwo: nil)
    }

    private static let redFlagInformation =
        "kol veya bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, "
        + "denge veya yürümede değişiklik ya da mesane veya bağırsak işlevinde değişiklik"

    private static let generalStopMessage =
        "Hareketi durdur. Belirtiyi bir sağlık profesyoneliyle değerlendir. "
        + "\(redFlagInformation) varsa acil tıbbi değerlendirme iste."

    private static let urgentMessage =
        "Hareketi durdur. \(redFlagInformation) için acil tıbbi değerlendirme iste."
}
