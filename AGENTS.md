# AGENTS.md — ox-epub (junghan0611 fork)

> **What belongs here**: things that do not change often — what the repo is, its
> contract, its neighbours, and traps that keep recurring. Operational notes and the
> next move go to `NEXT.md`; what closed goes to `CHANGELOG.md`.
>
> If this file contradicts the code, the code is right and this file is a bug.

## What this repo is

An Org-mode → **clean EPUB 3.0** exporter, one file: `ox-epub.el`, derived from
`ox-html`. A maintained fork of [ofosos/ox-epub](https://github.com/ofosos/ox-epub)
(v0.1.0, unmaintained since 2018, EPUB 2.0.1 only). The fork emits valid EPUB 3.0
natively and exports headless (daemon / `--batch`).

It is the Emacs half of a book pipeline: memex-kb turns scanned books into Org
(OCR → `mineru2org.py`), and this exporter turns that Org into an EPUB GLG reads and
listens to. The book logic is Emacs logic, so it lives here, not in memex-kb.

## Neighbours

| Where | Relation |
|---|---|
| `~/repos/gh/memex-kb` (`AGENTS.md` § EPUB, `./run.sh org2epub-build`) | Main consumer. Loads this file directly. Steward note `denote:20260223T040400`. |
| `~/repos/gh/doomemacs-config` (`packages.el`, `:local-repo "~/repos/gh/ox-epub"`) | GLG's Emacs loads this checkout live. Daemons need a restart or `doom/reload` to pick up edits. |
| `sample/sample.org` | The reference document: every construct the exporter must carry. |

## The contract

**`sample/sample.org` exports to an EPUB that passes EPUBCheck with 0 fatals / 0
errors / 0 warnings.** That is the release gate:

```sh
./run.sh verify    # export the sample headless, then epubcheck (EPUB 3.3 rules)
```

When the exporter learns a new construct, add it to `sample/sample.org` first, then
make the gate pass. The sample is Korean on purpose (GLG's daily use); other languages
get their own verified samples later.

What the sample carries today: images, figure groups (`#+begin_figure`), book-numbered
captions, `:align`, SVG math with LaTeX alt text, tables, footnotes (named, inline,
multi-paragraph), an org-glossary glossary, TOC, emphasis, dashes, entities.

## Structure of ox-epub.el

- Backend `epub` derives from `html` with `xhtml5` + `html5-fancy`.
- Transcoders override only what EPUB needs: `template`, `inner-template` (EPUB3
  `aside` footnotes), `footnote-reference` (`noteref`), `special-block` (figure group
  caption), `paragraph` (detached paragraphs), `link` / latex (manifest entries).
- String post-processing on the finished body: drop duplicate caption numbers, map
  img `align` to `org-align-*` classes, convert named entities to characters.
- Packaging (`org-epub--export-wrapper`): OPF, `nav.xhtml`, `toc.ncx`, cover, zip.

## Traps

- **String post-processing matches more than you meant.** `\bclass="` matched inside
  `data-class=` (fixed in 83b6c14). Anchor attribute regexps on a leading space and
  test them against real ox-html output, not a hand-written tag.
- **A lambda passed to `replace-regexp-in-string` must not leave match data changed.**
  The caller uses the match data after the lambda returns; wrap `string-match` inside
  it in `save-match-data`.
- **ox-html wraps detached paragraphs in `<p>`.** org-glossary exports each term as a
  parentless paragraph, which put a `<p>` inside an `<a>` (RSC-005).
  `org-epub-paragraph` unwraps them; plain ox-html still has the bug.
- **Org has no Korean export labels** (Org 9.8.9). `org-epub--dictionary-extra`
  supplies 그림 / 표 / 각주 / 차례 for the length of an export only.
- **EPUBCheck passing is not the whole contract.** A reversed ARIA role on footnote
  references passed EPUBCheck; read the generated `body.html` as well.

## Working rules

- Public repo: `README.org`, `AGENTS.md` and `CHANGELOG.md` are in English. `NEXT.md` is
  the internal handoff and may stay Korean.
- Use the `commit` skill; no AI attribution in commit messages. Releases use CalVer
  tags via the `tag-release` skill, with `CHANGELOG.md` as the release notes.
- Upstream is inactive. Adapt here; do not open upstream PRs unless GLG asks.
