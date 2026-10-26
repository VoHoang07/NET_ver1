"""Đo **từ file FBX gốc**, chưa qua bất kỳ bước xuất USD nào.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/measure_source_fbx.py

## Vì sao phải đo lại từ FBX gốc

Trong lúc điều tra lỗi người 3D, `bake_poses.py` đã bị sửa nhiều lần dựa trên giả
thuyết chưa kiểm chứng: bỏ xoay tay, đổi `convert_orientation`, bỏ `origin_set`.
Khi đã tìm ra nguyên nhân thật thì các sửa đổi đó **có thể không còn cần** — và
giữ mù quáng cũng là một cách sai.

Đo lại từ nguồn là cách duy nhất trả lời câu hỏi đó bằng số thay vì trí nhớ.

## Câu hỏi cần trả lời

1. Trong model và trong clip Mixamo có **mesh phụ nào** không (ghế, bàn, vật thể)?
   Nếu clip có ghế sẵn thì ghế hình khối của `FurnitureBuilder` chồng lên là
   đúng cái lỗi đang mở; nếu không có thì bỏ ghế hình khối đi.
2. Sau khi áp từng clip, người đứng hay nằm, và chiều cao thật là bao nhiêu.
3. Dáng ngồi có thấp rõ rệt so với dáng đứng không — vì app chấm người mẫu bằng
   **chiều cao trong khung hình**, nên nếu tư thế ngồi gần bằng tư thế đứng thì app
   không phân biệt được và hướng dẫn sai.

## Trục đứng

Blender dùng **Z là trục đứng**, USD dùng **Y**. Số in ra là hệ Blender; đối chiếu
với `tools/inspect_meshes.py` (đọc thẳng file USDZ) thì cột Z của Blender tương
ứng cột Y của USD.
"""

import os

import bpy

DOWNLOADS = os.path.expanduser("~/Downloads")

CLIPS = [
    ("seated-straight", "Sitting Idle.fbx"),
    ("seated-chin", "Thinking.fbx"),
    ("seated-lean", "Sitting.fbx"),
    ("standing-straight", "Idle.fbx"),
    ("standing-hip", "Female Standing Pose.fbx"),
    ("standing-aside", "Look Around.fbx"),
]

MODEL = "Idle.fbx"


def apply_clip(arm, clip_path):
    before_actions = set(bpy.data.actions)
    before_objects = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=clip_path, automatic_bone_orientation=True)
    action = next((a for a in bpy.data.actions if a not in before_actions), None)

    # Clip Mixamo đôi khi chứa sẵn lưới ghế. In ra **trước** khi xoá để câu hỏi
    # "ghế hình khối có chồng ghế trong model không" được trả lời bằng số.
    extra = [f"{o.type}:{o.name}" for o in bpy.data.objects if o not in before_objects]
    print(f"      clip mang theo: {', '.join(extra) if extra else '(khong co gi)'}")

    for obj in [o for o in bpy.data.objects if o not in before_objects]:
        bpy.data.objects.remove(obj, do_unlink=True)

    if action is None:
        raise SystemExit(f"Khong tim thay clip trong {clip_path}")
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and len(action.slots) > 0:
        arm.animation_data.action_slot = action.slots[0]
    return action


def world_points(obj):
    """Đỉnh **đã qua modifier** của một mesh.

    - Important: đọc `obj.data.vertices` là đọc mesh ở **tư thế nghỉ**, không phải
      tư thế sau khi xương cong nó. Lần đo đầu tiên in ra `rong(X) = 1.804` cho cả
      sáu tư thế — bằng chứng giống hệt lỗi "cả 6 tư thế ra một dáng", trong khi
      thực ra chỉ là chưa đánh giá modifier. Phải đi qua depsgraph.
    """
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    matrix = evaluated.matrix_world
    points = [matrix @ v.co for v in mesh.vertices]
    evaluated.to_mesh_clear()
    return points


def profile(points, bins=16):
    """Bề rộng theo từng lát chiều cao, để đọc bằng mắt xem đầu ở trên hay dưới."""
    if not points:
        return
    lo = min(p.z for p in points)
    hi = max(p.z for p in points)
    span = max(hi - lo, 1e-9)
    widths = []
    for i in range(bins):
        t0 = lo + span * i / bins
        t1 = lo + span * (i + 1) / bins
        slab = [p for p in points if t0 <= p.z < t1]
        if i == bins - 1:
            slab += [p for p in points if p.z >= t1]
        widths.append(max((max(p.x for p in slab) - min(p.x for p in slab)) for _ in [0]) if slab else 0.0)
    print("      be rong theo lat (0 = tren dinh): " + " ".join(f"{w:5.2f}" for w in widths))
    print(
        f"      ngan tren={widths[0]:5.2f}  ngan giua={max(widths):5.2f}  ngan duoi={widths[-1]:5.2f}"
    )


def describe(name, points, low_sample=4000):
    """In kích thước hình bao của một tập đỉnh."""
    if not points:
        return
    step = max(len(points) // low_sample, 1)
    sample = points[::step]
    xs = [p.x for p in sample]
    ys = [p.y for p in sample]
    zs = [p.z for p in sample]
    print(
        f"      {name:22s} n={len(points):6d}  "
        f"X {min(xs):7.3f}..{max(xs):7.3f} "
        f"Y {min(ys):7.3f}..{max(ys):7.3f} "
        f"Z {min(zs):7.3f}..{max(zs):7.3f}   "
        f"cao(Z)={max(zs) - min(zs):6.3f} rong(X)={max(xs) - min(xs):6.3f} "
        f"sau(Y)={max(ys) - min(ys):6.3f}"
    )


print("=" * 78)
print("CAU HOI 1 — model co mesh phu nao khong? (ghe, ban, vat the)")
print("=" * 78)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(DOWNLOADS, MODEL), automatic_bone_orientation=True)
for obj in bpy.data.objects:
    extra = f"  dinh={len(obj.data.vertices):6d}" if obj.type == "MESH" else ""
    print(f"  {obj.type:10s} {obj.name}{extra}")
bones = [b.name for b in bpy.data.armatures[0].bones] if bpy.data.armatures else []
print(f"  xuong: {len(bones)}")
print(f"  co xuong kieu Mixamo: {sum('mixamorig' in n for n in bones)}")

print()
print("=" * 78)
print("CAU HOI 2/3 — ap tung clip roi do hinh dang")
print("=" * 78)

for pose_id, filename in CLIPS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(DOWNLOADS, MODEL), automatic_bone_orientation=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    apply_clip(arm, os.path.join(DOWNLOADS, filename))
    bpy.context.scene.frame_set(40)
    bpy.context.view_layer.update()

    print(f"\n  --- {pose_id}  ({filename}) ---")
    all_points = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        pts = world_points(obj)
        all_points.extend(pts)
        describe(obj.name, pts)
    describe("TAT CA", all_points)
    profile(all_points)
