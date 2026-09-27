# NEXT — ox-epub (junghan0611 fork)

휘발성 후속 메모. 영속 사실은 README.org / AGENTS.md / CHANGELOG.md 로 옮긴다.
최근 컷: [CHANGELOG.md](CHANGELOG.md) `v2026.9.27` (첫 포크 릴리즈). 검증은 `./run.sh verify`.

## 배경

upstream `ofosos/ox-epub` 는 4년간 미업데이트(v0.1.0). memex-kb 가
org→EPUB 파이프라인에서 쓰는데, 원형은 **EPUB 2.0.1** 만 뱉어
`epub_upgrade.py` 후처리로 EPUB3 로 끌어올려야 했다. 이 포크는 그
후처리를 **exporter 본체로 흡수**해서 ox-epub 단독으로 clean EPUB 3.0 을
내도록 개선한다.

## 다음 한 걸음

0. **다른 언어 샘플** — 지금 샘플은 한국어만 검증했다(GLG 2026-09-27: 우선 한글로
   밀고, 외국 사용자용은 언어별 샘플을 검증해서 올린다). 영어 샘플 + 라벨 사전
   (`org-epub--dictionary-extra`) 확장 후 `./run.sh verify` 를 언어별로.

1. **memex-kb 파이프라인 단순화** — `org2epub/build.sh` 에서
   `epub_upgrade.py` 단계와 `org2epub.el` 로드 제거 가능. memex-kb 담당
   세션과 조율(역할 분담상 memex-kb 는 scanpdf→org 집중 중이므로 타이밍은 힣 결정).
2. **upstream PR 기여 검토** — headless 버그 / mimetype / EPUB3 lift 는
   upstream(`ofosos/ox-epub`)에도 유효. 단 upstream 활동 정지 상태.
3. **남은 should-fix (GPT-5.5 리뷰)** — 둘 다 blocker는 아님:
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
./run.sh verify   # sample/sample.org → sample/sample.epub → epubcheck (0/0/0 이 게이트)
```

## 알려진 한계 (고치지 않음)

- org-glossary 는 조사가 붙은 한국어 용어(`조판은`)를 잡지 못한다. 원본에서 용어와
  조사 사이에 NBSP 를 넣어 쓰고, 가든 export 는 그 NBSP 를 지운다
  (doomemacs-config `my/org-export-normalize-source-nbsp`).
- 문자열 후처리(캡션 번호 제거, align→class)는 정규식 기반이라 새 ox-html 출력 모양에서
  오탐할 수 있다 — AGENTS.md § Traps.
