"""Xác định hướng đầu-người của model, bằng số đo thay vì nhìn.

Vì sao cần: "đứng hay nằm" là câu hỏi về **hình dạng**, không phải kích thước.
File có chiều cao lớn ở một trục thì vẫn có thể là người nằm ngửa, hoặc lộn ngược.

Cách đo: người đứng thì **hẹp nhất ở đầu** (cổ), và phần hẹp đó nằm ở **trên**.
Đo bề rộng ngang theo từng đoạn chiều cao — đoạn hẹp nhất chính là cổ/đầu.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/head_finder.py
"""

import os
import tempfile

import bpy

ASSET_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources"
)

BANDS = 24


def load_mesh(usdz_path):
    """Trả về danh sách đỉnh của **mọi** mesh trong file.

    - Important: mỗi file giải nén vào thư mục **riêng**. Bản đầu dùng chung một
      thư mục rồi lấy `listdir()[0]`, nên từ file thứ hai trở đi nó vẫn trả về file
      của lần trước — cả 6 tư thế cho cùng một kết quả, và tôi tưởng asset bị trùng.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)

    with tempfile.TemporaryDirectory() as tmp:
        if os.system(f'unzip -o -q "{usdz_path}" -d "{tmp}"') != 0:
            return []
        usd_files = [f for f in os.listdir(tmp) if f.endswith((".usda", ".usdc"))]
        if not usd_files:
            return []

        bpy.ops.wm.usd_import(filepath=os.path.join(tmp, usd_files[0]))
        points = []
        for obj in bpy.data.objects:
            if obj.type != "MESH":
                continue
            matrix = obj.matrix_world
            for vertex in obj.data.vertices:
                world = matrix @ vertex.co
                points.append((world.x, world.y, world.z))
        return points


def report(points, pose_id):
    if not points:
        print(f"{pose_id}: doc that bai")
        return

    spans = [
        max(p[i] for p in points) - min(p[i] for p in points)
        for i in range(3)
    ]
    # Trục đứng là trục dài nhất — đó là điều duy nhất chắc chắn từ kích thước.
    upright = spans.index(max(spans))
    height = spans[upright]
    horizontal = [i for i in range(3) if i != upright]
    across, depth = horizontal

    print(f"\n=== {pose_id}  truc dung = {'XYZ'[upright]}  cao={height:.3f} ===")

    lo = min(p[upright] for p in points)
    narrowest = (None, 1e9)
    widths = []
    for band in range(BANDS):
        low = lo + height * band / BANDS
        high = lo + height * (band + 1) / BANDS
        slice_points = [p for p in points if low <= p[upright] < high]
        if not slice_points:
            continue
        width = max(p[across] for p in slice_points) - min(p[across] for p in slice_points)
        widths.append((band / BANDS, width))
        if width < narrowest[1]:
            narrowest = (band / BANDS, width)

    # In dạng thanh để nhìn: thanh ngắn = hẹp.
    print("  0.00 = day chan, 1.00 = dinh dau")
    for fraction, width in widths:
        print(f"  {fraction:4.2f}  rong={width:5.3f}  {'#' * int(width * 60)}")

    top_fraction = narrowest[0]
    where = "DAU o tren" if top_fraction > 0.7 else "DAU o duoi (LON NGUOC)"
    print(f"  -> phan hep nhat tai {top_fraction:.2f}  => {where}")


for filename in sorted(os.listdir(ASSET_DIR)):
    if filename.endswith(".usdz"):
        report(load_mesh(os.path.join(ASSET_DIR, filename)), filename[len("pose-"):-len(".usdz")])