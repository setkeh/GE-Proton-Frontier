#!/usr/bin/env bash
# Check a built release with a DirectWrite probe under umu-run.
#
# Builds test/dwtest.exe and a font with an empty style name (the defect in
# EVE Frontier's web font), then runs the probe against the built tool. Pass
# a stock GE-Proton directory as well to confirm the font still breaks it.
#
# Usage:   scripts/test.sh GE-Proton11-7-Frontier-v0.1.0 [path/to/stock/GE-Proton]
# Needs:   `nix develop` (compiler, test font) and umu-run on PATH.
set -euo pipefail

TAG=${1:?usage: scripts/test.sh <tag> [stock-proton-dir]}
STOCK=${2:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=${WORK_DIR:-$ROOT/work}/test
command -v umu-run >/dev/null || { echo "error: umu-run not found" >&2; exit 1; }
: "${TEST_FONT_SRC:?run inside nix develop}"

rm -rf "$T/tool" "$T/pfx"
mkdir -p "$T/tool"
tar -xzf "$ROOT/dist/$TAG.tar.gz" -C "$T/tool"
x86_64-w64-mingw32-g++ -O1 -municode -static -o "$T/dwtest.exe" "$ROOT/test/dwtest.cpp" -ldwrite
python3 -I "$ROOT/test/make-broken-font.py" "$TEST_FONT_SRC" "$T/broken.ttf"
install -m 0644 "$TEST_FONT_SRC" "$T/intact.ttf"

# Prints the last probe step reached and the face names seen.
probe() {
    local proton=$1 font=$2
    rm -f "$T/dwtest.log"
    (
        cd "$T"
        WINEPREFIX=$T/pfx GAMEID=umu-default PROTONPATH=$proton PROTON_VERB=waitforexitandrun WINEDEBUG=-all \
            timeout 300 umu-run ./dwtest.exe "Z:${T//\//\\}\\$font" > "$T/umu.log" 2>&1 || true
    )
    # The probe writes CRLF line endings.
    tr -d '\r' < "$T/dwtest.log" > "$T/dwtest.txt" 2>/dev/null || : > "$T/dwtest.txt"
    printf '%s|%s\n' "$(tail -n1 "$T/dwtest.txt")" \
        "$(grep -o 'face\[0\] = "[^"]*"' "$T/dwtest.txt" | cut -d'"' -f2 | paste -sd, -)"
}

fail=0
check() {
    local label=$1 proton=$2 font=$3 want=$4 result
    result=$(probe "$proton" "$font")
    if [[ ${result%%|*} == "[step] done" ]]; then got=completes; else got=fails; fi
    if [[ $got == "$want" ]]; then mark=PASS; else mark=FAIL; fail=1; fi
    printf '%s  %-26s %-11s expected %-9s (last: %s; faces: %s)\n' \
        "$mark" "$label" "$font" "$want" "${result%%|*}" "${result#*|}"
}

check "$TAG" "$T/tool/$TAG" broken.ttf completes
check "$TAG" "$T/tool/$TAG" intact.ttf completes
if [[ -n $STOCK ]]; then
    check "stock ${STOCK##*/}" "$STOCK" broken.ttf fails
    check "stock ${STOCK##*/}" "$STOCK" intact.ttf completes
fi
exit $fail
