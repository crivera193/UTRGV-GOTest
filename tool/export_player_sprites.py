"""Run in background Blender: render the accepted cowboy, never save its master.

blender -b -t 6 --python tool/export_player_sprites.py
Then: python tool/pack_player_sprites.py
Partial outputs resume only when their source hash/settings match.
"""
import bpy
import hashlib
import json
import math
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'SourceArt/human-cowboy/v008-hands-paint-repair/Cowboy_Hands_and_Paint_Repair.blend'
OUT = ROOT / 'tmp/avatar/frames-v2'
OUT.mkdir(parents=True, exist_ok=True)
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
s = bpy.context.scene
rig = bpy.data.objects['Meeps_Cowboy_Rig']
assert rig.animation_data.action.name == 'Cowboy_Relaxed_Walk'
preview = bpy.data.objects['Matched_Travel_Preview']
preview['enabled'] = 0.0
preview.animation_data_clear()
preview.location = (0, 0, 0)
rig.data.pose_position = 'POSE'
bpy.data.objects['Review_Ground_Do_Not_Export'].hide_render = True
s.render.engine = 'CYCLES'
s.cycles.samples = 8
s.cycles.use_denoising = True
s.render.resolution_x = 160
s.render.resolution_y = 192
s.render.resolution_percentage = 100
s.render.film_transparent = True
s.render.image_settings.file_format = 'PNG'
s.render.image_settings.color_mode = 'RGBA'
s.render.fps = 30
cam = s.camera
cam.parent = None
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 2.65
# Baking 40 source frames at 30fps into 12 images preserves the 1.333s cycle.
settings = dict(source_sha256=source_hash, action=rig.animation_data.action.name,
                width=160, height=192, directions=8, frames=12,
                pitches=[0, 30, 50], duration_seconds=40/30,
                speed_mps=float(rig.get('matched_travel_m_per_second', 1.2)),
                in_place=True, idle='existing walk frame 11, neutral rest lower body',
                source=str(SOURCE.relative_to(ROOT)), version=2)
record = OUT.parent / 'render-settings-v2.json'
if record.exists():
    assert json.loads(record.read_text()) == settings, 'Export settings changed; use a new output directory'
record.write_text(json.dumps(settings, indent=2))
anchors = []
action = rig.animation_data.action
for pitch_index, pitch in enumerate(settings['pitches']):
    # Map pitch 0 looks directly down; preserve north at screen top.
    a = math.radians(pitch)
    target = Vector((0, 0, 1.0))
    cam.location = target + Vector((0, -6*math.sin(a), 6*math.cos(a)))
    cam.rotation_euler = (target-cam.location).to_track_quat('-Z','Y').to_euler()
    bpy.context.view_layer.update()
    foot = world_to_camera_view(s, cam, Vector((0, 0, 0)))
    anchors.append([float(foot.x), float(1-foot.y)])
    for direction in range(8):
        # Source faces -Y; +Y is map north, so heading 0 rotates 180 degrees.
        rig.rotation_euler.z = math.pi - direction*math.pi/4
        for frame in range(13):
            path = OUT / f'p{pitch_index}-d{direction}-f{frame:02d}.png'
            if path.exists():
                continue
            rig.animation_data.action = action
            time = 11 if frame == 12 else 1 + frame*40/12
            s.frame_set(math.floor(time), subframe=time-math.floor(time))
            # Freeze the actual existing relaxed arms; neutral legs stand at rest.
            if frame == 12:
                rig.animation_data.action = None
                for bone in rig.pose.bones:
                    if any(part in bone.name for part in ['UpLeg','Leg','Foot','Toe','Hips','Walk_Root']):
                        bone.matrix_basis.identity()
            bpy.context.view_layer.update()
            s.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            print('SPRITE_PROGRESS', pitch_index, direction, frame, flush=True)
rig.animation_data.action = action
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
(OUT.parent / 'anchors.json').write_text(json.dumps(anchors))
print('SPRITE_EXPORT_COMPLETE master unchanged', source_hash, flush=True)
