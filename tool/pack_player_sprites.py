"""Assemble and validate the independently rendered runtime atlas."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'tmp/avatar'
OUT = ROOT / 'assets/player/cowboy'
OUT.mkdir(parents=True, exist_ok=True)
metadata = json.loads((WORK/'render-settings-v2.json').read_text())
metadata['anchors'] = json.loads((WORK/'anchors.json').read_text())
metadata['atlases'] = []
for pitch in range(3):
    atlas = Image.new('RGBA', (13*160, 8*192))
    for direction in range(8):
        hashes = set()
        for frame in range(13):
            image = Image.open(WORK/'frames-v2'/f'p{pitch}-d{direction}-f{frame:02d}.png').convert('RGBA')
            assert image.size == (160,192)
            box = image.getbbox()
            assert box and box[0]>0 and box[1]>0 and box[2]<160 and box[3]<192, (pitch,direction,frame,box)
            if frame < 12:
                hashes.add(hashlib.sha256(image.tobytes()).hexdigest())
            atlas.paste(image, (frame*160,direction*192))
        assert len(hashes) == 12, 'Walk must contain distinct animated frames'
    name = f'cowboy-pitch-{metadata["pitches"][pitch]}.png'
    atlas.save(OUT/name, optimize=True)
    metadata['atlases'].append(name)
assert hashlib.sha256((ROOT/metadata['source']).read_bytes()).hexdigest() == metadata['source_sha256']
(OUT/'manifest.json').write_text(json.dumps(metadata, indent=2)+'\n')
print('Verified 288 distinct walk frames + 24 idle views; master hash unchanged')
