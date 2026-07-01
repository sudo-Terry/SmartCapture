# SmartCapture

![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue)

Languages: 한국어 · [English](README.en.md)

macOS 메뉴 막대에서 동작하는 스크린샷 유틸리티입니다. 단축키로 화면을 캡처하고, 캡처한
이미지를 기기 내 문자 인식(OCR)으로 색인하여 나중에 내용으로 다시 찾을 수 있습니다.

기본 스크린샷 도구를 대체하면서, 캡처가 쌓일수록 원하는 화면을 찾기 어려워지는 문제를
검색으로 해결하는 것을 목표로 합니다. 캡처, 문자 인식, 검색은 모두 기기에서 처리되며 외부로
전송되지 않습니다.

## 주요 기능

- 메뉴 막대에 상주하며 Dock 아이콘이 없음
- 전역 단축키로 전체 화면, 영역, 창 캡처
- 캡처 즉시 클립보드 복사 및 우측 하단 썸네일 미리보기
- 이미지 속 문자(OCR)와 분류 태그 기반 검색
- 보관 기간이 지난 캡처를 휴지통으로 자동 정리
- 로컬 LLM을 이용한 이미지 맥락 캡션 (선택)

## 요구 사항

- macOS 12 이상 (Apple Silicon 권장)
- 화면 기록 권한

## 설치

소스에서 빌드합니다.

```bash
git clone https://github.com/sudo-Terry/SmartCapture.git
cd SmartCapture
./build_app.sh
open SmartCapture.app
```

처음 캡처를 시도하면 화면 기록 권한을 요청합니다.
`시스템 설정 > 개인정보 보호 및 보안 > 화면 기록`에서 SmartCapture를 허용한 뒤 앱을 다시
실행하세요.

> 반드시 빌드된 `.app`으로 실행해야 합니다. `swift run`으로 띄운 바이너리는 권한이 올바르게
> 연결되지 않습니다.

## 사용법

| 단축키 | 동작 |
| --- | --- |
| `⌃⌥⌘3` | 전체 화면 캡처 |
| `⌃⌥⌘4` | 영역 선택 캡처 |
| `⌃⌥⌘5` | 창 캡처 |
| `⌃⌥⌘F` | 검색 창 열기 |

캡처는 기본적으로 `~/Pictures/ScreenShots`에 저장되고 클립보드에도 복사됩니다.

### 검색

`⌃⌥⌘F`로 검색 창을 열어 이미지 속 문자나 태그로 캡처를 찾습니다. 결과 항목은 더블 클릭하면
Quick Look으로 미리 보고, 우클릭하면 Finder에서 위치를 열거나 경로를 복사할 수 있습니다.
색인은 캡처 직후 백그라운드에서 생성되므로 캡처 동작을 막지 않습니다.

## 이미지 맥락 해석 (선택)

OCR은 화면의 문자만 인식합니다. 문자가 적은 화면까지 의미로 검색하려면 로컬 비전 언어
모델(VLM)을 사용할 수 있습니다. [Ollama](https://ollama.com)와 비전 모델이 필요합니다.

```bash
./setup_vlm.sh            # 모델 내려받기 및 활성화 (기본: llava:7b)
./setup_vlm.sh moondream  # 더 가벼운 모델
```

메뉴 막대의 **이미지 맥락 해석** 항목에서 켜고 끌 수 있습니다. 비활성화 상태(기본값)에서는
OCR만으로 검색합니다. 생성된 캡션은 검색 용도로만 사용하며 캡처 파일을 옮기거나 삭제하지
않습니다.

## 설정

설정 파일은 `~/Library/Application Support/SmartCapture/config.json`에 있으며, 메뉴 막대의
**설정 파일 열기**로 접근할 수 있습니다. 저장 폴더, 보관 기간, VLM 모델 등을 조정할 수 있습니다.

## 동작 방식

- 캡처는 macOS의 `screencapture`를 사용합니다.
- 문자 인식, 분류, 이미지 특징 추출은 Apple Vision 프레임워크로 처리합니다.
- 색인은 SQLite에 저장합니다.
- 추출한 정보는 파일의 확장 속성(xattr)에도 함께 기록되어 파일을 따라갑니다.

## 문제 해결

<details>
<summary>단축키를 눌러도 캡처가 저장되지 않습니다</summary>

화면 기록 권한 문제입니다. 단축키 충돌은 아닙니다(이 앱은 `⌃⌥⌘`, 기본 스크린샷은 `⌘⇧`).
권한을 허용한 뒤 앱을 다시 실행하세요. ad-hoc 서명 특성상 앱을 다시 빌드하면 권한이 초기화될
수 있으며, 자체 서명 인증서로 서명하면 유지됩니다(`SIGN_IDENTITY="이름" ./build_app.sh`).
</details>

<details>
<summary>권한 요청 경고가 과도해 보입니다</summary>

화면을 캡처하는 모든 앱이 받는 macOS 표준 경고입니다. SmartCapture는 정지 이미지만 캡처하며
오디오나 연속 녹화는 하지 않습니다.
</details>

<details>
<summary>검색 결과가 없습니다</summary>

색인이 비어 있을 수 있습니다. 권한을 허용하고 캡처를 한 번 만든 뒤 다시 검색하세요.
</details>

## 라이선스

MIT License. [LICENSE](LICENSE)를 참고하세요.
