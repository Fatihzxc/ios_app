import DesignSystem
import SwiftUI

public struct ReportTextTable: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    private let descriptor: ReportChartDescriptor

    public init(descriptor: ReportChartDescriptor) {
        self.descriptor = descriptor
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                if descriptor.model.tableRows.isEmpty {
                    Text(String(localized: "reports.table.empty", bundle: .module))
                        .font(AppTypography.body)
                        .foregroundStyle(
                            AppColors.color(.inkSecondary, scheme: colorScheme)
                        )
                } else {
                    ForEach(
                        Array(descriptor.model.tableRows.enumerated()),
                        id: \.offset
                    ) { _, row in
                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text(row.seriesName)
                                .font(AppTypography.label)
                            Text(rowDescription(row))
                                .font(AppTypography.numericRow)
                                .foregroundStyle(
                                    AppColors.color(.inkSecondary, scheme: colorScheme)
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.top, AppSpacing.compact)
        } label: {
            Text(String(localized: "reports.table.action", bundle: .module))
                .font(AppTypography.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("reports.table.\(tableIdentifier)")
    }

    private var tableIdentifier: String {
        descriptor.model.series.first?.id ?? "empty"
    }

    private func rowDescription(_ row: ReportTextTableRow) -> String {
        ReportChartDescriptor.tableRowDescription(
            date: row.date,
            value: row.value,
            unit: row.unit,
            calendar: descriptor.calendar,
            locale: descriptor.locale
        )
    }
}
