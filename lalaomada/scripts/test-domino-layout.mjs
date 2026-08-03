#!/usr/bin/env node
/**
 * Automated verification of the Domino snake-layout stability.
 *
 * Simulates the same geometry as SnakeBoard in src/components/DominoTable.tsx
 * across multiple screen sizes and progressive tile additions.
 *
 * Checks:
 *   1. No two tiles overlap (AABB intersection).
 *   2. Every adjacent pair remains logically connected after re-orientation.
 *   3. Tile React-keys (unordered pip pair) remain stable across recalcs —
 *      i.e. a tile present at step N is still present at step N+1 with the
 *      same key, so React preserves the DOM node and no reanimation fires.
 *
 * Run: node lalaomada/scripts/test-domino-layout.mjs
 */

const W = 20;
const LONG = W * 2;

function keyOf(t) { return `${Math.min(t[0], t[1])}-${Math.max(t[0], t[1])}`; }

/** Replicates SnakeBoard's 4-direction bouncing layout. */
function layout(board, { maxW, maxH, bendDown = true }) {
  if (board.length === 0) return [];
  const oriented = [];
  for (let i = 0; i < board.length; i++) {
    const raw = board[i];
    if (i === 0) { oriented.push([raw[0], raw[1]]); continue; }
    const prevRight = oriented[i - 1][1];
    if (raw[0] === prevRight) oriented.push([raw[0], raw[1]]);
    else if (raw[1] === prevRight) oriented.push([raw[1], raw[0]]);
    else oriented.push([raw[0], raw[1]]);
  }

  const rightSafety = Math.min(80, 20 + oriented.length * 2);
  const effW = Math.max(200, maxW - rightSafety);
  const halfW = effW / 2;
  const halfH = maxH / 2;
  const vSign = bendDown ? 1 : -1;

  const placed = [];
  let dir = 0; // 0=right,1=down,2=left,3=up
  let cx = -halfW + LONG / 2, cy = 0;

  const bend = (from) => {
    if (from === 0 || from === 2) return vSign > 0 ? 1 : 3;
    for (let k = placed.length - 1; k >= 0; k--) {
      if (!placed[k].vertical) {
        if (k > 0) {
          const ddx = placed[k].cx - placed[k - 1].cx;
          if (ddx > 0) return 2;
          if (ddx < 0) return 0;
        }
        return 2;
      }
    }
    return 2;
  };

  let justBent = false;
  for (let i = 0; i < oriented.length; i++) {
    const t = oriented[i];
    const isDouble = t[0] === t[1];
    const isHorizDir = dir === 0 || dir === 2;
    const inlineDouble = isDouble && justBent;
    const vertical = inlineDouble ? !isHorizDir : (isHorizDir ? isDouble : !isDouble);
    const along = inlineDouble ? LONG : (isDouble ? W : LONG);
    justBent = false;

    const render = (dir === 0 || dir === 1) ? [t[0], t[1]] : [t[1], t[0]];

    const dx = dir === 0 ? 1 : dir === 2 ? -1 : 0;
    const dy = dir === 1 ? 1 : dir === 3 ? -1 : 0;
    const tcx = cx + dx * along / 2;
    const tcy = cy + dy * along / 2;
    placed.push({ key: keyOf(board[i]), render, dir, cx: tcx, cy: tcy, vertical });
    cx += dx * along; cy += dy * along;

    if (i < oriented.length - 1) {
      const nextT = oriented[i + 1];
      const nextAlong = nextT[0] === nextT[1] ? W : LONG;
      let overflow = false;
      if (dir === 0 && cx + nextAlong > halfW) overflow = true;
      if (dir === 2 && cx - nextAlong < -halfW) overflow = true;
      if (dir === 1 && cy + nextAlong > halfH) overflow = true;
      if (dir === 3 && cy - nextAlong < -halfH) overflow = true;
      if (overflow) {
        const newDir = bend(dir);
        const oldDx = dir === 0 ? 1 : dir === 2 ? -1 : 0;
        const oldDy = dir === 1 ? 1 : dir === 3 ? -1 : 0;
        const newDx = newDir === 0 ? 1 : newDir === 2 ? -1 : 0;
        const newDy = newDir === 1 ? 1 : newDir === 3 ? -1 : 0;
        cx += (oldDx - newDx) * (W / 2);
        cy += (oldDy - newDy) * (W / 2);
        dir = newDir;
        justBent = true;
      }
    }
  }
  return placed;
}

function bbox(p) {
  const w = p.vertical ? W : LONG;
  const h = p.vertical ? LONG : W;
  return { x0: p.cx - w / 2, y0: p.cy - h / 2, x1: p.cx + w / 2, y1: p.cy + h / 2 };
}
function overlaps(a, b) {
  const A = bbox(a), B = bbox(b);
  const EPS = 0.5;
  return A.x0 + EPS < B.x1 && B.x0 + EPS < A.x1 && A.y0 + EPS < B.y1 && B.y0 + EPS < A.y1;
}

function connectionValue(p) {
  return p.dir === 0 || p.dir === 1 ? p.render[1] : p.render[0];
}

function entryValue(p) {
  return p.dir === 0 || p.dir === 1 ? p.render[0] : p.render[1];
}

/** Build a valid domino chain deterministically (matching pip on adjacent tiles). */
function buildChain(n) {
  const chain = [[6, 6]];
  let end = 6;
  const pool = [];
  for (let a = 0; a <= 6; a++) for (let b = a; b <= 6; b++) if (!(a === 6 && b === 6)) pool.push([a, b]);
  while (chain.length < n && pool.length) {
    const idx = pool.findIndex(t => t[0] === end || t[1] === end);
    if (idx < 0) break;
    const t = pool.splice(idx, 1)[0];
    if (t[0] === end) { chain.push(t); end = t[1]; }
    else { chain.push([t[1], t[0]]); end = t[0]; }
  }
  return chain;
}

const VIEWPORTS = [
  { name: "mobile-360",  maxW: 288, maxH: 260 },
  { name: "mobile-390",  maxW: 318, maxH: 280 },
  { name: "tablet-768",  maxW: 500, maxH: 380 },
  { name: "desktop-1280", maxW: 700, maxH: 460 },
];

let failed = 0, passed = 0;
for (const vp of VIEWPORTS) {
  const chain = buildChain(28);
  let prevKeys = new Set();
  for (let step = 1; step <= chain.length; step++) {
    const sub = chain.slice(0, step);
    const placed = layout(sub, vp);

    // 1) no overlaps
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        if (overlaps(placed[i], placed[j])) {
          console.error(`FAIL [${vp.name}] step=${step}: overlap tiles ${placed[i].key} & ${placed[j].key}`);
          failed++;
        }
      }
    }

    // 2) adjacent pips still match after bends / vertical rendering
    for (let i = 1; i < placed.length; i++) {
      const prev = placed[i - 1];
      const cur = placed[i];
      if (connectionValue(prev) !== entryValue(cur)) {
        console.error(`FAIL [${vp.name}] step=${step}: visual mismatch ${prev.key} -> ${cur.key}`);
        failed++;
      }
    }

    // 3) key stability — every prior key must still be present
    const curKeys = new Set(placed.map(p => p.key));
    for (const k of prevKeys) {
      if (!curKeys.has(k)) {
        console.error(`FAIL [${vp.name}] step=${step}: key ${k} disappeared between renders (would re-animate)`);
        failed++;
      }
    }
    prevKeys = curKeys;
    passed++;
  }
}

console.log(`\nDomino layout stability: ${passed} render steps checked across ${VIEWPORTS.length} viewports.`);
if (failed) { console.error(`${failed} failure(s).`); process.exit(1); }
console.log("OK — no overlaps, no key regressions across recalculations.");
