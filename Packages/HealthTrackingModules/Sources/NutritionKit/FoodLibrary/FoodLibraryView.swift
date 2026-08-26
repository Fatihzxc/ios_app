import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct FoodLibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: FoodLibraryViewModel
    @State private var editorRoute: FoodEditorRoute?

    public init(viewModel: FoodLibraryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                FeatureStateView(state: .loading)
                    .padding(AppSpacing.screenHorizontal)
            case let .content(foods):
                foodList(foods)
            case .empty:
                stateView(
                    message: localized("nutrition.food.empty.message"),
                    actionTitle: localized("nutrition.food.add"),
                    action: { editorRoute = .create }
                )
            case .searchEmpty:
                stateView(
                    message: localized("nutrition.food.search.empty"),
                    actionTitle: localized("nutrition.food.search.clear"),
                    action: { Task { await viewModel.search("") } }
                )
            case .error:
                stateView(
                    message: localized("nutrition.food.load.error"),
                    actionTitle: localized("nutrition.food.retry"),
                    action: { Task { await viewModel.retry() } }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(localized("nutrition.food.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: Binding(
                get: { viewModel.query },
                set: { query in Task { await viewModel.search(query) } }
            ),
            prompt: Text(localized("nutrition.food.search.prompt"))
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorRoute = .create
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel(localized("nutrition.food.add"))
                .accessibilityHint(localized("nutrition.food.add.hint"))
                .accessibilityIdentifier("nutrition.food.add")
            }
        }
        .sheet(item: $editorRoute) { route in
            FoodEditorView(food: route.food) { input in
                switch route {
                case .create:
                    return await viewModel.create(input)
                case let .edit(food):
                    return await viewModel.update(id: food.id, input: input)
                }
            }
        }
        .alert(
            localized("nutrition.food.save.error.title"),
            isPresented: mutationErrorBinding
        ) {
            Button(localized("nutrition.food.save.error.dismiss")) {
                viewModel.dismissMutationError()
            }
        } message: {
            Text(localized("nutrition.food.save.error.message"))
        }
        .task { await viewModel.load() }
        .accessibilityIdentifier("nutrition.food.library")
    }

    private func foodList(_ foods: [FoodSnapshot]) -> some View {
        List(foods) { food in
            Group {
                if food.source == .userCreated {
                    Button {
                        editorRoute = .edit(food)
                    } label: {
                        foodRow(food)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(localized("nutrition.food.edit.hint"))
                } else {
                    foodRow(food)
                }
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel(food))
            .accessibilityIdentifier(
                "nutrition.food.row.\(food.id.uuidString.lowercased())"
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if food.source == .userCreated {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(id: food.id) }
                    } label: {
                        Label(
                            localized("nutrition.food.delete"),
                            systemImage: "trash"
                        )
                    }
                    .accessibilityHint(localized("nutrition.food.delete.hint"))
                    .accessibilityIdentifier(
                        "nutrition.food.delete.\(food.id.uuidString.lowercased())"
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    private func foodRow(_ food: FoodSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(food.name)
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if let brand = food.brand {
                Text(brand)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(servingSummary(food))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(macroSummary(food.macros))
                .font(AppTypography.numericRow)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.compact)
    }

    private func stateView(
        message: String,
        actionTitle: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(
                title: actionTitle,
                accessibilityLabel: actionTitle,
                minimumHeight: 52,
                action: action
            )
        }
        .padding(AppSpacing.screenHorizontal)
    }

    private var mutationErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.mutationState == .saveError },
            set: { isPresented in
                if !isPresented { viewModel.dismissMutationError() }
            }
        )
    }

    private func servingSummary(_ food: FoodSnapshot) -> String {
        String(
            format: localized("nutrition.food.serving.format"),
            locale: .current,
            formatted(food.servingSize),
            food.servingUnit
        )
    }

    private func macroSummary(_ macros: NutritionMacros) -> String {
        String(
            format: localized("nutrition.food.macros.format"),
            locale: .current,
            formatted(macros.calories),
            formatted(macros.proteinG),
            formatted(macros.carbG),
            formatted(macros.fatG)
        )
    }

    private func rowAccessibilityLabel(_ food: FoodSnapshot) -> String {
        let brand = food.brand ?? localized("nutrition.food.brand.none")
        return String(
            format: localized("nutrition.food.row.accessibility"),
            locale: .current,
            food.name,
            brand,
            servingSummary(food),
            macroSummary(food.macros)
        )
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

private enum FoodEditorRoute: Identifiable {
    case create
    case edit(FoodSnapshot)

    var id: String {
        switch self {
        case .create: return "create"
        case let .edit(food): return food.id.uuidString
        }
    }

    var food: FoodSnapshot? {
        switch self {
        case .create: return nil
        case let .edit(food): return food
        }
    }
}
