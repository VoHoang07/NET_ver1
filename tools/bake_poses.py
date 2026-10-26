"""Nướng 6 tư thế Mixamo thành 6 file USDZ tĩnh, mỗi tạo dáng một file.

Chạy:
    /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python tools/bake_poses.py

## Vì sao không gộp 6 clip vào một file

USD **chỉ giữ một** quan hệ `skel:animationSource` từ `SkelRoot` tới
`SkelAnimation`. RealityKit đọc animation **qua quan hệ đó**, nên một USDZ chỉ
dùng được đúng một clip. Ghép 6 clip vào một file được:

- file vẫn hợp lệ, `usdcat` đọc bình thường, 6 tên đều hiện
- nhưng `availableAnimations` trả về **rỗng**, app âm thầm rơi về xoay khớp

Đây là kiểu lỗi im lặng nguy hiểm nhất: build sạch, test khác xanh, không log
lỗi nào — chỉ có tạo dáng sai.

## Vì sao nướng thành mesh tĩnh thay vì để xương + animation

Brief yêu cầu người 3D **đứng yên, không tự chuyển động**. Vậy giữ xương là thừa.
Nướng tư thế vào mesh:

1. luôn hiển thị đúng, không phụ thuộc API animation nào của RealityKit
2. file nhỏ hơn nhiều — không cần skeleton, joint indices hay animation curves
3. `availableAnimations` rỗng là chuyện bình thường, không phải dấu hiệu lỗi
"""

import os
import struct
import zipfile

import bpy

HOME = os.path.expanduser("~")
DOWNLOADS = os.path.join(HOME, "Downloads")
OUT_DIR = os.path.join(HOME, "Documents", "NET_ver1", "NET_ver1", "Assets", "Resources")
WORK = "/tmp/net3d/bake"

# `pose.id` trong app ↔ file Mixamo. Tên file đầu ra dùng đúng `pose.id`.
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
#   ngồi hẳn xuống ghế, nên frame đầu là dáng đứng méo. Sau khoảng này giây đầu thì
#   cơ thể đã vào dạng và chỉ còn chuyển động nhẹ — lấy khung nào cũng gần như nhau.
POSE_FRAME = 40


def bake_pose(model_fbx, clip_fbx, pose_id, out_usdz):
    """Dựng một người đã nướng đúng tư thế, xuất thành USDZ tĩnh."""
    bpy.ops.wm.read_factory_settings(use_empty=True)

    bpy.ops.import_scene.fbx(filepath=model_fbx, automatic_bone_orientation=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

    # USD tính theo centimetre, RealityKit coi 1 đơn vị = 1 mét. Không chia tỉ lệ
    # thì người cao gấp 100 lần.
    #
    # - Important: scale phải áp cho **cả xương lẫn mesh**. Chỉ scale armature thì
    #   mesh deform theo bộ xương nhỏ đi 100 lần: đo được người chỉ còn 0,41–0,89 mét
    #   thay vì 1,70 mét, và dáng ngồi bị bóp méo. Đây là nguyên nhân người 3D to
    #   lấn khung trên thiết bị — app thấy model cao 1,7 m nên scale theo, nhưng
    #   thực tế model nhỏ hơn nhiều lần.
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    before_actions = set(bpy.data.actions)
    before_objects = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=clip_fbx, automatic_bone_orientation=True)
    action = next((a for a in bpy.data.actions if a not in before_actions), None)
    if action is None:
        raise SystemExit(f"Khong tim thay clip trong {clip_fbx}")

    # Xoá armature và mesh của lần import clip — giữ nguyên bản gốc.
    for obj in [o for o in bpy.data.objects if o not in before_objects]:
        bpy.data.objects.remove(obj, do_unlink=True)

    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action

    # - Important: Blender 4.4+ dùng **action slot**. Gán `action` mà không gán slot
    #   thì action chạy trên slot rỗng, xương **không nhận** chuyển động — cả 6 clip
    #   đều nướng ra cùng một dáng mà không có lỗi nào được báo. Đây chính là lý do
    #   6 file USDZ đầu tiên có hash giống hệt nhau.
    if hasattr(arm.animation_data, "action_slot") and len(action.slots) > 0:
        arm.animation_data.action_slot = action.slots[0]

    bpy.context.scene.frame_set(POSE_FRAME)
    bpy.context.view_layer.update()

    # Nướng: đánh giá armature ở tư thế rồi áp kết quả thẳng vào mesh, sau đó bỏ
    # xương đi. Đây là bước quyết định — giữ xương thì tư thế chỉ tồn tại ở frame 40
    # và app phải tua animation mới ra, mà RealityKit không cho tua kiểu đó.
    # - Important: CHỈ giữ mesh da, loại bỏ mesh khung xương.
    #
    #   Model FBX gốc có hai mesh: `Beta_Surface` (da người) và `Beta_Joints` (hiện
    #   thân các khớp — vai, khuỷu, hông). Cả hai nằm chồng lên nhau ở cùng vị trí, nên
    #   nếu xuất cả hai thì người ta thấy các khối cầu ở khớp **mọc ra từ thân** —
    #   đúng hình bóng người trên iPhone thật, trông như búp bê tháo rời.
    #
    #   Lọc theo tên vì tên mesh do Mixamo đặt và giữ nguyên qua modifier apply.
    all_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # `Beta_Joints` vẫn phải đi qua `modifier_apply` như mọi mesh khác, nếu không nó
    # mất liên kết xương và đứng ở T-pose khi xuất — cao hơn cả người thật.
    meshes = [o for o in all_meshes if "joints" not in o.name.lower()]
    joint_meshes = [o for o in all_meshes if "joints" in o.name.lower()]
    if not meshes:
        raise SystemExit("Model khong co mesh da")

    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    # KHÔNG gọi `transforms_clear`. Lệnh đó **xoá** tư thế mà action vừa áp, đưa người
    # về T-pose — nướng ra kết quả là người đứng thẳng cho cả 6 tư thế.
    # `frame_set(POSE_FRAME)` ở trên đã đặt đúng tư thế, chỉ cần áp modifier.
    for mesh in meshes:
        # Đảm bảo có modifier Armature trỏ đúng xương. FBX của Blender thường đã
        # có, nhưng nếu thiếu thì tạo — không có nó, mesh không cong theo tư thế.
        has_mod = any(m.type == "ARMATURE" for m in mesh.modifiers)
        if not has_mod:
            mod = mesh.modifiers.new(name="Armature", type="ARMATURE")
            mod.object = arm
        bpy.context.view_layer.objects.active = mesh
        bpy.ops.object.modifier_apply(modifier=mesh.modifiers[0].name)

    # Xoá xương và action: người 3D đứng yên, không cần xương nữa.
    for obj in meshes:
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
    bpy.data.objects.remove(arm, do_unlink=True)

    # - Important: xoá HẲN mesh xương khỏi scene, không chỉ bỏ khỏi danh sách xuất.
    #
    #   `export_meshes=True` kèm `export_armatures=False` **vẫn** ghi mesh xương ra
    #   file — đo lại sau khi chỉ lọc danh sách:
    #
    #   ```
    #   Beta_Surface  X[-0.25, 0.25]  Z[0.00 .. 1.80]   <- có tư thế
    #   Beta_Joints   X[-0.88, 0.88]  Z[0.00 .. 1.60]   <- T-pose, rộng hơn cả người
    #   ```
    #
    #   Khối cầu ở khớp nằm **ngoài** thân người và đúng cao bằng người thật ở mọi
    #   tư thế — đó là thứ nhìn thấy trên iPhone. Chỉ có cách xoá khỏi scene.
    for obj in joint_meshes:
        bpy.data.objects.remove(obj, do_unlink=True)

    # Đặt đáy người xuống gốc tọa độ trước khi xuất.
    #
    # - Important: **bắt buộc**, không phải cho đẹp. Mỗi clip Mixamo có hệ toạ độ
    #   riêng: đo thật thì vị trí người lệch nhau rõ rệt. Không gộp về một gốc thì
    #   người 3D lơ lửng hoặc chìm sâu, và mỗi tư thế nằm ở một độ cao khác nhau.
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    # KHONG dung `origin_set(type="ORIGIN_CURSOR")`.
    #
    # - Important: len do duoc duoc: file xuat ra co toa do **Y am**
    #   (`-2.494 .. -1.709`) trong khi truc dung Z la `0 .. 1.331`.
    #
    #   `ORIGIN_CURSOR` dua goc object ve vi tri con tro 3D, ma con tro do nam o
    #   `(0, 0, 0)` mac dinh — khac voi goc that cua mesh sau khi da bien doi. Hau qua
    #   la toa do bi lech theo con tro, khong con bat dau tu 0.
    #
    #   Buoc nay khong can: offset Z o duoi da dua chan nguoi ve dung Y = 0.
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

    # Đưa người về giữa gốc toạ độ.
    #
    # Blender nội bộ dùng trục Z là trục đứng; exporter đổi sang hệ USD (Y đứng).
    # KHONG xoay tay: giu nguyen he toa do cua Blender (truc dung la Z). Exporter lo
    # phan doi truc sang USD (Y dung).
    #
    # - Important: ket luan "RealityKit doc truc Z lam truc dung" trong cac ban ghi
    #   truoc day **sai**. Do lai truc tiep tu file `.usdz` bang `pxr`: file ghi
    #   `upAxis = "Y"` va hinh hoc that su nam tren truc Y:
    #
    #   ```
    #   pose-standing-straight.usdz  X: -0.345 .. 0.162
    #                                Y:  0.000 .. 1.797   <- truc dung
    #                                Z:  0.222 .. 0.636
    #   ```
    #
    #   Bai hoc: khong tin nhan USD `upAxis` mot minh cung sai, va khong tin so do
    #   cua chinh RealityKit cung sai. Phai doc truc tiep file.
    #
    # Đưa người về **giữa gốc toạ độ** theo cả ba trục.
    #
    # - Important: trước đây chỉ dịch trục Z. Đo lại từ file `.usdz` cho thấy người
    #   lệch hẳn sang bên theo X, mỗi tư thế lệch một hướng khác nhau:
    #
    #   | tư thế | X trong file | Y | Z |
    #   |---|---|---|---|
    #   | standing-aside | 2,61 .. 3,42 | 0,00 .. 1,74 | -4,13 .. -3,35 |
    #   | standing-straight | -0,35 .. 0,16 | 0,00 .. 1,80 | 0,22 .. 0,64 |
    #   | seated-chin | -2,81 .. -2,13 | 0,00 .. 1,76 | -1,31 .. -0,85 |
    #
    #   Camera nhìn thẳng vào trục Z tại X = 0, nên người lệch 3,4 m sang bên là
    #   **trượt khỏi khung hình**.
    #
    #   Còn trục Y của Blender (chiều sâu, thành trục Z khi xuất ra USD) thì **chưa
    #   từng** được dịch. Đó là nguyên nhân `standing-aside` không hiện gì trên màn
    #   hình: người nằm ở Z = −4,13 … −3,35 trong khi camera đứng ở Z = +2,0 — tức
    #   **camera nằm sau lưng người**. `seated-straight` có Z = +1,71 … +2,49 nên
    #   lọt vào khung và hiện ra, nhưng hình chụp chỉ có **bàn**, không thấy người.
    #
    #   Sự khác nhau giữa các tư thế không ngẫu nhiên: nó đúng bằng vị trí gốc riêng
    #   của từng clip Mixamo.

    all_vertices = [v for obj in meshes for v in obj.data.vertices]
    centre_x = (min(v.co.x for v in all_vertices) + max(v.co.x for v in all_vertices)) / 2
    centre_y = (min(v.co.y for v in all_vertices) + max(v.co.y for v in all_vertices)) / 2
    lowest = min(v.co.z for v in all_vertices)
    for vertex in all_vertices:
        vertex.co.x -= centre_x
        vertex.co.y -= centre_y
        vertex.co.z -= lowest
    for obj in meshes:
        obj.data.update()

    usda = os.path.join(WORK, f"{pose_id}.usdc")
    bpy.ops.wm.usd_export(
        # - Important: KHÔNG bật `convert_orientation`, và phải khai `up_axis` rõ ràng.
        #
        #   Đây là nguyên nhân khiến người 3D **nằm ngang** và trông như búp bê rời
        #   rạc, đã xác nhận trên iPhone thật. Đo trực tiếp trong file xuất ra:
        #
        #   ```
        #   upAxis default = Y
        #   /root            [Xform] ops=['xformOp:rotateXYZ=(-90, 0, 0)']
        #   /root/Beta_Joints [Mesh]  Z [0.00 .. 1.59]   ← trục cao nhất là Z
        #   ```
        #
        #   File **ghi** `upAxis = "Y"` nhưng prim gốc lại xoay −90°, nên hình học bị
        #   xoay đúng cái mà RealityKit đã tự làm theo `upAxis` — hai phép biến đổi
        #   triệt tiêu nhau và người nằm ngang dọc trục Z.
        #
        #   `convert_orientation=True` chính là thứ tạo ra cặp
        #   `upAxis="Y" + rotateXYZ(-90)` đó. Tắt đi thì Blender không còn tự xoay gì.
        #
        #   Blender 4.5 **không có** tham số `up_axis` — kiểm tra trực tiếp
        #   `bpy.ops.wm.usd_export.get_rna_type().properties`, chỉ có
        #   `convert_orientation`. Nên hệ toạ độ được ghi ra phải để USD writer tự lo.
        #
        #   Bài học: `upAxis` trong file là **metadata**, còn `rotateXYZ` là **hình học
        #   thật**. Chỉ nhìn metadata thì bị lừa — phải đo tọa độ đỉnh thật.
        convert_orientation=False,
        filepath=usda,
        # - Important: KHÔNG xuất khung xương. Mesh `Beta_Joints` là hiện thân của các
        #   khớp — những khối cầu nhỏ nằm đúng chỗ vai, khuỷu, hông. Nó **chồng đè**
        #   lên mesh da `Beta_Surface` ở cùng vị trí, và người ta thấy chính xác điều
        #   đó trên iPhone thật: bóng người là các khối cầu rời rạc mọc ra từ thân,
        #   trông như búp bê tháo rời chứ không phải cơ thể.
        #
        #   Xương đã bị áp vào mesh ở bước trên rồi (`modifier_apply`) và đã xoá khỏi
        #   `.blend`, nên bỏ qua lúc xuất là an toàn — không mất dữ liệu tư thế nào.
        export_animation=False,
        export_armatures=False,
        export_meshes=True,
        export_materials=False,
        export_textures=False,
        export_uvmaps=False,
        export_normals=True,
        selected_objects_only=False,
    )

    make_usdz(usda, os.path.join(OUT_DIR, f"pose-{pose_id}.usdz"))


USDZ_ALIGNMENT = 64


def _aligned_zip_info(filename):
    """`ZipInfo` với phần `extra` đệm sao cho dữ liệu bắt đầu đúng bội số 64.

    - Important: chuẩn USDZ yêu cầu **phần dữ liệu** của mỗi entry bắt đầu ở byte
      là bội số của 64. Vị trí đó là `30 + len(tên) + len(extra)`, không phải
      `header_offset`.

      Ban đầu script kiểm tra `header_offset % 64` — mà giá trị đó luôn bằng 0 vì
      entry luôn bắt đầu file, nên phép kiểm tra luôn đạt và không bắt được lỗi.
      File ra dẫn tới RealityKit từ chối nạp, `load()` trả `nil`, app rơi về hình
      khối — build sạch, test khác xanh, không có lỗi nào được in ra.
    """
    info = zipfile.ZipInfo(filename)
    header_len = 30 + len(filename.encode("utf-8"))

    padding = (USDZ_ALIGNMENT - header_len % USDZ_ALIGNMENT) % USDZ_ALIGNMENT
    if padding:
        # Extra field phải có cấu trúc: 2 byte id, 2 byte kích thước, rồi dữ liệu.
        info.extra = b"\xff\xff" + struct.pack("<H", padding - 4) + b"\x00" * (padding - 4)
    return info


def make_usdz(usda_path, usdz_path):
    """Đóng gói `.usda` thành `.usdz` đúng chuẩn Apple.

    - Important: USDZ là zip **không nén** (`ZIP_STORED`), và phần dữ liệu mỗi
      entry phải căn 64 byte. Bỏ điều kiện căn thì RealityKit từ chối file mà
      không báo lý do rõ ràng.
    """
    data = open(usda_path, "rb").read()
    name = os.path.basename(usda_path)

    with zipfile.ZipFile(usdz_path, "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr(_aligned_zip_info(name), data, compress_type=zipfile.ZIP_STORED)

    # Kiểm đúng thứ: vị trí **bắt đầu dữ liệu**, tính cả header và extra field.
    with zipfile.ZipFile(usdz_path) as z:
        info = z.infolist()[0]
        data_start = info.header_offset + 30 + len(info.filename.encode("utf-8")) + len(info.extra)
        if data_start % USDZ_ALIGNMENT != 0:
            raise SystemExit(
                f"USDZ khong dung chuan: du lieu bat dau tai byte {data_start}, "
                f"can boi so cua {USDZ_ALIGNMENT}"
            )
    return os.path.getsize(usdz_path)


def main():
    model_fbx = os.path.join(DOWNLOADS, "Idle.fbx")
    if not os.path.exists(model_fbx):
        raise SystemExit(f"Khong thay file model: {model_fbx}")

    os.makedirs(WORK, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)

    total = 0
    results = []
    for pose_id, filename in CLIPS:
        clip_fbx = os.path.join(DOWNLOADS, filename)
        if not os.path.exists(clip_fbx):
            results.append((pose_id, "THIEU FILE"))
            continue

        try:
            bake_pose(model_fbx, clip_fbx, pose_id, None)
            results.append((pose_id, "OK"))
        except SystemExit as err:
            results.append((pose_id, str(err)))
            continue

        target = os.path.join(OUT_DIR, f"pose-{pose_id}.usdz")
        total += os.path.getsize(target)

    print("\n===== KET QUA =====")
    for pose_id, status in results:
        size = os.path.getsize(os.path.join(OUT_DIR, f"pose-{pose_id}.usdz")) \
            if os.path.exists(os.path.join(OUT_DIR, f"pose-{pose_id}.usdz")) else 0
        print(f"  {pose_id:20s} {status:12s} {size / 1024 / 1024:.1f} MB")
    print(f"Tong: {total / 1024 / 1024:.1f} MB")


main()
