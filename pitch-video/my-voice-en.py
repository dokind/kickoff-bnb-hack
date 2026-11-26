"""English voiceover in the owner's own voice, made with SoloSpark Voice (the content-factory voice model).

SoloSpark Voice is tuned for Mongolian (its normaliser, lexicon and read-back check are Mongolian only), so this
script skips those and asks the same OmniVoice model + his voice to speak English directly. Run it with that
repo's Python:

  C:/Users/ADMIN/projects/solospark-voice/workspace/envs/train/Scripts/python.exe my-voice-en.py \
      [--voice namsrai-2.0] [--no-adapter] [--only 3,7] [--seed 0] [--speed 1.0]

Reads voiceover-lines.json (11 lines) and writes vo/s1.aiff ... vo/s11.aiff, which render.mjs reads.
--no-adapter keeps only his reference recording (zero-shot clone): usually cleaner English, a little less "him".
Licence: the OmniVoice weights are CC-BY-NC 4.0 (fine for a hackathon demo; not for paid use).
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SSV = Path('C:/Users/ADMIN/projects/solospark-voice')
sys.path.insert(0, str(SSV))

ap = argparse.ArgumentParser()
ap.add_argument('--voice', default='namsrai')
ap.add_argument('--no-adapter', action='store_true')
ap.add_argument('--only', default='')
ap.add_argument('--seed', type=int, default=0)
ap.add_argument('--speed', type=float, default=None)
ap.add_argument('--out', default=str(HERE / 'vo'))
ap.add_argument('--with-ref', action='store_true',
                help='also condition on his reference recording (namsrai-2.x leave it off for Mongolian; in English it '
                     'keeps the speaker from drifting)')
ap.add_argument('--takes', type=int, default=1, help='takes per line; more than 1 writes s<N>_t<K>.aiff for picking')
a = ap.parse_args()

import numpy as np
import soundfile as sf
from ssvoice.tts import Speaker

lines = json.loads((HERE / 'voiceover-lines.json').read_text(encoding='utf-8'))
only = {int(x) for x in a.only.split(',') if x.strip()}
out = Path(a.out)
out.mkdir(parents=True, exist_ok=True)

sp = Speaker(a.voice, qa=False, no_adapter=a.no_adapter or None, no_ref=False if a.with_ref else None)
print(f"voice: {sp.s['name']}  adapter: {sp.s.get('adapter')}  reference: {sp.prompt is not None}", flush=True)
for i, text in enumerate(lines, 1):
    if only and i not in only:
        continue
    for k in range(a.takes):
        sp.torch.manual_seed(a.seed + i + 1000 * k)
        audio = sp.model.generate(text=text, language='en', voice_clone_prompt=sp.prompt,
                                  speed=a.speed or sp.s.get('speed'), num_step=sp.s.get('num_step', 32),
                                  guidance_scale=sp.s.get('guidance', 2.0))[0]
        sp.torch.cuda.empty_cache()
        name = f's{i}' if a.takes == 1 else f's{i}_t{k}'
        wav = out / f'{name}.wav'
        sf.write(wav, np.asarray(audio, dtype=np.float32), sp.sr)
        # trim silence at both ends, level to -16 LUFS, 48 kHz AIFF for render.mjs
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-ar', '48000', '-af',
                        'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.08,areverse,'
                        'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.08,areverse,'
                        'loudnorm=I=-16:TP=-1.5:LRA=9', str(out / f'{name}.aiff')], check=True)
        wav.unlink()
        print(f'{name}: {len(audio) / sp.sr:.1f} s  {text[:60]}', flush=True)
print(f'wrote {out}/s*.aiff. Next: node render.mjs portrait && node render.mjs landscape')
