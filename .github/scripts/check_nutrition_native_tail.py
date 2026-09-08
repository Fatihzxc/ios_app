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

# The full-context experiment retains the native test -> Release failure contract.
# Execute only its native tail with command doubles; metadata redirections above
# that tail are intentionally excluded so this check does not write artifacts.
full_step = next(step for step in workflow['jobs']['diagnose']['steps']
                 if step.get('name') == 'Run one instrumented complete functional suite')
full_shell = 'set -euo pipefail\n' + full_step['run'][full_step['run'].index('xcodebuild test'):]
expected_full_test = ['XCODE', 'test', '-project', 'HealthTrackingApp.xcodeproj',
                      '-scheme', 'HealthTrackingApp-Local', '-destination',
                      'platform=iOS Simulator,id=diagnostic-simulator',
                      '-resultBundlePath', '.build/NutritionWarm.xcresult',
                      '-skip-testing:HealthTrackingAppUITests/TodayGuidanceUITests/testColdLaunchPublishesFirstMeaningfulDirectiveWithinOneSecondMedian',
                      'CODE_SIGNING_ALLOWED=NO']
for name, test, build, expected_code, expected_calls in [
    ('full native arguments', 0, 0, 0, [expected_full_test, expected_build]),
    ('full test failure prevents Release', 65, 0, 65, [expected_full_test]),
    ('full Release failure propagates', 0, 66, 66, [expected_full_test, expected_build]),
]:
    setup = f'''
destination='platform=iOS Simulator,id=diagnostic-simulator'
function tee {{ command cat; }}
function xcodebuild {{
  printf '%s\\0' XCODE "$@"
  if [[ "$1" == test ]]; then return {test}; fi
  return {build}
}}
'''
    result = subprocess.run(['bash', '-c', setup + full_shell], text=True, capture_output=True)
    assert result.returncode == expected_code, (name, result.returncode, result.stderr)
    actual_arguments = result.stdout.split('\0')[:-1] if result.stdout else []
    assert actual_arguments == [argument for call in expected_calls for argument in call], (name, actual_arguments)
    print('PASS', name)
