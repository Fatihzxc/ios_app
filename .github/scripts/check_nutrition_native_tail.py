"""Check the temporary native workflow against command doubles; requires PyYAML."""
from pathlib import Path
import subprocess
import yaml

workflow = yaml.safe_load(Path('.github/workflows/nutrition-diagnostic.yml').read_text())
shell = workflow['jobs']['diagnose']['steps'][2]['run']
expected_test = ['XCODE', 'test', '-project', 'HealthTrackingApp.xcodeproj', '-scheme',
                 'HealthTrackingApp-Local',
                 '-only-testing:HealthTrackingAppUITests/NutritionQuickAddUITests',
                 '-destination', 'platform=iOS Simulator,id=diagnostic-simulator',
                 '-resultBundlePath', f'{Path.cwd()}/.build/HealthTrackingApp.xcresult',
                 'CODE_SIGNING_ALLOWED=NO']
expected_build = ['XCODE', 'build', '-project', 'HealthTrackingApp.xcodeproj', '-scheme',
                  'HealthTrackingApp-Local', '-configuration', 'Release', '-destination',
                  'platform=iOS Simulator,id=diagnostic-simulator', 'CODE_SIGNING_ALLOWED=NO']
for name, bootstrap, selection, test, build, expected_code, expected_calls in [
    ('success preserves native arguments', 0, 0, 0, 0, 0, [expected_test, expected_build]),
    ('bootstrap failure stops execution', 7, 0, 0, 0, 7, []),
    ('destination failure stops execution', 0, 8, 0, 0, 8, []),
    ('test failure prevents Release build', 0, 0, 65, 0, 65, [expected_test]),
    ('Release failure remains failure', 0, 0, 0, 66, 66, [expected_test, expected_build]),
]:
    setup = f'''
function scripts/bootstrap.sh {{ return {bootstrap}; }}
function scripts/select-simulator.sh {{ printf 'platform=iOS Simulator,id=diagnostic-simulator\\n'; return {selection}; }}
function mkdir {{ :; }}
function xcodebuild {{
  printf '%s\\0' XCODE "$@"
  if [[ "$1" == test ]]; then return {test}; fi
  return {build}
}}
'''
    result = subprocess.run(['bash', '-c', setup + shell], text=True, capture_output=True)
    assert result.returncode == expected_code, (name, result.returncode, result.stderr)
    actual_arguments = result.stdout.split('\0')[:-1] if result.stdout else []
    assert actual_arguments == [argument for call in expected_calls for argument in call], (name, actual_arguments)
    print('PASS', name)
