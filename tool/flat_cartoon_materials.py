"""Owner-selected flat-cartoon preview C, applied only in the render worker.

Keep the original mesh, UVs, rig, animation, material datablocks and packed images
in the master untouched. Never save the opened source after applying this style.
"""
import bpy

STYLE = 'flat-cartoon-v1'
PALETTE = (
    (.055, .245, .52, 1), (.025, .065, .13, 1),
    (.25, .073, .025, 1), (.80, .145, .010, 1),
    (.085, .032, .013, 1), (.035, .043, .055, 1),
    (.18, .13, .085, 1), (.52, .36, .20, 1),
)


def apply_flat_cartoon():
    for image in bpy.data.images:
        if image.type == 'IMAGE' and image.size[0] > 0:
            width, height = image.size
            if max(width, height) > 128:
                factor = 128 / max(width, height)
                image.scale(max(1, round(width * factor)),
                            max(1, round(height * factor)))

    for material in bpy.data.materials:
        if not material.use_nodes or material.name == 'Neutral review floor':
            continue
        tree = material.node_tree
        principled = next((n for n in tree.nodes
                           if n.type == 'BSDF_PRINCIPLED'), None)
        if principled is None:
            continue
        output = next(n for n in tree.nodes if n.type == 'OUTPUT_MATERIAL')
        base = principled.inputs['Base Color']
        if base.is_linked:
            color = base.links[0].from_socket
        else:
            rgb = tree.nodes.new('ShaderNodeRGB')
            rgb.outputs[0].default_value = base.default_value
            color = rgb.outputs[0]

        best_distance = chosen_color = None
        for palette_color in PALETTE:
            rgb = tree.nodes.new('ShaderNodeRGB')
            rgb.outputs[0].default_value = palette_color
            distance = tree.nodes.new('ShaderNodeVectorMath')
            distance.operation = 'DISTANCE'
            tree.links.new(color, distance.inputs[0])
            distance.inputs[1].default_value = palette_color[:3]
            if best_distance is None:
                best_distance = distance.outputs['Value']
                chosen_color = rgb.outputs[0]
                continue
            less = tree.nodes.new('ShaderNodeMath')
            less.operation = 'LESS_THAN'
            tree.links.new(distance.outputs['Value'], less.inputs[0])
            tree.links.new(best_distance, less.inputs[1])
            select = tree.nodes.new('ShaderNodeMixRGB')
            tree.links.new(less.outputs[0], select.inputs[0])
            tree.links.new(chosen_color, select.inputs[1])
            tree.links.new(rgb.outputs[0], select.inputs[2])
            closest = tree.nodes.new('ShaderNodeMath')
            closest.operation = 'MINIMUM'
            tree.links.new(best_distance, closest.inputs[0])
            tree.links.new(distance.outputs['Value'], closest.inputs[1])
            chosen_color = select.outputs[0]
            best_distance = closest.outputs[0]

        toon = tree.nodes.new('ShaderNodeBsdfToon')
        toon.component = 'DIFFUSE'
        toon.inputs['Size'].default_value = .55
        toon.inputs['Smooth'].default_value = .03
        tree.links.new(chosen_color, toon.inputs['Color'])
        emission = tree.nodes.new('ShaderNodeEmission')
        tree.links.new(chosen_color, emission.inputs['Color'])
        mix = tree.nodes.new('ShaderNodeMixShader')
        mix.inputs[0].default_value = .70
        tree.links.new(toon.outputs[0], mix.inputs[1])
        tree.links.new(emission.outputs[0], mix.inputs[2])
        tree.links.new(mix.outputs[0], output.inputs['Surface'])
