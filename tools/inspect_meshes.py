"""Đo **từng mesh riêng** trong file USDZ, không gộp chung.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/inspect_meshes.py

## Vì sao phải tách từng mesh

File nướng ra có hai mesh: `Beta_Surface` (da) và `Beta_Joints` (xương). Gộp cả hai
rồi đo thì kết quả là **hình bao của cả hai**, tức hình hộp bao quanh cả người lẫn
bộ xương bên trong. Đó chính là lỗi đã mắc phải: đo bằng cách cộng dồn da và
xương rồi kết luận tư thế bị lộn ngược — trong khi bóng dạng chữ cho thấy cả hai đều
đúng.

Mesh xương nằm **bên trong** mesh da, nên gộp chung vẫn ra hình bao gần giống da.
Nhưng nếu xương bị kéo lệch (do tư thế riêng của nó), hình bao chung sẽ sai — và ta
không biết sai ở đâu. Đo từng cái thì thấy ngay.

## Cách đọc kết quả

- `Beta_Surface` là thứ app hiển thị. Số đo của nó mới là số đo của người 3D.
- `Beta_Joints` là bộ xương. Nếu nó lệch so với da thì tư thế bị nướng sai.
"""

import os
import tempfile
import zipfile

from pxr import Usd, UsdGeom, Gf

ASSET_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources"
)


def usd_file_in(usdz_path):
    tmp = tempfile.mkdtemp(prefix="net3d-mesh-")
    with zipfile.ZipFile(usdz_path) as archive:
        names = [n for n in archive.namelist() if n.endswith((".usda", ".usdc", ".usd"))]
        archive.extract(names[0], tmp)
    return os.path.join(tmp, names[0])


def report(usdz_path):
    stage = Usd.Stage.Open(usd_file_in(usdz_path))
    meters = float(UsdGeom.GetStageMetersPerUnit(stage) or 1.0)
    up = "XYZ".index(str(UsdGeom.GetStageUpAxis(stage)).upper())

    print(f"\n##### {os.path.basename(usdz_path)}   (metre/unit = {meters})")

    for prim in stage.Traverse():
        mesh = UsdGeom.Mesh(prim)
        if not mesh:
            continue
        matrix = UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
        pts = [matrix.Transform(Gf.Vec3d(p)) for p in (mesh.GetPointsAttr().Get() or [])]
        if not pts:
            continue

        lows = [min(p[a] for p in pts) * meters for a in range(3)]
        highs = [max(p[a] for p in pts) * meters for a in range(3)]
        spans = [highs[a] - lows[a] for a in range(3)]

        print(f"    {prim.GetPath().name:16s} dinh={len(pts):6d}")
        for a, axis in enumerate("XYZ"):
            mark = "  <- truc dung" if a == up else ""
            print(f"        {axis}: [{lows[a]:8.3f} .. {highs[a]:8.3f}]  dai={spans[a]:6.3f}{mark}")
        tall = max((a for a in range(3) if a != up), key=lambda a: spans[a])
        print(
            f"        cao/rong = {spans[up] / max(spans[tall], 1e-9):5.2f}"
            f"   (truc rong nhat = {'XYZ'[tall]})"
        )


for filename in sorted(os.listdir(ASSET_DIR)):
    if filename.endswith(".usdz"):
        report(os.path.join(ASSET_DIR, filename))
