#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

verify_repo() {
    local target_root="$1"
    python3 - "$target_root" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
catalogs = {}
for catalog in root.rglob("*.xcstrings"):
    try:
        payload = json.loads(catalog.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"Invalid String Catalog {catalog.relative_to(root)}: {error}") from error
    strings = payload.get("strings")
    if not isinstance(strings, dict):
        raise SystemExit(f"String Catalog {catalog.relative_to(root)} must contain an object named strings.")
    catalogs[catalog.parent] = strings

if not catalogs:
    raise SystemExit("No String Catalog files were found.")

source_roots = [root / "App", root / "Packages" / "HealthTrackingModules" / "Sources"]
swift_files = [
    path for source_root in source_roots if source_root.is_dir()
    for path in source_root.rglob("*.swift")
    if "Tests" not in path.parts
]

def owner_catalog(source):
    relative = source.relative_to(root)
    if relative.parts[0] == "App":
        return root / "App/Resources"
    return root / "Packages/HealthTrackingModules/Sources" / relative.parts[3] / "Resources"

def line_number(text, offset):
    return text.count("\n", 0, offset) + 1

def has_translated_turkish_value(catalog, key):
    entry = catalog.get(key)
    if not isinstance(entry, dict):
        return False
    try:
        unit = entry["localizations"]["tr"]["stringUnit"]
    except (KeyError, TypeError):
        return False
    if not isinstance(unit, dict) or not isinstance(unit.get("value"), str) or not unit["value"].strip():
        return False
    return "state" not in unit or unit["state"] == "translated"

missing = []
raw_literals = []
direct_localized = re.compile(r'String\s*\(\s*localized:\s*"([^"\\]+)"(?P<arguments>[^)]*)\)', re.S)
training_helper_key = re.compile(r'(?<!String\()\blocalized\s*\(\s*"([^"\\]+)"', re.S)
view_literal = re.compile(
    r'\b(?:Text|Button|Label|Toggle|navigationTitle|accessibilityLabel|accessibilityValue|accessibilityHint)\s*\(\s*(?:verbatim\s*:\s*)?"(?:\\.|[^"\\])*"',
    re.S,
)
for source in swift_files:
    text = source.read_text(encoding="utf-8")
    relative = source.relative_to(root)
    keys = catalogs.get(owner_catalog(source), {})
    for match in direct_localized.finditer(text):
        key = match.group(1)
        if key not in keys:
            missing.append(f"Missing owner String Catalog key {key!r} referenced by {relative}")
        if relative.parts[0] == "Packages" and not re.search(r'\bbundle\s*:\s*\.module\b', match.group('arguments')):
            missing.append(f"Package String Catalog key {key!r} in {relative} must declare bundle: .module")
    if relative.parts[:4] == ("Packages", "HealthTrackingModules", "Sources", "TrainingKit"):
        for match in training_helper_key.finditer(text):
            key = match.group(1)
            if key not in keys:
                missing.append(f"Missing owner String Catalog helper key {key!r} referenced by {relative}")
    for match in view_literal.finditer(text):
        raw_literals.append(
            f"Raw user-visible literal in {relative}:{line_number(text, match.start())}: {match.group(0).strip()}"
        )

tab_hint_mappings = [
    ("today", "tab.today.hint"),
    ("training", "tab.training.hint"),
    ("nutrition", "tab.nutrition.hint"),
    ("progress", "tab.progress.hint"),
    ("settings", "tab.settings.hint"),
]
tab_metadata = root / "App/Application/AppTab.swift"
tab_root = root / "App/Application/AppRootView.swift"
tab_metadata_text = tab_metadata.read_text(encoding="utf-8") if tab_metadata.is_file() else ""
hint_property = re.search(
    r'var\s+hint\s*:\s*String\s*\{\s*switch\s+self\s*\{(?P<body>.*?)\n\s*\}\s*\n\s*\}',
    tab_metadata_text,
    re.S,
)
hint_body = hint_property.group("body") if hint_property else ""
for case_name, key in tab_hint_mappings:
    tab_catalog = catalogs.get(root / "App/Resources", {})
    if key not in tab_catalog:
        missing.append(f"Missing owner String Catalog hint key {key!r} in App/Resources/Localizable.xcstrings")
    elif not has_translated_turkish_value(tab_catalog, key):
        missing.append(f"Hint key {key!r} must have a non-empty translated Turkish String Catalog value")
    if not re.search(
        r'case\s+\.' + re.escape(case_name) + r'\s*:\s*String\s*\(\s*localized:\s*"' + re.escape(key) + r'"\s*\)',
        hint_body,
        re.S,
    ):
        missing.append(f"AppTab case .{case_name} must map exactly to localized hint key {key!r}")
tab_root_text = tab_root.read_text(encoding="utf-8") if tab_root.is_file() else ""
tab_scopes = [
    (
        "modern Tab",
        re.search(r'private\s+var\s+modernTabView\s*:\s*some\s+View\s*\{(?P<body>.*?)(?=\n\s*private\s+var\s+legacyTabView)', tab_root_text, re.S),
    ),
    (
        "legacy tab label",
        re.search(r'private\s+func\s+legacyTabLabel\s*\([^)]*\)\s*->\s*some\s+View\s*\{(?P<body>.*?)\n\s*\}', tab_root_text, re.S),
    ),
]
for scope_name, scope in tab_scopes:
    if scope is None or not re.search(r'\.accessibilityHint\s*\(\s*tab\.hint\s*\)', scope.group("body"), re.S):
        missing.append(f"AppRootView {scope_name} must apply AppTab localized hint metadata with .accessibilityHint(tab.hint).")

hint_contracts = [
    ("Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift", "Packages/HealthTrackingModules/Sources/TrainingKit/Resources", "today.empty.hint", '.accessibilityIdentifier("today.state.empty")', 220, True),
    ("Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift", "Packages/HealthTrackingModules/Sources/TrainingKit/Resources", "today.error.hint", '.accessibilityIdentifier("today.state.error")', 220, True),
    ("Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/SettingsFoundationView.swift", "Packages/HealthTrackingModules/Sources/SettingsKit/Resources", "settings.gallery.hint", '.accessibilityIdentifier("settings.gallery-link")', 200, True),
    ("Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/FoundationProgramView.swift", "Packages/HealthTrackingModules/Sources/TrainingKit/Resources", "foundation.empty.hint", '.accessibilityIdentifier("foundation.state.empty")', 260, True),
    ("Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/FoundationProgramView.swift", "Packages/HealthTrackingModules/Sources/TrainingKit/Resources", "foundation.error.hint", '.accessibilityIdentifier("foundation.state.error")', 260, True),
    ("Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift", "Packages/HealthTrackingModules/Sources/TrainingKit/Resources", "session.set.save.hint", '.accessibilityIdentifier("session.set.save")', 240, True),
    ("Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift", "Packages/HealthTrackingModules/Sources/TrainingKit/Resources", "session.exercise.next.hint", '.accessibilityIdentifier("session.exercise.next")', 240, True),
    ("Packages/HealthTrackingModules/Sources/DesignSystem/Gallery/DesignSystemGalleryView.swift", "Packages/HealthTrackingModules/Sources/DesignSystem/Resources", "designSystem.gallery.actionHint", 'isEnabled: false,', 240, True),
    ("Packages/HealthTrackingModules/Sources/DesignSystem/Gallery/DesignSystemGalleryView.swift", "Packages/HealthTrackingModules/Sources/DesignSystem/Resources", "designSystem.gallery.emptyActionHint", 'actionFeedback = String(localized: "designSystem.gallery.emptyActionConfirmation", bundle: .module)', 320, True),
    ("Packages/HealthTrackingModules/Sources/DesignSystem/Gallery/DesignSystemGalleryView.swift", "Packages/HealthTrackingModules/Sources/DesignSystem/Resources", "designSystem.gallery.retryHint", 'actionFeedback = String(localized: "designSystem.gallery.retryConfirmation", bundle: .module)', 320, True),
]
for source_name, catalog_name, key, anchor, maximum_gap, requires_module_bundle in hint_contracts:
    source = root / source_name
    catalog_keys = catalogs.get(root / catalog_name, {})
    if key not in catalog_keys:
        missing.append(f"Missing owner String Catalog hint key {key!r} in {catalog_name}/Localizable.xcstrings")
    elif not has_translated_turkish_value(catalog_keys, key):
        missing.append(f"Hint key {key!r} must have a non-empty translated Turkish String Catalog value")
    else:
        source_text = source.read_text(encoding="utf-8") if source.is_file() else ""
        anchor_offset = source_text.find(anchor)
        bundle_pattern = r'\s*,\s*bundle\s*:\s*\.module' if requires_module_bundle else ""
        hint_match = re.search(
            r'\.accessibilityHint\s*\(\s*String\s*\(\s*localized:\s*"' + re.escape(key) + r'"' + bundle_pattern + r'\s*\)\s*\)',
            source_text[anchor_offset + len(anchor):anchor_offset + len(anchor) + maximum_gap] if anchor_offset >= 0 else "",
            re.S,
        )
        if anchor_offset < 0 or hint_match is None:
            missing.append(f"Missing localized accessibilityHint for {key!r} on its intended control in {source_name}")

if missing or raw_literals:
    raise SystemExit("\n".join(missing + raw_literals))
print(f"Localization verification passed ({sum(map(len, catalogs.values()))} catalog keys; {len(swift_files)} Swift sources).")
PY
}

self_test() {
    self_test_fixture="$(mktemp -d)"
    trap 'rm -rf -- "$self_test_fixture"' EXIT
    local fixture="$self_test_fixture"
    mkdir -p "$fixture/App/Resources" "$fixture/App/Tests" "$fixture/App/Components" "$fixture/Packages/HealthTrackingModules/Sources/Feature/Resources" "$fixture/Packages/HealthTrackingModules/Sources/Feature/Foundation"
    printf '%s\n' '{"sourceLanguage":"tr","strings":{"known.key":{}}}' > "$fixture/App/Resources/Localizable.xcstrings"
    printf '%s\n' '{"sourceLanguage":"tr","strings":{"module.key":{}}}' > "$fixture/Packages/HealthTrackingModules/Sources/Feature/Resources/Localizable.xcstrings"
    printf '%s\n' 'import SwiftUI' 'struct Allowed: View { var body: some View { Text(String(localized: "known.key")) } }' > "$fixture/App/Components/Allowed.swift"
    printf '%s\n' 'import XCTest' 'func debugOnly() { print("Türkçe debug") }' 'func assertionOnly() { XCTFail("Türkçe test açıklaması") }' > "$fixture/App/Tests/AllowedTests.swift"
    # Bypass absent production hint contracts in this isolated scanner fixture.
    python3 - "$fixture" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
metadata = path / 'App/Application/AppTab.swift'
metadata.parent.mkdir(parents=True)
metadata.write_text('''enum AppTab {
    case today, training, nutrition, progress, settings
    var hint: String {
        switch self {
        case .today: String(localized: "tab.today.hint")
        case .training: String(localized: "tab.training.hint")
        case .nutrition: String(localized: "tab.nutrition.hint")
        case .progress: String(localized: "tab.progress.hint")
        case .settings: String(localized: "tab.settings.hint")
        }
    }
}
''')
root_source = path / 'App/Application/AppRootView.swift'
root_source.write_text('''private var modernTabView: some View {
    EmptyView().accessibilityHint(tab.hint)
}
private var legacyTabView: some View { EmptyView() }
private func legacyTabLabel(for tab: AppTab) -> some View {
    EmptyView().accessibilityHint(tab.hint)
}
''')
catalog = path / 'App/Resources/Localizable.xcstrings'
catalog.write_text('{"sourceLanguage":"tr","strings":{' + ','.join(f'"{key}":{{"localizations":{{"tr":{{"stringUnit":{{"state":"translated","value":"İpucu"}}}}}}}}' for key in ['known.key', 'tab.today.hint', 'tab.training.hint', 'tab.nutrition.hint', 'tab.progress.hint', 'tab.settings.hint', 'foundation.empty.hint', 'foundation.error.hint']) + '}}')
for module, source_name, keys in [
    ('SettingsKit', 'Foundation/SettingsFoundationView.swift', ['settings.gallery.hint']),
    ('TrainingKit', 'Foundation/FoundationProgramView.swift', ['foundation.empty.hint', 'foundation.error.hint']),
    ('DesignSystem', 'Gallery/DesignSystemGalleryView.swift', ['designSystem.gallery.actionHint', 'designSystem.gallery.emptyActionHint', 'designSystem.gallery.retryHint']),
]:
    resources = path / f'Packages/HealthTrackingModules/Sources/{module}/Resources'
    resources.mkdir(parents=True)
    catalog_keys = list(keys)
    if module == 'DesignSystem':
        catalog_keys += ['designSystem.gallery.emptyActionConfirmation', 'designSystem.gallery.retryConfirmation']
    if module == 'TrainingKit':
        catalog_keys += [
            'today.empty.hint',
            'today.error.hint',
            'session.set.save.hint',
            'session.exercise.next.hint',
        ]
    (resources / 'Localizable.xcstrings').write_text('{"sourceLanguage":"tr","strings":{' + ','.join(f'"{key}":{{"localizations":{{"tr":{{"stringUnit":{{"state":"translated","value":"İpucu"}}}}}}}}' for key in catalog_keys) + '}}')
    source = path / f'Packages/HealthTrackingModules/Sources/{module}/{source_name}'
    source.parent.mkdir(parents=True, exist_ok=True)
    anchors = {
        'settings.gallery.hint': '.accessibilityIdentifier("settings.gallery-link")',
        'foundation.empty.hint': '.accessibilityIdentifier("foundation.state.empty")',
        'foundation.error.hint': '.accessibilityIdentifier("foundation.state.error")',
        'designSystem.gallery.actionHint': 'isEnabled: false,',
        'designSystem.gallery.emptyActionHint': 'actionFeedback = String(localized: "designSystem.gallery.emptyActionConfirmation", bundle: .module)',
        'designSystem.gallery.retryHint': 'actionFeedback = String(localized: "designSystem.gallery.retryConfirmation", bundle: .module)',
    }
    source.write_text(''.join(f'{anchors[key]}\n.accessibilityHint(String(localized: "{key}", bundle: .module))\n' for key in keys))
today_source = path / 'Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift'
today_source.parent.mkdir(parents=True, exist_ok=True)
today_source.write_text('''.accessibilityIdentifier("today.state.empty")
.accessibilityHint(String(localized: "today.empty.hint", bundle: .module))
.accessibilityIdentifier("today.state.error")
.accessibilityHint(String(localized: "today.error.hint", bundle: .module))
''')
set_entry_source = path / 'Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift'
set_entry_source.parent.mkdir(parents=True, exist_ok=True)
set_entry_source.write_text('''.accessibilityIdentifier("session.set.save")
.accessibilityHint(String(localized: "session.set.save.hint", bundle: .module))
''')
exercise_source = path / 'Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift'
exercise_source.write_text('''.accessibilityIdentifier("session.exercise.next")
.accessibilityHint(String(localized: "session.exercise.next.hint", bundle: .module))
''')
PY
    verify_repo "$fixture"

    printf '%s\n' 'import SwiftUI' 'struct Raw: View { var body: some View { Text(' '    "Merhaba dünya"' ') } }' > "$fixture/App/Components/RawComponent.swift"
    if verify_repo "$fixture" >"$fixture/raw.out" 2>&1; then echo "Localization self-test expected a raw Turkish literal failure." >&2; return 1; fi
    grep -Fq 'Raw user-visible literal' "$fixture/raw.out"
    rm "$fixture/App/Components/RawComponent.swift"

    printf '%s\n' 'import SwiftUI' 'struct ASCII: View { var body: some View { Button("Tekrar") {} } }' > "$fixture/App/Components/ASCIIComponent.swift"
    if verify_repo "$fixture" >"$fixture/ascii.out" 2>&1; then echo "Localization self-test expected an ASCII raw literal failure." >&2; return 1; fi
    grep -Fq 'Raw user-visible literal' "$fixture/ascii.out"
    rm "$fixture/App/Components/ASCIIComponent.swift"

    printf '%s\n' 'import SwiftUI' 'struct Interpolated: View { let name: String; var body: some View { Text("Merhaba \(name)") } }' > "$fixture/App/Components/InterpolatedComponent.swift"
    if verify_repo "$fixture" >"$fixture/interpolated.out" 2>&1; then echo "Localization self-test expected an interpolated raw literal failure." >&2; return 1; fi
    grep -Fq 'Raw user-visible literal' "$fixture/interpolated.out"
    rm "$fixture/App/Components/InterpolatedComponent.swift"

    printf '%s\n' 'import SwiftUI' 'struct Verbatim: View { var body: some View { Text(verbatim: "Merhaba") } }' > "$fixture/App/Components/VerbatimComponent.swift"
    if verify_repo "$fixture" >"$fixture/verbatim.out" 2>&1; then echo "Localization self-test expected a verbatim raw literal failure." >&2; return 1; fi
    grep -Fq 'Raw user-visible literal' "$fixture/verbatim.out"
    rm "$fixture/App/Components/VerbatimComponent.swift"

    printf '%s\n' 'import SwiftUI' 'struct ToggleLiteral: View { @State var enabled = false; var body: some View { Toggle("Açık", isOn: $enabled) } }' > "$fixture/App/Components/ToggleComponent.swift"
    if verify_repo "$fixture" >"$fixture/toggle.out" 2>&1; then echo "Localization self-test expected a Toggle raw literal failure." >&2; return 1; fi
    grep -Fq 'Raw user-visible literal' "$fixture/toggle.out"
    rm "$fixture/App/Components/ToggleComponent.swift"

    printf '%s\n' 'import SwiftUI' 'struct Missing: View { var body: some View { Text(String(localized: "missing.key")) } }' > "$fixture/App/Components/Missing.swift"
    if verify_repo "$fixture" >"$fixture/missing.out" 2>&1; then echo "Localization self-test expected a missing catalog-key failure." >&2; return 1; fi
    grep -Fq "Missing owner String Catalog key 'missing.key'" "$fixture/missing.out"
    rm "$fixture/App/Components/Missing.swift"

    printf '%s\n' 'localized("missing.helper")' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/MissingHelper.swift"
    if verify_repo "$fixture" >"$fixture/helper.out" 2>&1; then echo "Localization self-test expected a missing TrainingKit helper-key failure." >&2; return 1; fi
    grep -Fq "Missing owner String Catalog helper key 'missing.helper'" "$fixture/helper.out"
    rm "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/MissingHelper.swift"

    printf '%s\n' 'String(localized: "module.key")' > "$fixture/Packages/HealthTrackingModules/Sources/Feature/Foundation/MissingBundle.swift"
    if verify_repo "$fixture" >"$fixture/bundle.out" 2>&1; then echo "Localization self-test expected a missing bundle failure." >&2; return 1; fi
    grep -Fq "Package String Catalog key 'module.key'" "$fixture/bundle.out"
    rm "$fixture/Packages/HealthTrackingModules/Sources/Feature/Foundation/MissingBundle.swift"

    cp "$fixture/App/Application/AppRootView.swift" "$fixture/App/Application/AppRootView.valid.swift"
    printf '%s\n' '.accessibilityHint("tab.today.hint")' > "$fixture/App/Application/AppRootView.swift"
    if verify_repo "$fixture" >"$fixture/bare-hint.out" 2>&1; then echo "Localization self-test expected a bare hint failure." >&2; return 1; fi
    grep -Fq 'AppRootView modern Tab must apply AppTab localized hint metadata with .accessibilityHint(tab.hint).' "$fixture/bare-hint.out"
    mv "$fixture/App/Application/AppRootView.valid.swift" "$fixture/App/Application/AppRootView.swift"

    cp "$fixture/App/Application/AppRootView.swift" "$fixture/App/Application/AppRootView.valid.swift"
    python3 - "$fixture/App/Application/AppRootView.swift" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
text = path.read_text()
before, separator, after = text.rpartition('    EmptyView().accessibilityHint(tab.hint)')
path.write_text(before + ('    EmptyView()' if separator else '') + after)
PY
    if verify_repo "$fixture" >"$fixture/legacy-hint.out" 2>&1; then echo "Localization self-test expected a missing legacy hint failure." >&2; return 1; fi
    grep -Fq 'AppRootView legacy tab label must apply AppTab localized hint metadata with .accessibilityHint(tab.hint).' "$fixture/legacy-hint.out"
    mv "$fixture/App/Application/AppRootView.valid.swift" "$fixture/App/Application/AppRootView.swift"

    cp "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.valid.swift"
    python3 - "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('.accessibilityHint(String(localized: "today.empty.hint", bundle: .module))', '.accessibilityHint(unrelatedHint)', 1))
PY
    if verify_repo "$fixture" >"$fixture/today-hint.out" 2>&1; then echo "Localization self-test expected a missing Today empty-state hint failure." >&2; return 1; fi
    grep -Fq "Missing localized accessibilityHint for 'today.empty.hint' on its intended control in Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift" "$fixture/today-hint.out"
    mv "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.valid.swift" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"

    cp "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.valid.swift"
    printf '%s\n' '.accessibilityIdentifier("session.set.save")' '.accessibilityHint(unrelatedHint)' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift"
    if verify_repo "$fixture" >"$fixture/session-save-hint.out" 2>&1; then echo "Localization self-test expected a missing session save hint failure." >&2; return 1; fi
    grep -Fq "Missing localized accessibilityHint for 'session.set.save.hint' on its intended control" "$fixture/session-save-hint.out"
    mv "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.valid.swift" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift"

    cp "$fixture/App/Application/AppTab.swift" "$fixture/App/Application/AppTab.valid.swift"
    python3 - "$fixture/App/Application/AppTab.swift" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
text = path.read_text().replace('"tab.today.hint"', '"swap.sentinel"', 1).replace('"tab.training.hint"', '"tab.today.hint"', 1).replace('"swap.sentinel"', '"tab.training.hint"', 1)
path.write_text(text)
PY
    if verify_repo "$fixture" >"$fixture/swapped-tab.out" 2>&1; then echo "Localization self-test expected swapped AppTab hint mappings to fail." >&2; return 1; fi
    grep -Fq "AppTab case .today must map exactly to localized hint key 'tab.today.hint'" "$fixture/swapped-tab.out"
    mv "$fixture/App/Application/AppTab.valid.swift" "$fixture/App/Application/AppTab.swift"

    cp "$fixture/App/Application/AppTab.swift" "$fixture/App/Application/AppTab.valid.swift"
    printf '%s\n' 'String(localized: "tab.today.hint")' 'String(localized: "tab.training.hint")' 'String(localized: "tab.nutrition.hint")' 'String(localized: "tab.progress.hint")' 'String(localized: "tab.settings.hint")' > "$fixture/App/Application/AppTab.swift"
    if verify_repo "$fixture" >"$fixture/decoy-tab.out" 2>&1; then echo "Localization self-test expected dead AppTab hint occurrences to fail." >&2; return 1; fi
    grep -Fq "AppTab case .settings must map exactly to localized hint key 'tab.settings.hint'" "$fixture/decoy-tab.out"
    mv "$fixture/App/Application/AppTab.valid.swift" "$fixture/App/Application/AppTab.swift"

    python3 - "$fixture/Packages/HealthTrackingModules/Sources/SettingsKit/Resources/Localizable.xcstrings" <<'PY'
import json
from pathlib import Path
path = Path(__import__('sys').argv[1])
payload = json.loads(path.read_text())
payload['strings']['settings.gallery.hint']['localizations']['tr']['stringUnit']['value'] = ''
path.write_text(json.dumps(payload, ensure_ascii=False))
PY
    if verify_repo "$fixture" >"$fixture/empty-translation.out" 2>&1; then echo "Localization self-test expected an empty Turkish hint translation failure." >&2; return 1; fi
    grep -Fq "Hint key 'settings.gallery.hint' must have a non-empty translated Turkish String Catalog value" "$fixture/empty-translation.out"
    printf '%s\n' '{"sourceLanguage":"tr","strings":{"settings.gallery.hint":{"localizations":{"tr":{"stringUnit":{"state":"translated","value":"Galeri ipucu"}}}}}}' > "$fixture/Packages/HealthTrackingModules/Sources/SettingsKit/Resources/Localizable.xcstrings"

    printf '%s\n' 'String(localized: "settings.gallery.hint", bundle: .module)' '.accessibilityHint(unrelatedHint)' > "$fixture/Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/SettingsFoundationView.swift"
    if verify_repo "$fixture" >"$fixture/proxy-hint.out" 2>&1; then echo "Localization self-test expected an unused localized hint failure." >&2; return 1; fi
    grep -Fq "Missing localized accessibilityHint for 'settings.gallery.hint' on its intended control" "$fixture/proxy-hint.out"

    printf '%s\n' '.accessibilityHint("settings.gallery.hint")' > "$fixture/Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/SettingsFoundationView.swift"
    if verify_repo "$fixture" >"$fixture/package-bare-hint.out" 2>&1; then echo "Localization self-test expected a package bare hint failure." >&2; return 1; fi
    grep -Fq "Missing localized accessibilityHint for 'settings.gallery.hint' on its intended control" "$fixture/package-bare-hint.out"

    printf '%s\n' '.accessibilityHint(String(localized: "wrong.owner.key", bundle: .module))' > "$fixture/Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/SettingsFoundationView.swift"
    if verify_repo "$fixture" >"$fixture/wrong-owner-hint.out" 2>&1; then echo "Localization self-test expected a wrong owner hint failure." >&2; return 1; fi
    grep -Fq "Missing localized accessibilityHint for 'settings.gallery.hint' on its intended control" "$fixture/wrong-owner-hint.out"

    printf '%s\n' 'import SwiftUI' 'struct Collision: View { var body: some View { Text(String(localized: "module.key", bundle: .module)) } }' > "$fixture/App/Components/Collision.swift"
    if verify_repo "$fixture" >"$fixture/collision.out" 2>&1; then echo "Localization self-test expected a cross-bundle catalog collision failure." >&2; return 1; fi
    grep -Fq "Missing owner String Catalog key 'module.key'" "$fixture/collision.out"
    echo "Localization verifier self-tests passed."
}

case "${1:-}" in
    "") verify_repo "$repo_root" ;;
    --self-test) self_test ;;
    *) echo "Usage: $0 [--self-test]" >&2; exit 2 ;;
esac
