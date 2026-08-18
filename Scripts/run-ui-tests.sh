#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT="$PROJECT_DIR/PersonalStrengthCoach.xcodeproj"
SCHEME="${SCHEME:-PersonalStrengthCoach}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
RESULT_BUNDLE="${RESULT_BUNDLE:-$PROJECT_DIR/.build/ui-tests.xcresult}"

mkdir -p "$(dirname "$RESULT_BUNDLE")"
rm -rf "$RESULT_BUNDLE"

extra_args=()
if [[ "$#" -gt 0 ]]; then
    extra_args+=("$@")
fi

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -testPlan PersonalStrengthCoach \
    -destination "$DESTINATION" \
    -resultBundlePath "$RESULT_BUNDLE" \
    CODE_SIGNING_ALLOWED=NO \
    test "${extra_args[@]}"
