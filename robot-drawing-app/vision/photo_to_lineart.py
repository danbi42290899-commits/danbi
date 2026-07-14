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


# =========================================================================
# 1. 파일 선택 / 이미지 로드 / 리사이즈
# =========================================================================
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


# =========================================================================
# 2. 공통 유틸
# =========================================================================
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


# =========================================================================
# 3. lineart 모드: 검은 선 자체 추출
# =========================================================================
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


# =========================================================================
# 4. photo 모드: 실제 사진에서 Canny 윤곽선 추출
# =========================================================================
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


# =========================================================================
# 5. 곡선 직선화
# =========================================================================
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


# =========================================================================
# 6. 저장 / 시각화
# =========================================================================
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


# =========================================================================
# 7. 실행부
# =========================================================================
if __name__ == "__main__":
    input_path = select_image_file()
    result = process_image(input_path, CONFIG)
