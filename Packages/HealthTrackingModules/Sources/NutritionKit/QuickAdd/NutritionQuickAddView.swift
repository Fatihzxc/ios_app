import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct NutritionQuickAddView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: NutritionQuickAddViewModel
    @Bindable private var manualEntryViewModel: NutritionManualEntryViewModel
    private let intent: NutritionQuickAddIntent
    private let onPublish: @MainActor (
        NutritionDayEntriesSnapshot,
        NutritionMacroTargets?
    ) -> Void
    private let onComplete: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void
    @State private var quantityText = "1"

    public init(
        viewModel: NutritionQuickAddViewModel,
        manualEntryViewModel: NutritionManualEntryViewModel,
        intent: NutritionQuickAddIntent,
        onPublish: @escaping @MainActor (
            NutritionDayEntriesSnapshot,
            NutritionMacroTargets?
        ) -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.manualEntryViewModel = manualEntryViewModel
        self.intent = intent
        self.onPublish = onPublish
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
                    stateContent
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.color(.backgroundBase, scheme: colorScheme))
            .navigationTitle(localized("nutrition.quickAdd.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("nutrition.quickAdd.cancel")) {
                        viewModel.dismiss()
                        manualEntryViewModel.dismiss()
                        onCancel()
                    }
                    .frame(minWidth: 52, minHeight: 52)
                    .disabled(
                        viewModel.phase == .saving
                            || manualEntryViewModel.phase == .saving
                    )
                    .accessibilityIdentifier("nutrition.quick-add.cancel")
                }
            }
            .navigationDestination(for: NutritionManualEntryMode.self) { mode in
                NutritionManualEntryView(
                    viewModel: manualEntryViewModel,
                    mode: mode,
                    intent: intent,
                    onPublish: onPublish,
                    onComplete: onComplete
                )
            }
        }
        .interactiveDismissDisabled(
            viewModel.phase == .saving || manualEntryViewModel.phase == .saving
        )
        .task(id: intent.id) {
            await viewModel.begin(intent)
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
                .accessibilityIdentifier("nutrition.quick-add.state.loading")
        case .selecting:
            recipeSelection
        case .confirming:
            confirmation(
                isSaving: false,
                showsError: false,
                stateIdentifier: "nutrition.quick-add.state.confirming"
            )
        case .saving:
            confirmation(
                isSaving: true,
                showsError: false,
                stateIdentifier: "nutrition.quick-add.state.saving"
            )
        case .saveError:
            confirmation(
                isSaving: false,
                showsError: true,
                stateIdentifier: "nutrition.quick-add.state.error"
            )
        case .loadError:
            loadError
        case .completed:
            FeatureStateView(
                state: .empty(
                    message: localized("nutrition.quickAdd.success"),
                    actionTitle: localized("nutrition.quickAdd.close"),
                    actionAccessibilityLabel: localized("nutrition.quickAdd.close"),
                    action: onComplete
                )
            )
            .accessibilityIdentifier("nutrition.quick-add.state.completed")
        }
    }

    private var recipeSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            stateHeading(
                localized("nutrition.quickAdd.selectionHeading"),
                identifier: "nutrition.quick-add.state.selecting"
            )
            categoryPicker
            if viewModel.recipes.isEmpty {
                AppCard {
                    Text(localized("nutrition.quickAdd.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("nutrition.quick-add.state.empty")
            } else {
                ForEach(viewModel.recipes) { recipe in
                    Button {
                        viewModel.selectRecipe(id: recipe.id)
                        quantityText = formatted(viewModel.quantity)
                    } label: {
                        AppCard {
                            HStack(alignment: .center, spacing: AppSpacing.standard) {
                                VStack(alignment: .leading, spacing: AppSpacing.small) {
                                    Text(recipe.name)
                                        .font(AppTypography.label)
                                        .foregroundStyle(
                                            AppColors.color(.inkPrimary, scheme: colorScheme)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(recipeSummary(recipe))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(
                                            AppColors.color(.inkSecondary, scheme: colorScheme)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus")
                                    .frame(width: 52, height: 52)
                                    .foregroundStyle(
                                        AppColors.color(.accentAction, scheme: colorScheme)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recipe.name)
                    .accessibilityValue(recipeSummary(recipe))
                    .accessibilityHint(localized("nutrition.quickAdd.recipe.hint"))
                    .accessibilityIdentifier(
                        "nutrition.quick-add.recipe.\(recipe.id.uuidString.lowercased()).add"
                    )
                }
            }
            manualEntryActions
        }
    }

    private var manualEntryActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(localized("nutrition.manual.options.heading"))
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .accessibilityAddTraits(.isHeader)
            manualEntryAction(
                mode: .food,
                title: localized("nutrition.manual.food.action"),
                detail: localized("nutrition.manual.food.action.detail"),
                systemImage: "carrot",
                identifier: "nutrition.quick-add.manual.food"
            )
            manualEntryAction(
                mode: .adhoc,
                title: localized("nutrition.manual.adhoc.action"),
                detail: localized("nutrition.manual.adhoc.action.detail"),
                systemImage: "square.and.pencil",
                identifier: "nutrition.quick-add.manual.adhoc"
            )
        }
    }

    private func manualEntryAction(
        mode: NutritionManualEntryMode,
        title: String,
        detail: String,
        systemImage: String,
        identifier: String
    ) -> some View {
        NavigationLink(value: mode) {
            AppCard {
                HStack(alignment: .center, spacing: AppSpacing.standard) {
                    Image(systemName: systemImage)
                        .frame(width: 52, height: 52)
                        .foregroundStyle(AppColors.color(.accentAction, scheme: colorScheme))
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(title)
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        Text(detail)
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColors.color(.accentAction, scheme: colorScheme))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityHint(localized("nutrition.manual.action.hint"))
        .accessibilityIdentifier(identifier)
    }

    private func confirmation(
        isSaving: Bool,
        showsError: Bool,
        stateIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.comfortable) {
            stateHeading(
                localized("nutrition.quickAdd.confirmationHeading"),
                identifier: stateIdentifier
            )
            if let recipe = viewModel.selectedRecipe {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(recipe.name)
                            .font(AppTypography.titleMedium)
                            .foregroundStyle(
                                AppColors.color(.inkPrimary, scheme: colorScheme)
                            )
                        Text(recipeSummary(recipe))
                            .font(AppTypography.body)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("nutrition.quick-add.selection")
            }

            categoryPicker

            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(localized("nutrition.quickAdd.quantity"))
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                    TextField(
                        localized("nutrition.quickAdd.quantity"),
                        text: $quantityText
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 52)
                    .disabled(isSaving || showsError)
                    .accessibilityIdentifier("nutrition.quick-add.quantity")
                    .onChange(of: quantityText) { _, value in
                        guard let quantity = decimal(value) else { return }
                        try? viewModel.setQuantity(quantity)
                    }
                }
            }

            if let snapshot = viewModel.projectedSnapshot {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(localized("nutrition.quickAdd.projectedTotal"))
                            .font(AppTypography.label)
                        Text(macroSummary(snapshot.totalMacros))
                            .font(AppTypography.numericRow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("nutrition.quick-add.projected-total")
            }

            if showsError {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.standard) {
                        Text(localized("nutrition.quickAdd.saveError"))
                            .font(AppTypography.body)
                            .foregroundStyle(
                                AppColors.color(.stateDanger, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryActionButton(
                            title: localized("nutrition.quickAdd.retry"),
                            accessibilityLabel: localized("nutrition.quickAdd.retry"),
                            minimumHeight: 52
                        ) {
                            Task {
                                await viewModel.retrySave(onPublish: onPublish)
                                if viewModel.phase == .completed { onComplete() }
                            }
                        }
                        .accessibilityIdentifier("nutrition.quick-add.retry")
                    }
                }
            } else {
                PrimaryActionButton(
                    title: isSaving
                        ? localized("nutrition.quickAdd.saving")
                        : localized("nutrition.quickAdd.confirm"),
                    accessibilityLabel: isSaving
                        ? localized("nutrition.quickAdd.saving")
                        : localized("nutrition.quickAdd.confirm"),
                    minimumHeight: 52
                ) {
                    Task {
                        await viewModel.confirm(onPublish: onPublish)
                        if viewModel.phase == .completed { onComplete() }
                    }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("nutrition.quick-add.confirm")
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

    private var categoryPicker: some View {
        AppCard {
            Picker(
                localized("nutrition.quickAdd.category"),
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
            .accessibilityLabel(localized("nutrition.quickAdd.category"))
            .accessibilityValue(categoryName(viewModel.category ?? intent.category))
            .accessibilityIdentifier("nutrition.quick-add.category")
        }
    }

    private var loadError: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                Text(localized("nutrition.quickAdd.loadError"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryActionButton(
                    title: localized("nutrition.quickAdd.retry"),
                    accessibilityLabel: localized("nutrition.quickAdd.retry"),
                    minimumHeight: 52
                ) {
                    Task { await viewModel.retryLoad() }
                }
                .accessibilityIdentifier("nutrition.quick-add.load-retry")
            }
        }
        .accessibilityIdentifier("nutrition.quick-add.state.load-error")
    }

    private func recipeSummary(_ recipe: RecipeSnapshot) -> String {
        let macros = (try? recipe.resolvedMacros(consumedServings: 1))
            ?? recipe.totalMacros
        return String(
            format: localized("nutrition.quickAdd.recipe.format"),
            locale: .current,
            formatted(recipe.servings),
            macroSummary(macros)
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

    private func decimal(_ value: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        return formatter.number(from: value)?.decimalValue
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
