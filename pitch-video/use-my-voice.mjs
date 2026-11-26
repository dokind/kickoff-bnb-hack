// Turns one recorded voiceover take into the 11 lines the video uses, then the video can be
// re-rendered with the owner's voice:
//   node use-my-voice.mjs <recording.(m4a|mp3|wav|aiff)> [workdir]
// It cleans the take (high-pass, gentle noise reduction, level), finds the pauses between lines,
// keeps the 11 longest spoken stretches in order, and writes vo/s1.aiff ... vo/s11.aiff, which
// render.mjs reads. A stumble that was re-read becomes its own stretch; the last 11 are not
// assumed: the script prints every stretch so the split can be checked before rendering.
import { execFileSync } from 'node:child_process';
import { mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';

const input = process.argv[2];
const work = process.argv[3] || path.dirname(new URL(import.meta.url).pathname);
if (!input || !existsSync(input)) { console.error('usage: node use-my-voice.mjs <recording> [workdir]'); process.exit(1); }
const vo = path.join(work, 'vo');
mkdirSync(vo, { recursive: true });
const clean = path.join(work, 'my-voice-clean.wav');

// 1. clean and level the whole take
execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', input, '-ac', '1', '-ar', '48000',
  '-af', 'highpass=f=80,afftdn=nf=-25,acompressor=threshold=-20dB:ratio=3:attack=5:release=120,loudnorm=I=-16:TP=-1.5:LRA=9', clean]);

// 2. find silences of 0.6 s or more
// ffmpeg writes the silence report to stderr
const out = execFileSync('sh', ['-c', 'ffmpeg -hide_banner -i "$1" -af silencedetect=noise=-38dB:d=0.6 -f null - 2>&1 || true', 'sh', clean]).toString();
const total = parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', clean]).toString());
const starts = [...out.matchAll(/silence_start: ([\d.]+)/g)].map(m => +m[1]);
const ends = [...out.matchAll(/silence_end: ([\d.]+)/g)].map(m => +m[1]);

// 3. spoken stretches = gaps between silences
const speech = [];
let cursor = 0;
for (let i = 0; i < starts.length; i++) {
  if (starts[i] - cursor > 0.35) speech.push([cursor, starts[i]]);
  cursor = ends[i] ?? total;
}
if (total - cursor > 0.35) speech.push([cursor, total]);
console.log(`found ${speech.length} spoken stretches:`);
speech.forEach(([a, b], i) => console.log(`  ${i + 1}: ${a.toFixed(2)}–${b.toFixed(2)} s (${(b - a).toFixed(1)} s)`));
if (speech.length !== 11) {
  console.error(`\nExpected 11 lines, found ${speech.length}. Re-record with a full one-second pause between lines,\nor tell Claude which stretches to merge or drop.`);
  process.exit(2);
}

// 4. write each line with a little air around it
speech.forEach(([a, b], i) => {
  const s = Math.max(0, a - 0.12), e = Math.min(total, b + 0.18);
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-ss', String(s), '-to', String(e), '-i', clean, '-af', 'afade=t=in:d=0.04,areverse,afade=t=in:d=0.08,areverse', path.join(vo, `s${i + 1}.aiff`)]);
});
console.log(`\nwrote ${vo}/s1.aiff … s11.aiff. Next: node render.mjs portrait && node render.mjs landscape`);
