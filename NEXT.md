# NEXT — ox-epub (junghan0611 fork)

휘발성 후속 메모. 영속 사실은 README.org / commit 으로 옮긴다.

## 배경

upstream `ofosos/ox-epub` 는 4년간 미업데이트(v0.1.0). memex-kb 가
org→EPUB 파이프라인에서 쓰는데, 원형은 **EPUB 2.0.1** 만 뱉어
`epub_upgrade.py` 후처리로 EPUB3 로 끌어올려야 했다. 이 포크는 그
후처리를 **exporter 본체로 흡수**해서 ox-epub 단독으로 clean EPUB 3.0 을
내도록 개선한다.

## 완료 (2026-06-01) — EPUB 3.0 네이티브화

memex-kb `org2epub/samples/sample-fullset.org` 픽스처 기준,
`nix run nixpkgs#epubcheck` (EPUB 3.3 규칙) **0 errors / 0 warnings**.
후처리(`epub_upgrade.py`)·headless 우회(`org2epub.el`) **둘 다 없이** 통과.

흡수한 항목:

- OPF `version="3.0"` + `dcterms:modified` + 유효 UUID 정규화
  (`org-epub--normalize-uid`, OPF-085 해소)
- `image/svg`→`image/svg+xml` (`org-epub--mime-type`, RSC-032 해소)
- `<!DOCTYPE html>` + `xmlns:epub` (RSC-005 role 허용)
- named entity(`&ndash; &mdash; &hellip;` …) → 유니코드 (`org-epub--xmlify`)
- `nav.xhtml` (toc + landmarks) 생성 — `org-epub-generate-nav-single` /
  `org-epub-template-nav`, ncx navMap 과 동일 중첩
- cover: `properties="svg"/"cover-image"`, 비어있지 않은 `<title>`,
  실제 종횡비 viewBox
- 빈 `dc:*` 생략, obsolete 표 속성 제거(`org-html-table-default-attributes` nil)
- mimetype trailing newline 제거 (PKG-007)
- **headless 표지**: `image-size`(graphic frame 요구) → PNG/JPEG 헤더 직접
  읽기(`org-epub--image-pixel-size`). 데몬/`--batch` 에서 동작 →
  memex-kb `org2epub.el` cl-letf 우회 불필요.

## GPT-5.5 리뷰 반영 (2026-06-01) — blocker 5건 수정·검증

엣지 케이스 6종(full sample + JPEG표지 / 표지없음 / 헤딩없음 / `\alpha`엔티티 /
`&` 포함 URI uid) 모두 epubcheck 0/0. 검증은 `emacs --batch`(진짜 무프레임).

- **JPEG 표지 headless**: `org-epub--jpeg-size` SOF 스캔이 `0xFF` 접두를
  안 건너뛰어 항상 nil→image-size 폴백→무프레임 실패였음. FF 접두 + standalone
  마커 처리로 수정.
- **빈 `<guide>`**: cover 없을 때만 guide 출력(RSC-005).
- **빈 `<navMap>`**: 헤딩 없을 때 `org-epub-generate-toc-single`가 fallback
  navPoint(Start→body.html) 출력.
- **entity 누락**: 하드코딩 alist → `org-entities` 동적 테이블(`\alpha` 등 전부)
  + 타이포그래픽 extras. `org-epub--entity-table` 캐시.
- **uid XML escape**: URI uid의 `&`가 OPF `dc:identifier` + ncx `dtb:uid`
  양쪽에서 fatal이었음. `org-epub--xml-escape`(element+attribute) 적용.
- nit: 중복 `times` 제거, 단일 lookup, `eport`→`export` 오타, 에러 재시그널.

## 패키지 정리 (2026-06-01)

- **README.org** 포크 기준으로 새로 씀 (EPUB3 네이티브 / headless / 기능 /
  설치(doom local-repo, straight) / 사용 / 샘플 검증 / upstream 대비 변경).
- **샘플을 리포에 포함** — `sample/sample.org`(풀세트, 자체 UUID),
  `sample/images/{cover,figure-flow}.png`, `sample/gen-images.py`,
  `sample/sample.epub`(빌드 산출, epubcheck 0/0). 더는 memex-kb 의존 안 함.
- stale `.travis.yml` 제거.

## 다음 한 걸음

1. **memex-kb 파이프라인 단순화** — `org2epub/build.sh` 에서
   `epub_upgrade.py` 단계와 `org2epub.el` 로드 제거 가능. memex-kb 담당
   세션과 조율(역할 분담상 memex-kb 는 scanpdf→org 집중 중이므로 타이밍은 힣 결정).
2. **doom 반영** — `packages.el` 은 이미 `:local-repo "~/repos/gh/ox-epub"`.
   GUI/agent 데몬은 재시작 또는 `M-x doom/reload` 해야 새 코드 로드.
3. **upstream PR 기여 검토** — headless 버그 / mimetype / EPUB3 lift 는
   upstream(`ofosos/ox-epub`)에도 유효. 단 upstream 활동 정지 상태.
4. **남은 should-fix (GPT-5.5 리뷰)** — 둘 다 blocker는 아님:
   - (#6) `org-epub-generate-nav-single` 은 `1→3` 레벨 점프를 한 단계로
     압축(ncx `org-epub-generate-toc-single` 과 동일 동작이라 구조는 일치,
     XHTML invalid 아님). 엄밀한 TOC 깊이 보존 원하면 중간 레벨 정책 명시 필요.
   - (#7) 표지 비표준 포맷(GIF/WebP/SVG)은 여전히 `image-size` 폴백 →
     무프레임에서 실패 가능. 필요 시 SVG `viewBox`/GIF/WebP 헤더 직접 파싱 추가.
   - entity: `org-entities` 미등록 named entity는 그대로 통과(잠재 RSC-016).
     org 생성 콘텐츠는 사실상 전부 커버되나, 발견 시 `org-epub--html-entity-extra`
     보강.

## 검증 재현

```sh
WORK=/tmp/ox-epub-test; mkdir -p $WORK
cp ~/repos/gh/memex-kb/org2epub/samples/sample-fullset.org $WORK/sample.org
cp -r ~/repos/gh/memex-kb/org2epub/samples/images $WORK/images
emacsclient -s pi --eval "(progn (load \"~/repos/gh/ox-epub/ox-epub.el\")
  (with-current-buffer (find-file-noselect \"$WORK/sample.org\")
    (let ((default-directory \"$WORK/\")) (org-epub-export-to-epub))))"
cd $WORK && nix run nixpkgs#epubcheck -- sample.epub
```
