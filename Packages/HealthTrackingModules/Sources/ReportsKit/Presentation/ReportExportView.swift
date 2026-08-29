import DesignSystem
import SwiftUI

@MainActor
public struct ReportExportView: View {
    @Bindable private var viewModel: ReportExportViewModel
    private let referenceDate: @MainActor () -> Date
    private let onShare: @MainActor ([URL]) -> Void

    public init(
        viewModel: ReportExportViewModel,
        referenceDate: @escaping @MainActor () -> Date = { Date() },
        onShare: @escaping @MainActor ([URL]) -> Void
    ) {
        self.viewModel = viewModel
        self.referenceDate = referenceDate
        self.onShare = onShare
    }

    public var body: some View {
        Form {
            Section(String(localized: "reports.export.range", bundle: .module)) {
                Picker(
                    String(localized: "reports.export.range", bundle: .module),
                    selection: Binding(
                        get: { viewModel.selectedPreset },
                        set: { viewModel.setPreset($0) }
                    )
                ) {
                    ForEach(ReportDateRangePreset.allCases, id: \.self) { preset in
                        Text(presetTitle(preset)).tag(preset)
                    }
                }
                .accessibilityIdentifier("reports.export.range")
            }

            Section(String(localized: "reports.export.modules", bundle: .module)) {
                ForEach(ExportModuleV1.allCases, id: \.self) { module in
                    Toggle(
                        moduleTitle(module),
                        isOn: Binding(
                            get: { viewModel.selectedModules.contains(module) },
                            set: { _ in viewModel.toggleModule(module) }
                        )
                    )
                    .accessibilityIdentifier("reports.export.module.\(module.rawValue)")
                }
            }

            Section(String(localized: "reports.export.format", bundle: .module)) {
                Picker(
                    String(localized: "reports.export.format", bundle: .module),
                    selection: Binding(
                        get: { viewModel.format },
                        set: { viewModel.setFormat($0) }
                    )
                ) {
                    Text(String(localized: "reports.export.format.csv", bundle: .module))
                        .tag(ReportExportFormat.csv)
                    Text(String(localized: "reports.export.format.json", bundle: .module))
                        .tag(ReportExportFormat.json)
                    Text(String(localized: "reports.export.format.both", bundle: .module))
                        .tag(ReportExportFormat.bothZip)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reports.export.format")

                if viewModel.format == .bothZip {
                    Toggle(
                        String(localized: "reports.export.photos", bundle: .module),
                        isOn: Binding(
                            get: { viewModel.includesPhotos },
                            set: { viewModel.setIncludesPhotos($0) }
                        )
                    )
                    .accessibilityIdentifier("reports.export.photos")
                }
            }

            Section {
                if viewModel.isProgressVisible {
                    ProgressView(String(localized: "reports.export.progress", bundle: .module))
                        .accessibilityIdentifier("reports.export.progress")
                    Button(String(localized: "reports.export.cancel", bundle: .module)) {
                        viewModel.cancel()
                    }
                    .accessibilityIdentifier("reports.export.cancel")
                } else if viewModel.state == .ready {
                    Button(String(localized: "reports.export.share", bundle: .module)) {
                        onShare(viewModel.shareURLs)
                    }
                    .accessibilityIdentifier("reports.export.share")
                } else {
                    Button(String(localized: "reports.export.action", bundle: .module)) {
                        viewModel.generate(referenceDate: referenceDate())
                    }
                    .disabled(!viewModel.canGenerate)
                    .accessibilityIdentifier("reports.export.generate")
                }

                if viewModel.canRetry {
                    Button(String(localized: "reports.export.retry", bundle: .module)) {
                        viewModel.retry()
                    }
                    .accessibilityIdentifier("reports.export.retry")
                }
            }

            if viewModel.state == .failed {
                Section {
                    Text(String(localized: "reports.export.error", bundle: .module))
                        .accessibilityIdentifier("reports.export.error")
                }
            }
        }
        .navigationTitle(String(localized: "reports.export.title", bundle: .module))
        .onDisappear { viewModel.viewDidDisappear() }
    }

    private func presetTitle(_ preset: ReportDateRangePreset) -> String {
        switch preset {
        case .oneMonth: String(localized: "reports.export.range.one_month", bundle: .module)
        case .threeMonths: String(localized: "reports.export.range.three_months", bundle: .module)
        case .sixMonths: String(localized: "reports.export.range.six_months", bundle: .module)
        case .oneYear: String(localized: "reports.export.range.one_year", bundle: .module)
        }
    }

    private func moduleTitle(_ module: ExportModuleV1) -> String {
        switch module {
        case .profileProgram: String(localized: "reports.export.module.profile_program", bundle: .module)
        case .training: String(localized: "reports.export.module.training", bundle: .module)
        case .nutrition: String(localized: "reports.export.module.nutrition", bundle: .module)
        case .metrics: String(localized: "reports.export.module.metrics", bundle: .module)
        case .lifestyle: String(localized: "reports.export.module.lifestyle", bundle: .module)
        case .health: String(localized: "reports.export.module.health", bundle: .module)
        case .photos: String(localized: "reports.export.module.photos", bundle: .module)
        case .system: String(localized: "reports.export.module.system", bundle: .module)
        }
    }
}
