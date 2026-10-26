"""Chụp màn hình app và vẽ bóng người 3D bằng chữ, để **nhìn** thay vì đo.

Chạy:
    python3 tools/ascii_screenshot.py <anh.png> [--top 0.25 --bottom 0.65] [--rows 22]

## Vì sao cần

Đo bằng số cho biết "có bao nhiêu pixel đúng màu", nhưng không cho biết **hình dạng
gì**. Ba lỗi đã xảy ra đều là lỗi hình dạng, và cả ba đều lọt qua mọi phép đo:

  * camera lộn ngược — đầu ở dưới, chân ở trên
  * người bị cắt cụt — chiều cao mesh vẫn đúng, chỉ bị cắt trong khung
  * bàn hiện thay người — vì người nằm sai trục Z nên lọt khỏi khung

In ra hình bóng bằng chữ là bước nhìn duy nhất bắt được cả ba.

## Chọn vùng xem

Mặc định lấy 25%–65% chiều cao ảnh — đó là **khung nhìn**, nơi người 3D phải nằm.
Số liệu đo cho thấy phần dưới ảnh là UI của app: màu `netGreen` (72, 110, 83) chiếm
59.374 px, trùng khớp với "bóng xanh" mà phép đo tưởng là người 3D. Đo nhầm vùng thì
báo xanh ở khi app vốn không hiện người.
"""

import argparse

from PIL import Image


def warm(pixel):
    r, g, b = (c / 255 for c in pixel)
    return r > 0.12 and r - b > 0.10 and r > g + 0.15


def silhouette(image, top, bottom, rows, columns):
    width, height = image.size
    crop = image.crop((0, int(height * top), width, int(height * bottom)))
    cell_h = max(crop.size[1] // rows, 1)
    cell_w = max(crop.size[0] // columns, 1)

    lines = []
    for row in range(rows):
        line = ""
        for column in range(columns):
            hits = 0
            total = 0
            for y in range(row * cell_h, min((row + 1) * cell_h, crop.size[1])):
                for x in range(column * cell_w, min((column + 1) * cell_w, crop.size[0])):
                    total += 1
                    if warm(crop.getpixel((x, y))):
                        hits += 1
            ratio = hits / total if total else 0
            line += "#" if ratio > 0.5 else ("+" if ratio > 0.15 else ".")
        lines.append(line)
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--top", type=float, default=0.25)
    parser.add_argument("--bottom", type=float, default=0.65)
    parser.add_argument("--rows", type=int, default=22)
    parser.add_argument("--columns", type=int, default=20)
    args = parser.parse_args()

    image = Image.open(args.image).convert("RGB")
    lines = silhouette(image, args.top, args.bottom, args.rows, args.columns)

    print(f"{args.image}  {image.size[0]}x{image.size[1]}")
    print(f"khung xem: {args.top:.0%} .. {args.bottom:.0%} chieu cao   (dau # la bong nguoi)")
    for index, line in enumerate(lines):
        print(f"{index:2d}|{line}|")


if __name__ == "__main__":
    main()