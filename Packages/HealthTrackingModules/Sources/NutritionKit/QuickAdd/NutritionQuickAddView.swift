import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct NutritionQuickAddView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: NutritionQuickAddViewModel
    private let onSaved: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void

    public init(
        viewModel: NutritionQuickAddViewModel,
        onSaved: @escaping @MainActor () -> Void = {},
        onCancel: @escaping @MainActor () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onSaved = onSaved
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
                        onCancel()
                    }
                    .accessibilityIdentifier("nutrition.quick-add.cancel")
                }
            }
        }
        .accessibilityIdentifier("nutrition.quick-add.root")
        .task {
            if viewModel.state == .loading {
                await viewModel.load()
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: viewModel.state
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            FeatureStateView(state: .loading)
                .accessibilityIdentifier("nutrition.quick-add.loading")
        case .recipes:
            recipeSelection
        case .confirmation, .saving, .saveError:
            confirmation
        case .saved:
            FeatureStateView(state: .loading)
        case .empty:
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(localized("nutrition.quickAdd.empty"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    categoryPicker
                }
            }
            .accessibilityIdentifier("nutrition.quick-add.empty")
        case .loadError:
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    Text(localized("nutrition.quickAdd.loadError"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryActionButton(
                        title: localized("nutrition.quickAdd.retry"),
                        accessibilityLabel: localized("nutrition.quickAdd.retry")
                    ) {
                        Task { await viewModel.retryLoad() }
                    }
                    .accessibilityIdentifier("nutrition.quick-add.load-retry")
                }
            }
            .accessibilityIdentifier("nutrition.quick-add.load-error")
        }
    }

    private var recipeSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(categoryName(viewModel.category))
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            ForEach(viewModel.recipes) { recipe in
                Button {
                    viewModel.selectRecipe(id: recipe.id)
                } label: {
                    AppCard {
                        HStack(alignment: .center, spacing: AppSpacing.compact) {
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
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(
                                    AppColors.color(.accentAction, scheme: colorScheme)
                                )
                                .frame(width: 52, height: 52)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityLabel(recipe.name)
                .accessibilityValue(recipeSummary(recipe))
                .accessibilityHint(localized("nutrition.quickAdd.recipe.hint"))
                .accessibilityIdentifier(
                    "nutrition.quick-add.recipe.\(recipe.id.uuidString.lowercased())"
                )
            }
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            if let recipe = viewModel.selectedRecipe {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(recipe.name)
                            .font(AppTypography.titleMedium)
                            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recipeSummary(recipe))
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                AppColors.color(.inkSecondary, scheme: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(recipe.name)
                .accessibilityValue(recipeSummary(recipe))
                .accessibilityIdentifier("nutrition.quick-add.selection")
            }

            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.standard) {
                    categoryPicker
                    quantityStepper
                }
            }

            if viewModel.state == .saveError {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.standard) {
                        Text(localized("nutrition.quickAdd.saveError"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.color(.stateDanger, scheme: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("nutrition.quick-add.error")
                        PrimaryActionButton(
                            title: localized("nutrition.quickAdd.retry"),
                            accessibilityLabel: localized("nutrition.quickAdd.retry")
                        ) {
                            Task {
                                await viewModel.retrySave()
                                finishIfSaved()
                            }
                        }
                        .accessibilityIdentifier("nutrition.quick-add.retry")
                    }
                }
            } else {
                PrimaryActionButton(
                    title: localized("nutrition.quickAdd.confirm"),
                    accessibilityLabel: confirmAccessibilityLabel
                ) {
                    Task {
                        await viewModel.confirm()
                        finishIfSaved()
                    }
                }
                .disabled(viewModel.state == .saving)
                .accessibilityHint(localized("nutrition.quickAdd.confirm.hint"))
                .accessibilityIdentifier("nutrition.quick-add.confirm")
            }
        }
    }

    private var categoryPicker: some View {
        Picker(
            localized("nutrition.quickAdd.category"),
            selection: Binding(
                get: { viewModel.category.kind },
                set: { kind in
                    guard let category = try? MealCategory(kind: kind) else { return }
                    viewModel.updateCategory(category)
                }
            )
        ) {
            ForEach(standardCategoryKinds, id: \.self) { kind in
                Text(categoryName((try? MealCategory(kind: kind)) ?? .defaultValue))
                    .tag(kind)
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 52)
        .disabled(
            viewModel.state == .saving || viewModel.state == .saveError
        )
        .accessibilityIdentifier("nutrition.quick-add.category")
    }

    private var quantityStepper: some View {
        Stepper {
            Text(
                String(
                    format: localized("nutrition.quickAdd.quantity.format"),
                    locale: .current,
                    formatted(viewModel.quantity)
                )
            )
            .font(AppTypography.body)
            .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
        } onIncrement: {
            try? viewModel.updateQuantity(viewModel.quantity + Decimal(string: "0.5")!)
        } onDecrement: {
            guard viewModel.quantity > Decimal(string: "0.5")! else { return }
            try? viewModel.updateQuantity(viewModel.quantity - Decimal(string: "0.5")!)
        }
        .frame(minHeight: 52)
        .disabled(
            viewModel.state == .saving || viewModel.state == .saveError
        )
        .accessibilityLabel(localized("nutrition.quickAdd.quantity"))
        .accessibilityValue(formatted(viewModel.quantity))
        .accessibilityIdentifier("nutrition.quick-add.quantity")
    }

    private var standardCategoryKinds: [MealCategory.Kind] {
        [.breakfast, .lunch, .dinner, .snack]
    }

    private var confirmAccessibilityLabel: String {
        guard let recipe = viewModel.selectedRecipe else {
            return localized("nutrition.quickAdd.confirm")
        }
        return String(
            format: localized("nutrition.quickAdd.confirm.accessibility"),
            locale: .current,
            recipe.name,
            formatted(viewModel.quantity),
            categoryName(viewModel.category)
        )
    }

    private func finishIfSaved() {
        if viewModel.state == .saved {
            onSaved()
        }
    }

    private func categoryName(_ category: MealCategory) -> String {
        switch category.kind {
        case .breakfast:
            localized("nutrition.day.category.breakfast")
        case .lunch:
            localized("nutrition.day.category.lunch")
        case .dinner:
            localized("nutrition.day.category.dinner")
        case .snack:
            localized("nutrition.day.category.snack")
        case .custom:
            category.customName ?? localized("nutrition.day.category.custom")
        }
    }

    private func recipeSummary(_ recipe: RecipeSnapshot) -> String {
        let macros = (try? recipe.resolvedMacros(consumedServings: 1))
            ?? recipe.totalMacros
        return String(
            format: localized("nutrition.quickAdd.recipe.summary"),
            locale: .current,
            formatted(recipe.servings),
            formatted(macros.calories),
            formatted(macros.proteinG),
            formatted(macros.carbG),
            formatted(macros.fatG)
        )
    }

    private func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
