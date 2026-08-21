import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct NutritionDayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: NutritionDayViewModel
    private let foodLibraryViewModel: FoodLibraryViewModel
    private let recipeLibraryViewModel: RecipeLibraryViewModel

    public init(
        viewModel: NutritionDayViewModel,
        foodLibraryViewModel: FoodLibraryViewModel,
        recipeLibraryViewModel: RecipeLibraryViewModel
    ) {
        self.viewModel = viewModel
        self.foodLibraryViewModel = foodLibraryViewModel
        self.recipeLibraryViewModel = recipeLibraryViewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                dateControls
                stateContent
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.standard)
        }
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(localized("nutrition.day.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { libraryToolbar }
        .task {
            if viewModel.state == .loading {
                await viewModel.load()
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: viewModel.state
        )
        .accessibilityIdentifier("root.nutrition.content")
    }

    private var dateControls: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(formattedDate(viewModel.selectedDay.start))
                    .font(AppTypography.titleMedium)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(localized("nutrition.day.date.selected"))
                    .accessibilityValue(formattedDate(viewModel.selectedDay.start))
                    .accessibilityIdentifier("nutrition.day.date")

                HStack(spacing: AppSpacing.compact) {
                    dayNavigationButton(
                        direction: -1,
                        systemImage: "chevron.left",
                        label: localized("nutrition.day.previous"),
                        hint: localized("nutrition.day.previous.hint"),
                        identifier: "nutrition.day.previous"
                    ) {
                        await viewModel.selectPreviousDay()
                    }

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { viewModel.selectedDay.start },
                            set: { date in
                                Task { await viewModel.selectDay(containing: date) }
                            }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityLabel(localized("nutrition.day.picker"))
                    .accessibilityValue(formattedDate(viewModel.selectedDay.start))
                    .accessibilityHint(localized("nutrition.day.picker.hint"))
                    .accessibilityIdentifier("nutrition.day.date-picker")

                    dayNavigationButton(
                        direction: 1,
                        systemImage: "chevron.right",
                        label: localized("nutrition.day.next"),
                        hint: localized("nutrition.day.next.hint"),
                        identifier: "nutrition.day.next"
                    ) {
                        await viewModel.selectNextDay()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            FeatureStateView(state: .loading)
                .padding(.vertical, AppSpacing.large)
                .accessibilityIdentifier("nutrition.day.state.loading")
        case let .empty(presentation):
            loadedContent(presentation, isEmpty: true)
        case let .content(presentation):
            loadedContent(presentation, isEmpty: false)
        case .error:
            errorState
        }
    }

    private func loadedContent(
        _ presentation: NutritionDayPresentation,
        isEmpty: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                daySummary(presentation)
                if isEmpty {
                    AppCard {
                        Text(localized("nutrition.day.empty"))
                            .font(AppTypography.body)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("nutrition.day.state.empty")
                }
                ForEach(presentation.sections) { section in
                    sectionView(section)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                isEmpty ? "nutrition.day.empty-content" : "nutrition.day.content"
            )

            if case let .deleteError(entryID) = viewModel.mutationState {
                deleteError(entryID: entryID)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrition.day.loaded")
    }

    private func daySummary(_ presentation: NutritionDayPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(localized("nutrition.day.total"))
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    Text(macroSummary(presentation.totalMacros))
                        .font(AppTypography.numericRow)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("nutrition.day.total"))
            .accessibilityValue(macroSummary(presentation.totalMacros))
            .accessibilityIdentifier("nutrition.day.total")

            VStack(spacing: AppSpacing.compact) {
                macroView(
                    identifier: "calories",
                    title: localized("nutrition.day.macro.calories"),
                    unit: localized("nutrition.day.unit.kcal"),
                    presentation: presentation.targets.calories
                )
                macroView(
                    identifier: "protein",
                    title: localized("nutrition.day.macro.protein"),
                    unit: localized("nutrition.day.unit.gram"),
                    presentation: presentation.targets.proteinG
                )
                macroView(
                    identifier: "carbs",
                    title: localized("nutrition.day.macro.carbs"),
                    unit: localized("nutrition.day.unit.gram"),
                    presentation: presentation.targets.carbG
                )
                macroView(
                    identifier: "fat",
                    title: localized("nutrition.day.macro.fat"),
                    unit: localized("nutrition.day.unit.gram"),
                    presentation: presentation.targets.fatG
                )
            }
        }
    }

    private func macroView(
        identifier: String,
        title: String,
        unit: String,
        presentation: NutritionTargetPresentation
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(title)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                switch presentation {
                case let .total(consumed):
                    Text(totalText(consumed: consumed, unit: unit))
                        .font(AppTypography.numericRow)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                case let .targeted(consumed, target, remaining, _):
                    Text(targetedText(consumed: consumed, target: target, unit: unit))
                        .font(AppTypography.numericRow)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(
                        value: NSDecimalNumber(
                            decimal: presentation.clampedProgress ?? 0
                        ).doubleValue
                    )
                    .tint(AppColors.color(.accentAction, scheme: colorScheme))
                    Text(remainingText(remaining: remaining, unit: unit))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue(presentation, unit: unit))
        .accessibilityIdentifier("nutrition.day.macro.\(identifier)")
    }

    private func sectionView(
        _ section: NutritionMealSectionPresentation
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                HStack(alignment: .center, spacing: AppSpacing.compact) {
                    Text(categoryName(section.category))
                        .font(AppTypography.titleMedium)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(sectionIdentifier(section.category))
                    Spacer(minLength: AppSpacing.compact)
                    NavigationLink {
                        RecipeLibraryView(viewModel: recipeLibraryViewModel)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 52, height: 52)
                    }
                    .accessibilityLabel(
                        String(
                            format: localized("nutrition.day.section.add"),
                            locale: .current,
                            categoryName(section.category)
                        )
                    )
                    .accessibilityHint(localized("nutrition.day.section.add.hint"))
                    .accessibilityIdentifier(
                        "\(sectionIdentifier(section.category)).add"
                    )
                }

                Text(
                    String(
                        format: localized("nutrition.day.section.subtotal"),
                        locale: .current,
                        macroSummary(section.subtotal)
                    )
                )
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

                ForEach(section.entries) { entry in
                    entryRow(entry)
                    if entry.id != section.entries.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: MealEntrySnapshot) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(sourceName(entry.source))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(macroSummary(entry.resolvedMacros))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sourceName(entry.source))
            .accessibilityValue(macroSummary(entry.resolvedMacros))
            .accessibilityIdentifier(
                "nutrition.day.entry.\(entry.id.uuidString.lowercased())"
            )

            Button(role: .destructive) {
                Task { await viewModel.deleteEntry(id: entry.id) }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 52, height: 52)
            }
            .disabled(viewModel.mutationState == .deleting(entryID: entry.id))
            .accessibilityLabel(localized("nutrition.day.delete"))
            .accessibilityHint(localized("nutrition.day.delete.hint"))
            .accessibilityIdentifier(
                "nutrition.day.entry.\(entry.id.uuidString.lowercased()).delete"
            )
        }
    }

    private var errorState: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(localized("nutrition.day.error"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutrition.day.state.error")
                PrimaryActionButton(
                    title: localized("nutrition.day.retry"),
                    accessibilityLabel: localized("nutrition.day.retry"),
                    minimumHeight: 52
                ) {
                    Task { await viewModel.retry() }
                }
                .accessibilityIdentifier("nutrition.day.retry")
            }
        }
    }

    private func deleteError(entryID: UUID) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(localized("nutrition.day.delete.error"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutrition.day.mutation.error")
                PrimaryActionButton(
                    title: localized("nutrition.day.delete.retry"),
                    accessibilityLabel: localized("nutrition.day.delete.retry"),
                    minimumHeight: 52
                ) {
                    Task { await viewModel.retryDelete() }
                }
                .accessibilityIdentifier("nutrition.day.mutation.retry")
            }
        }
        .accessibilityValue(entryID.uuidString)
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            NavigationLink {
                FoodLibraryView(viewModel: foodLibraryViewModel)
            } label: {
                Image(systemName: "carrot")
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel(localized("nutrition.day.foodLibrary"))
            .accessibilityHint(localized("nutrition.day.foodLibrary.hint"))

            NavigationLink {
                RecipeLibraryView(viewModel: recipeLibraryViewModel)
            } label: {
                Image(systemName: "book.closed")
                    .frame(width: 52, height: 52)
            }
            .accessibilityLabel(localized("nutrition.day.recipeLibrary"))
            .accessibilityHint(localized("nutrition.day.recipeLibrary.hint"))
        }
    }

    private func dayNavigationButton(
        direction: Int,
        systemImage: String,
        label: String,
        hint: String,
        identifier: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel(label)
        .accessibilityValue(
            viewModel.adjacentDay(by: direction)
                .map { formattedDate($0.start) } ?? ""
        )
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    private func categoryName(_ category: MealCategory) -> String {
        if let customName = category.customName { return customName }
        switch category.kind {
        case .breakfast:
            return localized("nutrition.day.category.breakfast")
        case .lunch:
            return localized("nutrition.day.category.lunch")
        case .dinner:
            return localized("nutrition.day.category.dinner")
        case .snack:
            return localized("nutrition.day.category.snack")
        case .custom:
            return localized("nutrition.day.category.custom")
        }
    }

    private func sectionIdentifier(_ category: MealCategory) -> String {
        let suffix: String
        if let customName = category.customName {
            suffix = "custom.\(identifierComponent(customName))"
        } else {
            suffix = category.kind.rawValue
        }
        return "nutrition.day.section.\(suffix)"
    }

    private func identifierComponent(_ value: String) -> String {
        let locale = Locale(identifier: "tr_TR")
        return value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
            .lowercased(with: locale)
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    private func sourceName(_ source: MealEntrySourceSnapshot) -> String {
        switch source {
        case let .recipe(_, name):
            return name ?? localized("nutrition.day.source.archivedRecipe")
        case let .food(_, name):
            return name ?? localized("nutrition.day.source.deletedFood")
        case let .adhoc(name):
            return name
        }
    }

    private func macroSummary(_ macros: NutritionMacros) -> String {
        String(
            format: localized("nutrition.day.macros.format"),
            locale: .current,
            formatted(macros.calories),
            formatted(macros.proteinG),
            formatted(macros.carbG),
            formatted(macros.fatG)
        )
    }

    private func totalText(consumed: Decimal, unit: String) -> String {
        String(
            format: localized("nutrition.day.macro.total.format"),
            locale: .current,
            formatted(consumed),
            unit
        )
    }

    private func targetedText(
        consumed: Decimal,
        target: Decimal,
        unit: String
    ) -> String {
        String(
            format: localized("nutrition.day.macro.targeted.format"),
            locale: .current,
            formatted(consumed),
            formatted(target),
            unit
        )
    }

    private func remainingText(remaining: Decimal, unit: String) -> String {
        String(
            format: localized("nutrition.day.macro.remaining.format"),
            locale: .current,
            formatted(remaining),
            unit
        )
    }

    private func accessibilityValue(
        _ presentation: NutritionTargetPresentation,
        unit: String
    ) -> String {
        switch presentation {
        case let .total(consumed):
            return totalText(consumed: consumed, unit: unit)
        case let .targeted(consumed, target, remaining, _):
            return String(
                format: localized("nutrition.day.macro.accessibility.targeted"),
                locale: .current,
                formatted(consumed),
                formatted(target),
                formatted(remaining),
                unit
            )
        }
    }

    private func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = NutritionDecimalMath.scale
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private func formattedDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .full
        return formatter.string(from: value)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
