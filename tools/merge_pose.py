"""Gộp 6 animation Mixamo vào một `figure.usdz`, mỗi tạo dáng một khung hình.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/merge_pose.py

## Vì sao script này phải phức tạp

Ba điều đã làm hỏng lần đầu, ghi lại để không phải đoán lại:

1. **Mỗi lần import FBX sinh armature và mesh mới.** Không xoá thì 6 lần import
   cho ra 7 skeleton, 14 mesh. RealityKit chỉ nhận một.
2. **`arm.animation_data.action = x` chỉ giữ clip cuối.** Blender xoá action cũ
   không còn ai dùng. NLA strip thì giữ được cả 6, nhưng **exporter USD bỏ qua NLA**
   và chỉ xuất action gán trực tiếp — file ra rỗng.
3. **Exporter chỉ xuất animation cho frame range của scene.** Không đặt thì
   `SkelAnimation` không có `timeSamples`, tức không có dữ liệu chuyển động.

Nên cách làm: export **sáu lần**, mỗi lần một clip, rồi ghép các file `.usda` lại.
"""

import os
import re
import subprocess

import bpy

HOME = os.path.expanduser("~")
DOWNLOADS = os.path.join(HOME, "Downloads")
PROJECT = os.path.join(HOME, "Documents", "NET_ver1")
OUT_DIR = os.path.join(PROJECT, "NET_ver1", "Assets", "Resources")
OUT_FILE = os.path.join(OUT_DIR, "figure.usdz")
WORK = "/tmp/net3d/merge"

CLIPS = [
    ("seated-straight", "Sitting Idle.fbx"),
    ("seated-chin", "Thinking.fbx"),
    ("seated-lean", "Sitting.fbx"),
    ("standing-straight", "Idle.fbx"),
    ("standing-hip", "Female Standing Pose.fbx"),
    ("standing-aside", "Look Around.fbx"),
]

# Khung hình đại diện cho mỗi dáng.
#
# - Important: KHÔNG dùng frame 0. Clip `Sitting Idle` mở đầu lúc người còn chưa
#   ngồi hẳn xuống ghế nên frame đầu là dáng đứng méo. Sau khoảng này giây đầu thì
#   cơ thể đã vào dạng, chỉ còn chuyển động nhẹ — nên lấy khung nào cũng gần như nhau.
POSE_FRAME = 40


def build_single_clip(model_fbx, clip_fbx, pose_id, out_usda):
    """Dựng một file `.usda` chứa đúng một clip tên `pose_id`.

    Xuất `.usda` chứ không `.usdz` vì cần ghép text sau đó; bước nén `.usdz` làm ở
    cuối script bằng `usdzip` của hệ thống.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)

    bpy.ops.import_scene.fbx(filepath=model_fbx, automatic_bone_orientation=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

    # USD quy định 1 đơn vị = 1 centimetre, RealityKit coi 1 đơn vị = 1 mét.
    # Không chia tỉ lệ thì người cao gấp 100 lần.
    arm.scale = (0.01, 0.01, 0.01)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    before_actions = set(bpy.data.actions)
    before_objects = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=clip_fbx, automatic_bone_orientation=True)

    action = next(a for a in bpy.data.actions if a not in before_actions)

    # Xoá armature và mesh vừa sinh, giữ nguyên armature gốc.
    for obj in [o for o in bpy.data.objects if o not in before_objects]:
        bpy.data.objects.remove(obj, do_unlink=True)

    # Cắt còn đúng một khung hình.
    for fc in action.fcurves:
        keep = [(POSE_FRAME, kp.co[1], kp.interpolation)
                for kp in fc.keyframe_points
                if int(round(kp.co[0])) == POSE_FRAME]
        if not keep:
            continue
        fc.keyframe_points.clear()
        for x, y, interp in keep:
            kp = fc.keyframe_points.insert(x, y)
            kp.interpolation = interp
        fc.update()

    action.name = pose_id
    action.use_frame_range = True
    action.frame_start = POSE_FRAME
    action.frame_end = POSE_FRAME
    action.use_fake_user = True

    # Gán **trực tiếp** — exporter USD không đọc NLA.
    arm.animation_data_create()
    arm.animation_data.action = action

    scene = bpy.context.scene
    scene.frame_start = POSE_FRAME
    scene.frame_end = POSE_FRAME
    scene.frame_set(POSE_FRAME)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm

    bpy.ops.wm.usd_export(
        filepath=out_usda,
        export_animation=True,
        export_armatures=True,
        export_meshes=True,
        export_materials=False,
        export_textures=False,
        export_uvmaps=True,
        export_normals=True,
        selected_objects_only=False,
    )


def merge_usda(files, out_file):
    """Ghép các `.usda`: lấy phần khung hình của file đầu, thay bằng clip các file sau."""
    base = open(files[0]).read()

    def extract_animations(path):
    """Lấy riêng khối `SkelAnimation` khỏi một part.

    - Important: `SkelAnimation` nằm **bên trong** `def Xform "root"`, không phải ở
      cấp stage. Dán ở cấp stage thì USD không nạp được — phải chèn vào đúng chỗ
      bên trong `root`, cùng chỗ với block gốc.
    """
    text = open(path).read()
    start = text.find("def SkelAnimation ")
    if start < 0:
        return ""

    # Đếm ngoặc để tìm đúng khối: `timeSamples` chứa nhiều `{}` lồng nhau, nên
    # không thể dừng ở dấu `}` đầu tiên.
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return ""


def merge_usda(files, out_file):
    """Ghép các part thành một stage có đủ clip.

    - Important: chỉ giữ **một** bộ mesh và skeleton từ file đầu. Nối cả khối `root`
      của cả 6 file thì ra 6 nhân bản người chồng lên nhau, nặng gấp 6 lần.
    """
    base = open(files[0]).read()

    blocks = [b for b in (extract_animations(p) for p in files) if b]
    if not blocks:
        raise SystemExit("Khong tach duoc SkelAnimation nao")

    # `base` kết thúc bằng `}` đóng stage. Chèn các block animation ngay trước đó.
    merged = base[: base.rfind("}")] + "\n" + "\n\n".join(blocks) + "\n}\n"
    with open(out_file, "w") as f:
        f.write(merged)
    return len(blocks)


def main():
    model_fbx = os.path.join(DOWNLOADS, "Idle.fbx")
    if not os.path.exists(model_fbx):
        raise SystemExit(f"Khong thay file model: {model_fbx}")

    os.makedirs(WORK, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)

    parts = []
    results = []
    for pose_id, filename in CLIPS:
        clip_fbx = os.path.join(DOWNLOADS, filename)
        if not os.path.exists(clip_fbx):
            results.append((pose_id, "THIEU FILE"))
            continue

        out_usda = os.path.join(WORK, f"{pose_id}.usda")
        build_single_clip(model_fbx, clip_fbx, pose_id, out_usda)
        parts.append(out_usda)
        results.append((pose_id, "OK"))

    if not parts:
        raise SystemExit("Khong co clip nao nen duoc")

    merged_usda = os.path.join(WORK, "figure.usda")
    merge_usda(parts, merged_usda)

    # Nén thành USDZ. `usdzip` đi kèm Xcode.
    subprocess.run(["usdzip", merged_usda, OUT_FILE], check=True)

    size_mb = os.path.getsize(OUT_FILE) / 1024 / 1024
    print("\n===== KET QUA =====")
    for pose_id, status in results:
        print(f"  {pose_id:20s} {status}")
    print(f"File: {OUT_FILE}")
    print(f"Kich thuoc: {size_mb:.1f} MB")


main()