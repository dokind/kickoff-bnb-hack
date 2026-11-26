// Swaps the voice of an already-rendered Cypher Run video for vo/s1..s11.aiff, without re-rendering the picture.
//   node dub-video.mjs <rendered.mp4> [vo-dir] [out.mp4]
// It finds the 11 spoken lines in the video's own (voice-only) audio, starts each new line where the old one
// started, and speeds a line up (at most 15%) only when it would run into the next one. Picture is copied as is,
// so the burned-in captions and scene cuts stay where they were.
import { execFileSync, spawnSync } from 'node:child_process';
import path from 'node:path';

const [video, voDir = 'vo', out = video.replace(/\.mp4$/, '') + '-my-voice.mp4'] = process.argv.slice(2);
if (!video) { console.error('usage: node dub-video.mjs <rendered.mp4> [vo-dir] [out.mp4]'); process.exit(1); }
const probe = f => parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString());
const total = probe(video);

// old line spans = gaps between silences of 0.4 s or more in the video's audio
const rep = spawnSync('ffmpeg', ['-hide_banner', '-i', video, '-vn', '-af', 'silencedetect=noise=-38dB:d=0.4', '-f', 'null', '-'], { encoding: 'utf8' }).stderr;
const starts = [...rep.matchAll(/silence_start: ([\d.]+)/g)].map(m => +m[1]);
const ends = [...rep.matchAll(/silence_end: ([\d.]+)/g)].map(m => +m[1]);
const spans = [];
let cur = 0;
for (let i = 0; i < starts.length; i++) { if (starts[i] - cur > 0.3) spans.push([cur, starts[i]]); cur = ends[i] ?? total; }
if (total - cur > 0.3) spans.push([cur, total]);
if (spans.length !== 11) { console.error(`found ${spans.length} spoken lines in ${video}, expected 11`); process.exit(2); }

const inputs = [], chains = [];
spans.forEach(([a], i) => {
  const f = path.join(voDir, `s${i + 1}.aiff`);
  const d = probe(f);
  const room = (i < 10 ? spans[i + 1][0] - 0.25 : total - 0.4) - a;
  const tempo = d > room ? Math.min(1.15, d / room) : 1;
  console.log(`s${i + 1}: old ${(spans[i][1] - a).toFixed(1)} s at ${a.toFixed(2)}, new ${d.toFixed(1)} s, room ${room.toFixed(1)} s${tempo > 1 ? `, sped up x${tempo.toFixed(3)}` : ''}${d / tempo > room + 0.01 ? '  (still overlaps the next line)' : ''}`);
  inputs.push('-i', f);
  const ms = Math.round(a * 1000);
  chains.push(`[${i + 1}:a]aresample=48000${tempo > 1 ? `,atempo=${tempo.toFixed(4)}` : ''},adelay=${ms}|${ms}[a${i}]`);
});
const mix = spans.map((_, i) => `[a${i}]`).join('') + `amix=inputs=11:normalize=0,apad,atrim=0:${total.toFixed(2)},loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[out]`;
execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', video, ...inputs, '-filter_complex', chains.join(';') + ';' + mix,
  '-map', '0:v', '-map', '[out]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-ac', '2', '-movflags', '+faststart', out]);
console.log(`wrote ${out}`);
