# photo_to_robot_path.py 사용 가이드

사진 한 장을 로봇팔이 펜으로 따라 그릴 수 있는 "흰 배경 + 검은 선" 이미지와
mm 단위 좌표 경로(JSON/CSV/G-code)로 변환하는 스크립트.

## 1. 설치

```bash
# (권장) 가상환경 하나 만들어서 설치
python3 -m venv .venv
source .venv/bin/activate   # Windows는 .venv\Scripts\activate

pip install -r requirements.txt
```

conda를 쓴다면:

```bash
conda create -n robot-vision python=3.11
conda activate robot-vision
pip install -r requirements.txt
```

> 이 저장소에서는 `opencv-python` 대신 `opencv-python-headless`(GUI 없는
> 서버 환경)로 테스트했다. 로컬 PC(모니터 있는 환경)에서 돌린다면 그냥
> `opencv-python`을 써도 된다.

## 2. 실행 방법

### 2-1. 스크립트로 바로 실행

`photo_to_robot_path.py` 맨 아래 `input_path = "photo.jpg"` 부분을 실제 사진
경로로 바꾼 뒤:

```bash
python photo_to_robot_path.py
```

같은 폴더에 `output/` 디렉터리가 생기고 결과 파일들이 저장된다. 또한
matplotlib 창(또는 `pipeline_overview.png`)으로 각 단계 결과를 볼 수 있다.

### 2-2. 내 코드/Jupyter Notebook에서 함수로 사용

```python
from photo_to_robot_path import process_image_for_robot_drawing, CONFIG

config = dict(CONFIG)          # 기본값 복사
config["method"] = "canny"     # "canny" | "adaptive" | "xdog"
config["drawing_width_mm"] = 200
config["drawing_height_mm"] = 200
config["output_dir"] = "my_output"

result = process_image_for_robot_drawing("photo.jpg", config)

# result["paths_mm"]  : mm 좌표 경로 (로봇 제어 코드에서 바로 쓸 수 있음)
# result["paths_px"]  : 단순화된 픽셀 좌표 경로
# result["skeleton"], result["cleaned"], result["edge_binary"] 등 중간 결과도 다 들어있음
```

노트북(Jupyter)에서는 셀 맨 위에 `%matplotlib inline`을 넣으면
`visualize_pipeline`이 인라인으로 바로 보인다. 서버처럼 화면이 없는
환경에서는 스크립트 맨 위에 아래 두 줄을 추가하면 창을 띄우지 않고
`output/pipeline_overview.png` 파일로만 저장된다.

```python
import matplotlib
matplotlib.use("Agg")
```

## 3. 결과로 나오는 파일들 (`output/` 아래)

| 파일 | 내용 |
|---|---|
| `result_binary.png` | 흰 배경 + 검은 선 (morphology 정리까지 끝난 상태) |
| `result_skeleton.png` | 1px 중심선 |
| `result_paths_overlay.png` | 최종 추출된 path를 흰 배경 위에 그린 것 (로봇이 실제로 그릴 모양의 미리보기) |
| `pipeline_overview.png` | 전체 파이프라인 7단계를 한 장에 모아 비교한 이미지 |
| `robot_paths.json` | `[{"path_id": 0, "points": [[x_mm, y_mm], ...]}, ...]` |
| `robot_paths.csv` | `path_id, point_id, x_mm, y_mm, pen_state` (pen_state: 각 path의 첫 점=`up`, 이후=`down`) |
| `optional_gcode.txt` | `G0`(펜 업 이동) / `M3`(펜 다운) / `G1`(그리기) / `M5`(펜 업) 스타일 텍스트. 실제 로봇 제어기 명령 규격에 맞춰 나중에 바꿔 쓰는 용도의 중간 표현 |

로봇 제어 코드에서는 보통 `robot_paths.json`이 제일 다루기 쉽다 (path별로
묶여 있어서 "펜 들고 이동 → 펜 내리고 첫 점부터 순서대로 그리기 → 펜
들기"를 그대로 구현하면 됨).

## 4. CONFIG 파라미터 요약

파일 맨 위 `CONFIG` 딕셔너리 값만 바꿔서 실험하면 된다.

| 키 | 의미 | 올리면 | 내리면 |
|---|---|---|---|
| `method` | 선 추출 방식 (`canny`/`adaptive`/`xdog`) | - | - |
| `canny_low` / `canny_high` | Canny 임계값 | 선이 적어지고 뚜렷한 경계만 남음 | 잡음/질감까지 선으로 잡혀 복잡해짐 |
| `blur_strength` | 전처리 블러 강도 | 노이즈 줄고 선이 매끈해짐(과하면 디테일 소실) | 디테일은 살지만 노이즈도 그대로 |
| `morph_kernel_size` / `close_iter` | 끊어진 선 연결 | 끊긴 선이 잘 이어지지만 과하면 다른 선과 뭉개짐 | 끊어진 선이 그대로 남음 |
| `min_path_length` | 이보다 짧은 path 제거 | 로봇 그림이 단순해짐(작은 디테일도 사라질 수 있음) | 잔선/노이즈 곡선이 많이 남음 |
| `simplify_epsilon` | Douglas-Peucker 단순화 강도 | 점 개수 확 줄고 각져 보임 | 원래 곡선에 가깝지만 점이 많아짐 |
| `max_num_paths` | 상위 N개 긴 path만 사용 | 사진이 너무 복잡할 때 강제로 단순화 | - |
| `drawing_width_mm` / `drawing_height_mm` / `margin_mm` | 로봇 작업 영역(mm) | - | - |
| `flip_y` | 이미지 y축(아래로 증가) → 로봇 y축 반전 여부 | 로봇 좌표계에 맞춰 켜고 끄기 | - |

추천 기본값: `method="canny"`, `canny_low=50~80`, `canny_high=150~200`,
`blur_type="bilateral"`, `blur_strength=5~9`, `morph_kernel_size=3`,
`close_iter=1~2`, `min_path_length=15~25`, `simplify_epsilon=1.0~2.0`.
사진이 복잡하면 `min_path_length`/`simplify_epsilon`을 먼저 올리고, 그래도
선이 많으면 `max_num_paths`로 상한을 거는 순서를 추천한다.

## 5. 문제가 생기면

- **결과에 선이 하나도 없다**: `canny_low/high`를 낮추거나, `method`를
  `"adaptive"`로 바꿔보기. `adaptive_C`가 너무 크면 선이 아예 안 나올 수
  있다.
- **선이 전부 지워진다 / 결과가 새하얗다**: `morph_kernel_size`나
  `close_iter`/`dilate_iter`가 과하지 않은지 확인. (얇은 1px 선은 큰 커널의
  erosion 계열 연산에 통째로 사라질 수 있다.)
- **잔선/점 노이즈가 너무 많다**: `min_path_length`를 올리거나
  `blur_strength`를 올려서 전처리 단계에서 노이즈를 더 죽이기.
- **로봇이 그리기엔 여전히 선이 너무 많다**: `simplify_epsilon`을 올리고,
  `max_num_paths`로 상한을 걸기.
