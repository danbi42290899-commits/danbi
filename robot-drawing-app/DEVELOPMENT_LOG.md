# Robot Drawing App — 개발 로그

> 이 문서는 지금까지의 대화에서 논의·결정된 내용을 정리한 것입니다. 다음 세션에서 이어서
> 작업할 때 이 파일을 먼저 읽고 시작하세요.

## 1. 프로젝트 목적

태블릿을 고정해두고 **로봇팔이 S펜(또는 손가락)으로 조작해 그림을 그리는 전용 그림판 앱**.
기존 노트 앱은 버튼 위치/크기가 로봇팔 조작에 맞지 않아서, 처음부터 로봇팔이 누르기 쉬운
고정 레이아웃의 안드로이드 네이티브 앱으로 새로 제작했다. 태블릿 가로 모드 고정, 목표 기기는
Galaxy Tab S 시리즈(S6~S9).

## 2. 기술 스택 / 프로젝트 위치

- **Kotlin + Android Custom View** (Jetpack Compose 아님), Gradle(Groovy DSL, `.kts` 아님)
- 패키지명 `com.example.robotdrawing`, minSdk 26 / targetSdk 34 / compileSdk 34
- AGP 8.13.0, Gradle 8.14.3 — **AGP 8.13은 JDK 17 필요**. 이 서버(Tia) 기본 `java`는 JDK 11이라
  `/home/dbkim/jdk-17.0.13+11`을 `gradle.properties`의 `org.gradle.java.home`으로 지정해서 사용.
- Android SDK: `/home/dbkim/android-sdk` (platforms 34/36, build-tools 34.0.0/35.0.0)
- 저장소: 기존 `hearing-loss-app`(Capacitor 프로젝트)과 **같은 GitHub 저장소**
  (`danbi42290899-commits/danbi`) 안에 `robot-drawing-app/` 폴더로 추가 (Capacitor용 `android/`
  폴더와는 별개의, 완전히 독립된 Gradle 프로젝트). 로컬 클론 경로:
  `/home/dbkim/hearing-loss-app/robot-drawing-app/`
- 빌드: `./gradlew assembleDebug` → `app/build/outputs/apk/debug/app-debug.apk`
- 배포: 이 서버는 사용자의 실제 기기와 별개의 원격 서버라 로컬 파일 전달이 불가능함.
  APK를 빌드해서 **GitHub Release 자산**으로 올리고 다운로드 링크를 전달하는 방식 사용
  (저장소는 이미 public). debug 서명 APK라 설치 시 Play Protect가 막을 수 있음 — 설치 화면에서
  "무시하고 설치" 또는 Play Protect 설정에서 보안 검사 토글을 잠시 끄면 됨.

## 3. 화면 구성 (최종, v1.1.0 이후 기준)

`ConstraintLayout` + 퍼센트 가이드라인 2개로 3분할:

- **왼쪽 패널 (13%)**: Pen / Eraser / Clear All / Undo / Record — 세로로 5개, 흰 배경 카드
- **중앙 캔버스 (74%)**: `DrawingView` — 흰 배경, 얇은 테두리, 화면 전체 높이를 채움
  (별도의 "아래쪽 펜 크기 행"은 없음 — 캔버스를 최대한 넓히기 위해 제거)
- **오른쪽 패널 (13%)**: 이미지 저장 / 비디오 저장 아이콘 버튼 2개(상단 고정, 나란히 절반씩)
  + 색상 원형 버튼 5개(빨/파/초/노/검, 세로)
- **캔버스 좌측 하단에 떠 있는 pill**: 펜 크기 선택 원형 버튼 5개, 안의 점(dot) 크기로
  굵기를 표현 (숫자 없음). 1→4px, 2→8px, 3→12px, 4→20px, 5→32px

버튼/컬럼 비율은 로봇팔이 "누르기 쉽게 크고 간격 넉넉하게"를 요청받아 여러 차례 조정했지만,
**컬럼 경계(13/74/13%) 자체는 한번 확정된 뒤로는 바꾸지 않기로 함** — 사용자가 "지금의 라인은
벗어나지 않은 상태로" 크기만 키워달라고 명시했기 때문. 패널 내부 padding을 줄여서 확보한
여유로 버튼을 키움.

## 4. 기능

- **펜 / 지우개**: Path 기반, 각 스트로크는 하나의 Path로 누적 후 `canvas.drawPath()` 1회 호출
  (스트로크 내부에서 겹쳐도 알파가 이중으로 blend되지 않도록).
- **펜 타입 3종** (Pen 버튼을 이미 Pen 모드에서 다시 누르면 다이얼로그로 선택):
  - 연필(Pencil): 얇고 불투명, 굵기 × 0.7
  - 형광펜(Highlighter): 두껍고 반투명(alpha 140/255), 굵기 × 2.2, 하나의 Path를 한 번에
    그려서 겹침 부분이 끊기거나 이중으로 어두워지지 않음
  - 만년필(Fountain pen): 그리는 속도 기반으로 굵기가 부드럽게 변함(지수 스무딩, 좁은 범위
    0.82~1.25배) — 시작/끝에 뾰족한 꼭짓점이 생기지 않도록 조정됨
- **펜 크기 5단계**: 4 / 8 / 12 / 20 / 32px, 점 크기로 표시
- **색상 5개**: 빨강 `#F44336`, 파랑 `#2196F3`, 초록 `#4CAF50`, 노랑 `#FFEB3B`, 검정 `#000000`
  — 유리구슬 느낌의 방사형 그라디언트 원형 버튼, 선택 시 링 오버레이
- **Undo**: 마지막 스트로크 하나만 제거 (`strokes.removeAt(last)`)
- **Clear All**: 전체 삭제, Eraser 바로 아래 배치, 빨간 톤으로 구분
- **화면 녹화**: `DrawingVideoRecorder` — `MediaRecorder`(VideoSource.SURFACE) +
  `Surface.lockCanvas()/unlockCanvasAndPost()`로 `DrawingView`의 매 프레임을 밀어넣는 방식.
  카메라/마이크 사용 안 함, 추가 권한 불필요. 10fps, 4Mbps.
- **저장**: 오른쪽 패널 상단의 이미지/비디오 저장 버튼을 각각 누르면 팝업 없이 바로 저장됨
  (로봇팔이 반복해서 누르기 쉽도록 v1.4.0에서 다이얼로그 선택 방식을 없애고 버튼을 분리).
  텍스트 없이 아이콘(사진 모양 / 비디오카메라 모양)만 표시.
  - 이미지 저장 버튼 → 바로 PNG로 저장 (`Pictures/RobotDrawing`). PDF 저장 기능은 제거됨.
  - 비디오 저장 버튼 → 방금 녹화한 mp4를 `Movies/RobotDrawing`에 저장
  - 파일명: `robot_drawing_yyyyMMdd_HHmmss.{png|mp4}`
  - API 29+는 MediaStore, API 28 이하는 legacy File + `WRITE_EXTERNAL_STORAGE`(maxSdk 28)

## 5. 디자인 방향 변화

1. **MVP (v1.0.0)**: 회색 툴바 블록, 중첩 LinearLayout, amber 강조색
2. **화이트 리디자인 (v1.1.0)**: 전체 흰 배경, 카드형 패널(얇은 테두리+옅은 그림자),
   캔버스 확장(하단 행 제거), 펜 크기를 숫자 버튼 → 점 크기 pill로 변경, 인디고
   액센트(`#3D5AFE`) 링+틴트로 선택 상태 통일
3. **금속/유리 + 펜 타입 (v1.2.0)**: 버튼에 그라디언트 "메탈" 배경, 색상 버튼은 완전한
   원형(글래스 오브 느낌), 펜 타입 3종, Clear All 추가. **배경 자체는 계속 흰색 유지**
   (미리보기에서 어두운 "콕핏" 배경도 제안했었지만 사용자가 화이트 유지를 선택함)
4. **녹화 기능 (v1.3.0)**: Record 토글 버튼 + Save 메뉴를 Video/Image 2단계로 개편
5. **저장 버튼 분리 (v1.4.0)**: 로봇팔이 다이얼로그 팝업을 반복 조작하기 어려워해서, 단일
   Save 버튼 + 2단계 선택 다이얼로그(Video/Image → PNG/PDF)를 없애고 "이미지 저장" /
   "비디오 저장" 아이콘 버튼 2개를 오른쪽 패널 상단에 나란히 배치. 텍스트 없이 아이콘만
   사용(`ic_image.xml`, `ic_video.xml`, Material 아이콘 경로 기반 벡터). PDF 저장은 이제
   UI에서 접근 불가능해져서 관련 코드(`savePdf()`, `SaveFormat.PDF`, PNG/PDF 선택 다이얼로그)
   전체 제거.

## 6. 겪었던 버그와 원인 (중요 — 재발 방지용)

| 버그 | 원인 | 해결 |
|---|---|---|
| 버튼 색상이 전부 파랗게 깨짐 (v1.2.0) | `MaterialButton`의 기본 스타일이 테마 `colorPrimary` 기반 `app:backgroundTint`를 커스텀 `android:background` 위에 자동으로 덧씌움 | 커스텀 배경을 쓰는 모든 버튼에 `app:backgroundTint="@null"` 명시 |
| 검은색 버튼이 안 보임 (v1.2.1) | 태블릿이 시스템 다크 모드일 때 Android의 force-dark가 흰 패널을 강제로 어둡게 바꿔서, 이미 어두운 검은 원과 색 구분이 안 됨 | 테마를 `DayNight`→고정 `Light`로 변경 + `android:forceDarkAllowed="false"` |
| 검은색 버튼이 패널 아래로 잘림 (v1.3.1) | `SquareButton`(원형 강제용 커스텀 View)이 `heightMeasureSpec`을 무시하고 무조건 width와 같은 height를 강제 → 실제 남은 세로 공간보다 커지면 패널 밖으로 밀려나 클리핑됨 | `onMeasure`에서 `min(measuredWidth, measuredHeight)`로 제한 + 스와치 컨테이너를 `wrap_content`→weight 기반 높이로 변경(그래야 실제 height 제약이 전달됨) |

**교훈**: `SquareButton`을 쓰는 곳은 항상 weight 기반 높이 안에 넣어야 클리핑 방지 로직이
작동함. 커스텀 `android:background`를 쓰는 `MaterialButton`엔 항상 `app:backgroundTint="@null"`을
같이 써야 함. 이 앱은 로봇팔용 "고정 UI" 취지상 시스템 다크모드 등 외부 요인에 영향받지 않아야
하므로, 테마는 계속 고정 Light로 유지.

## 7. 작업 방식 (다음 세션에서도 유지)

- **새 UI/기능 아이디어는 먼저 HTML 미리보기(Claude Artifact)로 만들어서 보여주고, 사용자가
  확인한 뒤에만 실제 Kotlin/XML에 포팅**한다. 특히 화면 녹화처럼 실제 기기 없이 검증하기 어려운
  기능은 브라우저에서 먼저 동작을 확인(예: `canvas.captureStream()` + `MediaRecorder`로 실제
  webm 다운로드까지 테스트)한 뒤에 네이티브로 옮겼다.
- 이 서버엔 실제 태블릿/에뮬레이터가 없어서 **빌드 성공 + `aapt dump badging` 점검까지만
  가능**하고, 실제 기기 동작 확인은 항상 사용자가 설치해서 테스트. 버그 리포트를 받으면 원인을
  추정해서 고치고 패치 릴리스로 배포하는 흐름을 반복함.
- `main`에 직접 push하는 것은 자동 승인되지 않는 액션이라, 매번 진행 여부를 확인받고 진행함.

## 8. 릴리스 히스토리 (오래된 것 → 최신)

| 태그 | 주요 내용 |
|---|---|
| `v1.0.0-robot-drawing-mvp` | 최초 MVP |
| `v1.1.0-robot-drawing-ui-redesign` | 화이트 리디자인, 캔버스 확장, 점 크기 pill |
| `v1.2.0-robot-drawing-pentypes` | 펜 타입 3종, Clear All, 원형 색상 버튼, 메탈 UI |
| `v1.2.1-robot-drawing-colorfix` | 버튼 색상 파랗게 깨지는 문제 수정 |
| `v1.2.2-robot-drawing-darkmodefix` | 검은색 버튼이 다크모드에 묻히는 문제 수정 |
| `v1.3.0-robot-drawing-recording` | 화면 녹화 + Save 메뉴 Video/Image 분리 |
| `v1.3.1-robot-drawing-swatchfix` | 검은색 버튼 클리핑(잘림) 문제 수정 |
| `v1.4.0-robot-drawing-savebuttons` | Save 버튼을 이미지/비디오 저장 아이콘 버튼 2개로 분리, PDF 저장 제거 |

최신 다운로드 링크:
`https://github.com/danbi42290899-commits/danbi/releases/download/v1.4.0-robot-drawing-savebuttons/app-debug.apk`

## 9. 아직 안 한 것 / 나중에 고려할 것 (원래 스펙의 "있으면 좋은 기능" 중 미구현)

- 저장 파일 이름은 이미 타임스탬프 자동 생성됨 (완료)
- S펜 압력 감지, 손가락 입력 비활성화 옵션은 아직 없음
- 전체 화면 immersive mode 아직 적용 안 함
- 저장 후 파일 공유(Share) 기능 아직 없음
- 실제 로봇팔로 태블릿 조작 테스트는 사용자가 직접 진행 중 (이 서버에서는 검증 불가)
