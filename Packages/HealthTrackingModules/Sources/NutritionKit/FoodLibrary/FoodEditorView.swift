import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct FoodEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand: String
    @State private var servingSize: String
    @State private var servingUnit: String
    @State private var calories: String
    @State private var proteinG: String
    @State private var carbG: String
    @State private var fatG: String
    @State private var fiberG: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    private let food: FoodSnapshot?
    private let onSave: @MainActor (FoodInput) async -> Bool

    public init(
        food: FoodSnapshot? = nil,
        onSave: @escaping @MainActor (FoodInput) async -> Bool
    ) {
        self.food = food
        self.onSave = onSave
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _servingSize = State(initialValue: Self.decimalString(food?.servingSize))
        _servingUnit = State(initialValue: food?.servingUnit ?? "")
        _calories = State(initialValue: Self.decimalString(food?.macros.calories))
        _proteinG = State(initialValue: Self.decimalString(food?.macros.proteinG))
        _carbG = State(initialValue: Self.decimalString(food?.macros.carbG))
        _fatG = State(initialValue: Self.decimalString(food?.macros.fatG))
        _fiberG = State(initialValue: Self.decimalString(food?.fiberG))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(localized("nutrition.food.editor.identity.section")) {
                    editorField("nutrition.food.field.name", text: $name)
                    editorField("nutrition.food.field.brand", text: $brand)
                    editorField("nutrition.food.field.servingSize", text: $servingSize)
                        .keyboardType(.decimalPad)
                    editorField("nutrition.food.field.servingUnit", text: $servingUnit)
                }

                Section(localized("nutrition.food.editor.macros.section")) {
                    editorField("nutrition.food.field.calories", text: $calories)
                        .keyboardType(.decimalPad)
                    editorField("nutrition.food.field.protein", text: $proteinG)
                        .keyboardType(.decimalPad)
                    editorField("nutrition.food.field.carbs", text: $carbG)
                        .keyboardType(.decimalPad)
                    editorField("nutrition.food.field.fat", text: $fatG)
                        .keyboardType(.decimalPad)
                    editorField("nutrition.food.field.fiber", text: $fiberG)
                        .keyboardType(.decimalPad)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(AppTypography.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nutrition.food.editor.error")
                }
            }
            .navigationTitle(
                localized(
                    food == nil
                        ? "nutrition.food.editor.create.title"
                        : "nutrition.food.editor.edit.title"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("nutrition.food.editor.cancel")) {
                        dismiss()
                    }
                    .frame(minWidth: 52, minHeight: 52)
                    .accessibilityHint(localized("nutrition.food.editor.cancel.hint"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("nutrition.food.editor.save")) {
                        Task { await submit() }
                    }
                    .frame(minWidth: 52, minHeight: 52)
                    .disabled(isSaving)
                    .accessibilityHint(localized("nutrition.food.editor.save.hint"))
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("nutrition.food.editor")
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
        guard let servingSize = Self.decimal(servingSize),
              let calories = Self.decimal(calories),
              let proteinG = Self.decimal(proteinG),
              let carbG = Self.decimal(carbG),
              let fatG = Self.decimal(fatG) else {
            validationMessage = localized("nutrition.food.editor.invalidNumber")
            return
        }
        let fiberText = fiberG.trimmingCharacters(in: .whitespacesAndNewlines)
        let fiber: Decimal?
        if fiberText.isEmpty {
            fiber = nil
        } else if let parsed = Self.decimal(fiberText) {
            fiber = parsed
        } else {
            validationMessage = localized("nutrition.food.editor.invalidNumber")
            return
        }

        do {
            let input = try FoodInput(
                name: name,
                brand: brand,
                servingSize: servingSize,
                servingUnit: servingUnit,
                caloriesPerServing: calories,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                fiberG: fiber
            )
            isSaving = true
            let saved = await onSave(input)
            isSaving = false
            if saved {
                dismiss()
            } else {
                validationMessage = localized("nutrition.food.editor.saveError")
            }
        } catch {
            validationMessage = localized("nutrition.food.editor.invalidInput")
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
