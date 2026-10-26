"""Đọc trực tiếp file USDZ cuối cùng và in ra: hệ toạ độ, kích thước, hình bóng.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/inspect_poses.py

## Vì sao đọc thẳng bằng `pxr` thay vì cho Blender import rồi đo

`tools/preview_poses.py` cho Blender import USDZ rồi đo `matrix_world`. Blender
tự **đổi hệ** lúc import (USD Y-up → Blender Z-up), nên `world.y` trong kết quả
không phải trục đứng của file mà là trục **chiều sâu**. Script đó in
`rong=0.51 cao=0.41` cho dáng đứng — "thấp hơn rộng" — và nhìn vào đó ai cũng
kết luận người nằm ngang, trong khi người vẫn đứng thẳng.

Đó đúng là cái bẫy đã ghi trong nhật ký: đo bằng công cụ đọc sai hệ toạ độ rồi
tin số đo.

Ở đây không qua bước đổi hệ nào: `UsdGeom` trả toạ độ **đúng như trong file**, kèm
`metersPerUnit` và `upAxis` viết ngay trong file. Số in ra là số thật.

## Vì sao in hình bóng

Số đo phân biệt được "ngồi" với "đứng" nhưng **không** phân biệt được "đầu ở trên"
với "đầu ở dưới" — hai trường hợp đó có cùng ba con số X/Y/Z. Hình bóng là thứ
nhìn được bằng mắt, và chữ ký "bài sai là không nhìn thấy bằng mắt" đã xảy ra
đúng một lần rồi.
"""

import os
import tempfile
import zipfile

from pxr import Usd, UsdGeom, Gf

ASSET_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources"
)

WIDTH = 64
HEIGHT = 36


def usd_file_in(usdz_path):
    """Trả về đường dẫn tới file `.usd` bên trong `.usdz` (giải nén ra tạm)."""
    tmp = tempfile.mkdtemp(prefix="net3d-inspect-")
    with zipfile.ZipFile(usdz_path) as archive:
        names = [n for n in archive.namelist() if n.endswith((".usda", ".usdc", ".usd"))]
        if not names:
            raise SystemExit(f"{usdz_path}: khong co file USD ben trong")
        archive.extract(names[0], tmp)
    return os.path.join(tmp, names[0])


def world_points(stage):
    """Mọi đỉnh mesh, đã đưa về **world space** của file.

    - Important: `UsdGeom.PointBased` đọc điểm là **local**. Prim cha có thể mang
      `xformOp` riêng — đọc thẳng điểm mà bỏ qua `transformMatrix` là lỗi đã mắc
      phải một lần. Ở đây nhân qua `UsdGeom.Xformable(prim).ComputeLocalToWorldTransform`.
    """
    points = []
    names = []
    for prim in stage.Traverse():
        mesh = UsdGeom.Mesh(prim)
        if not mesh:
            continue
        matrix = UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
        pts = mesh.GetPointsAttr().Get() or []
        for p in pts:
            world = matrix.Transform(Gf.Vec3d(p))
            points.append((world[0], world[1], world[2]))
        names.append(prim.GetPath().name)
    return points, names


def profile(points, up_axis, bins=16):
    """Bề rộng lớn nhất theo từng lát chiều cao — đọc đầu/vai/hông bằng số.

    Trả về danh sách `(từ_trên_0_đến_1, bề_rộng)`. Lát trên cùng là **đầu** nếu
    model đúng chiều, và sẽ hẹp; lát dưới là **chân**, cũng hẹp, còn giữa là
    vai/hông, rộng nhất. Ba đỉnh hình "bình hành – rộng – hẹp" đó là dấu hiệu
    người đang đứng/ngồi đúng chiều.
    """
    heights = [p[up_axis] for p in points]
    lo, hi = min(heights), max(heights)
    span = max(hi - lo, 1e-9)
    other = [a for a in range(3) if a != up_axis]

    widths = []
    for i in range(bins):
        t0 = lo + span * i / bins
        t1 = lo + span * (i + 1) / bins
        slab = [p for p in points if t0 <= p[up_axis] < t1 or (i == bins - 1 and p[up_axis] == hi)]
        if not slab:
            widths.append(0.0)
            continue
        widths.append(max(max(p[a] for p in slab) - min(p[a] for p in slab) for a in other))
    return widths, span


def print_silhouette(points, up_axis, cross_axis, title):
    """Hình bóng: trục đứng lấy đúng trục của file, không đoán."""
    verticals = [p[up_axis] for p in points]
    horizontals = [p[cross_axis] for p in points]
    vlo, vhi = min(verticals), max(verticals)
    hlo, hhi = min(horizontals), max(horizontals)
    vspan = max(vhi - vlo, 1e-9)
    hspan = max(hhi - hlo, 1e-9)

    grid = [[" "] * WIDTH for _ in range(HEIGHT)]
    for point in points:
        col = int((point[cross_axis] - hlo) / hspan * (WIDTH - 1))
        row = HEIGHT - 1 - int((point[up_axis] - vlo) / vspan * (HEIGHT - 1))
        grid[row][col] = "#"

    print(f"\n=== {title} ===")
    print(
        f"    truc dung = {'XYZ'[up_axis]}   rong({('XYZ')[cross_axis]}) = {hspan:.3f}"
        f"   cao = {vspan:.3f}"
    )
    for row in grid:
        print("    " + "".join(row).rstrip())


def inspect(usdz_path):
    path = usd_file_in(usdz_path)
    stage = Usd.Stage.Open(path)
    points, names = world_points(stage)

    # `GetStageUpAxis` trả `TfToken`, không phải `str` — phải ép kiểu rồi mới
    # đánh chỉ mục "XYZ" được.
    meters = UsdGeom.GetStageMetersPerUnit(stage) or 1.0
    up_axis = str(UsdGeom.GetStageUpAxis(stage)).upper()

    scale = float(meters)
    pts = [(p[0] * scale, p[1] * scale, p[2] * scale) for p in points]

    spans = [(max(p[a] for p in pts) - min(p[a] for p in pts)) for a in range(3)]
    lows = [min(p[a] for p in pts) for a in range(3)]

    up = "XYZ".index(up_axis)
    cross = max((i for i in range(3) if i != up), key=lambda i: spans[i])

    title = os.path.basename(usdz_path)
    print(f"\n##### {title}")
    print(f"    metersPerUnit = {meters}   upAxis = {up_axis}   mesh = {names}")
    for i, axis in enumerate("XYZ"):
        print(
            f"    {axis}: [{lows[i] * scale:8.3f} .. {(lows[i] + spans[i]) * scale:8.3f}]"
            f"   dai={spans[i] * scale:.3f}"
        )

    widths, span = profile(pts, up)
    print("    be rong theo lat chieu cao (0 = tren dinh):")
    print("      " + "  ".join(f"{i * 6.25:4.1f}:{w:5.2f}" for i, w in enumerate(widths)))

    # Trục ngang là trục **rộng nhất** còn lại: bề ngang vai lớn hơn chiều sâu
    # ngực–bụng, nên chọn theo tổng bề rộng sẽ ra đúng góc nhìn người đang đứng
    # (chính diện hoặc chếch), thay vì chọn nhầm mặt bên.
    print_silhouette(pts, up, cross, title)


for filename in sorted(os.listdir(ASSET_DIR)):
    if filename.endswith(".usdz"):
        inspect(os.path.join(ASSET_DIR, filename))
