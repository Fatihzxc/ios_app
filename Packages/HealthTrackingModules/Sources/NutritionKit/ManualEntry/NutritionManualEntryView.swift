import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct NutritionManualEntryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: NutritionManualEntryViewModel
    private let mode: NutritionManualEntryMode
    private let intent: NutritionQuickAddIntent
    private let onPublish: @MainActor (
        NutritionDayEntriesSnapshot,
        NutritionMacroTargets?
    ) -> Void
    private let onComplete: @MainActor () -> Void

    @State private var foodQuantityText = "1"
    @State private var adhocName = ""
    @State private var adhocQuantityText = "1"
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var validationMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    public init(
        viewModel: NutritionManualEntryViewModel,
        mode: NutritionManualEntryMode,
        intent: NutritionQuickAddIntent,
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.mode = mode
        self.intent = intent
        self.onPublish = onPublish
        self.onComplete = onComplete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                stateContent
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(
            localized(
                mode == .food
                    ? "nutrition.manual.food.title"
                    : "nutrition.manual.adhoc.title"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localized("nutrition.keyboard.dismiss")) {
                    isTextFieldFocused = false
                }
                .accessibilityIdentifier("nutrition.keyboard.dismiss")
            }
        }
        .task(id: NutritionManualEntryTaskID(mode: mode, intentID: intent.id)) {
            resetFields()
            await viewModel.begin(mode: mode, intent: intent)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: viewModel.phase
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.phase {
        case .idle, .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("nutrition.manual.state.loading")
        case .foodSelection:
            foodSelection
        case .foodConfirmation:
            foodConfirmation(isSaving: false, showsError: false)
        case .adhocEntry:
            adhocEntry(isSaving: false, showsError: false)
        case .saving:
            if mode == .food {
                foodConfirmation(isSaving: true, showsError: false)
            } else {
                adhocEntry(isSaving: true, showsError: false)
            }
        case .saveError:
            if mode == .food {
                foodConfirmation(isSaving: false, showsError: true)
            } else {
                adhocEntry(isSaving: false, showsError: true)
            }
        case .loadError:
            loadError
        case .completed:
            FeatureStateView(
                state: .empty(
                    message: localized("nutrition.manual.success"),
                    actionTitle: localized("nutrition.manual.close"),
                    actionAccessibilityLabel: localized("nutrition.manual.close"),
                    action: onComplete
                )
            )
            .accessibilityIdentifier("nutrition.manual.state.completed")
        }
    }

    private var foodSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            stateHeading(
                localized("nutrition.manual.food.heading"),
                identifier: "nutrition.manual.state.food-selection"
            )
            categoryPicker
            if viewModel.foods.isEmpty {
                AppCard {
                    Text(localized("nutrition.manual.food.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(
                            AppColors.color(.inkSecondary, scheme: colorScheme)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("nutrition.manual.food.empty")
            } else {
                ForEach(viewModel.foods) { food in
                    Button {
                        viewModel.selectFood(id: food.id)
                        foodQuantityText = formatted(viewModel.quantity)
                    } label: {
                        AppCard {
                            HStack(alignment: .center, spacing: AppSpacing.standard) {
                                VStack(alignment: .leading, spacing: AppSpacing.small) {
                                    Text(food.name)
                                        .font(AppTypography.label)
                                        .foregroundStyle(
                                            AppColors.color(.inkPrimary, scheme: colorScheme)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(foodSummary(food))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(
                                            AppColors.color(.inkSecondary, scheme: colorScheme)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .frame(width: 52, height: 52)
                                    .foregroundStyle(
                                        AppColors.color(.accentAction, scheme: colorScheme)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(food.name)
                    .accessibilityValue(foodSummary(food))
                    .accessibilityHint(localized("nutrition.manual.food.select.hint"))
                    .accessibilityIdentifier(
                        "nutrition.manual.food.\(food.id.uuidString.lowercased()).select"
                    )
                }
            }
        }
    }

    private func foodConfirmation(
        isSaving: Bool,
        showsError: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            stateHeading(
                localized("nutrition.manual.food.confirmationHeading"),
                identifier: "nutrition.manual.state.food-confirmation"
            )
            if let selectedFood = viewModel.selectedFood {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(selectedFood.name)
                            .font(AppTypography.titleMedium)
                        Text(foodSummary(selectedFood))
                            .font(AppTypography.body)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("nutrition.manual.food.selection")
            }
            categoryPicker
            fieldCard(
                title: localized("nutrition.manual.quantity"),
                text: $foodQuantityText,
                identifier: "nutrition.manual.quantity",
                keyboard: .decimalPad,
                disabled: isSaving || showsError
            )
            if showsError { saveError }
            if !showsError {
                PrimaryActionButton(
                    title: isSaving
                        ? localized("nutrition.manual.saving")
                        : localized("nutrition.manual.save"),
                    accessibilityLabel: isSaving
                        ? localized("nutrition.manual.saving")
                        : localized("nutrition.manual.save"),
                    minimumHeight: 52
                ) {
                    Task { await submitFood() }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("nutrition.manual.confirm")
            }
            validationError
        }
    }

    private func adhocEntry(
        isSaving: Bool,
        showsError: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            stateHeading(
                localized("nutrition.manual.adhoc.heading"),
                identifier: "nutrition.manual.state.adhoc-entry"
            )
            Text(localized("nutrition.manual.adhoc.help"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            categoryPicker
            fieldCard(
                title: localized("nutrition.manual.adhoc.name"),
                text: $adhocName,
                identifier: "nutrition.manual.adhoc.name",
                disabled: isSaving || showsError
            )
            fieldCard(
                title: localized("nutrition.manual.quantity"),
                text: $adhocQuantityText,
                identifier: "nutrition.manual.adhoc.quantity",
                keyboard: .decimalPad,
                disabled: isSaving || showsError
            )
            fieldCard(
                title: localized("nutrition.manual.adhoc.calories"),
                text: $caloriesText,
                identifier: "nutrition.manual.adhoc.calories",
                keyboard: .decimalPad,
                disabled: isSaving || showsError
            )
            fieldCard(
                title: localized("nutrition.manual.adhoc.protein"),
                text: $proteinText,
                identifier: "nutrition.manual.adhoc.protein",
                keyboard: .decimalPad,
                disabled: isSaving || showsError
            )
            fieldCard(
                title: localized("nutrition.manual.adhoc.carbs"),
                text: $carbsText,
                identifier: "nutrition.manual.adhoc.carbs",
                keyboard: .decimalPad,
                disabled: isSaving || showsError
            )
            fieldCard(
                title: localized("nutrition.manual.adhoc.fat"),
                text: $fatText,
                identifier: "nutrition.manual.adhoc.fat",
                keyboard: .decimalPad,
                disabled: isSaving || showsError
            )
            if showsError { saveError }
            if !showsError {
                PrimaryActionButton(
                    title: isSaving
                        ? localized("nutrition.manual.saving")
                        : localized("nutrition.manual.save"),
                    accessibilityLabel: isSaving
                        ? localized("nutrition.manual.saving")
                        : localized("nutrition.manual.save"),
                    minimumHeight: 52
                ) {
                    Task { await submitAdhoc() }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("nutrition.manual.adhoc.save")
            }
            validationError
        }
    }

    private var categoryPicker: some View {
        AppCard {
            Picker(
                localized("nutrition.manual.category"),
                selection: Binding(
                    get: { viewModel.category ?? intent.category },
                    set: { viewModel.selectCategory($0) }
                )
            ) {
                ForEach(viewModel.categoryOptions, id: \.self) { category in
                    Text(categoryName(category)).tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .accessibilityLabel(localized("nutrition.manual.category"))
            .accessibilityValue(categoryName(viewModel.category ?? intent.category))
            .accessibilityIdentifier("nutrition.manual.category")
        }
    }

    private func fieldCard(
        title: String,
        text: Binding<String>,
        identifier: String,
        keyboard: UIKeyboardType = .default,
        disabled: Bool
    ) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(title)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .focused($isTextFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 52)
                    .disabled(disabled)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    private var saveError: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(localized("nutrition.manual.saveError"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutrition.manual.state.error")
                PrimaryActionButton(
                    title: localized("nutrition.manual.retry"),
                    accessibilityLabel: localized("nutrition.manual.retry"),
                    minimumHeight: 52
                ) {
                    Task {
                        await viewModel.retrySave(onPublish: onPublish)
                        if viewModel.phase == .completed { onComplete() }
                    }
                }
                .accessibilityIdentifier("nutrition.manual.retry")
            }
        }
    }

    @ViewBuilder
    private var validationError: some View {
        if let validationMessage {
            Text(validationMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nutrition.manual.validation-error")
        }
    }

    private var loadError: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(localized("nutrition.manual.loadError"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nutrition.manual.state.load-error")
                PrimaryActionButton(
                    title: localized("nutrition.manual.retry"),
                    accessibilityLabel: localized("nutrition.manual.retry"),
                    minimumHeight: 52
                ) {
                    Task { await viewModel.retryLoad() }
                }
                .accessibilityIdentifier("nutrition.manual.load-retry")
            }
        }
    }

    private func stateHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(AppTypography.titleMedium)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func submitFood() async {
        validationMessage = nil
        guard let quantity = decimal(foodQuantityText) else {
            validationMessage = localized("nutrition.manual.validation")
            return
        }
        do {
            try viewModel.setQuantity(quantity)
        } catch {
            validationMessage = localized("nutrition.manual.validation")
            return
        }
        await viewModel.saveFood(onPublish: onPublish)
        if viewModel.phase == .completed { onComplete() }
    }

    private func submitAdhoc() async {
        validationMessage = nil
        guard let quantity = decimal(adhocQuantityText),
              let calories = decimal(caloriesText),
              let protein = decimal(proteinText),
              let carbs = decimal(carbsText),
              let fat = decimal(fatText) else {
            validationMessage = localized("nutrition.manual.validation")
            return
        }
        do {
            let macros = try NutritionMacros(
                calories: calories,
                proteinG: protein,
                carbG: carbs,
                fatG: fat
            )
            await viewModel.saveAdhoc(
                name: adhocName,
                quantity: quantity,
                resolvedMacros: macros,
                onPublish: onPublish
            )
            if viewModel.phase == .completed { onComplete() }
            if viewModel.phase == .adhocEntry {
                validationMessage = localized("nutrition.manual.validation")
            }
        } catch {
            validationMessage = localized("nutrition.manual.validation")
        }
    }

    private func resetFields() {
        foodQuantityText = "1"
        adhocName = ""
        adhocQuantityText = "1"
        caloriesText = ""
        proteinText = ""
        carbsText = ""
        fatText = ""
        validationMessage = nil
    }

    private func foodSummary(_ food: FoodSnapshot) -> String {
        String(
            format: localized("nutrition.manual.food.format"),
            locale: .current,
            formatted(food.servingSize),
            food.servingUnit,
            macroSummary(food.macros)
        )
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

    private func categoryName(_ category: MealCategory) -> String {
        if let customName = category.customName { return customName }
        switch category.kind {
        case .breakfast: return localized("nutrition.day.category.breakfast")
        case .lunch: return localized("nutrition.day.category.lunch")
        case .dinner: return localized("nutrition.day.category.dinner")
        case .snack: return localized("nutrition.day.category.snack")
        case .custom: return localized("nutrition.day.category.custom")
        }
    }

    private func decimal(_ text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        return formatter.number(from: text)?.decimalValue
    }

    private func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = NutritionDecimalMath.scale
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}

private struct NutritionManualEntryTaskID: Hashable {
    let mode: NutritionManualEntryMode
    let intentID: UUID
}
