"""Chụp màn hình app trên simulator và **nhìn** bằng bảng chữ màu.

Chạy:
    python3 tools/look_at_app.py [--crop x0 y0 x1 y1] [--rows 46] [--cols 84]

## Vì sao cần

Ưu tiên 1 là xác minh người 3D **bằng mắt** trên thiết bị thật. Trên máy thật
thì chưa làm được, nhưng simulator vẫn chạy được RealityKit — nên đây là bước gần
nhất có thể: nhìn app thật, đúng nhánh code đang chạy, thay vì tin số đo.

Nhìn bằng **bảng chữ màu**, không phải đo. Bảng không khẳng định điều gì — nó đặt
hình trước mắt để người đọc tự kết luận.

## Chế độ sáng

Lệnh `--light` chuyển simulator sang giao diện sáng. Không phải tuỳ thẩm mỹ:
simulator mặc định tối, mà phần lớn ứng dụng iPhone chạy trên nền sáng. Ảnh chụp
trong chế độ tối là **không đại diện** cho cách dùng thật, nên kết luận rút ra từ
đó cũng không đại diện.
"""

import argparse
import subprocess
import sys

SIM = "06424DC9-DCA2-4D13-B170-7D5C6303A02E"
BUNDLE = "vn.net.camera"
SHOT = "/tmp/net3d/look.png"
ASCII_TOOL = "tools/ascii_screenshot.py"


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--crop", nargs=4, type=int)
    parser.add_argument("--rows", type=int, default=46)
    parser.add_argument("--cols", type=int, default=84)
    parser.add_argument("--light", action="store_true")
    args = parser.parse_args()

    if args.light:
        sh("xcrun", "simctl", "ui", SIM, "appearance", "light")

    sh("xcrun", "simctl", "launch", SIM, BUNDLE)
    # Cho thời gian RealityKit nạp asset và camera mở.
    subprocess.run(["sleep", "7"], check=True)
    shot = sh("xcrun", "simctl", "io", SIM, "screenshot", SHOT)
    sh("xcrun", "simctl", "terminate", SIM, BUNDLE)
    if not SHOT or "Wrote screenshot" not in shot.stderr:
        print(shot.stderr[-500:])
        raise SystemExit("khong chup duoc man hinh")

    command = [sys.executable, ASCII_TOOL, SHOT, str(args.rows), str(args.cols)]
    if args.crop:
        command += ["--crop", *map(str, args.crop)]
    # Bảng chữ phải **nhìn** được — in thẳng ra terminal, không nuốt vào buffer.
    subprocess.run(command, check=True)


main()
