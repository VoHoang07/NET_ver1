"""Render từng tư thế và in silhouette, độc lập với test.

Chạy:
    python3 tools/render_each_pose.py [pose-id ...]

Không tham số = render cả sáu.

Cách làm: dựng đúng cảnh của app (ARView nonAR), chụp snapshot(),
rồi in silhouette theo hàng — chữ `#` là pixel thuộc bóng người.
Đây là thứ người dùng thấy trên màn hình, không phải suy diễn từ file.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import objc  # noqa: E402

# Xcode không sinh Swift cho script Python; cần dựng qua xcodebuild test.
# Nên script này chỉ in lệnh cần chạy + phân tích ảnh PNG nếu có.

import subprocess  # noqa: E402
import json  # noqa: E402
import glob  # noqa: E402
import os  # noqa: E402


def latest_xcresult():
    pattern = os.path.expanduser(
        "~/Library/Developer/Xcode/DerivedData/NET_ver1-*/Logs/Test/*.xcresult"
    )
    return max(glob.glob(pattern), key=os.path.getmtime)


def failure_messages(path):
    raw = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path],
        capture_output=True, text=True,
    ).stdout
    out = []

    def walk(node):
        if isinstance(node, dict):
            if node.get("nodeType") == "Failure Message":
                out.append(node.get("name", ""))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(json.loads(raw))
    return out


MARK = "Hinh dang (dau # la bong nguoi):"


def main():
    result = latest_xcresult()
    for message in failure_messages(result):
        text = message.replace("\\n", "\n")
        if MARK not in text:
            continue
        head, body = text.split(MARK)
        body = body.split("|||")[0]
        print(head.rstrip())
        print(body.rstrip())
        print()


if __name__ == "__main__":
    main()
