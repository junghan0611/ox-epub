# Changelog

All notable changes to this fork are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The fork uses CalVer
(`vYYYY.M.D`). Upstream history before the fork is in `git log` up to `0d341b8`.

## Unreleased

## v2026.9.27 — First fork release: native EPUB 3.0, book figures, popup footnotes

### Added

- **Native EPUB 3.0 output with no post-processing step** (`1f81653`). OPF `version="3.0"` with `dcterms:modified`, a generated `nav.xhtml` (toc + landmarks) beside `toc.ncx`, `image/svg+xml`, `<!DOCTYPE html>` + `xmlns:epub`, named entities converted to characters, a valid and escaped `dc:identifier` (UUID normalised), and a mimetype stored first without a trailing newline.
- **Headless export** from `emacs --daemon` / `--batch`: cover dimensions are read from the PNG/JPEG header instead of `image-size`, which needs a graphic frame.
- **Book figures.** Captioned images become `<figure>`/`<figcaption>`; a `#+begin_figure` block groups images into one figure and keeps its own caption (ox-html drops it); sub-figures sit two per row.
- **Captions that keep the book's numbering.** A caption starting with its own label (`그림 1-1:`, `Table 2.3`) gets no second Org number, so book captions can be pasted as they are.
- **`:align left|right|center`** on images maps to `org-align-*` classes; HTML5 has no img `align`.
- **Popup footnotes**: references carry `epub:type="noteref"` and `role="doc-noteref"`, notes are `<aside epub:type="footnote">`.
- **Listenable math**: each formula image carries its LaTeX source as `alt`, so screen readers and text-to-speech read the formula rather than a file name.
- **Korean export labels** (그림 / 표 / 각주 / 차례), which Org's own export dictionary lacks.
- **org-glossary support**: detached term paragraphs are unwrapped, so a term no longer puts a `<p>` inside an `<a>`.
- **Reference sample** `sample/sample.org` (Korean) exercising every construct above, and `run.sh` (`sample`, `check`, `verify`, `images`). `./run.sh verify` gives EPUBCheck 5.3.0 0 fatals / 0 errors / 0 warnings.
- **Repository layout**: `AGENTS.md`, `CLAUDE.md`, `NEXT.md`, this changelog.

### Changed

- **XHTML5 with `html5-fancy`** instead of XHTML 1.1 content documents.
- **Math SVGs size naturally** (`max-width: 90%; height: auto`) instead of being forced to 90% width, so inline formulas stay text-sized (`75e65d3`).
- **README rewritten for the fork**; stale Travis config removed.

### Fixed

- JPEG cover size detection skips `0xFF` fill bytes and standalone markers.
- No empty `<guide>` without a cover and no empty `<navMap>` without headings.
- `data-class=` attributes no longer receive the align class (`83b6c14`).
- The `figure-flow.png` sample asset is no longer clipped.
