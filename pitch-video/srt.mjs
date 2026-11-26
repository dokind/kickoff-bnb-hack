import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const dur = id => parseFloat(execFileSync('ffprobe', ['-v','error','-show_entries','format=duration','-of','csv=p=0',`vo/${id}.aiff`]).toString());
const lines = Object.fromEntries(readFileSync('vo/lines.txt','utf8').trim().split('\n').map(l => l.split('|')));
// same scene lengths as render.mjs
const clips = { s4: 8.8, s5: 12.2, s6: 8.4, s7b: 9.8 };
const order = ['s1','s2','s3','s4','s5','s6','s7','s7b','s8','s9','s10','s11'];
let t = 0.3, n = 1, out = '';
const ts = x => { const ms = Math.round(x*1000); const h=String(Math.floor(ms/3600000)).padStart(2,'0'), m=String(Math.floor(ms/60000)%60).padStart(2,'0'), s=String(Math.floor(ms/1000)%60).padStart(2,'0'), r=String(ms%1000).padStart(3,'0'); return `${h}:${m}:${s},${r}`; };
for (const id of order) {
  const v = lines[id] ? dur(id) : 0;
  let d = id === 's7' ? 6.4 : id === 's7b' ? clips.s7b : id === 's11' ? v + 3.2 : Math.max(v + 0.75, clips[id] || 0);
  if (lines[id]) {
    // split long lines into sentences over the voice's length
    const parts = lines[id].match(/[^.?!]+[.?!]?/g).map(x => x.trim()).filter(Boolean);
    const total = parts.reduce((a, p) => a + p.length, 0); let at = t + 0.2;
    for (const p of parts) { const len = v * p.length / total; out += `${n++}\n${ts(at)} --> ${ts(at + len)}\n${p}\n\n`; at += len; }
  }
  t += d;
}
writeFileSync('cypher-run-demo.srt', out); console.log(out.split('\n\n').length - 1, 'cues, ends', ts(t));
