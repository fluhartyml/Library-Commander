#!/bin/sh
# Refuses any Swift text smaller than 18 pt — Michael's rule for every app:
#   "text is supposed to be NO SMALLER THAN 18 POINTS in any app of mine"
#   "unless explicitly given permmission to deviate"
# On macOS the SwiftUI text styles are all under 18 (body 13, title3 15, title2 17), so a
# style name counts as a violation. The ONLY way past is a comment on the same line:
#   // font-ok: <his words granting it>
# Claude never adds one on its own judgement.
# Sizes are written .lc(<points at the 18 pt default>) and scale with Accessibility › Text size
# (12–32, default 18 — the one exception he granted, because the USER sets it).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PAT='\.font\(\.(caption2?|footnote|subheadline|callout|body|headline|title3|title2)\b|\.system\(\.(caption2?|footnote|subheadline|callout|body|headline|title3|title2)\b|\.system\(size: *([0-9]|1[0-7])(\.[0-9]+)?[,)]|ofSize: *([0-9]|1[0-7])(\.[0-9]+)?[,)]|controlSize\(\.(small|mini)\)|\.lc\(([0-9]|1[0-7])(\.[0-9]+)?[,)]|[?:] *\.(caption2?|footnote|subheadline|callout|body|headline|title3|title2)\b'
HITS=$(grep -rnE "$PAT" --include='*.swift' "$ROOT" | grep -v 'font-ok:' | grep -vE '^[^:]+:[0-9]+:\s*//')
if [ -n "$HITS" ]; then
    echo "⛔ TEXT UNDER 18 PT — commit refused (his rule; exceptions only with // font-ok: <his words>)" >&2
    echo "$HITS" | sed "s|$ROOT/||" >&2
    exit 1
fi
echo "font floor: nothing under 18 pt"
