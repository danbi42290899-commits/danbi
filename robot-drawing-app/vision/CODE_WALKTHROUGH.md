# photo_to_lineart.py — 코드 전체 설명

사진을 골라서 로봇팔이 그릴 수 있는 "흰 배경 + 검은 선" 이미지로 바꿔주는 파이썬
스크립트입니다. `robot-drawing-app/vision/photo_to_lineart.py`에 있고, 아래 각
코드 블록 위에 "이게 뭘 하는 코드인지"를 먼저 설명한 뒤 실제 코드를 붙였습니다.
위에서 아래로 순서대로 읽으면 됩니다.

**전체 그림**: 파일 선택창에서 이미지를 고름 → 사진인지 이미 선화(lineart)인지
자동 판단(또는 직접 지정) → 각각 다른 방식으로 "검은 선 vs 흰 배경" 이진 이미지를
만듦 → (옵션) 곡선을 직선 조각으로 단순화 → `output/edge_binary.png`로 저장 +
화면에 미리보기. 이 스크립트는 **로봇이 실제로 움직일 좌표(JSON/CSV/G-code)는
만들지 않고**, 그 앞 단계인 "이미지 필터링" 결과만 만드는 게 목적입니다. 좌표
변환까지 하는 버전은 같은 폴더의 `photo_to_robot_path.py`를 참고하세요.

---

## 0. `CONFIG` — 값만 바꿔가며 결과를 실험하는 곳

이 스크립트는 함수 로직을 직접 건드리지 않고도 `CONFIG` 딕셔너리 값만 바꿔서
결과를 조정할 수 있게 만들어졌습니다. 크게 세 그룹으로 나뉩니다.

- **`source_type`**: 입력 이미지가 이미 흰 배경 + 검은 선인 그림(`"lineart"`)인지,
  실제 사진(`"photo"`)인지를 정합니다. `"auto"`로 두면 아래 3번 섹션의
  `guess_source_type`이 자동으로 판단합니다.
- **`lineart_*`**: 이미 선화인 이미지에서 검은 픽셀 자체를 얼마나 엄격하게
  잡을지(`lineart_threshold`), 작은 노이즈 점을 얼마나 제거할지
  (`lineart_min_component_area`), 끊긴 선을 이어붙이거나(`close_iter`) 얇게
  만들지(`thin_iter`) 등을 조절합니다. 기본값은 대부분 0(적용 안 함)이라, 손을
  대지 않으면 원본 선을 거의 그대로 씁니다.
- **`blur_*` / `use_clahe` / `canny_*` / `photo_*`**: 실제 사진에서 Canny로
  윤곽선을 딸 때 쓰는 전처리(블러, 대비 향상)와 임계값입니다.
- **`linearize_curves` / `approx_epsilon_ratio`**: 로봇팔이 매끄러운 곡선을 잘
  못 그린다면, 추출된 선을 직선 조각(polyline)으로 단순화합니다.
  `approx_epsilon_ratio`가 클수록 더 각지고 단순해집니다.

```python
import os
import cv2
import numpy as np
import matplotlib.pyplot as plt
import tkinter as tk
from tkinter import filedialog

# =========================================================================
# PHOTO -> BLACK LINE IMAGE FOR ROBOT DRAWING
# - 이미지 파일 선택창에서 사진을 고르면 바로 필터링
# - 결과: 흰 배경 + 검은 선
# - 곡선은 필요하면 직선 조각으로 단순화 가능
# - robot path/json/csv/gcode 생성 안 함
# - 최종 결과: 선택한 이미지 폴더/output/edge_binary.png
# =========================================================================

CONFIG = {
    # ---------------------------------------------------------------------
    # mode 선택
    # "auto"      : 이미지가 이미 선화인지 일반 사진인지 자동 판단
    # "lineart"   : 이미 흰 배경 + 검은 그림/아이콘/스케치인 경우 추천
    # "photo"     : 실제 사진인 경우 추천
    # ---------------------------------------------------------------------
    "source_type": "auto",

    # 이미지 크기
    "max_size": 900,

    # ---------------------------------------------------------------------
    # lineart 모드 설정
    # 이미 흰 배경 + 검은 선 이미지일 때 사용
    # Canny를 쓰지 않고 검은 픽셀 자체를 잡음
    # ---------------------------------------------------------------------
    "lineart_threshold": 200,
    "lineart_min_component_area": 5,
    "lineart_close_iter": 0,
    "lineart_open_iter": 0,
    "lineart_thin_iter": 0,
    "lineart_dilate_iter": 0,

    # ---------------------------------------------------------------------
    # photo 모드 설정
    # 실제 사진에서 윤곽선을 따는 경우 사용
    # ---------------------------------------------------------------------
    "blur_type": "bilateral",       # "bilateral" | "gaussian" | None
    "blur_strength": 7,
    "use_clahe": True,
    "canny_low": 35,
    "canny_high": 110,
    "photo_min_component_area": 15,
    "photo_close_iter": 1,
    "photo_open_iter": 0,

    # ---------------------------------------------------------------------
    # 곡선 직선화 설정
    # 로봇이 곡선을 잘 못 그리면 True
    # 처음 확인할 때는 False로 두고, 선이 잘 나오면 True로 바꾸는 걸 추천
    # ---------------------------------------------------------------------
    "linearize_curves": True,

    # 너무 짧은 선 제거
    "min_contour_length": 5,

    # 곡선 직선화 정도
    # 작을수록 원래 곡선에 가까움: 0.003
    # 클수록 직선화/단순화 강함: 0.01 ~ 0.03
    "approx_epsilon_ratio": 0.006,

    # 최종 선 두께
    "final_line_thickness": 1,

    # 결과 화면 표시
    "show_result": True,

    # 결과 폴더 이름
    "output_folder_name": "output",
}
```

---

## 1. 파일 선택 / 이미지 로드 / 리사이즈

`select_image_file`은 tkinter의 파일 선택창(OS 기본 "열기" 대화상자)을 띄워서
사용자가 이미지를 직접 고르게 합니다. `root.withdraw()`로 tkinter의 빈 메인
창은 숨기고 파일 대화상자만 보이게 하는 게 포인트입니다. 아무것도 고르지 않고
창을 닫으면 `SystemExit(1)`로 바로 프로그램을 종료합니다.

`load_image_white_background`는 PNG 투명 배경(알파 채널) 이미지를 다룰 때
중요합니다. 알파 채널을 무시하고 그냥 읽으면 투명한 부분이 검은색으로 나올 수
있는데, 여기서는 알파값 비율만큼 흰색과 원본 색을 섞어서(`bgr * alpha + white *
(1 - alpha)`) "투명한 부분 = 흰 배경"으로 자연스럽게 합성합니다. 흑백(grayscale)
이미지나 일반 3채널 BGR 이미지도 모두 같은 함수 하나로 처리되도록 분기했습니다.

`resize_keep_aspect`는 가로/세로 중 긴 변을 `max_size`에 맞춰 줄입니다(비율
유지). 이미 이미지가 `max_size`보다 작으면(`scale >= 1.0`) 억지로 확대하지
않고 원본 그대로 둡니다 — 확대는 화질 손실만 만들고 얻는 게 없기 때문입니다.

```python
def select_image_file():
    root = tk.Tk()
    root.withdraw()

    input_path = filedialog.askopenfilename(
        title="필터링할 이미지 선택",
        filetypes=[
            ("Image files", "*.png *.jpg *.jpeg *.bmp *.webp"),
            ("All files", "*.*"),
        ],
    )

    if not input_path:
        print("이미지를 선택하지 않았습니다.")
        raise SystemExit(1)

    return input_path


def load_image_white_background(path):
    """
    PNG 투명 배경이 있는 경우 흰 배경 위에 합성해서 읽음.
    일반 jpg/png도 처리 가능.
    """
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED)

    if image is None:
        raise FileNotFoundError(f"이미지를 읽을 수 없습니다: {path}")

    # BGRA, 즉 알파 채널이 있는 경우
    if len(image.shape) == 3 and image.shape[2] == 4:
        bgr = image[:, :, :3].astype(np.float32)
        alpha = image[:, :, 3].astype(np.float32) / 255.0
        alpha = alpha[:, :, None]

        white = np.full_like(bgr, 255, dtype=np.float32)
        composite = bgr * alpha + white * (1.0 - alpha)

        return composite.astype(np.uint8)

    # grayscale인 경우 BGR로 변환
    if len(image.shape) == 2:
        return cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)

    # BGR 3채널
    return image[:, :, :3]


def resize_keep_aspect(image, max_size):
    if max_size is None:
        return image.copy()

    h, w = image.shape[:2]
    scale = max_size / float(max(h, w))

    if scale >= 1.0:
        return image.copy()

    new_w = int(round(w * scale))
    new_h = int(round(h * scale))

    return cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)
```

---

## 2. 공통 유틸 — 두 모드(lineart/photo)가 함께 쓰는 도구들

`odd`는 OpenCV의 블러 함수들이 커널 크기로 홀수만 받기 때문에 짝수가 들어오면
+1 해서 항상 홀수로 맞춰주는 아주 작은 안전장치입니다.

`remove_small_components`가 이 스크립트에서 가장 자주 쓰이는 핵심 유틸입니다.
`cv2.connectedComponentsWithStats`로 흰 선(mask에서 255인 픽셀들)을 서로
붙어있는 덩어리(컴포넌트) 단위로 묶고, 각 덩어리의 면적(`stats[label,
CC_STAT_AREA]`)이 `min_area`보다 작으면 통째로 지웁니다. 즉 "길이/크기가
일정 이상인 선/점만 남기고, 잡티 같은 아주 작은 얼룩은 제거"하는 노이즈
필터입니다. `min_area`가 0 이하면 아무 것도 하지 않고 그대로 반환합니다.

`guess_source_type`은 `source_type: "auto"`일 때 호출되는 간단한 휴리스틱입니다.
전체 픽셀 중 아주 밝은(255에 가까운, 배경으로 추정) 픽셀 비율과 아주 어두운(선으로
추정) 픽셀 비율, 그 사이(중간 톤) 비율을 각각 계산해서, "배경이 압도적으로 밝고
+ 검은 부분도 어느 정도 있고 + 중간 톤은 적은" 이미지면 이미 정리된 lineart로
보고, 그렇지 않으면(그림자/그라데이션 등 중간 톤이 많으면) 실제 사진으로
판단합니다.

```python
def odd(n):
    n = int(n)
    return n if n % 2 == 1 else n + 1


def remove_small_components(mask, min_area=10):
    """
    mask: 선/검은 영역이 255, 배경이 0인 이미지
    작은 점/짧은 잡선 제거
    """
    if min_area is None or min_area <= 0:
        return mask

    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask,
        connectivity=8,
    )

    cleaned = np.zeros_like(mask)

    for label in range(1, num_labels):
        area = stats[label, cv2.CC_STAT_AREA]

        if area >= min_area:
            cleaned[labels == label] = 255

    return cleaned


def guess_source_type(image):
    """
    간단 자동 판단:
    - 흰 배경/검은 선 비율이 높은 단순 이미지면 lineart
    - 아니면 photo
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    very_dark_ratio = np.mean(gray < 80)
    very_bright_ratio = np.mean(gray > 220)
    mid_ratio = np.mean((gray >= 80) & (gray <= 220))

    if very_bright_ratio > 0.55 and very_dark_ratio > 0.005 and mid_ratio < 0.35:
        return "lineart"

    return "photo"
```

---

## 3. lineart 모드 — 이미 그려진 검은 선을 그대로 추출

이 함수는 이미 "흰 배경 + 검은 선"인 그림(아이콘, 손그림 스캔, 클립아트 등)을
다룹니다. 핵심은 Canny 같은 경계선(edge) 검출을 쓰지 않는다는 점입니다. Canny는
선의 양쪽 가장자리를 따라가며 테두리를 그리기 때문에, 이미 하나의 검은 선인
그림에 쓰면 선 하나가 두 줄로 갈라져 나오는 부작용이 생깁니다. 대신 그냥
"어두운 픽셀(`gray < lineart_threshold`)은 전부 선"이라고 보고 그대로 마스크로
만듭니다(`np.where`).

그 다음 `remove_small_components`로 작은 점 노이즈를 지우고, `CONFIG`에서 값이
0보다 클 때만 morphology 연산(닫기=끊어진 선 잇기, 열기=잔가지 제거, 침식=선
얇게, 팽창=선 굵게)을 추가로 적용합니다. 기본값은 전부 0이라 원본 선을 최대한
보존하고, 필요할 때만 값을 올려서 튜닝하는 구조입니다. 마지막 `255 - black_mask`는
"선=255(흰색), 배경=0(검은색)"이던 마스크를 이 스크립트 전체가 약속한 최종 포맷인
"배경=255(흰색), 선=0(검은색)"으로 뒤집는 부분입니다.

```python
def make_binary_from_lineart(image, config):
    """
    이미 흰 배경 + 검은 선 그림일 때 사용.
    Canny처럼 선의 양쪽 테두리를 따지 않고,
    실제 검은 선 자체를 그대로 잡음.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    threshold_value = config.get("lineart_threshold", 200)

    # black_mask: 검은 선/그림 255, 배경 0
    black_mask = np.where(gray < threshold_value, 255, 0).astype(np.uint8)

    black_mask = remove_small_components(
        black_mask,
        min_area=config.get("lineart_min_component_area", 5),
    )

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))

    close_iter = config.get("lineart_close_iter", 0)
    if close_iter > 0:
        black_mask = cv2.morphologyEx(
            black_mask,
            cv2.MORPH_CLOSE,
            kernel,
            iterations=close_iter,
        )

    open_iter = config.get("lineart_open_iter", 0)
    if open_iter > 0:
        black_mask = cv2.morphologyEx(
            black_mask,
            cv2.MORPH_OPEN,
            kernel,
            iterations=open_iter,
        )

    thin_iter = config.get("lineart_thin_iter", 0)
    if thin_iter > 0:
        black_mask = cv2.erode(
            black_mask,
            kernel,
            iterations=thin_iter,
        )

    dilate_iter = config.get("lineart_dilate_iter", 0)
    if dilate_iter > 0:
        black_mask = cv2.dilate(
            black_mask,
            kernel,
            iterations=dilate_iter,
        )

    # 최종: 흰 배경 255 + 검은 선 0
    result = 255 - black_mask

    return result
```

---

## 4. photo 모드 — 실제 사진에서 Canny로 윤곽선 추출

`preprocess_photo`는 Canny를 돌리기 전 사진을 다듬는 단계입니다. 실제 사진은
카메라 노이즈나 미세한 질감이 많아서 그대로 Canny를 돌리면 원치 않는 잔선이
잔뜩 나옵니다. `blur_type`에 따라 `bilateralFilter`(경계는 보존하면서 안쪽
노이즈만 부드럽게 — 기본값)나 `GaussianBlur`(전체적으로 부드럽게)를 선택할 수
있고, `use_clahe`가 켜져 있으면 CLAHE(지역별 대비 향상)로 그림자 진 부분의
윤곽도 더 잘 드러나게 만듭니다.

`make_binary_from_photo`는 전처리된 이미지에 `cv2.Canny(low, high)`를 적용해
윤곽선을 뽑고, 3번 섹션과 같은 `remove_small_components`로 짧은 잔선을 지운
뒤, `close_iter`가 있으면 닫기 연산으로 끊어진 윤곽선을 이어붙입니다. 마지막
반전(`255 - edges`)은 lineart 모드와 동일하게 "배경 흰색 / 선 검은색" 포맷으로
맞추는 부분입니다.

```python
def preprocess_photo(image, config):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    blur_type = config.get("blur_type", "bilateral")
    blur_strength = config.get("blur_strength", 7)

    if blur_type == "bilateral":
        d = max(3, int(blur_strength))

        processed = cv2.bilateralFilter(
            gray,
            d=d,
            sigmaColor=blur_strength * 10,
            sigmaSpace=blur_strength * 10,
        )

    elif blur_type == "gaussian":
        k = odd(blur_strength)

        processed = cv2.GaussianBlur(
            gray,
            (k, k),
            0,
        )

    elif blur_type is None:
        processed = gray

    else:
        raise ValueError(f"알 수 없는 blur_type: {blur_type}")

    if config.get("use_clahe", True):
        clahe = cv2.createCLAHE(
            clipLimit=2.0,
            tileGridSize=(8, 8),
        )

        processed = clahe.apply(processed)

    return processed


def make_binary_from_photo(image, config):
    """
    실제 사진용.
    Canny로 윤곽선을 따고, 작은 선을 제거한 뒤
    흰 배경 + 검은 선으로 변환.
    """
    processed = preprocess_photo(image, config)

    edges = cv2.Canny(
        processed,
        config.get("canny_low", 35),
        config.get("canny_high", 110),
    )

    edges = remove_small_components(
        edges,
        min_area=config.get("photo_min_component_area", 15),
    )

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))

    close_iter = config.get("photo_close_iter", 1)
    if close_iter > 0:
        edges = cv2.morphologyEx(
            edges,
            cv2.MORPH_CLOSE,
            kernel,
            iterations=close_iter,
        )

    open_iter = config.get("photo_open_iter", 0)
    if open_iter > 0:
        edges = cv2.morphologyEx(
            edges,
            cv2.MORPH_OPEN,
            kernel,
            iterations=open_iter,
        )

    # 최종: 흰 배경 255 + 검은 선 0
    result = 255 - edges

    return result
```

---

## 5. 곡선 직선화 — 로봇팔이 그리기 쉬운 직선 조각으로 단순화

지금까지 나온 결과(흰 배경 + 검은 선)는 픽셀 단위로 울퉁불퉁한 곡선일 수
있습니다. 로봇팔이 부드러운 곡선을 정확히 따라가기 어렵다면, 이 함수가 각
선을 "몇 개의 꼭짓점을 잇는 직선 조각(polyline)"으로 단순화합니다.

먼저 `255 - binary`로 다시 "선=255" 마스크로 뒤집고, `cv2.findContours`로 선을
하나하나의 윤곽선(contour) 목록으로 뽑습니다. 각 윤곽선에 대해 `arcLength`로
길이를 재서 `min_contour_length`보다 짧으면(노이즈로 보고) 건너뜁니다. 남은
윤곽선은 `cv2.approxPolyDP`(Douglas-Peucker 알고리즘)로 근사하는데, 여기 쓰이는
오차 허용치(`epsilon`)가 고정값이 아니라 **그 윤곽선 길이에 비례한 값**
(`epsilon_ratio * arc_len`)이라는 점이 포인트입니다 — 그래야 긴 곡선과 짧은
곡선이 똑같은 비율로 단순화되어, 짧은 선이 과하게 뭉개지거나 긴 선이 덜
단순화되는 불균형이 생기지 않습니다. 마지막으로 근사된 꼭짓점들을
`cv2.line`으로 순서대로 이어 그려서 새 흰 배경 이미지에 그립니다.

```python
def linearize_curve_to_lines(binary, config):
    """
    binary: 흰 배경 255, 검은 선 0 이미지
    검은 선 contour를 찾아서 approxPolyDP로 직선 조각화.
    """
    h, w = binary.shape[:2]

    # black_mask: 선 255, 배경 0
    black_mask = 255 - binary

    contours, _ = cv2.findContours(
        black_mask,
        cv2.RETR_LIST,
        cv2.CHAIN_APPROX_NONE,
    )

    output = np.full((h, w), 255, dtype=np.uint8)

    min_len = config.get("min_contour_length", 5)
    epsilon_ratio = config.get("approx_epsilon_ratio", 0.005)
    thickness = config.get("final_line_thickness", 1)

    for contour in contours:
        arc_len = cv2.arcLength(contour, closed=False)

        if arc_len < min_len:
            continue

        epsilon = epsilon_ratio * arc_len

        approx = cv2.approxPolyDP(
            contour,
            epsilon,
            closed=False,
        )

        if len(approx) < 2:
            continue

        points = approx.reshape(-1, 2)

        for i in range(len(points) - 1):
            p1 = tuple(points[i])
            p2 = tuple(points[i + 1])

            cv2.line(
                output,
                p1,
                p2,
                color=0,
                thickness=thickness,
                lineType=cv2.LINE_AA,
            )

    return output
```

---

## 6. 저장 / 시각화 — 전체 파이프라인을 하나로 묶는 `process_image`

`show_result_image`는 matplotlib로 결과 이미지를 흑백(`cmap="gray"`)으로
띄우는 아주 단순한 미리보기 함수입니다.

`process_image`가 앞의 모든 함수를 순서대로 호출하는 이 스크립트의
지휘자(orchestrator)입니다. 흐름은: 이미지 로드 → 리사이즈 → `source_type`이
`"auto"`면 자동 판단 → lineart/photo 중 맞는 모드로 이진화 → 설정에 따라 곡선
직선화 → **입력 파일이 있던 폴더 밑에 `output/` 폴더를 새로 만들어**
`edge_binary.png`로 저장 → (옵션) 화면에 표시, 순서입니다. 결과를 입력 이미지와
같은 폴더 하위에 저장하는 방식이라, 어떤 사진을 선택하든 그 사진 옆에 결과가
남는 구조입니다.

```python
def show_result_image(result, source_type):
    plt.figure(figsize=(8, 8))
    plt.imshow(result, cmap="gray", vmin=0, vmax=255)
    plt.title(f"edge_binary | mode: {source_type}")
    plt.axis("off")
    plt.tight_layout()
    plt.show()


def process_image(input_path, config):
    image = load_image_white_background(input_path)
    image = resize_keep_aspect(image, config.get("max_size", 900))

    source_type = config.get("source_type", "auto")

    if source_type == "auto":
        source_type = guess_source_type(image)

    if source_type == "lineart":
        result = make_binary_from_lineart(image, config)

    elif source_type == "photo":
        result = make_binary_from_photo(image, config)

    else:
        raise ValueError('source_type은 "auto", "lineart", "photo" 중 하나여야 합니다.')

    if config.get("linearize_curves", False):
        result = linearize_curve_to_lines(result, config)

    input_folder = os.path.dirname(input_path)

    output_dir = os.path.join(
        input_folder,
        config.get("output_folder_name", "output"),
    )

    os.makedirs(output_dir, exist_ok=True)

    output_path = os.path.join(output_dir, "edge_binary.png")

    cv2.imwrite(output_path, result)

    if config.get("show_result", True):
        show_result_image(result, source_type)

    print("[입력 이미지]", input_path)
    print("[모드]", source_type)
    print("[곡선 직선화]", config.get("linearize_curves", False))
    print("[완료] 저장 위치:", os.path.abspath(output_path))

    return result
```

---

## 7. 실행부 — 스크립트를 직접 실행했을 때

`python photo_to_lineart.py`로 직접 실행하면 이 블록만 동작합니다. 파일
선택창을 띄워서(`select_image_file`) 사용자가 고른 이미지 경로를 받고, 그
경로와 맨 위 `CONFIG`를 그대로 `process_image`에 넘겨 전체 파이프라인을
돌립니다.

```python
if __name__ == "__main__":
    input_path = select_image_file()
    result = process_image(input_path, CONFIG)
```

---

## 마무리 — 전체를 한 문장으로

**파일 선택창에서 이미지를 고르면(`select_image_file`), 사진인지 선화인지
자동으로 판단해(`guess_source_type`) 서로 다른 방식으로 검은 선을
추출하고(`make_binary_from_lineart` / `make_binary_from_photo`), 필요하면
그 선을 직선 조각으로 단순화한 뒤(`linearize_curve_to_lines`), 입력 이미지
옆의 `output/edge_binary.png`로 저장한다(`process_image`).** 아직 로봇팔이
실제로 움직일 mm 좌표/G-code는 만들지 않으므로, 이 결과를 확인하고 필터링
품질(선이 끊기지 않는지, 잡음이 없는지)에 만족한 다음 `photo_to_robot_path.py`
쪽 경로 추출 단계로 넘어가는 흐름을 염두에 두고 만들어졌습니다.
