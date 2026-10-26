"""Đo kích thước thật của file `.usdz` đang đóng gói trong app.

Chạy:
    usdcat <file>.usdc > <out>.usda   rồi chạy script này

Vì sao cần: `visualBounds` của RealityKit và phép đo trong Blender cho ra hai con
số khác nhau (0,41–0,89 mét so với 1,70 mét). Khi hai nguồn số liệu lệch nhau thì
phải đo trực tiếp file cuối cùng thay vì tin bên nào.
"""

import os
import re
import subprocess
import sys
import tempfile

ASSET_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources"
)


def measure(usdz_path):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["unzip", "-q", usdz_path, "-d", tmp], check=True)
        usd_files = [f for f in os.listdir(tmp) if f.endswith((".usda", ".usdc"))]
        if not usd_files:
            print(f"  {os.path.basename(usdz_path):32s} KHONG DOC DUOC")
            return

        text = subprocess.run(
            ["usdcat", os.path.join(tmp, usd_files[0])],
            capture_output=True, text=True,
        ).stdout

    units = re.search(r'metersPerUnit = ([0-9.]+)', text)
    up = re.search(r'upAxis = "(\w)"', text)
    scale = float(units.group(1)) if units else 1.0
    axis = up.group(1) if up else "?"

    extents = []
    for block in re.findall(r'point3f\[\] points = \[(.*?)\]', text, re.S):
        values = re.findall(r'\((-?[0-9.e]+), (-?[0-9.e]+), (-?[0-9.e]+)\)', block)
        if not values:
            continue
        for idx, name in ((0, "X"), (1, "Y"), (2, "Z")):
            column = [float(v[idx]) * scale for v in values]
            extents.append((name, min(column), max(column), max(column) - min(column)))

    print(f"  {os.path.basename(usdz_path):32s} units={scale} up={axis}")
    for name, low, high, span in extents:
        print(f"      {name}: [{low:8.3f} .. {high:8.3f}]  cao={span:.3f}")


for filename in sorted(os.listdir(ASSET_DIR)):
    if filename.endswith(".usdz"):
        measure(os.path.join(ASSET_DIR, filename))