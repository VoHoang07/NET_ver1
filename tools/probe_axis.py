import os

import bpy

DOWNLOADS = os.path.expanduser("~/Downloads")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(DOWNLOADS, "Idle.fbx"))
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

before_actions = set(bpy.data.actions)
before_objects = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=os.path.join(DOWNLOADS, "Sitting Idle.fbx"))
action = next(a for a in bpy.data.actions if a not in before_actions)
for obj in [o for o in bpy.data.objects if o not in before_objects]:
    bpy.data.objects.remove(obj, do_unlink=True)

arm.animation_data_create()
arm.animation_data.action = action
if hasattr(arm.animation_data, "action_slot") and len(action.slots) > 0:
    arm.animation_data.action_slot = action.slots[0]

bpy.context.scene.frame_set(40)
bpy.context.view_layer.update()

mesh = next(
    o for o in bpy.data.objects
    if o.type == "MESH" and "Surface" in o.name
)

ys = [(mesh.matrix_world @ v.co).y for v in mesh.data.vertices]
print(f"RESULT truoc: minY={min(ys):.3f} maxY={max(ys):.3f}")
print(f"RESULT location={tuple(round(v, 3) for v in mesh.location)}")

mesh.location.y -= min(ys)
bpy.context.view_layer.update()

ys2 = [(mesh.matrix_world @ v.co).y for v in mesh.data.vertices]
print(f"RESULT sau  : minY={min(ys2):.3f} maxY={max(ys2):.3f}")
print(f"RESULT location={tuple(round(v, 3) for v in mesh.location)}")

# Kiem tra data vertices co bi transform_apply lam doi khong
raw = [v.co.y for v in mesh.data.vertices]
print(f"RESULT raw data Y: min={min(raw):.3f} max={max(raw):.3f}")