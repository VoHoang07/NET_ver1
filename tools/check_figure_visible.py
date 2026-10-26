"""Kiểm cảnh 3D có **thật sự hiện** trong app không, bằng ảnh đã chụp màn hình.

Chạy:
    python3 tools/check_figure_visible.py <anh.png> [--crop 0.25:0.80]

## Vì sao cần

Cứ xây xong là "xong" — đó là sai lầm đã lặp lại: số đo cho thấy model đúng chiều,
test xanh, build sạch, nhưng **chưa ai nhìn**. Riêng lần này, chỉ nhìn ảnh render mới
thấy hai lỗi mà mọi phép đo khác đều bỏ qua:

  * `standing-aside` không hiện gì — người nằm lệch 3,4 m sang bên và 3,7 m ra sau
    trong file USDZ, nên trượt khỏi khung.
  * `seated-straight` chỉ hiện **bàn**, không thấy người.

## Phân biệt bóng người với nền

Màu là thứ app **tự quyết định**: `FigureMaterial.guide` là cam khi chưa khớp,
`.aligned` là xanh lá khi đã khớp. Nhưng vật liệu pha trộn với cảnh camera phía sau
ở alpha 0,30 rồi nhân với ánh sáng, nên **màu đo được không bao giờ bằng màu gốc**:

    màu gốc (255, 115, 51)  ->  đo được (214, 97, 79) trên nền tối

Nên phải so theo **quan hệ giữa các kênh** — đỏ rõ hơn xanh dương thì là bóng cam,
xanh lá rõ hơn đỏ thì là bóng xanh — chứ so sát màu gốc thì luôn ra 0 và báo đỏ
nhầm trên một hình đang hiện đúng.

## Vì sao không đo hình dạng

Hình dạng thì phụ thuộc phối cảnh: người thật có thể che bóng, tư thế ngồi khác
tư thế đứng, nền sáng nền tối. Màu thì do app tự quyết định nên ổn định hơn. Muốn
xem hình dạng thì dùng `tools/ascii_screenshot.py`.
"""

import argparse
import sys

from PIL import Image

# Ngưỡng nhận diện, chọn theo đặc tính vật liệu chứ không phải đoán:
#   cam   -> đỏ rõ hơn xanh dương 0.12 và rõ hơn xanh lá 0.10
#   xanh  -> xanh lá rõ hơn đỏ 0.06 và rõ hơn xanh dương 0.04
# Khoảng cách giữa cam và xanh lá trên ảnh thật là ~0.35, nên hai điều kiện này không
# bao giờ cùng đúng với một pixel.
WARM_RED, WARM_BLUE, WARM_GREEN = 0.12, 0.10, 0.20
GREEN_GREEN, GREEN_RED, GREEN_BLUE = 0.06, 0.06, 0.04


def is_warm(pixel):
    r, g, b = (c / 255 for c in pixel)
    return r > WARM_RED and r - b > WARM_BLUE and r > g + WARM_GREEN


def is_green(pixel):
    r, g, b = (c / 255 for c in pixel)
    return g > GREEN_GREEN and g - r > GREEN_RED and g - b > GREEN_BLUE


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument(
        "--crop",
        default="0.25:0.80",
        help="vùng cần xem, dạng tỉ lệ chiều cao ảnh (mặc định: khung nhìn)",
    )
    args = parser.parse_args()

    top, bottom = (float(v) for v in args.crop.split(":"))
    image = Image.open(args.image).convert("RGB")
    width, height = image.size
    crop = image.crop((0, int(height * top), width, int(height * bottom)))

    warm = green = 0
    for pixel in crop.getdata():
        if is_warm(pixel):
            warm += 1
        elif is_green(pixel):
            green += 1

    print(f"{args.image}  {width}x{height}")
    print(f"  khung xem: {crop.size}  ({int(height*top)} .. {int(height*bottom)})")
    print(f"  cam (dang huong dan)  : {warm:>8} px")
    print(f"  xanh (da dung vi tri) : {green:>8} px")

    total = warm + green
    if total > 500:
        share = 100.0 * total / (crop.size[0] * crop.size[1])
        print(f"  => CO BONG NGUOI ({share:.1f}% khung, mau {total} px)")
        return 0
    if total > 0:
        print("  => chi vai pixel le — co the chi la UI, khong con lai la bong nguoi")
    else:
        print("  => KHONG co bong nguoi tren man hinh")
    return 1


if __name__ == "__main__":
    sys.exit(main())