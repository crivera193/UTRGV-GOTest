"""Package the owner-approved transparent animation for bounded mobile decoding.

Usage: python tool/pack_campus_dragon.py PATH_TO_CLEANED_JSON
Original frame timing is retained; crop is common to all 150 source frames.
"""
import base64, hashlib, json, pathlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
source = pathlib.Path(sys.argv[1])
doc = json.loads(source.read_text(encoding='utf-8'))
assert (doc['w'], doc['h'], doc['fr'], len(doc['assets'])) == (1200, 600, 30, 150)
work = ROOT/'tmp/campus-creatures/source-frames'
work.mkdir(parents=True, exist_ok=True)
out = ROOT/'assets/animations/campus-creatures'
out.mkdir(parents=True, exist_ok=True)
for i, asset in enumerate(doc['assets']):
    (work/f'{i:03}.png').write_bytes(base64.b64decode(asset['p'].split(',', 1)[1]))
ffmpeg = shutil.which('ffmpeg')
assert ffmpeg
common = 'crop=716:504:484:0,scale=540:380:flags=lanczos'
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30', '-i', str(work/'%03d.png'), '-vf', common, '-c:v', 'libwebp_anim', '-lossless', '1', '-compression_level', '4', '-loop', '0', str(out/'dragon.webp')], check=True)
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(work/'000.png'), '-vf', common, '-frames:v', '1', str(out/'dragon-still.png')], check=True)
(out/'dragon-provenance.json').write_text(json.dumps({'source_name':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_canvas':[1200,600],'shared_crop':[484,0,716,504],'runtime_canvas':[540,380],'frames':150,'fps':30,'duration_seconds':5,'loop':True,'dragon_motion':'Original frames; no Blender reconstruction or generated body','license':'Owner supplied; distribution rights not supplied'},indent=2))
print('PACKED', (out/'dragon.webp').stat().st_size)
