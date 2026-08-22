import CoreModels
import DesignSystem
import Foundation
import SwiftUI

@MainActor
public struct RecipeLibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var viewModel: RecipeLibraryViewModel
    @State private var editorRoute: RecipeEditorRoute?

    public init(viewModel: RecipeLibraryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                FeatureStateView(state: .loading)
                    .padding(AppSpacing.screenHorizontal)
            case let .content(library):
                recipeList(library)
            case .empty:
                stateView(
                    message: localized("nutrition.recipe.empty.message"),
                    actionTitle: localized("nutrition.recipe.add"),
                    action: { editorRoute = .create }
                )
            case .searchEmpty:
                stateView(
                    message: localized("nutrition.recipe.search.empty"),
                    actionTitle: localized("nutrition.recipe.search.clear"),
                    action: {
                        Task {
                            await viewModel.search("")
                            await viewModel.filter(by: nil)
                        }
                    }
                )
            case .error:
                stateView(
                    message: localized("nutrition.recipe.load.error"),
                    actionTitle: localized("nutrition.recipe.retry"),
                    action: { Task { await viewModel.retry() } }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.color(.backgroundBase, scheme: colorScheme))
        .navigationTitle(localized("nutrition.recipe.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: Binding(
                get: { viewModel.query },
                set: { query in Task { await viewModel.search(query) } }
            ),
            prompt: Text(localized("nutrition.recipe.search.prompt"))
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                categoryFilterMenu
                Button {
                    editorRoute = .create
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel(localized("nutrition.recipe.add"))
                .accessibilityHint(localized("nutrition.recipe.add.hint"))
                .accessibilityIdentifier("nutrition.recipe.add")
            }
        }
        .sheet(item: $editorRoute) { route in
            RecipeEditorView(recipe: route.recipe) { input in
                switch route {
                case .create:
                    return await viewModel.create(input)
                case let .edit(recipe):
                    return await viewModel.update(id: recipe.id, input: input)
                }
            }
        }
        .alert(
            localized("nutrition.recipe.save.error.title"),
            isPresented: mutationErrorBinding
        ) {
            Button(localized("nutrition.recipe.save.error.dismiss")) {
                viewModel.dismissMutationError()
            }
        } message: {
            Text(localized("nutrition.recipe.save.error.message"))
        }
        .task { await viewModel.load() }
        .accessibilityIdentifier("nutrition.recipe.library")
    }

    private var categoryFilterMenu: some View {
        Menu {
            Picker(
                localized("nutrition.recipe.filter.title"),
                selection: Binding(
                    get: { viewModel.categoryFilter },
                    set: { category in
                        Task { await viewModel.filter(by: category) }
                    }
                )
            ) {
                Text(localized("nutrition.recipe.filter.all"))
                    .tag(MealCategory.Kind?.none)
                ForEach(MealCategory.Kind.allCases, id: \.self) { category in
                    Text(categoryName(category))
                        .tag(Optional(category))
                }
            }
        } label: {
            Image(systemName: viewModel.categoryFilter == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel(localized("nutrition.recipe.filter.title"))
        .accessibilityValue(
            viewModel.categoryFilter.map { categoryName($0) }
                ?? localized("nutrition.recipe.filter.all")
        )
        .accessibilityHint(localized("nutrition.recipe.filter.hint"))
        .accessibilityIdentifier("nutrition.recipe.filter")
    }

    private func recipeList(_ library: RecipeLibrarySnapshot) -> some View {
        List {
            if !library.active.isEmpty {
                Section(localized("nutrition.recipe.active.section")) {
                    ForEach(library.active) { recipe in
                        Button {
                            editorRoute = .edit(recipe)
                        } label: {
                            recipeRow(recipe)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 52)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(rowAccessibilityLabel(recipe))
                        .accessibilityHint(localized("nutrition.recipe.edit.hint"))
                        .accessibilityIdentifier(
                            "nutrition.recipe.row.\(recipe.id.uuidString.lowercased())"
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.remove(id: recipe.id) }
                            } label: {
                                Label(
                                    localized("nutrition.recipe.remove"),
                                    systemImage: "archivebox"
                                )
                            }
                            .accessibilityHint(
                                localized("nutrition.recipe.remove.hint")
                            )
                            .accessibilityIdentifier(
                                "nutrition.recipe.remove.\(recipe.id.uuidString.lowercased())"
                            )
                        }
                    }
                }
            }

            if !library.archived.isEmpty {
                Section(localized("nutrition.recipe.archived.section")) {
                    ForEach(library.archived) { recipe in
                        VStack(alignment: .leading, spacing: AppSpacing.standard) {
                            recipeRow(recipe)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(rowAccessibilityLabel(recipe))
                                .accessibilityIdentifier(
                                    "nutrition.recipe.archived.\(recipe.id.uuidString.lowercased())"
                                )
                            Button {
                                Task { await viewModel.restore(id: recipe.id) }
                            } label: {
                                Label(
                                    localized("nutrition.recipe.restore"),
                                    systemImage: "arrow.uturn.backward"
                                )
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint(
                                localized("nutrition.recipe.restore.hint")
                            )
                            .accessibilityIdentifier(
                                "nutrition.recipe.restore.\(recipe.id.uuidString.lowercased())"
                            )
                        }
                        .padding(.vertical, AppSpacing.compact)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func recipeRow(_ recipe: RecipeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(recipe.name)
                .font(AppTypography.titleMedium)
                .foregroundStyle(AppColors.color(.inkPrimary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(categorySummary(recipe.category))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(servingsSummary(recipe.servings))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.color(.inkSecondary, scheme: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text(macroSummary(recipe.totalMacros))
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

    private func categorySummary(_ category: MealCategory) -> String {
        if let customName = category.customName { return customName }
        return categoryName(category.kind)
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

    private func servingsSummary(_ servings: Decimal) -> String {
        String(
            format: localized("nutrition.recipe.servings.format"),
            locale: .current,
            formatted(servings)
        )
    }

    private func macroSummary(_ macros: NutritionMacros) -> String {
        String(
            format: localized("nutrition.recipe.macros.format"),
            locale: .current,
            formatted(macros.calories),
            formatted(macros.proteinG),
            formatted(macros.carbG),
            formatted(macros.fatG)
        )
    }

    private func rowAccessibilityLabel(_ recipe: RecipeSnapshot) -> String {
        String(
            format: localized("nutrition.recipe.row.accessibility"),
            locale: .current,
            recipe.name,
            categorySummary(recipe.category),
            servingsSummary(recipe.servings),
            macroSummary(recipe.totalMacros)
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

private enum RecipeEditorRoute: Identifiable {
    case create
    case edit(RecipeSnapshot)

    var id: String {
        switch self {
        case .create: return "create"
        case let .edit(recipe): return recipe.id.uuidString
        }
    }

    var recipe: RecipeSnapshot? {
        switch self {
        case .create: return nil
        case let .edit(recipe): return recipe
        }
    }
}
