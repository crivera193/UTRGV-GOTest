"""Join building names to the current display footprints; never move geometry.

Requires the existing shapely environment. Cached OSM is passed explicitly.
"""
import json, re, sys, hashlib
from pathlib import Path
import xml.etree.ElementTree as ET
from shapely.geometry import shape
from shapely.ops import polylabel

ROOT=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
osm=ET.fromstring(source.read_bytes())
tags={kind+'/'+n.attrib['id']:{t.attrib['k']:t.attrib['v'] for t in n.findall('tag')} for kind in ('way','relation') for n in osm.findall(kind)}
legacy=json.loads(re.search("r'''(.*?)'''",(ROOT/'lib/data/campus_buildings.dart').read_text(),re.S)[1])
directory=[(shape(f['geometry']),f['properties']) for f in legacy['features'] if f['properties']['name']!='pineapplepie']
display=json.loads((ROOT/'assets/campus/features.geojson').read_text())
aliases={'EIEAB':'CS','ELIBR':'LIB','EMEBL':'MED','EEDUC':'EDU','ESCNE':'SCI','EENGR':'ENG','ESTUN':'UNION','EUREC':'REC','ECOBE':'COBE','ECHAP':'CHAP','EHPE1':'HPE1','EHPE2':'HPE2','Greenhouse':'GRNH','RAHC':'REBL','EVLG':'VLG'}
canonical={'EMLH':'EEMLH','RAHC':'EREBL','Greenhouse':'EGRNH','ELAMR':'EREB'}
special={'ELIBR':'University Library','EMEBL':'Medical Education Building (School of Medicine)','EIEAB':'Interdisciplinary Engineering & Academic Building','ESWKH':'Schweick Hall'}
labels=[]
part_counts={}
for feature in display['features']:
    props=feature['properties']
    if props['kind']!='building':continue
    source_tags=tags.get(props['osm_id'],{})
    if source_tags.get('building') in ('roof','bridge'):continue
    geom=shape(feature['geometry'])
    matches=sorted([(geom.intersection(g).area/geom.area,p) for g,p in directory],key=lambda a:a[0],reverse=True)
    match=matches[0][1] if matches and matches[0][0]>.35 else {}
    code=match.get('short_name',match.get('name',source_tags.get('short_name','')))
    name=source_tags.get('name',match.get('source_name','')).strip()
    # Names/abbreviations from the current university inventory take priority.
    if code in special:name=special[code]
    if name.startswith('The Village '):code='EVLG'+name[-1]
    if name.startswith('Portable Building '):code='EPOB'+name.split()[-1]
    if name=='Student Health Center':code='ESTHC'
    if name=='Central Utility Plant':code='ECULP'
    if name=='Rio Grande Center for Manufacturing':code='EASFC'
    if name=='UTPA Academic Support Facilities Complex':code='EASFC'
    if not name:
        code='B'+props['osm_id'].split('/')[-1][-4:]
        name='Campus building '+code
    if not code:
        words=re.findall(r'[A-Za-z]+',name)
        code=''.join(w[0] for w in words if w.lower() not in ('of','the','and','for'))[:5].upper()
    short=aliases.get(code,code[1:] if code.startswith('E') else code)
    center=geom.centroid
    if not geom.contains(center):center=polylabel(geom,tolerance=.000005)
    assert geom.contains(center)
    part=part_counts.get(props['osm_id'],0)
    part_counts[props['osm_id']]=part+1
    labels.append({'id':props['osm_id']+'#'+str(part),'osm_id':props['osm_id'],'part':part,'short':short,'code':canonical.get(code,code),'name':name,'verified_name':bool(source_tags.get('name') or match),'center':[round(center.x,8),round(center.y,8)],'roof_m':props['height_m']+.4})
target=ROOT/'assets/campus/building-labels.json'
target.write_text(json.dumps({'sources':['Existing campus footprint/directory data','https://www.utrgv.edu/campus-operations/departments/campus-facilities-operations/building/index.htm'],'source_osm_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'labels':labels},indent=2)+'\n',encoding='utf-8')
print('Building labels:',len(labels),'named:',sum(l['verified_name'] for l in labels),'unverified:',[(l['id'],l['short']) for l in labels if not l['verified_name']])
