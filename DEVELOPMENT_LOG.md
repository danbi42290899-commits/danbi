# Hearing Loss 프로젝트 — 개발 로그

> 이 문서는 지금까지의 대화에서 논의·결정된 내용을 정리한 것입니다. 다음 세션에서 이어서
> 작업할 때 이 파일을 먼저 읽고 시작하세요.

## 1. 프로젝트 목적

"Hearing Loss"라는 과제를 위한 청력 확인용 웹앱. 사용자가 저주파부터 고주파까지 순서대로
재생되는 sine wave를 듣고, 소리가 더 이상 들리지 않기 시작하는 지점을 스스로 표시해 자신의
청취 가능 주파수 범위를 확인하는 것이 핵심 목표. 의료 진단용이 아닌 **교육/데모 목적**이며,
Fourier Transform(FFT)과 디지털 필터(LPF/HPF/BPF) 개념을 시각적으로 함께 보여주는 것도 목적에
포함된다.

## 2. 앱 이름 / 컨셉

- **이름**: Frequency Hearing Test (초기엔 "Hearing Range Check"였다가 변경)
- **부제**: "Find the frequency where sound becomes hard to hear"
- **크레딧**: "MADE BY DB" (부제 옆 작은 글씨)
- **비주얼 컨셉**: 오디오미터(청력검사 차트) + 오실로스코프/스펙트럼 분석기 계기판을 결합한
  "인스트루먼트 패널" 디자인. 로그 스케일 그리드 배경(오디오그램 차트지 느낌), 상단
  "MODEL HR‑1" 네임플레이트 칩, 안전 안내는 위험 경고 대각선 줄무늬(hazard stripe) 박스로 표현.
  디지털 장비의 화면(오실로스코프/스펙트럼/주파수 카운터)은 페이지 테마(라이트/다크)와
  무관하게 항상 거의 순수 블랙에 가까운 배경 유지.

## 3. 선택한 기술 스택

- **React + Vite + Web Audio API** (백엔드 없음, 프론트엔드 전용, 정적 배포 가능)
- Node.js는 이 sandbox 환경에 설치되어 있지 않아서 **nvm으로 사용자 권한 설치**함
  (`~/.nvm`, Node v24.18.0). 새 셸에서는 `. ~/.nvm/nvm.sh` 먼저 source 필요.
- 폰트는 CDN 없이 **로컬 OTF 파일을 직접 임베드**: URW Gothic Demi(제목), URW Bookman
  Light(본문), Nimbus Mono PS Bold(숫자/라벨) — `src/assets/fonts/`에 저장, `index.css`에서
  `@font-face`로 로드.
- lint: `oxlint` (`npm run lint`)
- 이 프로젝트와는 별개로, 브라우저에서 바로 열어볼 수 있는 **Claude Artifact 버전**(순수
  HTML/vanilla JS, 폰트는 base64 data URI로 인라인)도 병행 유지 중 — 아래 6번 참고.

## 4. 현재 구현된 기능 (Phase 1 + Phase 2 일부)

**Phase 1 (완료)**
- 200Hz~30,000Hz 로그 스케일 28스텝 자동 sweep (`src/utils/frequencySteps.js`)
- "Can't hear from here" 버튼으로 청취 중단 지점 기록
- Time-domain waveform(오실로스코프)과 Frequency-domain FFT spectrum 실시간 시각화
- 결과 화면(마지막으로 들은 주파수 / 처음 안 들린 주파수)

**Phase 2 (진행 중, 아래 항목 완료)**
- **Confirmation test — bracketing(이분탐색) 방식**: Last heard와 First not heard 사이를
  최대 4라운드에 걸쳐 절반씩 좁혀가며 각 후보 주파수에 "Heard"/"Not Heard" 응답을 받아 청취
  임계값을 정밀화 (`src/components/ConfirmationTestScreen.jsx`)
- **결과 화면 5개 섹션**: Main sweep last/first-not-heard, Confirmation test 결과(칩
  형태), Estimated hearing threshold range, "This is not a clinical diagnosis." 안내문
  (`src/components/ResultScreen.jsx`)
- **Digital Filter Lab 탭**: White noise 신호에 Low-Pass/High-Pass/Band-Pass biquad
  필터를 적용, 필터 전(BEFORE)/후(AFTER) FFT 스펙트럼을 나란히 비교
  (`src/components/FilterLabScreen.jsx`, `src/hooks/useFilterLab.js`)
- FFT 스펙트럼 시각화는 막대 그래프가 아니라 **부드러운 라인 + 그라디언트 영역 채우기 +
  글로우 피크 마커 + "PEAK: xxx Hz" 라벨** 스타일 (스펙트럼 분석기 느낌)

**Phase 3 일부 완료 (신규 — 14번 항목 참고)**
- **Ear-by-Ear Pure-Tone Audiogram 모드**: 별도 "Audiogram Test" 탭, `StereoPannerNode`로
  좌/우 귀 완전 분리 재생, 6개 표준 주파수(250~8000Hz) × 2귀에서 dB축 bracketing으로 청취
  임계값 추정, ASHA 스타일 audiogram 차트(SVG), per-ear 요약/고주파소실 플래그/overall
  category/hearing profile 패턴 매칭(비진단적 표현)/percentile placeholder
- **JARVIS HUD 리디자인**: 앱 전체 블랙+레드 테마로 전환(라이트모드 제거)

**아직 안 한 것 (Phase 2 잔여 + Phase 3 나머지)** — 12번 항목 참고

## 5. 현재 실행 방법

```bash
# Node가 nvm으로 설치되어 있음. 새 셸이면 먼저:
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh"

cd ~/hearing-loss-app
npm run dev            # Vite dev server, http://localhost:5173
# 또는
npm run build && npm run preview
```

- `npm run lint` — oxlint
- `npm run build` — 프로덕션 빌드 (`dist/`, 폰트 3종 포함 약 270KB + JS/CSS)
- `npm run electron:start` — Electron 데스크톱 앱으로 빌드+실행 (15번 항목 참고)
- `npm run electron:build` — 설치 파일 패키징(mac dmg / win nsis / linux AppImage), `release/`에 생성

## 6. 현재 브라우저 접속 방법

이 세션이 실행되는 sandbox 머신은 사용자의 실제 개발 환경(브라우저)과 **분리된 별도
컨테이너**임이 확인됨 — Codespaces 관련 환경변수나 `/workspaces` 디렉터리가 전혀 없음.
즉 `npm run dev`로 띄운 `localhost:5173`은 **사용자 브라우저에서 직접 열 수 없음** (포트
포워딩 경로가 없음).

**해결책**: 앱이 순수 프론트엔드(백엔드 통신 없음)이므로, 매번 변경 시 **Claude Artifact로
게시**해서 사용자가 브라우저에서 바로 열어보는 방식을 사용 중.

- 최신 Artifact URL: `https://claude.ai/code/artifact/3f1fa411-42cd-4569-846c-b1c24a74e82f`
  (같은 URL로 계속 redeploy됨 — 2026-07-06 세션에서 audiogram 모드 + JARVIS HUD 반영 후 갱신)
- Artifact는 React 코드를 그대로 옮긴 게 아니라, **동일한 기능을 vanilla HTML/JS로 재구현**한
  거울 버전. 폰트는 base64 data URI로 인라인(외부 요청 불가한 Artifact CSP 때문).
  실제 개발/유지보수는 `~/hearing-loss-app`의 React 프로젝트에서 계속하고, 기능을 바꿀 때마다
  **React 쪽을 먼저 고치고 → 같은 로직을 Artifact의 `hearing-template.html`에도 반영 → 폰트
  base64 주입해서 `hearing-artifact.html` 재생성 → Artifact 재배포** 순서로 작업해왔음.
- Artifact 소스 파일 위치(세션 scratchpad, 세션 종료 시 사라질 수 있음 — 아래 13번 참고):
  `/tmp/claude-1030/-home-dbkim/032a3e7f-adcd-4ae4-90b9-cb16d5fcb6aa/scratchpad/hearing-template.html`
  (폰트 placeholder 포함된 원본) 및 `hearing-artifact.html` (폰트 주입된 최종본). **이전 경로
  (`43e6de81-...`)는 세션이 바뀌며 실제로 사라졌음** — 13번 항목의 경고가 현실화된 사례이니,
  다음 세션에서도 이 경로가 없으면 React 코드 기준으로 처음부터 다시 작성할 것.

## 7. 현재까지 결정한 UI/UX 방향

- **색상 토큰**(라이트/다크 테마 모두 지원, `prefers-color-scheme` 기반):
  - `--bg`, `--panel-bg`, `--ink`, `--ink-soft`, `--panel-border`, `--grid-line` — 테마별로 다름
  - `--accent` (버튼/탭 강조, 테일 계열), `--alert` (위험/Not Heard, 레드 계열) — 테마별로 다름
  - `--scope-bezel`, `--scope-green`(오실로스코프), `--spectrum-line`(FFT 라인, 민트/청록),
    `--readout-bg`, `--readout-fg`(디지털 숫자 표시) — **테마 무관하게 항상 거의 순수
    블랙 배경**(실제 계측장비 화면은 방 조명과 무관하게 어둡다는 컨셉)
- **타이포그래피**: 제목(URW Gothic Demi) / 본문(URW Bookman Light) / 숫자·라벨(Nimbus
  Mono PS Bold, tabular-nums) 3단 페어링
- **레이아웃**: `.rack`(전체 wrapper, max-width 640px) → `.nameplate`(제목/부제/크레딧) →
  `.tab-row`(Hearing Test / Filter Lab 탭) → `.panel`(카드, 실제 화면 전환이 일어나는 곳) →
  `.rack-footer`(200Hz ~ 30,000Hz 범위 표시)
- **안전 안내 박스**: 이모지 대신 **대각선 hazard stripe**(경고 테이프 패턴)로 "CAUTION" 표시
- **버튼**: Start/Test Again = `--accent`, Can't hear/Not Heard/Stop = `--alert`, 항상 진한
  하단 그림자로 물리 버튼처럼 눌리는 느낌
- **FFT 스펙트럼**: 로그 스케일 x축, 부드러운 라인 + 그라디언트 영역 채우기 + 피크 지점 글로우
  점 + "PEAK: xxx Hz" 직접 라벨(점 위치가 좌/우 어디든 라벨이 겹치지 않게 자동 반전)
- Confirmation test의 Heard/Not Heard 응답은 결과 화면에서 초록/빨강 칩으로 표시(의미색과
  accent색은 분리해서 사용)

## 8. Fourier Transform과 FFT 시각화의 역할

- **소리 생성**과 **FFT 분석**은 완전히 분리된 파이프라인:
  - 생성: `OscillatorNode`가 `sin(2πft)`를 실시간 합성(이미 알고 있는 주파수를 "만드는" 과정)
  - 분석: `AnalyserNode.getByteFrequencyData()`가 실제 출력 파형을 받아 "이 신호에 어떤
    주파수 성분이 얼마나 있는가"를 **역으로 추정**하는 과정 (`getByteTimeDomainData()`는
    시간 영역, `getByteFrequencyData()`는 FFT 결과인 주파수 영역)
- 단일 sine wave만 재생할 때는 FFT 결과가 항상 "재생 중인 주파수 하나에 peak"으로 나와 다소
  뻔하지만, 이것이 오히려 FFT가 무엇을 하는지 보여주는 교육적 예시가 됨
- FFT의 진짜 교육적 가치는 **Filter Lab**에서 드러남: white noise(모든 주파수에 에너지가
  고르게 분포)에 필터를 걸면, FFT 스펙트럼에서 "이 대역은 남고 저 대역은 사라졌다"가 뚜렷하게
  보임 — 순수 sine wave로는 이 효과를 보여줄 수 없어서 필터 데모에는 별도로 white noise를
  사용하기로 결정함(이전 대화에서 사용자가 선택)

## 9. Time-domain waveform과 Frequency-domain spectrum 설명

- **Time-domain (오실로스코프, CH.1)**: x축 = 시간, y축 = amplitude. 실제 스피커를 진동시키는
  파형 그대로를 보여줌. 낮은 주파수일수록 화면에 보이는 파동 주기가 길게(느리게) 보임.
- **Frequency-domain (FFT spectrum, CH.2)**: x축 = 주파수(로그 스케일, 200Hz~30,000Hz),
  y축 = 그 주파수 성분의 magnitude. 현재 재생 중인 주파수 위치에 뾰족한 peak가 나타남.
  `analyser.frequencyBinCount`개의 bin은 선형 간격이라, 로그 스케일 x축에 매핑할 때 인접
  bin 사이를 **선형 보간**해서 계단식이 아닌 매끄러운 곡선으로 그림(구현 세부사항).
- 두 시각화 모두 매 프레임(`requestAnimationFrame`) 갱신되는 라이브 뷰이며, Hearing Test /
  Confirmation Test / Filter Lab 화면에서 공통 컴포넌트(`WaveformCanvas.jsx`,
  `SpectrumCanvas.jsx`)로 재사용됨.

## 10. 앞으로 개선할 디자인 방향

- 사용자가 제안했던 **"Hearing threshold / sweep trace" 결과 그래프**: sweep 전체 구간에서
  주파수별 반응(들림/안들림)을 로그축 라인으로 그리고 threshold 지점을 마커로 찍는 방식.
  현재는 텍스트/카드 형태로만 결과를 보여주고 있어서, 이 시각적 그래프는 **아직 미구현** —
  다음 작업 후보 1순위.
- Filter Lab의 cutoff/center frequency 슬라이더 조작 시, 슬라이더 드래그 중에는 캔버스를
  다시 그리지 않고 값만 패치하도록 구현되어 있음(성능/깜빡임 방지) — 이 패턴을 다른 컨트롤에도
  일관되게 적용할 것.
- 아직 시도 안 해본 것: 필터 cutoff 지점을 스펙트럼 그래프 위에 세로선으로 표시하는 것(필터
  전/후 비교를 더 직관적으로 만들 수 있음)

## 11. Confirmation test / bracketing / staircase 방식 아이디어

- 사용자가 처음 제안한 방식은 **고정 목록**(예: last=4000Hz, first-not-heard=8000Hz일 때
  5000/6000/7000/8000Hz를 순서대로 재확인)이었으나, "가능하다면 bracketing 또는 staircase
  방식으로" 요청이 있어 **이분탐색(bracketing) 방식으로 구현**함.
- **알고리즘**: `candidate = round((lower + upper) / 2)`. Heard면 `lower = candidate`,
  Not Heard면 `upper = candidate`. 최대 4라운드(`MAX_ROUNDS`) 또는 구간이 1Hz 이하로 좁혀지면
  종료. 최종 `[lower, upper]` 구간이 "Estimated Hearing Threshold Range"로 표시됨.
- 각 라운드에서는 해당 주파수를 **연속 재생**(자동으로 다음으로 안 넘어감, 사용자가 응답할
  때까지 유지)하며 오실로스코프/스펙트럼을 그대로 보여줌.
- 향후 개선 아이디어(미구현, 아직 논의만 됨): 라운드 수를 초기 구간 크기에 따라 동적으로
  조정, 또는 실제 audiometry의 "2-of-3 재확인" 규칙 도입.

## 12. Phase 2, Phase 3에서 구현할 기능

**Phase 2 잔여**
- [x] Confirmation test (bracketing)
- [x] 필터(LPF/HPF/BPF) 적용 + 전후 FFT 비교
- [ ] **결과 그래프 (sweep용)** (10번 항목 참고 — sweep 결과 화면은 아직 텍스트/카드 형태만
      있음. Audiogram Test 탭에는 14번 항목의 SVG audiogram 차트가 이미 있지만, 이건 별도
      모드이고 기존 sweep 결과 화면에는 아직 그래프가 없음)

**Phase 3**
- [ ] White noise 추가 (Filter Lab에는 이미 있음(`useFilterLab.js`의 `ensureNoiseBuffer`);
      Audiogram Test는 순음(sine)만 사용 — 필요시 재사용 가능)
- [x] **왼쪽 귀 / 오른쪽 귀 분리 테스트** — 14번 항목의 Audiogram Test 탭으로 완료
      (`StereoPannerNode` 기반, 기존 sweep 탭은 여전히 모노 양쪽 동일 재생 유지)
- [ ] 결과 저장 또는 다운로드 (localStorage 또는 JSON/CSV 다운로드 — sweep, audiogram 둘 다
      아직 새로고침하면 결과가 사라짐)
- [ ] Percentile 비교 (14번 항목 참고 — normative dataset 없어서 현재는 placeholder만 존재)

## 13. 나중에 이어서 작업할 때 Claude가 알아야 할 내용

- **이 sandbox는 사용자의 실제 환경과 분리되어 있다.** `npm run dev`를 실행해도 사용자가
  직접 그 URL을 열 수 없다. 매번 변경 후 사용자에게 보여줘야 할 때는 **Artifact로
  재배포**해야 한다 (6번 항목 참고).
- **React 앱과 Artifact는 두 벌의 코드베이스**다(하나는 React/JSX, 하나는 vanilla
  HTML/JS). 기능을 추가/수정할 때는 **반드시 양쪽에 동일하게 반영**해야 한다. 지금까지는
  React를 먼저 고치고 Artifact에 미러링하는 순서로 작업했다.
- **Artifact 소스 파일들은 세션 scratchpad에 있다** (`/tmp/claude-1030/.../scratchpad/`).
  이 디렉터리는 세션이 바뀌면 사라질 수 있으므로, 다음 세션에서 Artifact를 다시 수정하려면
  **React 앱(`~/hearing-loss-app`, 영구 보존됨)을 기준으로 vanilla JS 버전을 다시
  작성**해야 할 수도 있다. React 쪽 컴포넌트/훅 구조를 그대로 따라가면 포팅이 수월하다.
- **폰트**: URW Gothic Demi / URW Bookman Light / Nimbus Mono PS Bold는 시스템에 이미 설치된
  OTF(`/usr/share/fonts/opentype/urw-base35/`)를 복사해서 쓴 것. React는
  `src/assets/fonts/`에 실제 파일로, Artifact는 base64 data URI로 인라인했다.
- **헤드리스 브라우저 오디오 테스트의 한계**: 이 세션 후반부에 headless Chromium(Playwright)의
  AudioContext 렌더링 clock이 멈추는 현상이 발생함(`audioCtx.currentTime`이 진행되지 않아
  분석기 데이터가 항상 무음으로 나옴). pulseaudio 재시작, null-sink 모듈 재로드로도 해결 안
  됨 — **코드 버그가 아니라 이 sandbox 환경의 오디오 백엔드 문제**로 결론지었다(같은 코드가
  세션 초반에는 정상적으로 실제 파형을 보여줬음). 다음 세션에서 오디오 기능을 Playwright로
  검증할 때 스펙트럼/파형이 계속 평평하게(무음으로) 나온다면, 먼저 이 문제인지 의심하고
  `pulseaudio --kill` 후 재시도하거나, 사용자에게 직접 실제 브라우저에서 확인해달라고 요청할 것.
- **주파수 범위는 200Hz~30,000Hz** (사람의 가청 범위인 20~20,000Hz가 아님 — 사용자가 저주파는
  잘 안 들려서 200Hz부터, 그리고 청력 한계를 넘어서는 지점까지 보고 싶다고 30,000Hz로 명시적
  요청함). 30,000Hz를 제대로 재생하기 위해 AudioContext를 96kHz 샘플링레이트로 생성함
  (Nyquist 한계를 48kHz로 확보).
- Node.js는 nvm으로 설치되어 있고 기본 PATH에 없음 — Bash 명령 실행 시 항상
  `export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh"`를 먼저 실행해야 한다.

## 현재 프로젝트 파일 구조

```
~/hearing-loss-app/
├── DEVELOPMENT_LOG.md          (이 문서)
├── README.md
├── index.html
├── package.json
├── package-lock.json
├── vite.config.js
├── .oxlintrc.json
├── public/
│   ├── favicon.svg
│   └── icons.svg
└── src/
    ├── main.jsx
    ├── App.jsx                       탭(Hearing Test/Audiogram Test/Filter Lab) + phase 상태머신
    ├── App.css                       레이아웃, 버튼, 슬라이더, 결과카드, audiogram 차트 등 전체 스타일
    ├── index.css                     색상 토큰(@font-face, :root — JARVIS HUD 블랙+레드, 라이트모드 없음)
    ├── assets/
    │   └── fonts/
    │       ├── HRGothic-Demi.otf     제목용
    │       ├── HRBookman-Light.otf   본문용
    │       └── HRMono-Bold.otf       숫자/라벨용
    ├── utils/
    │   ├── frequencySteps.js         MIN_FREQ(200)~MAX_FREQ(30000) 로그스케일 28스텝 생성 (sweep용)
    │   ├── audiogramFrequencies.js   표준 주파수 [250..8000], LEVEL_MIN/MAX_DB (audiogram용)
    │   ├── hearingCategories.js      ASHA 기반 6단계 중증도 테이블 + classifyLevel
    │   ├── audiogramAnalysis.js      PTA, high-frequency loss 감지, overall category
    │   └── hearingPatterns.js        hearing profile 패턴 매칭(비진단적 표현)
    ├── hooks/
    │   ├── useAudioEngine.js         메인 sweep용 오디오 엔진 (오실레이터+애널라이저, 96kHz)
    │   ├── useAudiogramEngine.js     audiogram용 오디오 엔진 (StereoPannerNode, dB→gain 매핑)
    │   └── useFilterLab.js           Filter Lab용 오디오 엔진 (white noise+biquad filter)
    └── components/
        ├── SafetyIntroScreen.jsx     sweep 인트로 + 안전 안내(hazard stripe)
        ├── HearingTestScreen.jsx     메인 sweep 화면 (readout+파형+스펙트럼+버튼)
        ├── ConfirmationTestScreen.jsx  sweep bracketing 방식 확인 테스트(주파수 축)
        ├── ResultScreen.jsx          sweep 결과 화면 (5개 섹션)
        ├── AudiogramTab.jsx          audiogram phase 상태머신(intro→testing→result)
        ├── AudiogramIntroScreen.jsx  귀 분리 테스트 안내 + 헤드폰 필수 안내 + reference tone
        ├── AudiogramTrialScreen.jsx  audiogram bracketing(레벨/dB 축), MAX_ROUNDS=6
        ├── AudiogramResultScreen.jsx audiogram 결과(per-ear 요약/고주파플래그/overall/profile/percentile placeholder)
        ├── AudiogramChart.jsx        SVG audiogram 차트(우측=빨간 원 실선, 좌측=시안 X 점선, 중증도 밴드)
        ├── HearingProfileAvatar.jsx  hearing profile 패턴별 미니멀 라인아트 SVG 아이콘
        ├── FilterLabScreen.jsx       필터 랩 화면 (타입선택+슬라이더+전후 비교)
        ├── WaveformCanvas.jsx        오실로스코프 캔버스 (공용)
        └── SpectrumCanvas.jsx        FFT 스펙트럼 캔버스 (공용, 라인+피크 스타일)
```

## 14. (신규) Ear-by-Ear Pure-Tone Audiogram 모드 + JARVIS HUD 리디자인

기존 sweep 데모는 그대로 유지하고, **완전히 별도의 "Audiogram Test" 탭**을 추가함(3번째 탭:
Hearing Test / Audiogram Test / Filter Lab). 이유: sweep의 confirmation test는 **주파수 축**을
이분탐색하고, audiogram은 고정 주파수에서 **레벨(dB) 축**을 이분탐색해야 해서 축이 정반대이고,
데이터 모양도(단일 last/first-not-heard 쌍 vs 2귀×6주파수 행렬) 근본적으로 다름. Filter Lab이
이미 "탭 활성화될 때만 마운트되는 독립 hook" 패턴이라 동일 패턴을 재사용함.

**새 파일 (React, `~/hearing-loss-app/src`)**
- `utils/audiogramFrequencies.js` — 표준 옥타브 주파수 `[250,500,1000,2000,4000,8000]`,
  `LEVEL_MIN_DB=-10`, `LEVEL_MAX_DB=100`
- `utils/hearingCategories.js` — ASHA 기반 6단계 중증도(Normal/Mild/Moderate/Moderately
  Severe/Severe/Profound) 테이블 + `classifyLevel(db)`
- `utils/audiogramAnalysis.js` — `pureToneAverage`(500/1000/2000 평균, PTA), `detectHighFrequencyLoss`,
  `classifyEar`, `overallCategory`(worse-ear PTA 기준)
- `utils/hearingPatterns.js` — 4가지 패턴(Normal/High-Frequency Sloping/Flat/Asymmetric) 규칙
  기반 매칭. **비대칭(두 귀 PTA 차이 ≥15dB)을 최우선으로 체크** — high-frequency sloping보다
  임상적으로 더 중요하다고 판단. 표현은 항상 "pattern resembles/similar to"이지 진단명 아님.
- `hooks/useAudiogramEngine.js` — `StereoPannerNode` 포함 오디오 엔진. `dB→gain` 변환은
  `gain = 0.25 * 10^((db-100)/20)` (물리적으로 올바른 20*log10 관계, 단 **dB SPL/HL 보정 아님**
  — 아래 캘리브레이션 항목 참고). `setEar('right'|'left')`가 `pan.value = ±1` 설정.
  `playReferenceTone()`는 1kHz를 pan=0(중앙)으로 재생하는 캘리브레이션용 톤.
- `components/AudiogramTab.jsx` — phase state machine(`intro→testing→result`), 귀 전환은
  React effect가 아니라 **각 전환 시점에 직접 `engine.setEar()` 호출**(effect 순서 경쟁 상태
  방지 — 이전에 실제로 문제가 될 뻔해서 명시적 호출로 고침).
- `components/AudiogramIntroScreen.jsx`, `AudiogramTrialScreen.jsx`(dB축 bracketing, MAX_ROUNDS=6),
  `AudiogramResultScreen.jsx`, `AudiogramChart.jsx`(SVG, 우측=빨간 원+실선, 좌측=시안 X+점선,
  ASHA 표준 배색), `HearingProfileAvatar.jsx`(패턴별 미니멀 라인아트 SVG 아이콘)

**후속 수정 (같은 세션, 사용자 피드백 반영)**:
- 탭/화면 이름을 "Audiogram Test" → **"Right/Left Ear Test"**로 변경(탭 버튼, intro 화면 h2,
  footer 라벨 전부). 결과 화면 제목도 "Audiogram Results" → "Right/Left Ear Test Results"로
  통일. 단, 그래프 섹션 자체는 여전히 "Audiogram Graph"로 표기(차트는 audiogram이라는 용어가
  더 정확해서 유지).
- sweep 결과 화면(`ResultScreen.jsx`) 카드 순서를 First Not Heard → Last Heard로 스왑.
- `AudiogramResultScreen.jsx` 정보 배치 순서를 **1) Overall Hearing Category(+hearing
  profile+avatar, +percentile placeholder를 한 카드에 통합) → 2) Left Ear Result / Right
  Ear Result(화면 기준 왼쪽에 Left) → 3) Audiogram Graph** 순으로 재배치. 각 ear 카드에 PTA,
  category, high-frequency drop-off 여부, **가장 민감도가 낮은 주파수 대역**(신규
  `worstFrequency()` — `utils/audiogramAnalysis.js`에 추가, 6개 표준 주파수 중 threshold가
  가장 높은(=가장 안 들리는) 주파수를 반환) 4가지를 한 줄씩 표시.
- CSS: `.overall-card`/`.overall-value`(글로우 있는 큰 카테고리 표시), `.profile-inline`,
  `.percentile-row`, `.ear-result-card`/`.ear-result-rows`/`.ear-result-row` 추가, 기존
  `.profile-card`/`.ear-category`/`.ear-flag`/`.percentile-placeholder`는 대체되어 제거.

**중요 — 정직성 제약(향후 세션에서도 반드시 지킬 것)**: Web Audio `GainNode` 값은 dB SPL/HL로
보정되지 않음(실제 음량은 사용자 기기 볼륨/헤드폰에 좌우됨). 그래서 이 audiogram은 **임상적으로
유효한 dB HL 수치를 만들 수 없음**. 차트 y축 라벨은 항상 "Relative Hearing Level (dB,
uncalibrated)"로 표기하고, "dB HL"이라는 표현은 쓰지 않음. Intro 화면에 "Play Reference Tone"
버튼으로 시작 전 볼륨을 고정하도록 유도(절대 보정은 아니지만 좌/우, 주파수 간 상대 비교는
의미 있게 유지). 카테고리/고주파소실 플래그/hearing profile은 전부 "estimated/pattern
resembles" 톤 유지, 진단처럼 단정하지 않음.

**Percentile 기능**: 실제 normative dataset 없이 임의 수치 표시하지 않기로 함 — 결과 화면에
"Requires a normative reference dataset — not available in this demo. Future feature." placeholder
카드만 표시.

**JARVIS HUD 리디자인**: `index.css`의 라이트/다크 `prefers-color-scheme` 분기를 **완전히
제거**하고 항상 블랙 테마로 고정(기존에 계기판 화면만 항상 블랙이었던 것을 앱 전체로 확장).
새 토큰: `--hud-cyan`(좌측 귀 마커/보조 색상), `--hud-red-dim`, `--hud-glow`(box/text-shadow
글로우). `--alert`를 빨강에서 **호박색(amber, #ffb020)** 으로 바꿔서 "Not Heard/Stop" 계열
버튼이 accent(빨강)와 구분되게 함. 오실로스코프/스펙트럼 트레이스 색도 초록/민트 계열에서
빨강/주황 계열로 교체. 거의 모든 색이 CSS 커스텀 프로퍼티를 거치고 있어서 토큰 교체만으로
전체 앱(Sweep/Audiogram/Filter Lab)에 일관 적용됨 — `App.css`/`index.css` 외 로직 파일은
건드릴 필요 없었음.

**Artifact 포팅**: 이전 세션의 Artifact 소스(`hearing-template.html`)는 세션 scratchpad가
사라지면서 함께 사라졌음(13번 항목에서 이미 경고했던 상황이 실제로 발생) — React 코드를
기준으로 vanilla JS 버전을 처음부터 다시 작성함. 새 Artifact 소스는
`/tmp/claude-1030/-home-dbkim/032a3e7f-adcd-4ae4-90b9-cb16d5fcb6aa/scratchpad/hearing-template.html`
(폰트 placeholder `__FONT_GOTHIC__`/`__FONT_BOOKMAN__`/`__FONT_MONO__` 포함) +
`hearing-artifact.html`(폰트 base64 주입된 최종본, python3로 치환). **`<meta charset="utf-8">`를
반드시 head 최상단에 넣을 것** — 빠뜨리면 em dash(—) 등이 mojibake로 깨짐(이번 세션에서 실제로
겪은 버그). 최신 Artifact URL: `https://claude.ai/code/artifact/3f1fa411-42cd-4569-846c-b1c24a74e82f`.
헤드리스 Playwright로 열어봤을 때 이번엔 실제 오디오 파형/스펙트럼이 정상적으로 렌더링됨(13번
항목의 예전 AudioContext-clock-정지 문제는 이번 세션에서는 재현되지 않음 — 환경이 바뀌었을 수
있으니 다음 세션에서도 여전히 문제라면 그때 다시 의심할 것).

## 15. (신규) Electron 데스크톱 앱 패키징 — 안드로이드는 다음 단계

사용자가 "컴퓨터 앱으로 먼저, 나중에 안드로이드 앱으로" 요청함. **Electron을 선택**함(질문 없이
합리적 기본값으로 진행) — 이유: 현재 앱이 Web Audio API(StereoPannerNode, AnalyserNode, 정밀한
gain scheduling)에 깊이 의존하는데, Electron은 Chromium을 그대로 번들하므로 브라우저에서 검증한
동작이 100% 그대로 재현됨. Tauri(OS 기본 웹뷰 사용, 더 가볍고 최신 버전은 모바일도 지원)도
고려했으나, 모바일 지원이 상대적으로 신생 기능이고 Rust 툴체인이 추가로 필요해서 "지금 당장
가장 안전하게 데스크톱 앱부터" 라는 목표에는 Electron이 더 적합하다고 판단함. **안드로이드
단계에서는 Capacitor를 권장** — 지금의 React/Vite 웹 코드를 그대로 wrapping하는 방식이라 코드
재작성이 필요 없고, Android WebView가 Chromium 기반이라 Web Audio API 호환성도 충분함(다음
세션에서 이어갈 때 이 판단을 다시 검토해도 됨, 확정된 건 아님).

**새 파일/변경**
- `electron/main.cjs` — Electron 메인 프로세스. `contextIsolation:true`, `nodeIntegration:false`,
  `sandbox:true`(현재 앱은 Node/OS API가 전혀 필요 없는 순수 프론트엔드라 가장 안전한 기본값
  그대로 사용 가능). `VITE_DEV_SERVER_URL` 환경변수가 있으면 그 URL을 로드(dev 모드, HMR 가능),
  없으면 `dist/index.html`을 `loadFile`로 로드(production 모드).
- `package.json` — `"main": "electron/main.cjs"`, 스크립트 4개 추가:
  - `electron` — `dist/`가 이미 빌드돼 있다고 가정하고 그냥 실행
  - `electron:dev` — `cross-env`로 `VITE_DEV_SERVER_URL` 설정 후 실행(먼저 별도 터미널에서
    `npm run dev`로 Vite dev server를 띄워둬야 함)
  - `electron:start` — `npm run build && electron .` (빌드+실행 한 번에, 가장 자주 쓸 명령)
  - `electron:build` — `npm run build && electron-builder` (설치 파일 패키징: mac→dmg,
    win→nsis, linux→AppImage)
  - `"build"` 필드에 electron-builder 설정(appId, productName, icon, files, 플랫폼별 target)
- **`vite.config.js`에 `base: './'` 추가 — 이게 없으면 Electron에서 흰 화면만 뜨는 치명적
  버그였음**(빌드 산출물의 `<script src="/assets/...">`가 절대경로라서, `file://`로 열면
  `/assets/...`가 파일시스템 루트를 가리켜버려서 JS 번들 로드 자체가 실패함 — 웹 서버로 서빙할
  땐 멀쩡해서 지금까지 안 드러났던 문제). 이 프로젝트를 다시 웹으로만 배포할 계획이 생기더라도
  상대경로(`./assets/...`)는 웹 서버에서도 정상 동작하므로 되돌릴 필요 없음.
- `index.html`에 `<meta http-equiv="Content-Security-Policy">` 추가(Electron이 CSP 없으면
  보안 경고를 띄움; 이 앱은 외부 요청이 전혀 없어서 `default-src 'self'`로 충분히 엄격하게
  잠글 수 있었음). `<title>`도 오래전에 안 바뀌어 있던 "Hearing Range Check" → "Frequency
  Hearing Test"로 수정.
- `public/favicon.svg` 교체 — 기존 파비콘은 **Vite 템플릿 기본값(보라색 번개 아이콘)이 그대로
  남아있던 것**으로, 이번에 데스크톱 앱 아이콘을 만들다가 발견함. JARVIS 테마에 맞는 심플한
  아이콘(검정 배경 + 빨간 원, audiogram의 우측 귀 마커를 그대로 재사용한 디자인)으로 교체.
  `build/icon.png`(1024×1024, Playwright로 SVG를 스크린샷해서 생성 — 이 sandbox엔 imagemagick
  등 SVG→PNG 변환 도구가 없어서 우회한 방법)를 electron-builder와 `main.cjs`의 창 아이콘 양쪽에
  사용.
- 검증: 이 sandbox에는 디스플레이가 없어서 `xvfb-run`(설치돼 있음)으로 가상 디스플레이를 띄운
  뒤 Electron을 `--no-sandbox`로 실행해 확인함(root 권한 컨테이너라 Chromium sandbox가 막힘 —
  **사용자의 실제 컴퓨터에서는 `--no-sandbox` 없이 정상 실행되어야 함**, 이건 순전히 이 sandbox
  환경 한정 우회책). `executeJavaScript`로 DOM을 직접 조회해서 3개 탭 렌더링, 버튼 클릭,
  `AudioContext` 생성, 탭 전환까지 실제로 동작하는 것을 확인했고, `npm run electron:build`로
  Linux AppImage(약 130MB) 패키징까지 끝까지 성공하는 것도 확인함.
- **이 sandbox에서 만든 결과물(AppImage 등)은 사용자 컴퓨터로 전달할 방법이 없음** — 6번/13번
  항목과 같은 맥락. 사용자가 자기 컴퓨터에서 직접 `npm run electron:start`(테스트) 또는
  `npm run electron:build`(배포용 설치파일 생성)를 실행해야 함. `release/`는 매번 재생성되는
  산출물이라 `.gitignore`에 추가해둠.

## 다음 작업 시작할 때 사용할 추천 프롬프트

```
DEVELOPMENT_LOG.md를 읽고 지금까지의 결정 사항을 파악한 다음,
[여기에 다음에 하고 싶은 작업을 적으세요. 예:
 - "Phase 2 결과 그래프(hearing threshold / sweep trace 시각화)부터 이어서 진행해줘"
 - "Phase 3의 white noise / 좌우 귀 분리 테스트로 넘어가줘"
 - "결과 저장/다운로드 기능부터 추가해줘"]
을 진행해줘. React 앱(~/hearing-loss-app)을 먼저 수정하고, 같은 내용을 Claude Artifact
(vanilla HTML/JS 버전)에도 반영해서 재배포해줘. 이 sandbox는 사용자 브라우저와 분리되어
있으니 dev server URL이 아니라 Artifact 링크로 확인시켜줘.
```
