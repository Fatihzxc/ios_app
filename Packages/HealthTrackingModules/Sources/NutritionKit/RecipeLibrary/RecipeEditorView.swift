import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: MealCategory.Kind
    @State private var customCategoryName: String
    @State private var servings: String
    @State private var calories: String
    @State private var proteinG: String
    @State private var carbG: String
    @State private var fatG: String
    @State private var note: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    private let recipe: RecipeSnapshot?
    private let onSave: @MainActor (RecipeInput) async -> Bool

    public init(
        recipe: RecipeSnapshot? = nil,
        onSave: @escaping @MainActor (RecipeInput) async -> Bool
    ) {
        self.recipe = recipe
        self.onSave = onSave
        _name = State(initialValue: recipe?.name ?? "")
        _category = State(initialValue: recipe?.category.kind ?? .dinner)
        _customCategoryName = State(
            initialValue: recipe?.category.customName ?? ""
        )
        _servings = State(initialValue: Self.decimalString(recipe?.servings))
        _calories = State(
            initialValue: Self.decimalString(recipe?.totalMacros.calories)
        )
        _proteinG = State(
            initialValue: Self.decimalString(recipe?.totalMacros.proteinG)
        )
        _carbG = State(
            initialValue: Self.decimalString(recipe?.totalMacros.carbG)
        )
        _fatG = State(
            initialValue: Self.decimalString(recipe?.totalMacros.fatG)
        )
        _note = State(initialValue: recipe?.note ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(localized("nutrition.recipe.editor.identity.section")) {
                    editorField("nutrition.recipe.field.name", text: $name)
                    Picker(
                        localized("nutrition.recipe.field.category"),
                        selection: $category
                    ) {
                        ForEach(MealCategory.Kind.allCases, id: \.self) { kind in
                            Text(categoryName(kind)).tag(kind)
                        }
                    }
                    .frame(minHeight: 52)
                    .accessibilityHint(
                        localized("nutrition.recipe.field.category.hint")
                    )

                    if category == .custom {
                        editorField(
                            "nutrition.recipe.field.customCategory",
                            text: $customCategoryName
                        )
                    }
                    editorField(
                        "nutrition.recipe.field.servings",
                        text: $servings
                    )
                    .keyboardType(.decimalPad)
                }

                Section(localized("nutrition.recipe.editor.macros.section")) {
                    Text(localized("nutrition.recipe.editor.macros.help"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    editorField(
                        "nutrition.recipe.field.calories",
                        text: $calories
                    )
                    .keyboardType(.decimalPad)
                    editorField(
                        "nutrition.recipe.field.protein",
                        text: $proteinG
                    )
                    .keyboardType(.decimalPad)
                    editorField(
                        "nutrition.recipe.field.carbs",
                        text: $carbG
                    )
                    .keyboardType(.decimalPad)
                    editorField("nutrition.recipe.field.fat", text: $fatG)
                        .keyboardType(.decimalPad)
                }

                Section(localized("nutrition.recipe.editor.note.section")) {
                    TextField(
                        localized("nutrition.recipe.field.note"),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .frame(minHeight: 52)
                    .accessibilityLabel(localized("nutrition.recipe.field.note"))
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutrition.recipe.editor.error")
                }
            }
            .navigationTitle(
                localized(
                    recipe == nil
                        ? "nutrition.recipe.editor.create.title"
                        : "nutrition.recipe.editor.edit.title"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("nutrition.recipe.editor.cancel")) {
                        dismiss()
                    }
                    .frame(minWidth: 52, minHeight: 52)
                    .accessibilityHint(
                        localized("nutrition.recipe.editor.cancel.hint")
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("nutrition.recipe.editor.save")) {
                        Task { await submit() }
                    }
                    .frame(minWidth: 52, minHeight: 52)
                    .disabled(isSaving)
                    .accessibilityHint(
                        localized("nutrition.recipe.editor.save.hint")
                    )
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("nutrition.recipe.editor")
    }

    private func editorField(
        _ key: String.LocalizationValue,
        text: Binding<String>
    ) -> some View {
        TextField(localized(key), text: text)
            .frame(minHeight: 52)
            .accessibilityLabel(localized(key))
    }

    private func submit() async {
        validationMessage = nil
        guard let servings = Self.decimal(servings),
              let calories = Self.decimal(calories),
              let proteinG = Self.decimal(proteinG),
              let carbG = Self.decimal(carbG),
              let fatG = Self.decimal(fatG) else {
            validationMessage = localized("nutrition.recipe.editor.invalidNumber")
            return
        }

        do {
            let mealCategory = try MealCategory(
                kind: category,
                customName: category == .custom ? customCategoryName : nil
            )
            let input = try RecipeInput(
                name: name,
                category: mealCategory,
                servings: servings,
                caloriesTotal: calories,
                proteinTotalG: proteinG,
                carbTotalG: carbG,
                fatTotalG: fatG,
                note: note
            )
            isSaving = true
            let saved = await onSave(input)
            isSaving = false
            if saved {
                dismiss()
            } else {
                validationMessage = localized(
                    "nutrition.recipe.editor.saveError"
                )
            }
        } catch {
            validationMessage = localized("nutrition.recipe.editor.invalidInput")
        }
    }

    private func categoryName(_ category: MealCategory.Kind) -> String {
        switch category {
        case .breakfast:
            return localized("nutrition.recipe.category.breakfast")
        case .lunch:
            return localized("nutrition.recipe.category.lunch")
        case .dinner:
            return localized("nutrition.recipe.category.dinner")
        case .snack:
            return localized("nutrition.recipe.category.snack")
        case .custom:
            return localized("nutrition.recipe.category.custom")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    private static func decimal(_ text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        return formatter.number(from: text)?.decimalValue
    }

    private static func decimalString(_ value: Decimal?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = NutritionDecimalMath.scale
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}
