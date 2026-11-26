// Renders the Cypher Run product video: an HTML timeline (compositor.html) drawn frame by frame in
// the system Chrome and piped into ffmpeg, with the voiceover mixed in.
//   node render.mjs portrait|landscape [preview]
import { chromium } from 'playwright-core';
import { spawn, execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const layout = process.argv[2] === 'landscape' ? 'landscape' : 'portrait';
const preview = process.argv[3] === 'preview';
const [W, H] = layout === 'landscape' ? [1920, 1080] : [1080, 1920];
const FPS = 30;

const dur = id => parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path.join(DIR, 'vo', id + '.aiff')]).toString());
const sum = cs => cs.reduce((a, c) => a + c.out, 0);

const FINE = 'Simulator demo: steps were added in the Health app by hand. On a real phone, only steps the phone counted are read.';
const scenes = [
  { id: 's1', vo: 's1' },
  { id: 's2', vo: 's2' },
  { id: 's3', vo: 's3' },
  { id: 's4', vo: 's4', clips: [
    { v: 'vapp', from: 27.6, to: 31, out: 2.6, tag: 'CYPHER RUN', cap: 'Join with <span class=volt>one tap</span>' },
    { v: 'vapp', from: 33.5, to: 45.5, out: 3.6, cap: 'Free test dollars, deposit paid' },
    { v: 'vapp', from: 46, to: 49, out: 2.6, cap: "You're in." } ] },
  { id: 's5', vo: 's5', fine: FINE, clips: [
    { v: 'vhealth', from: 34.2, to: 38.5, out: 3.2, tag: 'APPLE HEALTH', cap: 'Walk. Your phone counts the steps.' },
    { v: 'vapp', from: 57, to: 61.6, out: 3.0, tag: 'CYPHER RUN', cap: 'Read only: steps, nothing else' },
    { v: 'vapp', from: 62, to: 68, out: 3.2, cap: '1,000+ steps = <span class=volt>a check-in</span>' },
    { v: 'vapp', from: 75.6, to: 78.2, out: 2.8, cap: 'Your share: <span class=volt>0% → 100%</span>' } ] },
  { id: 's6', vo: 's6', clips: [
    { v: 'vapp', from: 78.2, to: 83, out: 4.0, cap: 'If it launched now: <span class=volt>700 test USD</span>' },
    { v: 'vapp', from: 86, to: 96, out: 4.4, cap: 'Every ending, spelled out' } ] },
  { id: 's7', vo: 's7', fixed: 6.4 },
  { id: 's7b', clips: [
    { v: 'vapp', from: 110, to: 113, out: 2.6, tag: 'LAUNCHED ON FLAP', cap: 'A real round on BSC testnet' },
    { v: 'vapp', from: 115.5, to: 124, out: 7.2, cap: '2 days: <span class=volt>822.32</span> · 1 day: <span class=volt>411.16</span> · 0 days: nothing' } ] },
  { id: 's8', vo: 's8' },
  { id: 's9', vo: 's9' },
  { id: 's10', vo: 's10' },
  { id: 's11', vo: 's11', tail: 3.2 },
];

let t = 0.3;
const tl = [];
const voAt = [];
for (const s of scenes) {
  const v = s.vo ? dur(s.vo) : 0;
  let d = s.fixed ?? Math.max(v + 0.75, s.clips ? sum(s.clips) : 0);
  if (s.clips && !s.vo) d = sum(s.clips);
  if (s.tail) d = v + s.tail;
  tl.push({ id: s.id, start: t, dur: d, clips: s.clips, fine: s.fine });
  if (s.vo) voAt.push({ id: s.vo, at: t + 0.2 });
  t += d;
}
const TOTAL = preview ? 12 : t + 0.3;
console.log(`layout ${layout}, ${TOTAL.toFixed(1)} s, ${Math.round(TOTAL * FPS)} frames`);

// Voiceover mix: every line placed at its scene, then normalised.
const audio = path.join(DIR, `vo_mix.wav`);
{
  const args = ['-v', 'error', '-y'];
  voAt.forEach(a => args.push('-i', path.join(DIR, 'vo', a.id + '.aiff')));
  const chains = voAt.map((a, i) => `[${i}:a]aresample=48000,adelay=${Math.round(a.at * 1000)}|${Math.round(a.at * 1000)}[a${i}]`);
  const mix = voAt.map((_, i) => `[a${i}]`).join('') + `amix=inputs=${voAt.length}:normalize=0,apad,atrim=0:${TOTAL.toFixed(2)},loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[out]`;
  args.push('-filter_complex', chains.join(';') + ';' + mix, '-map', '[out]', '-ac', '2', audio);
  execFileSync('ffmpeg', args);
}

const out = path.join(DIR, preview ? `preview_${layout}.mp4` : `cypher-run-demo-${layout === 'landscape' ? '1920x1080' : '1080x1920'}.mp4`);
const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-', '-i', audio,
  '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS),
  '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });

const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true,
  args: ['--autoplay-policy=no-user-gesture-required', '--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto('file://' + path.join(DIR, 'compositor.html') + '?layout=' + layout);
await page.evaluate(async () => {
  await document.fonts.ready;
  for (const v of document.querySelectorAll('video')) if (v.readyState < 2) await new Promise(r => v.addEventListener('loadeddata', r, { once: true }));
});
await page.evaluate(tl => window.init(tl), tl);

if (process.argv[3] === 'stills') {
  const { mkdirSync } = await import('node:fs');
  mkdirSync(path.join(DIR, 'stills'), { recursive: true });
  const marks = tl.map(s => s.start + Math.min(s.dur * 0.6, s.dur - 0.4));
  for (const m of marks) {
    await page.evaluate(x => window.render(x), m);
    await page.screenshot({ path: path.join(DIR, 'stills', `${layout}_${m.toFixed(1)}.jpg`), type: 'jpeg', quality: 70 });
  }
  console.log('stills at', marks.map(m => m.toFixed(1)).join(', '));
  await browser.close(); ff.kill(); process.exit(0);
}

const N = Math.round(TOTAL * FPS);
for (let f = 0; f < N; f++) {
  await page.evaluate(x => window.render(x), f / FPS);
  const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (f % 300 === 0) console.log(`frame ${f}/${N}`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log('wrote', out);
