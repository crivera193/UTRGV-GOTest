"""Create color-only derivatives; keep the owner's supplied dark file intact."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/animations/kitty-island'
source = json.loads((ASSETS / 'cat-dark.json').read_text(encoding='utf-8'))
# Layer-specific palette: preserve nose, pale chest/belly and both shadows.
palettes = {
    'orange': ('C77C37', 'A85F29', '895028'),
    'gray': ('7D858C', '606971', '49535C'),
}
for name, (body, rear, ears) in palettes.items():
    result = copy.deepcopy(source)
    for layer in result['layers']:
        layer_name = layer['nm']
        if layer_name in ('Museau Outlines', 'Collier Blanc Outlines',
                          'Ventre Blanc Outlines', 'Queue Ombre', 'Ombre'):
            continue
        def recolor(node):
            if isinstance(node, list):
                for item in node:
                    recolor(item)
            elif isinstance(node, dict):
                if node.get('ty') in ('fl', 'st'):
                    color = ears if 'Oreill' in layer_name else (
                        rear if layer_name == 'Arrière Train Outlines'
                        and node.get('nm') == 'Fill 2' else body)
                    assert node['c']['a'] == 0
                    node['c']['k'] = [int(color[i:i+2], 16) / 255
                                      for i in (0, 2, 4)] + [1]
                for key, value in node.items():
                    if key != 'c':
                        recolor(value)
        recolor(layer.get('shapes', []))
    (ASSETS / f'cat-{name}.json').write_text(
        json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n',
        encoding='utf-8')
    print(f'Created cat-{name}.json (color-only derivative)')
