"""Tìm frame **đứng yên nhất** cho từng clip Mixamo, bằng phép đo thật.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/find_pose_frames.py

## Vì sao lại tìm frame, khi đã có `find_pose_frames.py` cũ

Bản cũ lấy điểm bằng `obj.data.vertices` — đó là mesh ở **tư thế nghỉ**, không
phải tư thế sau khi xương cong nó. Nên mọi frame cho ra cùng một kết quả, và bản
cũ chỉ có thể in ra "frame 40".

Ở đây đi qua `evaluated_depsgraph_get()` để đọc mesh **đã qua modifier
Armature**. Đó là phép đo duy nhất phản ánh đúng tư thế ở frame đó.

## Cách chọn frame

Ứng viên là frame mà hình dạng **không đổi** so với frame liền kề — tức người
đang giữ nguyên tư thế chứ không đang chuyển sang tư thế khác. Với người mẫu chụp
ảnh, chỉ những tư thế giữ được mới chụp được.

Ngoài ra in ra bề rộng theo lát để **nhìn** đầu ở trên hay dưới: phần hẹp nhất là
cổ/đầu, và nó phải nằm ở trên.
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
BANDS = 8


def attach_clip(arm, clip_path):
    before_actions = set(bpy.data.actions)
    before_objects = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=clip_path, automatic_bone_orientation=True)
    action = next((a for a in bpy.data.actions if a not in before_actions), None)
    for obj in [o for o in bpy.data.objects if o not in before_objects]:
        bpy.data.objects.remove(obj, do_unlink=True)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    if hasattr(arm.animation_data, "action_slot") and len(action.slots) > 0:
        arm.animation_data.action_slot = action.slots[0]


def points_at_frame(frame):
    """Toạ độ thế giới của mọi đỉnh mesh ở `frame`, đã qua modifier xương."""
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    out = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        matrix = evaluated.matrix_world
        out.extend(matrix @ v.co for v in mesh.vertices)
        evaluated.to_mesh_clear()
    return out


def signature(points):
    """Chữ ký hình dạng: bề rộng theo từng lát, chuẩn hoá theo chiều cao.

    Chuẩn hoá theo chiều cao là bắt buộc — nếu không, một frame mà người cao thêm
    1 cm cũng ra chữ ký khác và bị coi là "đang chuyển động".
    """
    if not points:
        return None
    lo = min(p.z for p in points)
    height = max(p.z for p in points) - lo
    if height < 1e-6:
        return None

    widths = []
    for band in range(BANDS):
        t0 = lo + height * band / BANDS
        t1 = lo + height * (band + 1) / BANDS
        slab = [p for p in points if t0 <= p.z < t1]
        if band == BANDS - 1:
            slab += [p for p in points if p.z >= t1]
        widths.append(
            int(round(
                (max(p.x for p in slab) - min(p.x for p in slab)) / height * 100
            )) if slab else -1
        )
    return tuple(widths)


def head_is_up(points):
    """Lát hẹp nhất là cổ/đầu; nó phải nằm ở **nửa trên**."""
    if not points:
        return None
    lo = min(p.z for p in points)
    height = max(p.z for p in points) - lo
    best, best_band = 1e9, None
    for band in range(BANDS * 2):
        t0 = lo + height * band / (BANDS * 2)
        t1 = lo + height * (band + 1) / (BANDS * 2)
        slab = [p for p in points if t0 <= p.z < t1]
        if not slab:
            continue
        width = max(p.x for p in slab) - min(p.x for p in slab)
        if width < best:
            best, best_band = width, band / (BANDS * 2)
    return best_band


for pose_id, filename in CLIPS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(DOWNLOADS, MODEL), automatic_bone_orientation=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    attach_clip(arm, os.path.join(DOWNLOADS, filename))

    scene = bpy.context.scene
    end = scene.frame_end
    print(f"\n=== {pose_id}  ({filename})  frame 1..{end} ===")

    signatures = {}
    for frame in range(1, end + 1):
        signatures[frame] = signature(points_at_frame(frame))

    still = [
        f for f in range(2, end)
        if signatures[f] is not None
        and signatures[f] == signatures[f - 1]
        and signatures[f] == signatures[f + 1]
    ]

    if not still:
        print("  KHONG co frame nao dung yen (clip chay lien tuc)")
        # Vẫn in frame đầu/cuối để biết clip dài bao nhiêu và dạng ra sao.
        for frame in (1, end // 2, end):
            points = points_at_frame(frame)
            print(f"    frame {frame:4d}: {signatures[frame]}  dau o {head_is_up(points)}")
        continue

    best = min(still, key=lambda f: head_is_up(points_at_frame(f)) or 1.0)
    for frame in still[:40]:
        points = points_at_frame(frame)
        lo = min(p.z for p in points)
        hi = max(p.z for p in points)
        print(
            f"    frame {frame:4d}: cao={hi - lo:5.3f}  dau o {head_is_up(points):4.2f}"
            f"  {signatures[frame]}"
        )
    print(f"  -> chon: {best}")
