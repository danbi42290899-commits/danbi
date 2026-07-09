"""
photo_to_robot_path.py

일반 사진을 입력받아 로봇팔(펜 플로터)이 따라 그릴 수 있는
"흰 배경 + 검은 선" 드로잉과, mm 단위 좌표 경로(JSON/CSV/G-code)로
변환하는 파이프라인.

파이프라인 개요
----------------
사진 로드 -> resize -> grayscale -> 노이즈 제거/대비 향상
    -> edge/sketch 추출(Canny / Adaptive Threshold / XDoG)
    -> morphology 정리 -> skeletonize(1px 중심선)
    -> skeleton graph 기반 path 추출 -> 짧은 path 제거
    -> Douglas-Peucker 단순화 -> 로봇 mm 좌표 변환
    -> pen 이동 순서 최적화(nearest-neighbor)
    -> JSON / CSV / G-code 저장 + 시각화

필요 라이브러리
----------------
    pip install opencv-python numpy scikit-image matplotlib

선택(대안) 라이브러리
----------------------
- 더 매끄러운 벡터 SVG 경로가 필요하면 potrace(pypotrace) 또는
  autotrace로 bitmap -> SVG 변환 후 svgpathtools로 좌표를 읽는 방법도
  고려할 수 있음. 이 스크립트는 외부 바이너리 의존성 없이 OpenCV /
  scikit-image 만으로 동작하도록 만들어졌음.
- skeleton을 그래프로 다룰 때 더 정교한 분석이 필요하면 `skan`
  패키지(skeleton analysis)를 사용하는 것도 고려할 수 있음. 여기서는
  추가 의존성 없이 간단한 이웃-픽셀 추적(neighbor tracing)으로 직접
  구현했다.

Jupyter Notebook에서도, 일반 `python photo_to_robot_path.py` 스크립트
실행에서도 그대로 동작한다 (하단 `if __name__ == "__main__":` 블록 참고).
"""

import os
import csv
import json

import cv2
import numpy as np
import matplotlib.pyplot as plt
from skimage.morphology import skeletonize


# =========================================================================
# 0. CONFIG - 여기 값만 바꿔가며 결과를 비교하면 된다.
# =========================================================================
CONFIG = {
    # ---- edge/sketch 추출 방식: "canny" | "adaptive" | "xdog" ----
    "method": "canny",

    # ---- 이미지 크기 ----
    "max_size": 800,                 # resize 시 긴 변 기준 최대 픽셀 수

    # ---- 전처리(preprocess_image) ----
    "blur_type": "bilateral",        # "bilateral" | "gaussian" | None
    "blur_strength": 7,              # 커널/필터 크기 (홀수로 자동 보정됨)
    "use_clahe": True,               # CLAHE로 대비 향상 여부

    # ---- Canny ----
    "canny_low": 50,
    "canny_high": 150,

    # ---- Adaptive threshold ----
    "adaptive_block_size": 21,       # 홀수, 클수록 큰 영역 기준으로 이진화
    "adaptive_C": 8,                 # 클수록 선이 얇아지고 적어짐
    "adaptive_median_blur": 3,       # None이면 미적용, 정수면 median blur 커널 크기

    # ---- XDoG (확장 옵션) ----
    "xdog_sigma": 0.5,
    "xdog_k": 1.6,
    "xdog_gamma": 0.98,
    "xdog_epsilon": -0.01,           # DoG 결과값 스케일(-0.2~0.3 정도)에 맞춘 값. -0.5처럼
                                      # 실제 diff 범위 밖의 값을 주면 선이 하나도 안 나옴
    "xdog_phi": 50,

    # ---- Morphology 후처리(clean_binary_image) ----
    "morph_kernel_size": 3,
    "open_iter": 1,                  # 작은 점 노이즈 제거 (opening)
    "close_iter": 1,                 # 끊어진 선 살짝 연결 (closing)
    "dilate_iter": 0,                # 선을 두껍게 (필요할 때만)
    "erode_iter": 0,                 # 선을 얇게 (너무 두꺼운 선 정리)

    # ---- Path 추출 / 단순화 ----
    "min_path_length": 20,           # 이보다 짧은 path(픽셀 길이)는 제거
    "simplify_epsilon": 1.5,         # Douglas-Peucker epsilon (픽셀 단위)
    "max_num_paths": None,           # 정수 지정 시 긴 path 순으로 상위 N개만 사용
                                      # (사진이 너무 복잡할 때 선 개수를 줄이는 옵션)

    # ---- 로봇 좌표 변환 ----
    "drawing_width_mm": 150,
    "drawing_height_mm": 150,
    "margin_mm": 10,
    "flip_y": True,                  # 이미지 y축(아래로 증가) -> 로봇 y축 반전 여부

    # ---- 출력 ----
    "output_dir": "output",
    "gcode_feed_draw": 800,          # 펜 다운 상태 이동 속도 (선택적으로 사용)
    "gcode_feed_travel": 1500,       # 펜 업 상태 이동 속도 (선택적으로 사용)
}


# =========================================================================
# 1. 이미지 로드 / 리사이즈
# =========================================================================
def load_image(path):
    """사진 파일을 BGR(OpenCV 기본) 이미지로 읽는다."""
    image = cv2.imread(path, cv2.IMREAD_COLOR)
    if image is None:
        raise FileNotFoundError(f"이미지를 읽을 수 없습니다: {path}")
    return image


def resize_keep_aspect(image, max_size):
    """긴 변이 max_size가 되도록 비율을 유지하며 리사이즈한다."""
    h, w = image.shape[:2]
    scale = max_size / float(max(h, w))
    if scale >= 1.0:
        # 원본이 이미 max_size보다 작으면 확대하지 않는다
        # (확대는 선이 뭉개지고 노이즈만 늘어나는 경우가 많음)
        return image.copy()
    new_w, new_h = int(round(w * scale)), int(round(h * scale))
    return cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)


# =========================================================================
# 2. 전처리: grayscale -> blur -> CLAHE
# =========================================================================
def _odd(n):
    """블러/블록 커널 크기는 홀수여야 하므로 짝수면 +1 해준다."""
    n = int(n)
    return n if n % 2 == 1 else n + 1


def preprocess_image(image, blur_type="bilateral", blur_strength=7, use_clahe=True):
    """
    BGR 이미지를 받아 grayscale -> 노이즈 제거(blur) -> 대비 향상(CLAHE)
    순서로 처리한 단일 채널(grayscale) 이미지를 반환한다.

    - blur_type="bilateral": 경계는 보존하면서 잡음만 제거 (스케치용으로 추천)
    - blur_type="gaussian" : 더 강하게 부드럽게, 속도가 빠름
    - blur_type=None       : blur 생략
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    if blur_type == "bilateral":
        # d(이웃 지름)와 sigma를 강도에 맞춰 조절
        d = max(3, int(blur_strength))
        blurred = cv2.bilateralFilter(gray, d=d, sigmaColor=blur_strength * 10,
                                       sigmaSpace=blur_strength * 10)
    elif blur_type == "gaussian":
        k = _odd(blur_strength)
        blurred = cv2.GaussianBlur(gray, (k, k), 0)
    elif blur_type is None:
        blurred = gray
    else:
        raise ValueError(f"알 수 없는 blur_type: {blur_type}")

    if use_clahe:
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        result = clahe.apply(blurred)
    else:
        result = blurred

    return result


# =========================================================================
# 3. 선 검출: Canny / Adaptive threshold / XDoG
#    (세 함수 모두 출력은 "흰 배경(255) + 검은 선(0)" uint8 이미지로 통일)
# =========================================================================
def generate_edges_canny(gray, low_threshold=50, high_threshold=150):
    """Canny edge detection. 결과는 흰 배경 + 검은 선으로 반전해서 반환."""
    edges = cv2.Canny(gray, low_threshold, high_threshold)
    binary = 255 - edges  # edge=255(흰색) -> 선을 검은색(0)으로 반전
    return binary


def generate_edges_adaptive(gray, block_size=21, C=8, median_blur_ksize=3):
    """
    Adaptive threshold 기반 스케치 방식.
    지역 평균보다 어두운 픽셀을 선으로 남겨 연필 스케치 느낌을 낸다.
    """
    block_size = _odd(max(3, block_size))
    src = gray
    if median_blur_ksize:
        src = cv2.medianBlur(src, _odd(median_blur_ksize))

    binary = cv2.adaptiveThreshold(
        src, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        block_size, C,
    )
    # adaptiveThreshold(THRESH_BINARY)는 이미 "밝은 배경 + 어두운 선"이 나온다.
    return binary


def generate_edges_xdog(gray, sigma=0.5, k=1.6, gamma=0.98, epsilon=-0.01, phi=50):
    """
    XDoG(eXtended Difference-of-Gaussians) 기반 스케치 필터.
    Canny/adaptive보다 손그림 느낌의 부드러운 윤곽선을 얻고 싶을 때 사용.
    나중에 다른 스타일의 sketch 필터를 추가하고 싶다면 이 함수와 같은
    시그니처(gray -> 0/255 binary)로 새 generate_edges_xxx 함수를 만들고
    process_image_for_robot_drawing의 method 분기에 추가하면 된다.
    """
    gray_f = gray.astype(np.float32) / 255.0
    g1 = cv2.GaussianBlur(gray_f, (0, 0), sigma)
    g2 = cv2.GaussianBlur(gray_f, (0, 0), sigma * k)
    diff = g1 - gamma * g2

    xdog = np.where(
        diff >= epsilon,
        1.0,
        1.0 + np.tanh(phi * (diff - epsilon)),
    )
    xdog = np.clip(xdog, 0.0, 1.0)
    xdog_img = (xdog * 255).astype(np.uint8)

    # 부드러운 톤 이미지를 이진화해서 파이프라인의 나머지 단계(0/255)와 맞춘다
    _, binary = cv2.threshold(xdog_img, 127, 255, cv2.THRESH_BINARY)
    return binary


# =========================================================================
# 4. Morphology 후처리
# =========================================================================
def clean_binary_image(binary, kernel_size=3, open_iter=1, close_iter=1,
                        dilate_iter=0, erode_iter=0, min_component_area=None):
    """
    "흰 배경 + 검은 선" 이진 이미지를 받아 morphology로 정리한다.

    - close_iter : closing(dilate->erode). 끊어진 선을 살짝 이어붙임.
    - dilate_iter: 추가로 선을 두껍게 하고 싶을 때.
    - erode_iter : 너무 두꺼운 선을 다시 얇게 정리하고 싶을 때.
    - open_iter  : 작은 점 노이즈 제거. 단, 선 그림에서 고전적인
      morphological opening(erode->dilate)을 그대로 쓰면 Canny 등으로 뽑은
      1px짜리 얇은 선이 구조 요소보다 얇다는 이유만으로 통째로 침식되어
      사라져버린다(선 길이와 무관하게). 그래서 여기서는 open_iter>0일 때
      "opening" 대신 연결 요소(connected component) 면적 기준으로 작은
      점만 골라 지우는 방식을 사용해 실제 선은 보존한다.

    내부적으로는 "선=255(foreground)"인 마스크로 뒤집어서 연산한 뒤
    다시 "흰 배경 + 검은 선"으로 되돌려 반환한다.
    """
    kernel_size = max(1, int(kernel_size))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))

    mask = 255 - binary  # 선=255, 배경=0 으로 변환 (foreground 기준으로 연산)

    # 1) closing: 끊어진 선을 살짝 이어붙임 (먼저 해서 짧은 선이 노이즈
    #    제거 단계에서 통째로 지워지기 전에 서로 이어지도록 함)
    if close_iter > 0:
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=close_iter)

    # 2) 두께 조정 (선택)
    if dilate_iter > 0:
        mask = cv2.dilate(mask, kernel, iterations=dilate_iter)
    if erode_iter > 0:
        mask = cv2.erode(mask, kernel, iterations=erode_iter)

    # 3) 작은 점 노이즈 제거 (연결 요소 면적 기준)
    if open_iter > 0:
        area_threshold = (
            min_component_area if min_component_area is not None
            else (kernel_size ** 2) * open_iter
        )
        num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
        for label in range(1, num_labels):
            if stats[label, cv2.CC_STAT_AREA] < area_threshold:
                mask[labels == label] = 0

    cleaned = 255 - mask  # 다시 흰 배경 + 검은 선 표현으로 변환
    return cleaned


# =========================================================================
# 5. Skeletonization (1픽셀 중심선)
# =========================================================================
def skeletonize_binary(binary):
    """
    "흰 배경 + 검은 선" 0/255 이미지를 받아 1픽셀 두께 중심선으로 변환한다.
    입력/출력 모두 0/255 형태(흰 배경 + 검은 선)로 유지한다.
    """
    mask = (binary == 0)  # 선(검은 픽셀)을 True로
    skeleton_mask = skeletonize(mask)
    skeleton = np.where(skeleton_mask, 0, 255).astype(np.uint8)
    return skeleton


# =========================================================================
# 6. Skeleton -> path 추출 (이웃 픽셀 추적 기반 그래프 탐색)
# =========================================================================
def _neighbor_offsets():
    return [(-1, -1), (-1, 0), (-1, 1),
            (0, -1),           (0, 1),
            (1, -1),  (1, 0),  (1, 1)]


def _count_neighbors(mask):
    """8-이웃 개수를 픽셀별로 세는 벡터화된 연산 (scipy 의존성 없이 shift로 계산)."""
    m = mask.astype(np.uint8)
    padded = np.pad(m, 1, mode="constant")
    count = np.zeros_like(m, dtype=np.uint8)
    for dy, dx in _neighbor_offsets():
        count += padded[1 + dy: 1 + dy + m.shape[0], 1 + dx: 1 + dx + m.shape[1]]
    return count * m


def extract_paths_from_skeleton(skeleton, min_path_length=20):
    """
    skeleton(1px 중심선, 흰 배경+검은 선 0/255) 이미지에서 경로를 추출한다.

    단순히 cv2.findContours를 skeleton에 바로 쓰면 1픽셀 선의 "양쪽 테두리"를
    따라가면서 사실상 같은 선을 두 번 그리게 된다(로봇이 같은 선을 중복해서
    그리는 문제). 이를 피하기 위해 skeleton을 그래프로 보고, 끝점(neighbor
    count==1)과 분기점(neighbor count>=3)을 노드로, 그 사이의 1px 체인을
    edge(=하나의 path)로 추적하는 방식을 사용한다.

    복잡한 분기가 매우 많은 이미지에서는 완벽하지 않을 수 있는 휴리스틱이며,
    더 엄밀한 skeleton 그래프 분석이 필요하면 `skan` 패키지 사용을 고려할 것.

    반환값: [[(x, y), (x, y), ...], ...]  (path 별 픽셀 좌표 리스트)
    """
    mask = (skeleton == 0)
    if not mask.any():
        return []

    neighbor_count = _count_neighbors(mask)
    visited_interior = np.zeros_like(mask, dtype=bool)

    def get_neighbors(y, x):
        H, W = mask.shape
        result = []
        for dy, dx in _neighbor_offsets():
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and mask[ny, nx]:
                result.append((ny, nx))
        return result

    def walk(anchor, first):
        """anchor(끝점/분기점)에서 first 방향으로 다음 anchor까지 추적.

        고립된 폐곡선(원처럼 끝점/분기점이 하나도 없는 루프)의 경우 anchor
        자체도 neighbor_count==2일 수 있다. 이때는 다른 anchor를 만날 일이
        없으므로, 출발점(anchor)로 정확히 되돌아오면 루프를 닫고 종료한다.
        이 체크가 없으면 원형 곡선에서 무한 루프에 빠진다.
        """
        path = [anchor]
        prev, cur = anchor, first
        while True:
            path.append(cur)
            if cur == anchor:
                # 폐곡선을 한 바퀴 돌아 출발점으로 복귀 -> 종료
                break
            if neighbor_count[cur] != 2:
                # 다른 끝점/분기점에 도달 -> edge 종료
                break
            visited_interior[cur] = True
            nxts = [n for n in get_neighbors(*cur) if n != prev]
            if not nxts:
                break
            prev, cur = cur, nxts[0]
        return path

    ys, xs = np.where(mask)
    anchors = [(y, x) for y, x in zip(ys, xs) if neighbor_count[y, x] != 2]

    raw_paths = []
    seen_short_edges = set()  # 분기점끼리 바로 붙어있는 길이-1 edge 중복 방지용

    for a in anchors:
        for n in get_neighbors(*a):
            if visited_interior[n]:
                continue
            p = walk(a, n)
            if len(p) == 2:
                key = frozenset((p[0], p[1]))
                if key in seen_short_edges:
                    continue
                seen_short_edges.add(key)
            raw_paths.append(p)

    # 분기/끝점이 전혀 없는 고립된 폐곡선(원형 loop) 처리
    remaining_mask = mask & ~visited_interior
    for a in anchors:
        remaining_mask[a] = False
    ys2, xs2 = np.where(remaining_mask)
    handled = np.zeros_like(mask, dtype=bool)
    for y, x in zip(ys2, xs2):
        if handled[(y, x)] or visited_interior[y, x]:
            continue
        neighbors = get_neighbors(y, x)
        if not neighbors:
            continue
        loop = walk((y, x), neighbors[0])
        for py, px in loop:
            handled[py, px] = True
        raw_paths.append(loop)

    # (y, x) -> (x, y) 로 변환하고, 픽셀 기준 실제 길이로 필터링
    filtered = []
    for p in raw_paths:
        pts = [(x, y) for (y, x) in p]
        if len(pts) < 2:
            continue
        length = sum(
            np.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            for i in range(len(pts) - 1)
        )
        if length >= min_path_length:
            filtered.append(pts)

    return filtered


# =========================================================================
# 7. Path 단순화 (Douglas-Peucker)
# =========================================================================
def simplify_paths(paths, epsilon=1.5):
    """cv2.approxPolyDP(Douglas-Peucker)로 각 path의 점 개수를 줄인다."""
    simplified = []
    for pts in paths:
        arr = np.array(pts, dtype=np.float32).reshape(-1, 1, 2)
        approx = cv2.approxPolyDP(arr, epsilon, closed=False)
        simplified.append([(float(p[0][0]), float(p[0][1])) for p in approx])
    return simplified


# =========================================================================
# 8. Path 순서 최적화 (Nearest-Neighbor + 방향 reverse)
# =========================================================================
def optimize_path_order(paths):
    """
    현재 펜 위치에서 가장 가까운 다음 path를 그리도록 순서를 재배열한다.
    각 path는 시작점/끝점 중 더 가까운 쪽이 먼저 오도록 필요하면 뒤집는다.
    (완전한 TSP가 아닌 greedy nearest-neighbor 휴리스틱)
    """
    remaining = list(paths)
    if not remaining:
        return []

    ordered = []
    current_pos = np.array([0.0, 0.0])

    while remaining:
        best_idx, best_dist, best_reversed = None, None, False
        for i, pts in enumerate(remaining):
            start, end = np.array(pts[0]), np.array(pts[-1])
            d_start = np.linalg.norm(start - current_pos)
            d_end = np.linalg.norm(end - current_pos)
            if best_dist is None or min(d_start, d_end) < best_dist:
                if d_start <= d_end:
                    best_idx, best_dist, best_reversed = i, d_start, False
                else:
                    best_idx, best_dist, best_reversed = i, d_end, True

        chosen = remaining.pop(best_idx)
        if best_reversed:
            chosen = list(reversed(chosen))
        ordered.append(chosen)
        current_pos = np.array(chosen[-1])

    return ordered


# =========================================================================
# 9. 이미지 좌표 -> 로봇 mm 좌표 변환
# =========================================================================
def image_paths_to_robot_coords(paths, image_shape, drawing_width_mm,
                                 drawing_height_mm, margin_mm=10, flip_y=True):
    """
    이미지 픽셀 좌표(왼쪽 위 원점, y 아래로 증가) path들을
    로봇 작업 영역(mm) 좌표로 변환한다.

    - 그림 비율을 유지한 채 usable area(작업영역 - margin*2) 안에 맞추고
      중앙 정렬한다.
    - flip_y=True면 이미지 y축(아래로 증가)을 로봇 y축(보통 위로 증가)에
      맞게 반전한다. 실제 로봇 좌표계에 따라 켜고 끌 수 있다.
    """
    H, W = image_shape[:2]
    usable_w = drawing_width_mm - 2 * margin_mm
    usable_h = drawing_height_mm - 2 * margin_mm
    if usable_w <= 0 or usable_h <= 0:
        raise ValueError("margin_mm이 너무 커서 usable area가 없습니다.")

    scale = min(usable_w / W, usable_h / H)
    offset_x = margin_mm + (usable_w - W * scale) / 2.0
    offset_y = margin_mm + (usable_h - H * scale) / 2.0

    paths_mm = []
    for pts in paths:
        converted = []
        for px, py in pts:
            x_mm = offset_x + px * scale
            y_img_mm = offset_y + py * scale
            y_mm = (drawing_height_mm - y_img_mm) if flip_y else y_img_mm
            converted.append((round(float(x_mm), 3), round(float(y_mm), 3)))
        paths_mm.append(converted)

    return paths_mm


# =========================================================================
# 10. 저장: JSON / CSV / G-code
# =========================================================================
def save_paths_json(paths_mm, output_path):
    """[{"path_id": i, "points": [[x_mm, y_mm], ...]}, ...] 형태로 저장."""
    data = [
        {"path_id": i, "points": [[x, y] for x, y in pts]}
        for i, pts in enumerate(paths_mm)
    ]
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def save_paths_csv(paths_mm, output_path):
    """path_id, point_id, x_mm, y_mm, pen_state 컬럼의 CSV로 저장.

    pen_state: 각 path의 첫 점은 "up"(펜을 든 채 이동해서 도착하는 시작점),
    그 이후 점들은 "down"(펜을 대고 그리는 구간)으로 표기한다.
    """
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["path_id", "point_id", "x_mm", "y_mm", "pen_state"])
        for path_id, pts in enumerate(paths_mm):
            for point_id, (x, y) in enumerate(pts):
                pen_state = "up" if point_id == 0 else "down"
                writer.writerow([path_id, point_id, x, y, pen_state])


def save_gcode(paths_mm, output_path, feed_draw=800, feed_travel=1500):
    """
    간단한 G-code 스타일 텍스트로 저장한다.
    G0: 펜 업 상태 이동, M3: 펜 다운, G1: 펜 다운 상태 이동, M5: 펜 업.
    실제 로봇 제어기 명령 규격에 맞춰 나중에 얼마든지 바꿀 수 있는
    "중간 표현"으로 취급할 것.
    """
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("; robot pen-plotter path, auto-generated\n")
        for path_id, pts in enumerate(paths_mm):
            if not pts:
                continue
            f.write(f"; --- path {path_id} ---\n")
            x0, y0 = pts[0]
            f.write(f"G0 X{x0:.3f} Y{y0:.3f} F{feed_travel} ; pen up move\n")
            f.write("M3 ; pen down\n")
            for x, y in pts[1:]:
                f.write(f"G1 X{x:.3f} Y{y:.3f} F{feed_draw}\n")
            f.write("M5 ; pen up\n")


# =========================================================================
# 11. 시각화
# =========================================================================
def visualize_pipeline(original, gray, preprocessed, edge_binary, cleaned,
                        skeleton, final_paths_overlay, save_path=None):
    """파이프라인 각 단계 결과를 한 번에 보여준다."""
    images = [
        ("1. Original", cv2.cvtColor(original, cv2.COLOR_BGR2RGB), None),
        ("2. Grayscale", gray, "gray"),
        ("3. Preprocessed", preprocessed, "gray"),
        ("4. Edge/Binary", edge_binary, "gray"),
        ("5. Cleaned (morphology)", cleaned, "gray"),
        ("6. Skeleton (1px)", skeleton, "gray"),
        ("7. Final paths overlay", final_paths_overlay, None),
    ]

    fig, axes = plt.subplots(2, 4, figsize=(20, 10))
    axes = axes.ravel()
    for ax, (title, img, cmap) in zip(axes, images):
        ax.imshow(img, cmap=cmap)
        ax.set_title(title, fontsize=11)
        ax.axis("off")
    for ax in axes[len(images):]:
        ax.axis("off")

    plt.tight_layout()
    if save_path:
        fig.savefig(save_path, dpi=150, bbox_inches="tight")
    plt.show()


def draw_paths_overlay(shape, paths, background=None, color=(255, 0, 0), thickness=1):
    """추출된 path를 흰 배경(또는 지정한 background) 위에 그려서 반환한다."""
    if background is not None:
        canvas = background.copy()
        if canvas.ndim == 2:
            canvas = cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR)
    else:
        h, w = shape[:2]
        canvas = np.full((h, w, 3), 255, dtype=np.uint8)

    for pts in paths:
        for i in range(len(pts) - 1):
            p1 = tuple(int(round(v)) for v in pts[i])
            p2 = tuple(int(round(v)) for v in pts[i + 1])
            cv2.line(canvas, p1, p2, color, thickness, lineType=cv2.LINE_AA)

    return cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)


# =========================================================================
# 12. 전체 파이프라인 실행 함수
# =========================================================================
def process_image_for_robot_drawing(input_path, config):
    """
    사진 한 장을 받아 전체 파이프라인을 실행하고,
    결과 이미지/좌표 파일들을 config["output_dir"]에 저장한다.

    반환값: dict (중간 결과 + 최종 mm 좌표 paths 포함, 노트북에서
    추가로 확인/디버깅할 때 활용)
    """
    output_dir = config.get("output_dir", "output")
    os.makedirs(output_dir, exist_ok=True)

    # ---- 1. 로드 & 리사이즈 ----
    original_full = load_image(input_path)
    original = resize_keep_aspect(original_full, config["max_size"])

    # ---- 2. grayscale (시각화용 원본 grayscale) ----
    gray_raw = cv2.cvtColor(original, cv2.COLOR_BGR2GRAY)

    # ---- 3. 전처리 (blur + CLAHE) ----
    preprocessed = preprocess_image(
        original,
        blur_type=config.get("blur_type", "bilateral"),
        blur_strength=config.get("blur_strength", 7),
        use_clahe=config.get("use_clahe", True),
    )

    # ---- 4. 선 검출 (method에 따라 분기) ----
    method = config.get("method", "canny")
    if method == "canny":
        edge_binary = generate_edges_canny(
            preprocessed,
            low_threshold=config.get("canny_low", 50),
            high_threshold=config.get("canny_high", 150),
        )
    elif method == "adaptive":
        edge_binary = generate_edges_adaptive(
            preprocessed,
            block_size=config.get("adaptive_block_size", 21),
            C=config.get("adaptive_C", 8),
            median_blur_ksize=config.get("adaptive_median_blur", 3),
        )
    elif method == "xdog":
        edge_binary = generate_edges_xdog(
            preprocessed,
            sigma=config.get("xdog_sigma", 0.5),
            k=config.get("xdog_k", 1.6),
            gamma=config.get("xdog_gamma", 0.98),
            epsilon=config.get("xdog_epsilon", -0.5),
            phi=config.get("xdog_phi", 10),
        )
    else:
        raise ValueError(f"알 수 없는 method: {method}")

    # ---- 5. Morphology 정리 ----
    cleaned = clean_binary_image(
        edge_binary,
        kernel_size=config.get("morph_kernel_size", 3),
        open_iter=config.get("open_iter", 1),
        close_iter=config.get("close_iter", 1),
        dilate_iter=config.get("dilate_iter", 0),
        erode_iter=config.get("erode_iter", 0),
    )

    # ---- 6. Skeletonize ----
    skeleton = skeletonize_binary(cleaned)

    # ---- 7. Path 추출 (짧은 선 제거 포함) ----
    paths_px = extract_paths_from_skeleton(
        skeleton, min_path_length=config.get("min_path_length", 20)
    )

    # ---- 8. 단순화 (Douglas-Peucker) ----
    paths_px = simplify_paths(paths_px, epsilon=config.get("simplify_epsilon", 1.5))

    # ---- 9. (선택) 너무 복잡하면 긴 path 위주로 개수 제한 ----
    max_num_paths = config.get("max_num_paths")
    if max_num_paths is not None and len(paths_px) > max_num_paths:
        def path_len(pts):
            return sum(
                np.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
                for i in range(len(pts) - 1)
            )
        paths_px = sorted(paths_px, key=path_len, reverse=True)[:max_num_paths]

    # ---- 10. 그리기 순서 최적화 (nearest-neighbor) ----
    paths_px = optimize_path_order(paths_px)

    # ---- 11. 로봇 mm 좌표로 변환 ----
    paths_mm = image_paths_to_robot_coords(
        paths_px,
        image_shape=original.shape,
        drawing_width_mm=config.get("drawing_width_mm", 150),
        drawing_height_mm=config.get("drawing_height_mm", 150),
        margin_mm=config.get("margin_mm", 10),
        flip_y=config.get("flip_y", True),
    )

    # ---- 12. 시각화용 overlay 이미지 ----
    overlay_rgb = draw_paths_overlay(original.shape, paths_px)

    # ---- 13. 결과 저장 ----
    cv2.imwrite(os.path.join(output_dir, "result_binary.png"), cleaned)
    cv2.imwrite(os.path.join(output_dir, "result_skeleton.png"), skeleton)
    cv2.imwrite(
        os.path.join(output_dir, "result_paths_overlay.png"),
        cv2.cvtColor(overlay_rgb, cv2.COLOR_RGB2BGR),
    )
    save_paths_json(paths_mm, os.path.join(output_dir, "robot_paths.json"))
    save_paths_csv(paths_mm, os.path.join(output_dir, "robot_paths.csv"))
    save_gcode(
        paths_mm, os.path.join(output_dir, "optional_gcode.txt"),
        feed_draw=config.get("gcode_feed_draw", 800),
        feed_travel=config.get("gcode_feed_travel", 1500),
    )

    # ---- 14. 파이프라인 시각화 ----
    visualize_pipeline(
        original, gray_raw, preprocessed, edge_binary, cleaned, skeleton,
        overlay_rgb,
        save_path=os.path.join(output_dir, "pipeline_overview.png"),
    )

    num_points = sum(len(p) for p in paths_mm)
    print(f"[완료] path {len(paths_mm)}개, 총 점 {num_points}개")
    print(f"[완료] 결과 저장 위치: {os.path.abspath(output_dir)}")

    return {
        "original": original,
        "gray": gray_raw,
        "preprocessed": preprocessed,
        "edge_binary": edge_binary,
        "cleaned": cleaned,
        "skeleton": skeleton,
        "paths_px": paths_px,
        "paths_mm": paths_mm,
        "overlay_rgb": overlay_rgb,
    }


# =========================================================================
# 실행 예시
# =========================================================================
if __name__ == "__main__":
    input_path = "photo.jpg"  # 실제 사진 경로로 바꿔서 사용

    CONFIG_EXAMPLE = dict(CONFIG)  # 기본 CONFIG를 복사해서 필요한 값만 덮어써도 됨
    CONFIG_EXAMPLE.update({
        "method": "canny",
        "max_size": 800,
        "blur_type": "bilateral",
        "blur_strength": 7,
        "use_clahe": True,
        "canny_low": 50,
        "canny_high": 150,
        "adaptive_block_size": 21,
        "adaptive_C": 8,
        "morph_kernel_size": 3,
        "open_iter": 1,
        "close_iter": 1,
        "min_path_length": 20,
        "simplify_epsilon": 1.5,
        "drawing_width_mm": 150,
        "drawing_height_mm": 150,
        "margin_mm": 10,
        "flip_y": True,
    })

    if os.path.exists(input_path):
        result = process_image_for_robot_drawing(input_path, CONFIG_EXAMPLE)
    else:
        print(f"'{input_path}' 파일이 없습니다. input_path를 실제 사진 경로로 바꿔서 실행하세요.")
