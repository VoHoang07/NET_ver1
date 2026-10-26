"""Vẽ từng tư thế bằng **chữ**, từ nhiều góc nhìn.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/preview_poses.py

## Vì sao lại vẽ lại

`preview_poses.py` cũ cho Blender import USDZ rồi đo `matrix_world`. Blender tự đổi
hệ lúc import, nên trục đứng của file **không còn là trục đứng** trong kết quả, và
hình in ra bị đọc sai — tưởng người nằm ngang.

Bản này đọc thẳng bằng `pxr` (đúng hệ toạ độ ghi trong file) và in **nhiều góc**:
chính diện, chếch, và mặt bên. Một dáng chỉ đúng ở một góc thì không phải là người
đứng vững — chân và tay phải đúng ở mọi góc.

Đây là bước **nhìn**, không phải đo. Số đo không phân biệt được "đầu trên" với "đầu
dưới"; hình thì có.
"""

import math
import os
import tempfile
import zipfile

from pxr import Usd, UsdGeom, Gf

ASSET_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources"
)

WIDTH = 58
HEIGHT = 30
VIEWS = [("chinh dien", 0.0), ("chec 30 do", 30.0), ("mep 90 do", 90.0)]


def usd_file_in(usdz_path):
    tmp = tempfile.mkdtemp(prefix="net3d-preview-")
    with zipfile.ZipFile(usdz_path) as archive:
        names = [n for n in archive.namelist() if n.endswith((".usda", ".usdc", ".usd"))]
        archive.extract(names[0], tmp)
    return os.path.join(tmp, names[0])


def points_of(usdz_path):
    stage = Usd.Stage.Open(usd_file_in(usdz_path))
    index = "XYZ".index(str(UsdGeom.GetStageUpAxis(stage)).upper())
    points = []
    for prim in stage.Traverse():
        mesh = UsdGeom.Mesh(prim)
        if not mesh:
            continue
        matrix = UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
        for p in mesh.GetPointsAttr().Get() or []:
            points.append(matrix.Transform(Gf.Vec3d(p)))
    return points, index


def rotated(points, index, degrees):
    """Xoay quanh trục đứng — mô phỏng góc nhìn quanh người.

    Trả về điểm dạng `(ngang, day, cao)` để `print_view` không cần biết trục nào là
    trục đứng của file.
    """
    radians = degrees * math.pi / 180
    cos, sin = math.cos(radians), math.sin(radians)
    other = [a for a in range(3) if a != index]
    return [
        (p[other[0]] * cos - p[other[1]] * sin, p[other[0]] * sin + p[other[1]] * cos, p[index])
        for p in points
    ]


def print_view(points, title):
    """`points` đã ở dạng `(ngang, day, cao)`."""
    lo = min(p[2] for p in points)
    hi = max(p[2] for p in points)
    vspan = max(hi - lo, 1e-9)
    widths = [
        max(p[0] for p in points) - min(p[0] for p in points),
        max(p[1] for p in points) - min(p[1] for p in points),
    ]
    horizontal = 0 if widths[0] >= widths[1] else 1
    hspan = max(widths[horizontal], 1e-9)
    hlo = min(p[horizontal] for p in points)

    grid = [[" "] * WIDTH for _ in range(HEIGHT)]
    for point in points:
        col = int((point[horizontal] - hlo) / hspan * (WIDTH - 1))
        row = HEIGHT - 1 - int((point[2] - lo) / vspan * (HEIGHT - 1))
        grid[row][col] = "#"

    print(f"\n  -- {title} (cao={vspan:.2f} rong={hspan:.2f}) --")
    for row in grid:
        print("  |" + "".join(row).rstrip())


for filename in sorted(os.listdir(ASSET_DIR)):
    if not filename.endswith(".usdz"):
        continue
    pose_id = filename[len("pose-"):-len(".usdz")]
    points, up = points_of(os.path.join(ASSET_DIR, filename))
    if not points:
        print(f"\n##### {pose_id}: KHONG DOC DUOC")
        continue
    print(f"\n##### {pose_id}")
    for label, degrees in VIEWS:
        print_view(rotated(points, up, degrees), label)
