#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
generator=$repo_dir/bin/generate-copilot-status-font
committed_font=$repo_dir/kitty/fonts/CopilotStatus.ttf
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

generated_font=$temp_dir/CopilotStatus.ttf
"$generator" --output "$generated_font" >/dev/null
cmp -s "$generated_font" "$committed_font" ||
  fail "committed font differs from deterministic output"

node - "$generated_font" <<'NODE'
const fs = require('fs');
const vscodeApp =
  process.env.VSCODE_APP || '/Applications/Visual Studio Code.app';
const opentype = require(
  process.env.OPENTYPE_JS_PATH ||
    `${vscodeApp}/Contents/Resources/app/node_modules/opentype.js/dist/opentype.js`
);
const contents = fs.readFileSync(process.argv[2]);
const font = opentype.parse(
  contents.buffer.slice(
    contents.byteOffset,
    contents.byteOffset + contents.byteLength
  )
);
const glyph = font.charToGlyph(String.fromCodePoint(0xec3a));
const bounds = glyph.getBoundingBox();
if (font.names.unicode.fontFamily.en !== 'Copilot Status') {
  throw new Error('unexpected font family');
}
if (font.glyphs.length !== 3) {
  throw new Error('unexpected glyph count');
}
if (
  font.tables.post.isFixedPitch !== 1 ||
  font.tables.cff.topDict.isFixedPitch !== 1
) {
  throw new Error('font is not fixed-pitch');
}
if (
  [bounds.x1, bounds.y1, bounds.x2, bounds.y2].join(',') !==
  '6,-52,994,772'
) {
  throw new Error('unexpected glyph bounds');
}
if (font.tables.head.created !== 0 || font.tables.head.modified !== 0) {
  throw new Error('timestamps are not normalized');
}
NODE

printf 'ok - Copilot Status font fixtures\n'
