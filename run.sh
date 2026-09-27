#!/usr/bin/env bash
# run.sh — ox-epub fork: build the sample EPUB and validate it.
#
#   ./run.sh sample   export sample/sample.org -> sample/sample.epub (headless)
#   ./run.sh check    epubcheck sample/sample.epub (EPUB 3.3 rules)
#   ./run.sh verify   sample + check  (the release gate: 0 fatals / 0 errors / 0 warnings)
#   ./run.sh images   regenerate sample/images/*.png (python + Pillow via nix)
#
# Org comes from Doom's straight build when present, so the sample is exported
# with the same Org the author runs; set ORG_LISP_DIR to override.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_DIR="$ROOT/sample"

find_org_dir() {
	if [[ -n "${ORG_LISP_DIR:-}" ]]; then
		echo "$ORG_LISP_DIR"
		return
	fi
	local d
	for d in "$HOME"/doomemacs/.local/straight/build-*/org "$HOME"/.emacs.d/.local/straight/build-*/org; do
		[[ -f "$d/org.el" ]] && { echo "$d"; return; }
	done
	echo "" # fall back to the Org bundled with Emacs
}

cmd_sample() {
	local org_dir load_args=()
	org_dir="$(find_org_dir)"
	if [[ -n "$org_dir" ]]; then
		load_args+=(-L "$org_dir")
		# org-glossary is optional; the sample's glossary section needs it.
		[[ -d "$org_dir/../org-glossary" ]] && load_args+=(-L "$org_dir/../org-glossary")
	fi
	rm -f "$SAMPLE_DIR/sample.epub"
	(cd "$SAMPLE_DIR" && emacs --batch "${load_args[@]}" -L "$ROOT" \
		--eval "(progn (require 'org) (require 'org-glossary nil t) (require 'ox-epub)
		  (with-current-buffer (find-file-noselect \"$SAMPLE_DIR/sample.org\")
		    (org-epub-export-to-epub)))" 2>&1 | grep -E "Generated|error" || true)
	rm -rf "$SAMPLE_DIR/ltximg"
	[[ -s "$SAMPLE_DIR/sample.epub" ]] || { echo "export failed: no sample.epub" >&2; exit 1; }
	echo "built: sample/sample.epub"
}

cmd_check() {
	nix run nixpkgs#epubcheck -- "$SAMPLE_DIR/sample.epub" 2>&1 | grep -E "^(ERROR|FATAL|WARNING)|Messages:"
}

cmd_images() {
	(cd "$SAMPLE_DIR" && nix shell --impure \
		--expr 'with import <nixpkgs> {}; python3.withPackages (p: [p.pillow])' \
		-c python gen-images.py)
}

case "${1:-verify}" in
	sample) cmd_sample ;;
	check) cmd_check ;;
	verify) cmd_sample && cmd_check ;;
	images) cmd_images ;;
	*) sed -n '2,9p' "$0"; exit 2 ;;
esac
