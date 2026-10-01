#!/usr/bin/env python3
"""Build the pinned CC BY-SA 3.0 Mandarin sample pack. Requires macOS, numpy and soundfile.
Usage: python3 script/build_chinese_voice.py /tmp/weibei-animalese-research
The checked-in pack is used offline; this maintenance command alone downloads sources.
"""
import http.client
import hashlib, io, json, pathlib, struct, subprocess, sys, time, urllib.request, wave
import numpy as np
import soundfile as sf

COMMIT = 'ff9ed3d0c631195bd2c06f39450f3264c7124040'
cache = pathlib.Path(sys.argv[1]); cache.mkdir(parents=True, exist_ok=True)
root = pathlib.Path(__file__).resolve().parent.parent
resources = root / 'Sources/WeiBei/Resources/Editor'
def download(url):
    for attempt in range(4):
        try: return urllib.request.urlopen(url, timeout=60).read()
        except (OSError, http.client.IncompleteRead):
            if attempt == 3: raise
            time.sleep(attempt+1)
tree_file = cache / 'cmn-tree.json'
if not tree_file.exists(): tree_file.write_bytes(download(f'https://api.github.com/repos/hugolpz/audio-cmn/git/trees/{COMMIT}?recursive=1'))
tree = json.loads(tree_file.read_text())
assert tree['sha'] == COMMIT
files = sorted(x['path'] for x in tree['tree'] if x['path'].startswith('64k/syllabs/') and x['path'].endswith('.mp3'))
assert len(files) == 1707

def read(path):
    local = cache / pathlib.Path(path).name
    if not local.exists():
        local.write_bytes(download(f'https://raw.githubusercontent.com/hugolpz/audio-cmn/{COMMIT}/{path}'))
    raw = local.read_bytes()
    if b'CC-BY-SA-3.0' not in raw: raise ValueError('Missing license: ' + path)
    expected = next(x['sha'] for x in tree['tree'] if x['path'] == path)
    assert hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == expected
    data, rate = sf.read(io.BytesIO(raw), dtype='float32', always_2d=True); data = data.mean(axis=1)
    audible = np.flatnonzero(np.abs(data) > .012)
    if not len(audible): raise ValueError('Silent recording: ' + path)
    data = data[max(0, audible[0] - int(rate*.008)):min(len(data), audible[-1]+int(rate*.012))]
    data = np.interp(np.arange(int(len(data)*16000/rate))*rate/16000, np.arange(len(data)), data)
    peak = np.max(np.abs(data)); data = data * min(2, .8/peak)
    return pathlib.Path(path).stem.removeprefix('cmn-'), np.round(np.clip(data, -1, 1)*32767).astype('<i2').tobytes()

groups={}
for i,path in enumerate(files):
    name,pcm=read(path)
    groups.setdefault(name.lstrip('_')[0],[]).append((name,pcm))
    if i%200 == 0: print('verified samples', i, flush=True)
pack_dir=resources
index={}
for old in resources.glob('chinese-voice-*'):
    if old.suffix in ('.js', '.caf'): old.unlink()
for group,clips in groups.items():
    parts=[]; sprites={}; length=0
    for name,pcm in clips:
        sprites[name]={'startMs':length/32, 'durationMs':len(pcm)/32}; parts.append(pcm); length+=len(pcm);index[name]=group
    raw=cache/('pack-'+group+'.wav')
    with wave.open(str(raw),'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(16000);wav.writeframes(b''.join(parts))
    # Core Audio preserves the CAF packet table (including Opus pre-skip), so
    # decoded samples retain their exact boundaries. No codec ships in the app.
    encoded=pack_dir/('chinese-voice-'+group+'.caf')
    subprocess.run(['/usr/bin/afconvert',str(raw),str(encoded),'-f','caff','-d','opus','-b','10000'],check=True)
    # CAF reserves a free chunk for later metadata edits. Bundled assets are immutable.
    data=encoded.read_bytes(); compact=data[:8]; offset=8
    while offset<len(data):
        kind=data[offset:offset+4]; size=struct.unpack('>q',data[offset+4:offset+12])[0]
        assert size>=0 and offset+12+size<=len(data)
        if kind!=b'free': compact+=data[offset:offset+12+size]
        offset+=12+size
    encoded.write_bytes(compact)
    pack={'sampleRate':16000,'sprites':sprites}
    (pack_dir/('chinese-voice-'+group+'.js')).write_text('/* CC BY-SA 3.0. Chen Wang, Hugo Lopez, Nicolas Vion. See chinese-voice-LICENSE.txt. */\nwindow.WeiBeiChineseVoices['+json.dumps(group)+']='+json.dumps(pack,separators=(',',':'))+';\n')
(resources/'chinese-voice-index.js').write_text('window.WeiBeiChineseVoices={};window.WeiBeiChineseVoiceIndex='+json.dumps(index,separators=(',',':'))+';\n')
license_file=cache/'CC-BY-SA-3.0.txt'
if not license_file.exists(): license_file.write_bytes(download('https://raw.githubusercontent.com/spdx/license-list-data/main/text/CC-BY-SA-3.0.txt'))
license_text=license_file.read_text()
(resources/'chinese-voice-LICENSE.txt').write_text('中文动物语音节素材\n\nRecording: Chen Wang\nCopyright 2013 Wang Chen, Lopez Hugo, Vion Nicolas\nSource: https://github.com/hugolpz/audio-cmn/tree/'+COMMIT+'/64k/syllabs\n1707 source files; each verified against the Git blob SHA and its embedded CC-BY-SA-3.0 license.\nChanges by WeiBei: trim outer silence, normalize gain, downsample to mono 16000 Hz, concatenate by initial, encode Opus at 10000 bits/s in CAF using macOS Core Audio. The transformed sample pack remains CC BY-SA 3.0.\nRebuild: script/build_chinese_voice.py (macOS, numpy, soundfile).\nNeutral tones use the first-tone sample, following upstream removal of duplicated tone-5 recordings; no English or game audio is included.\n\n'+license_text)
print('packs',len(groups),'bytes',sum(p.stat().st_size for p in resources.glob('chinese-voice-*')),flush=True)
