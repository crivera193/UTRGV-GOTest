"""Background Blender export; never save or change the supplied hat master.

blender -b -t 6 --python tool/export_team_assets.py
"""
import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'SourceArt/human-cowboy/v010-hat-only/Cowboy_Hat.blend'
OUT = ROOT / 'assets/teams'
DERIVED = ROOT / 'SourceArt/team-selection/v001'
OUT.mkdir(parents=True, exist_ok=True)
DERIVED.mkdir(parents=True, exist_ok=True)
sha = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
s = bpy.context.scene
hat = bpy.data.objects.get('Cowboy Hat')
assert hat is not None and hat.type == 'MESH'
inventory = [{'name': o.name, 'type': o.type} for o in s.objects]
materials = [m.name for m in hat.data.materials]
for o in list(s.objects):
    if o != hat:
        bpy.data.objects.remove(o, do_unlink=True)
s.render.engine = 'CYCLES'
s.cycles.samples = 32
s.cycles.use_denoising = True
s.render.resolution_x = 512
s.render.resolution_y = 384
s.render.resolution_percentage = 100
s.render.film_transparent = True
formats = s.render.image_settings.bl_rna.properties['file_format'].enum_items
assert 'PNG' in [i.identifier for i in formats]
s.render.image_settings.file_format = 'PNG'
s.render.image_settings.color_mode = 'RGBA'
world = bpy.data.worlds.new('Team export studio')
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
background.inputs['Color'].default_value = (.32, .36, .43, 1)
background.inputs['Strength'].default_value = .45
s.world = world

def light(name, position, power, size):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = power
    data.shape = 'DISK'
    data.size = size
    obj = bpy.data.objects.new(name, data)
    s.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector((0, 0, .06)) - obj.location).to_track_quat('-Z', 'Y').to_euler()

light('Warm key', (-1, -2, 3), 170, 2)
light('Soft fill', (2, -1, 1.4), 80, 2)
light('Rim', (0, 2, 2), 180, 1.5)
data = bpy.data.cameras.new('Team export camera')
cam = bpy.data.objects.new('Team export camera', data)
s.collection.objects.link(cam)
s.camera = cam
cam.data.type = 'ORTHO'
cam.data.ortho_scale = .58
target = Vector((0, 0, .055))
cam.location = target + Vector((.5, -3, 1.45))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
s.render.filepath = str(OUT / 'cowboy-hat.png')
bpy.ops.render.render(write_still=True)
hat.hide_render = True

stone = bpy.data.materials.new('Original sandstone')
stone.use_nodes = True
bs = next(n for n in stone.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bs.inputs['Base Color'].default_value = (.32, .29, .24, 1)
bs.inputs['Roughness'].default_value = .83

def cylinder(name, radius, depth, z, vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(stone)
    bevel = obj.modifiers.new('Soft stone edges', 'BEVEL')
    bevel.width = .012
    bevel.segments = 3
    obj.modifiers.new('Weighted stone normals', 'WEIGHTED_NORMAL')
    return obj

cylinder('Octagonal foundation', .23, .075, .0375, 8)
cylinder('Lower molding', .19, .045, .098)
cylinder('Column shaft', .14, .57, .405, 12)
cylinder('Upper molding', .18, .035, .7075)
cylinder('Crown slab', .215, .065, .7575, 8)
# Original recessed vertical detailing, without copying the reference ornament.
trim = bpy.data.materials.new('Antique brass inlay')
trim.use_nodes = True
bs = next(n for n in trim.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
bs.inputs['Base Color'].default_value = (.48, .31, .12, 1)
bs.inputs['Metallic'].default_value = .65
bs.inputs['Roughness'].default_value = .4
for z in [.15, .655]:
    obj = cylinder('Thin brass ring', .147, .012, z)
    obj.data.materials.clear()
    obj.data.materials.append(trim)
target = Vector((0, 0, .4))
cam.location = target + Vector((.55, -3, 1.1))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 1.08
s.render.resolution_x = 256
s.render.resolution_y = 448
s.render.filepath = str(OUT / 'pedestal.png')
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED / 'Team_Selection_Export.blend'))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == sha
(OUT / 'provenance.json').write_text(json.dumps({
    'hat_source': str(SOURCE.relative_to(ROOT)), 'source_sha256': sha,
    'source_unchanged': True, 'source_inventory': inventory,
    'hat_materials_preserved': materials, 'blender': bpy.app.version_string,
    'hat_size': [512, 384], 'pedestal_size': [256, 448],
    'pipeline': 'Isolated background Blender; shared neutral hat sprite, original geometric stone pedestal; Flame draws team illumination.',
    'reference_use': 'Arrangement and stone-column mood only; no reference pixels used.',
}, indent=2))
print('TEAM_ASSETS_EXPORTED source unchanged', sha)
