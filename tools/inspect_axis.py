"""Kiểm tra hệ toạ độ thực tế của file `.usdz`, không đoán qua số liệu gián tiếp.

Câu hỏi: sau khi USD khai `upAxis = "Y"`, **hình học thực sự nằm theo hệ nào**?

- Nếu RealityKit dùng luôn trục Y thì hình học phải nằm ngay trên trục Y.
- Nếu RealityKit áp thêm phép xoay theo `upAxis` thì hình học vẫn nằm trên Z là
  đúng, và phép xoay ở prim gốc là cần thiết.

Đo bằng cách lấy đỉnh đã qua **world matrix** (tức đã bao gồm xoay của prim cha).

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/inspect_axis.py
"""

import os
import tempfile

import bpy

ASSET_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources"
)


def axis_report(usdz_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)

    with tempfile.TemporaryDirectory() as tmp:
        if os.system(f'unzip -o -q "{usdz_path}" -d "{tmp}"') != 0:
            return None
        usd_files = [f for f in os.listdir(tmp) if f.endswith((".usda", ".usdc"))]
        if not usd_files:
            return None
        bpy.ops.wm.usd_import(filepath=os.path.join(tmp, usd_files[0]))

        local = []
        world = []
        for obj in bpy.data.objects:
            if obj.type != "MESH":
                continue
            for vertex in obj.data.vertices:
                local.append(tuple(vertex.co))
                world.append(tuple(obj.matrix_world @ vertex.co))

    return local, world


def spans(points, index):
    values = [p[index] for p in points]
    return max(values) - min(values)


for filename in sorted(os.listdir(ASSET_DIR)):
    if not filename.endswith(".usdz"):
        continue

    pose_id = filename[len("pose-"):-len(".usdz")]
    result = axis_report(os.path.join(ASSET_DIR, filename))
    if result is None:
        print(f"{pose_id}: doc that bai")
        continue

    local, world = result
    print(f"\n{pose_id}  ({len(world)} dinh)")
    print(f"  raw (chua ap xoay)      X={spans(local,0):.3f}  Y={spans(local,1):.3f}  Z={spans(local,2):.3f}")
    print(f"  world (da ap xoay)      X={spans(world,0):.3f}  Y={spans(world,1):.3f}  Z={spans(world,2):.3f}")
    print(f"  truc dung sau khi xoay : {'Y' if spans(world,1) >= spans(world,2) else 'Z'}")
    print(f"  minY world             : {min(p[1] for p in world):.3f}")