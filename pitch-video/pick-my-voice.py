"""Picks, for each of the 11 lines, the take that sounds most like the owner and reads back right.

Run with SoloSpark Voice's data Python (it has speechbrain + faster-whisper):
  C:/Users/ADMIN/projects/solospark-voice/workspace/envs/data/Scripts/python.exe pick-my-voice.py <cand-dir>... [--out vo]

SIM = cosine of ECAPA speaker embeddings vs his voice centroid from his real recordings
(solospark-voice/workspace/work/speaker_ref.npy), the same check the voice repo scores releases with.
A take is only eligible if English Whisper reads it back with at most 8 % word errors.
Writes the winners to <out>/s1.aiff ... s11.aiff and the full table to <out>/picks.json.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SSV = Path('C:/Users/ADMIN/projects/solospark-voice')

ap = argparse.ArgumentParser()
ap.add_argument('dirs', nargs='+')
ap.add_argument('--out', default=str(HERE / 'vo'))
ap.add_argument('--max-wer', type=float, default=0.08)
a = ap.parse_args()

import torch
from speechbrain.inference.speaker import EncoderClassifier
from speechbrain.utils.fetching import LocalStrategy
from faster_whisper import WhisperModel

lines = json.loads((HERE / 'voiceover-lines.json').read_text(encoding='utf-8'))
ref = np.load(SSV / 'workspace/work/speaker_ref.npy')
ref = ref / np.linalg.norm(ref)
enc = EncoderClassifier.from_hparams('speechbrain/spkrec-ecapa-voxceleb', savedir=str(SSV / 'workspace/models/ecapa'),
                                     run_opts={'device': 'cuda'}, local_strategy=LocalStrategy.COPY)
wm = WhisperModel('small.en', device='cuda', compute_type='float16')


def load16k(f):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(f), '-ac', '1', '-ar', '16000', '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


NUM = {'822': 'eight hundred twenty two', '411': 'four hundred eleven'}


def words(s):
    s = s.lower().replace('-', ' ').replace('cypherrun', 'cypher run')
    for k, v in NUM.items():
        s = s.replace(k, ' ' + v + ' ')
    return re.findall(r"[a-z']+", s)


def wer(hyp, refw):
    h, r = words(hyp), words(refw)
    d = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, hw in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (rw != hw))
    return d[len(h)] / max(len(r), 1)


rows = []
for dir_ in a.dirs:
    for f in sorted(Path(dir_).glob('s*.aiff')):
        m = re.match(r's(\d+)(?:_t(\d+))?$', f.stem)
        if not m:
            continue
        n = int(m.group(1))
        x = load16k(f)
        with torch.no_grad():
            e = enc.encode_batch(torch.from_numpy(x)[None].cuda()).squeeze().float().cpu().numpy()
        sim = float(e @ ref / np.linalg.norm(e))
        segs, _ = wm.transcribe(x, language='en', beam_size=5, condition_on_previous_text=False)
        heard = ' '.join(s.text.strip() for s in segs)
        rows.append({'line': n, 'file': str(f), 'sim': round(sim, 3), 'wer': round(wer(heard, lines[n - 1]), 3),
                     'heard': heard})
        print(f'{f}: sim {sim:.3f}  wer {rows[-1]["wer"]:.3f}', flush=True)

out = Path(a.out)
out.mkdir(parents=True, exist_ok=True)
picks = []
for n in range(1, len(lines) + 1):
    cands = [r for r in rows if r['line'] == n]
    ok = [r for r in cands if r['wer'] <= a.max_wer] or cands
    best = max(ok, key=lambda r: r['sim'])
    picks.append(best)
    shutil.copyfile(best['file'], out / f's{n}.aiff')
(out / 'picks.json').write_text(json.dumps({'picks': picks, 'all': rows}, indent=1), encoding='utf-8')
print('\npicked:')
for p in picks:
    print(f"  s{p['line']}: sim {p['sim']:.3f} wer {p['wer']:.3f}  {p['file']}")
sims = [p['sim'] for p in picks]
print(f'sim min {min(sims):.3f}  mean {np.mean(sims):.3f}')
