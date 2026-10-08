#!/usr/bin/env bash
# Caelestia Greeter test runner. Runs without root and never touches the
# system: every script under test is pointed at a temporary directory.
#
#   ./tests/run.sh            run everything
#   ./tests/run.sh lint       syntax checks only
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
FAILED=0
PASSED=0

pass() { PASSED=$((PASSED + 1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { FAILED=$((FAILED + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

assert_file_absent() {
    if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2 ($1 exists)"; fi
}

assert_file_present() {
    if [[ -e "$1" ]]; then pass "$2"; else fail "$2 ($1 missing)"; fi
}

export -f pass fail assert_eq assert_file_absent assert_file_present
export PASSED FAILED

run_lint() {
    section "Syntax"
    local script
    for script in "$ROOT"/install.sh "$ROOT"/scripts/* "$ROOT"/tests/*.sh; do
        [[ -f "$script" ]] || continue
        if bash -n "$script"; then pass "bash -n $(basename "$script")"; else fail "bash -n $(basename "$script")"; fi
    done

    if python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$ROOT/services/catalog.py"; then
        pass "python ast services/catalog.py"
    else
        fail "python ast services/catalog.py"
    fi

    local json
    for json in "$ROOT"/config/defaults.json "$ROOT"/i18n/*.json; do
        if python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$json"; then
            pass "json $(basename "$json")"
        else
            fail "json $(basename "$json")"
        fi
    done

    if command -v qmllint >/dev/null 2>&1; then
        local qml output
        for qml in "$ROOT"/shell.qml "$ROOT"/{components,config,design,i18n,services}/*.qml; do
            # Quickshell modules are not visible to qmllint; only hard
            # syntax errors fail the check.
            if output="$(qmllint -I /usr/lib/qt6/qml --no-unqualified-id "$qml" 2>&1)" \
                || ! grep -q 'Error' <<<"$output"; then
                pass "qmllint $(basename "$qml")"
            else
                fail "qmllint $(basename "$qml"): $output"
            fi
        done
    else
        printf '  skip qmllint (not installed)\n'
    fi
}

run_suite() {
    local suite="$1"
    section "$(basename "$suite" .sh)"
    local before_failed=$FAILED
    # Each suite runs in a subshell with its own temp dir; counters come back
    # through a result file.
    local result
    result="$(mktemp)"
    (
        PASSED=0 FAILED=0
        TMP="$(mktemp -d)"
        trap 'rm -rf -- "$TMP"' EXIT
        export TMP
        # shellcheck disable=SC1090
        source "$suite"
        printf '%s %s\n' "$PASSED" "$FAILED" >"$result"
    ) || true
    local suite_passed suite_failed
    read -r suite_passed suite_failed <"$result" || { suite_passed=0; suite_failed=1; fail "suite crashed"; }
    rm -f -- "$result"
    PASSED=$((PASSED + suite_passed))
    FAILED=$((FAILED + suite_failed))
    (( FAILED == before_failed )) || true
}

mode="${1:-all}"
run_lint
if [[ "$mode" == "all" ]]; then
    for suite in "$ROOT"/tests/test_*.sh; do
        run_suite "$suite"
    done
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
(( FAILED == 0 ))
