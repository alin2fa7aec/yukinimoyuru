#!/usr/bin/env node
// Checks the boxes and wiring in layout.mjs and writes the following three files.
//   - the marked box and wiring section of dotfiles/waybar/style.css
//   - pkgs/clock-ring/wires.json (wiring pixels for the round clock)
//   - dotfiles/waybar/circuit/preview.html (a preview to view in a browser)
// If anything breaks the rules, only the preview is written and it exits with code 1.
// Usage: node dotfiles/waybar/circuit/build.mjs
//
// Lines are turned into sequences of 1px pixels, then each horizontal or vertical segment becomes one rectangle drawn as a background layer.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as L from "./layout.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const STYLE = join(here, "..", "style.css");
const THEME = join(here, "..", "..", "theme", "nordfox.css");
const WIRES = join(here, "..", "..", "..", "pkgs", "clock-ring", "wires.json");
const PREVIEW = join(here, "preview.html");
const BEGIN = "/* circuit: begin (written by dotfiles/waybar/circuit/build.mjs. Do not edit by hand) */";
const END = "/* circuit: end */";

const errors = [];
const fail = (where, msg) => errors.push(`${where}: ${msg}`);
const eq = (a, b) => a[0] === b[0] && a[1] === b[1];
const add = (a, b, k = 1) => [a[0] + b[0] * k, a[1] + b[1] * k];

// ---- Contact points between lines and boxes ----

const RING_DIRS = { n: [0, -1], e: [1, 0], s: [0, 1], w: [-1, 0] };

// Return the contact point's pixel c on the box border and the outward direction n. A line ends touching the box at pixel c + n
function pinOf(mod, el, where) {
  if ("below" in el) {
    const at = el.below;
    if (at - L.tray.left < 3 || L.tray.right - at < 3) fail(where, `contact point on the tray's top edge (${at}) is too close to a corner`);
    return { c: [at, mod.h], n: [0, -1] };
  }
  if (mod.r) {
    const d = RING_DIRS[el.pin];
    if (!d) {
      fail(where, `cannot enter the circle at bearing ${el.pin} (must be one of n, e, s, w)`);
      return { c: [mod.cx, mod.cy], n: [0, -1] };
    }
    return { c: [mod.cx + d[0] * mod.r, mod.cy + d[1] * mod.r], n: d };
  }
  const [bx, by, s] = mod.box;
  const right = bx + s - 1;
  const bottom = by + s - 1;
  const sides = {
    top: { c: [el.at, by], n: [0, -1] },
    bottom: { c: [el.at, bottom], n: [0, 1] },
    left: { c: [bx, el.at], n: [-1, 0] },
    right: { c: [right, el.at], n: [1, 0] },
  };
  const p = sides[el.pin];
  if (!p) {
    fail(where, `box has no side ${el.pin}`);
    return { c: [0, 0], n: [0, -1] };
  }
  // Keep at least 3px from corners
  const horizontal = p.n[1] !== 0;
  const lo = horizontal ? bx : by;
  const hi = horizontal ? right : bottom;
  if (el.at - lo < 3 || hi - el.at < 3) fail(where, `contact point on ${el.pin} (${el.at}) is too close to a box corner`);
  return p;
}

// ---- Paths ----

// Turn a path into a sequence of pixels. Each pixel carries the direction taken to reach it
function trace(mod, tr, where) {
  const pins = [];
  const pts = tr.path.map((el, i) => {
    if (Array.isArray(el)) return el;
    if (i !== 0 && i !== tr.path.length - 1) fail(where, "contact points with boxes must be at the ends of the path only");
    const p = pinOf(mod, el, where);
    pins.push({ ...p, end: i === 0 ? "start" : "end" });
    return add(p.c, p.n);
  });

  const dirs = [];
  for (let i = 1; i < pts.length; i++) {
    const dx = pts[i][0] - pts[i - 1][0];
    const dy = pts[i][1] - pts[i - 1][1];
    if ((dx === 0) === (dy === 0)) fail(where, `[${pts[i - 1]}] to [${pts[i]}] is neither horizontal nor vertical`);
    dirs.push([Math.sign(dx), Math.sign(dy)]);
  }
  for (let i = 1; i < dirs.length; i++) {
    const a = dirs[i - 1];
    const b = dirs[i];
    if (a[0] * b[0] + a[1] * b[1] < 0) fail(where, `path doubles back at [${pts[i]}]`);
  }

  // Lines enter and leave box sides perpendicularly
  for (const p of pins) {
    const d = p.end === "start" ? dirs[0] : dirs[dirs.length - 1].map((v) => -v);
    if (!eq(d, p.n)) fail(where, "line does not enter or leave the box side perpendicularly");
  }

  const pixels = [{ x: pts[0][0], y: pts[0][1], d: dirs[0] }];
  let cur = pts[0];
  for (let i = 1; i < pts.length; i++) {
    const d = dirs[i - 1];
    let guard = 0;
    while (!eq(cur, pts[i]) && guard++ < 10000) {
      cur = add(cur, d);
      pixels.push({ x: cur[0], y: cur[1], d });
    }
  }
  const seen = new Set();
  for (const p of pixels) {
    const k = `${p.x},${p.y}`;
    if (seen.has(k)) fail(where, `passes [${k}] twice`);
    seen.add(k);
  }
  return { pixels, pins, fade: !!tr.fade, where };
}

// Turn a pixel sequence into one rectangle per run in the same direction
function runs(pixels) {
  const out = [];
  for (const p of pixels) {
    const last = out[out.length - 1];
    if (last && eq(last.d, p.d)) last.pixels.push(p);
    else out.push({ d: p.d, pixels: [p] });
  }
  return out.map((r) => {
    const xs = r.pixels.map((p) => p.x);
    const ys = r.pixels.map((p) => p.y);
    const x = Math.min(...xs);
    const y = Math.min(...ys);
    return { ...r, x, y, w: Math.max(...xs) - x + 1, h: Math.max(...ys) - y + 1 };
  });
}

// ---- Checks ----

function checkModule(name, mod, traces) {
  const w = mod.w ?? L.BAR_WIDTH;
  for (const t of traces) {
    for (const p of t.pixels) {
      if (p.x < 0 || p.x >= w || p.y < 0 || p.y >= mod.h) fail(t.where, `[${p.x},${p.y}] is outside the module`);
    }
  }

  // Distance from boxes (circles). Only the perpendicular part at a contact point may come close
  for (const t of traces) {
    const approach = new Set();
    for (const p of t.pins) {
      for (let k = 1; k <= L.CLEARANCE; k++) approach.add(add(p.c, p.n, k).join());
    }
    for (const p of t.pixels) {
      if (approach.has(`${p.x},${p.y}`)) continue;
      let near;
      if (mod.r) {
        near = Math.hypot(p.x + 0.5 - mod.cx, p.y + 0.5 - mod.cy) < mod.r + L.CLEARANCE;
      } else {
        const [bx, by, s] = mod.box;
        near = p.x > bx - 1 - L.CLEARANCE && p.x < bx + s + L.CLEARANCE && p.y > by - 1 - L.CLEARANCE && p.y < by + s + L.CLEARANCE;
      }
      if (near) {
        fail(t.where, `[${p.x},${p.y}] is too close to a box (keep at least ${L.CLEARANCE}px)`);
        break;
      }
    }
  }

  // Distance from other lines
  for (let i = 0; i < traces.length; i++) {
    for (let j = i + 1; j < traces.length; j++) {
      const hit = traces[i].pixels.find((a) =>
        traces[j].pixels.some((b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y)) < L.SPACING),
      );
      if (hit) fail(name, `lines ${i + 1} and ${j + 1} are too close at [${hit.x},${hit.y}] (keep at least ${L.SPACING}px)`);
    }
  }
}

// Positions of pixels crossing a boundary. Also checks that they are in a segment running in the crossing direction (vertical or horizontal)
function crossings(traces, test, vertical) {
  const xs = [];
  for (const t of traces) {
    t.pixels.forEach((p, i) => {
      if (!test(p)) return;
      const next = t.pixels[i + 1];
      const ok = [p.d, next?.d].filter(Boolean).every((d) => (vertical ? d[0] === 0 : d[1] === 0));
      if (!ok) fail(t.where, `[${p.x},${p.y}] does not cross the boundary with a ${vertical ? "vertical" : "horizontal"} segment`);
      xs.push(vertical ? p.x : p.y);
    });
  }
  return [...new Set(xs)].sort((a, b) => a - b);
}

// ---- Assembly ----

const built = {};
for (const [name, mod] of Object.entries(L.modules)) {
  const traces = mod.traces.map((tr, i) => trace(mod, tr, `${name} line ${i + 1}`));
  checkModule(name, mod, traces);
  built[name] = traces;
}
const ringTraces = L.ring.traces.map((tr, i) => trace(L.ring, tr, `clock ring line ${i + 1}`));
checkModule("clock ring", L.ring, ringTraces);

for (const [upper, lower] of L.stacks) {
  const a = crossings(built[upper], (p) => p.y === L.modules[upper].h - 1, true);
  const b = crossings(built[lower], (p) => p.y === 0, true);
  if (a.join() !== b.join()) fail(`${upper} -> ${lower}`, `line positions at the boundary do not match (upper [${a}], lower [${b}])`);
}
// The bar's leftmost column is also used as a vertical lane, so only line ends finishing horizontally at x=0 cross over to the clock ring
{
  const ends = new Set(built.overview.flatMap((t) => [t.pixels[0], t.pixels[t.pixels.length - 1]]));
  const a = crossings(built.overview, (p) => p.x === 0 && ends.has(p) && p.d[1] === 0, false);
  const b = crossings(ringTraces, (p) => p.x === L.ring.w - 1, false);
  if (a.join() !== b.join()) fail("overview -> clock ring", `line positions at the boundary do not match (bar [${a}], clock [${b}])`);
}

// ---- CSS ----

const px = (v) => `${v}px`;
const solid = (c) => `linear-gradient(${c}, ${c})`;
const FADES = {
  "0,1": "linear-gradient(@wire, @wire-end)",
  "0,-1": "linear-gradient(@wire-end, @wire)",
  "1,0": "linear-gradient(to right, @wire, @wire-end)",
  "-1,0": "linear-gradient(to right, @wire-end, @wire)",
};

// A module's background layers. From top to bottom: box border, lines, box fill
function layers(mod, traces) {
  const [bx, by, s] = mod.box;
  const edges = [
    { x: bx, y: by, w: s, h: 1 },
    { x: bx, y: by + s - 1, w: s, h: 1 },
    { x: bx, y: by, w: 1, h: s },
    { x: bx + s - 1, y: by, w: 1, h: s },
  ];
  const wires = traces.flatMap((t) => {
    const rs = runs(t.pixels);
    return rs.map((r, i) => ({ ...r, img: t.fade && i === rs.length - 1 ? FADES[r.d.join()] : null }));
  });
  return { edges, wires, glass: { x: bx, y: by, w: s, h: s } };
}

const HIDDEN = { x: -5, y: -5, w: 1, h: 1 };

function boxDecls(mod) {
  const [bx, by, s] = mod.box;
  return [`padding: ${px(by)} ${px(L.BAR_WIDTH - bx - s)} ${px(mod.h - by - s)} ${px(bx)};`, `min-height: ${px(s)};`];
}

function geometry(list) {
  return [
    `background-size: ${list.map((l) => `${px(l.w)} ${px(l.h)}`).join(", ")};`,
    `background-position: ${list.map((l) => `${px(l.x)} ${px(l.y)}`).join(", ")};`,
  ];
}

function images(list) {
  return ["background-image:", ...list.map((img, i) => `  ${img}${i === list.length - 1 ? ";" : ","}`)];
}

function rule(selector, decls) {
  return `${selector} {\n${decls.map((d) => `  ${d}`).join("\n")}\n}\n`;
}

const css = [];
const workspaceNames = Object.keys(L.modules).filter((n) => n.startsWith("ws"));

for (const [name, mod] of Object.entries(L.modules)) {
  if (workspaceNames.includes(name)) continue;
  const l = layers(mod, built[name]);
  const list = [...l.edges, ...l.wires, l.glass];
  const imgs = [...l.edges.map(() => solid("@edge")), ...l.wires.map((w) => w.img ?? solid("@wire")), solid("@glass")];
  css.push(rule(mod.selector, [...boxDecls(mod), ...images(imgs), ...geometry(list)]));
}

// Workspaces swap background layers per state, so keep the number and order of layers the same at every position
{
  const all = workspaceNames.map((n) => layers(L.modules[n], built[n]));
  const nWires = Math.max(...all.map((l) => l.wires.length));
  if (all.some((l) => l.wires.some((w) => w.img))) fail("workspaces", "fading lines cannot be used");
  workspaceNames.forEach((n, i) => {
    const l = all[i];
    const wires = [...l.wires, ...Array(nWires - l.wires.length).fill(HIDDEN)];
    css.push(rule(L.modules[n].selector, [...boxDecls(L.modules[n]), ...geometry([...l.edges, ...wires, l.glass])]));
  });
  for (const st of L.workspaceStates) {
    const imgs = [...Array(4).fill(solid(st.edge)), ...Array(nWires).fill(solid("@wire")), solid(st.glass)];
    css.push(rule(st.selector, images(imgs)));
  }
}

// ---- Clock ring ----

const ringJson = {
  size: [L.ring.w, L.ring.h],
  wires: ringTraces.flatMap((t) => {
    const rs = runs(t.pixels);
    return rs.flatMap((r, i) => {
      const fade = t.fade && i === rs.length - 1;
      // Fading segments get fainter starting from the beginning of the line
      return r.pixels.map((p, k) => [p.x, p.y, fade ? +(1 - (k + 0.5) / r.pixels.length).toFixed(3) : 1]);
    });
  }),
};

// ---- Output ----

const style = readFileSync(STYLE, "utf8");
const begin = style.indexOf(BEGIN);
const end = style.indexOf(END);
if (begin < 0 || end < begin) fail("style.css", "markers for the output location not found");
const generated = `${BEGIN}\n\n${css.join("\n")}\n${END}`;
const nextStyle = begin < 0 ? style : style.slice(0, begin) + generated + style.slice(end + END.length);

writeFileSync(PREVIEW, preview(nextStyle, readFileSync(THEME, "utf8"), ringJson));

if (errors.length) {
  console.error(`${errors.length} rule violations. style.css and wires.json were not rewritten`);
  for (const e of errors) console.error(`  ${e}`);
  console.error(`preview: ${PREVIEW}`);
  process.exit(1);
}
writeFileSync(STYLE, nextStyle);
writeFileSync(WIRES, `${JSON.stringify(ringJson)}\n`);
console.log(`wrote: ${STYLE}, ${WIRES}`);
console.log(`preview: ${PREVIEW}`);

// ---- Preview ----

// Make GTK CSS readable by browsers. Replace @define-color and alpha() with rgba()
function browserCss(gtk, theme) {
  const defs = new Map();
  for (const m of (theme + gtk).matchAll(/@define-color\s+([a-z0-9-]+)\s+([^;]+);/g)) defs.set(m[1], m[2].trim());
  const resolve = (expr) => {
    expr = expr.trim();
    let m;
    if ((m = expr.match(/^#([0-9a-f]{6})$/i))) return [0, 2, 4].map((i) => parseInt(m[1].slice(i, i + 2), 16)).concat(1);
    if ((m = expr.match(/^@([a-z0-9-]+)$/))) return resolve(defs.get(m[1]));
    if ((m = expr.match(/^alpha\((.+),\s*([\d.]+)\)$/))) {
      const c = resolve(m[1]);
      return [c[0], c[1], c[2], c[3] * Number(m[2])];
    }
    if (expr === "transparent") return [0, 0, 0, 0];
    throw new Error(`cannot parse color: ${expr}`);
  };
  const rgba = (c) => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${+c[3].toFixed(3)})`;
  let out = gtk.replace(/^@(define-color|import).*$/gm, "");
  let prev;
  do {
    prev = out;
    out = out.replace(/alpha\(([^()]+?),\s*([\d.]+)\)/g, (_, c, a) => rgba(resolve(`alpha(${c}, ${a})`)));
  } while (out !== prev);
  return out.replace(/@([a-z][a-z0-9-]*)/g, (_, n) => rgba(resolve(`@${n}`)));
}

function preview(gtkStyle, theme, ringData) {
  const css = browserCss(gtkStyle, theme);
  const colors = Object.fromEntries([...theme.matchAll(/@define-color ([a-z0-9]+) (#[0-9a-f]{6});/g)].map((m) => [m[1], m[2]]));
  const data = JSON.stringify({ ring: { ...L.ring, traces: undefined }, wires: ringData, colors, errors, rules: L.RULES });
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Circuit Preview</title>
<style>
:root { color-scheme: dark; }
body { margin: 0; padding: 16px; background: #15191f; color: #cdcecf; font: 14px/1.6 system-ui, sans-serif; }
h1 { font-size: 16px; margin: 0 0 8px; }
.layout { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.layout > div:first-child { flex: none; max-width: 100%; }
.side { max-width: 460px; }
.side ol { padding-left: 20px; margin: 4px 0 12px; }
.errors { color: #bf616a; white-space: pre-wrap; font-family: monospace; font-size: 12px; }
.ok { color: #a3be8c; }
.controls { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; align-items: center; }
.controls button { background: #2e3440; color: inherit; border: 1px solid #444c5e; padding: 2px 10px; cursor: pointer; }
.controls button.on { border-color: #88c0d0; color: #88c0d0; }
.viewport { overflow: auto; max-width: 100%; border: 1px solid #2e3440; }
.stage { display: flex; padding: 0; transform-origin: 0 0; background: radial-gradient(circle at 30% 20%, #3a4658, #1c2129 70%); width: max-content; }
.monitor { position: relative; display: flex; align-items: flex-start; }
.monitor > * { flex: none; }
.monitor + .monitor { border-left: 1px dashed rgba(255, 255, 255, 0.15); }
.monitor .label { position: absolute; bottom: 4px; font-size: 11px; color: rgba(255, 255, 255, 0.35); white-space: nowrap; }
.qhd .label { right: 60px; }
.k4 .label { left: 60px; }
canvas { image-rendering: pixelated; display: block; }
window { display: flex; flex-direction: column; justify-content: space-between; width: 52px; height: 760px; }
window > .ml, window > .mr { display: flex; flex-direction: column; }
window > div > div, #workspaces > button, #tray > span { display: flex; align-items: center; justify-content: center; white-space: pre; text-align: center; line-height: 1.1; }
#workspaces { flex-direction: column; align-items: stretch; }
#workspaces > button { font: inherit; }
#tray { flex-direction: column; gap: 8px; }
#tray > span { width: 16px; height: 16px; margin: 0 auto; background: #5a657d; }
</style>
<style>
${css}
</style>
</head>
<body>
<div class="layout">
<div>
<div class="controls">
<span>Zoom</span><span id="zoom"></span>
<span>Workspaces</span><span id="count"></span>
</div>
<div class="viewport">
<div id="scaled">
<div class="stage" id="stage">
<div class="monitor qhd">
<canvas id="ring"></canvas>
<window id="waybar" class="right">
<div class="ml">
<div id="custom-overview">󱒆</div>
<div id="workspaces"></div>
<div id="cpu">\n7</div>
<div id="memory">\n41</div>
<div id="idle_inhibitor" class="deactivated"></div>
<div id="pulseaudio">\n35</div>
<div id="clock">2026\n11/06</div>
<div id="custom-notification"></div>
<div id="tray"><span></span><span></span></div>
</div>
<div class="mr"><div id="custom-power">󰐥</div></div>
</window>
<span class="label">QHD (height shown shortened)</span>
</div>
<div class="monitor k4">
<window id="waybar" class="left">
<div class="ml">
<div id="custom-overview">󱒆</div>
<div id="workspaces"></div>
<div id="cpu">\n7</div>
<div id="memory">\n41</div>
<div id="idle_inhibitor" class="deactivated"></div>
<div id="pulseaudio">\n35</div>
<div id="clock">2026\n11/06</div>
<div id="custom-notification"></div>
</div>
<div class="mr"><div id="custom-power">󰐥</div></div>
</window>
<span class="label">4K</span>
</div>
</div>
</div>
</div>
</div>
<div class="side">
<h1>Wiring rules</h1>
<ol id="rules"></ol>
<h1>Checks</h1>
<div id="errors"></div>
</div>
</div>
<script>
const D = ${data};
document.getElementById("rules").innerHTML = D.rules.map((r) => "<li>" + r + "</li>").join("");
document.getElementById("errors").innerHTML = D.errors.length
  ? '<div class="errors">' + D.errors.join("\\n") + "</div>"
  : '<div class="ok">No rule violations</div>';

// Zoom and the number of workspaces can also be set in the URL as ?zoom=3&count=5
const q = new URLSearchParams(location.search);
let zoom = Number(q.get("zoom") ?? 2);
let count = Number(q.get("count") ?? 4);
function controls(id, values, get, set) {
  const el = document.getElementById(id);
  el.innerHTML = "";
  for (const v of values) {
    const b = document.createElement("button");
    b.textContent = v;
    b.className = get() === v ? "on" : "";
    b.onclick = () => { set(v); render(); };
    el.append(b);
  }
}
function render() {
  controls("zoom", [1, 2, 3, 4], () => zoom, (v) => (zoom = v));
  controls("count", [1, 2, 3, 4, 5, 6], () => count, (v) => (count = v));
  const stage = document.getElementById("stage");
  stage.style.transform = "scale(" + zoom + ")";
  const scaled = document.getElementById("scaled");
  scaled.style.width = stage.offsetWidth * zoom + "px";
  scaled.style.height = stage.offsetHeight * zoom + "px";
  for (const ws of document.querySelectorAll("#workspaces")) {
    ws.innerHTML = "";
    for (let i = 1; i <= count; i++) {
      const b = document.createElement("button");
      b.textContent = i;
      if (i === 1) b.className = "focused";
      ws.append(b);
    }
  }
}

// The clock ring. Drawn in the same order as paint in clock-ring.py
const ring = D.ring;
const canvas = document.getElementById("ring");
canvas.width = ring.w;
canvas.height = ring.h;
const cx = canvas.getContext("2d");
const C = D.colors;
const rgba = (hex, a) => "rgba(" + [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(",") + "," + a + ")";
function drawRing(t) {
  cx.clearRect(0, 0, ring.w, ring.h);
  for (const [x, y, a] of D.wires.wires) {
    cx.fillStyle = rgba(C.fg1, 0.3 * a);
    cx.fillRect(x, y, 1, 1);
  }
  cx.beginPath();
  cx.arc(ring.cx, ring.cy, ring.r, 0, Math.PI * 2);
  cx.fillStyle = rgba(C.bg1, 0.6);
  cx.fill();
  cx.beginPath();
  cx.arc(ring.cx, ring.cy, ring.r - 0.5, 0, Math.PI * 2);
  cx.strokeStyle = rgba(C.fg1, 0.4);
  cx.lineWidth = 1;
  cx.stroke();
  // Animate the spectrum with dummy values
  const n = 48;
  cx.strokeStyle = rgba(C.cyan, 0.7);
  cx.lineWidth = 3;
  cx.lineCap = "round";
  cx.beginPath();
  for (let i = 0; i < n; i++) {
    const v = Math.abs(Math.sin(t / 700 + i * 0.37) * Math.cos(t / 1300 + i * 0.11)) * (1 - Math.abs(i - n / 2) / n);
    if (v < 0.02) continue;
    const a = (300 / 180) * Math.PI - ((i + 0.5) / n) * (240 / 180) * Math.PI;
    const dx = Math.sin(a), dy = -Math.cos(a);
    const r0 = ring.r - 4, r1 = r0 - v * 30;
    cx.moveTo(ring.cx + dx * r0, ring.cy + dy * r0);
    cx.lineTo(ring.cx + dx * r1, ring.cy + dy * r1);
  }
  cx.stroke();
  const now = new Date();
  cx.font = "52px 'Moralerspace Argon HW', monospace";
  cx.textAlign = "center";
  cx.textBaseline = "middle";
  const half = 52 * 0.25;
  [[String(now.getHours()).padStart(2, "0"), C.fg1, -half, -0.42], [String(now.getMinutes()).padStart(2, "0"), C.cyan, half, 0.42]].forEach(([s, col, ox, oy]) => {
    const x = ring.cx + ox, y = ring.cy + oy * 52;
    cx.fillStyle = "rgba(0,0,0,0.6)";
    cx.fillText(s, x, y + 1);
    cx.fillStyle = col;
    cx.fillText(s, x, y);
  });
  requestAnimationFrame(drawRing);
}
render();
requestAnimationFrame(drawRing);
</script>
</body>
</html>
`;
}
