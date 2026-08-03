import { useEffect, useMemo, useRef, useState } from "react";

type Color = "red" | "green" | "yellow" | "blue";
const COLORS: Color[] = ["red", "green", "yellow", "blue"];

const COLOR_META: Record<Color, { name: string; bg: string; text: string; soft: string; ring: string }> = {
  red: { name: "Rouge", bg: "bg-red-500", text: "text-red-600", soft: "bg-red-200", ring: "ring-red-600" },
  green: { name: "Vert", bg: "bg-green-500", text: "text-green-600", soft: "bg-green-200", ring: "ring-green-600" },
  yellow: { name: "Jaune", bg: "bg-yellow-400", text: "text-yellow-600", soft: "bg-yellow-200", ring: "ring-yellow-500" },
  blue: { name: "Bleu", bg: "bg-blue-500", text: "text-blue-600", soft: "bg-blue-200", ring: "ring-blue-600" },
};

// 52-cell path on a 15x15 board, [row, col]
const PATH: [number, number][] = [
  // Red arm 0-12
  [6, 1], [6, 2], [6, 3], [6, 4], [6, 5],
  [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6],
  [0, 7], [0, 8],
  // Green arm 13-25
  [1, 8], [2, 8], [3, 8], [4, 8], [5, 8],
  [6, 9], [6, 10], [6, 11], [6, 12], [6, 13], [6, 14],
  [7, 14], [8, 14],
  // Yellow arm 26-38
  [8, 13], [8, 12], [8, 11], [8, 10], [8, 9],
  [9, 8], [10, 8], [11, 8], [12, 8], [13, 8], [14, 8],
  [14, 7], [14, 6],
  // Blue arm 39-51
  [13, 6], [12, 6], [11, 6], [10, 6], [9, 6],
  [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0],
  [7, 0], [6, 0],
];

const START_IDX: Record<Color, number> = { red: 0, green: 13, yellow: 26, blue: 39 };

const HOME_STRETCH: Record<Color, [number, number][]> = {
  red:    [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6]],
  green:  [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7], [6, 7]],
  yellow: [[7, 13], [7, 12], [7, 11], [7, 10], [7, 9], [7, 8]],
  blue:   [[13, 7], [12, 7], [11, 7], [10, 7], [9, 7], [8, 7]],
};

// safe cells (starts of all colors)
const SAFE_CELLS = new Set(Object.values(START_IDX));

const YARD_SPOTS: Record<Color, [number, number][]> = {
  red:    [[1.6, 1.6], [1.6, 3.4], [3.4, 1.6], [3.4, 3.4]],
  green:  [[1.6, 10.6], [1.6, 12.4], [3.4, 10.6], [3.4, 12.4]],
  yellow: [[10.6, 10.6], [10.6, 12.4], [12.4, 10.6], [12.4, 12.4]],
  blue:   [[10.6, 1.6], [10.6, 3.4], [12.4, 1.6], [12.4, 3.4]],
};

const YARD_AREA: Record<Color, { r: number; c: number; bgClass: string; softClass: string }> = {
  red:    { r: 0, c: 0, bgClass: "bg-red-500", softClass: "bg-red-100" },
  green:  { r: 0, c: 9, bgClass: "bg-green-500", softClass: "bg-green-100" },
  yellow: { r: 9, c: 9, bgClass: "bg-yellow-400", softClass: "bg-yellow-100" },
  blue:   { r: 9, c: 0, bgClass: "bg-blue-500", softClass: "bg-blue-100" },
};

interface Pawn {
  id: string;
  color: Color;
  state: "yard" | "track" | "finished";
  step: number; // 0..56 when on track; -1 in yard; 57 when finished
}

function pawnCell(p: Pawn): [number, number] | null {
  if (p.state === "yard") return null;
  if (p.state === "finished") return null;
  if (p.step <= 50) {
    return PATH[(START_IDX[p.color] + p.step) % 52];
  }
  return HOME_STRETCH[p.color][p.step - 51];
}

const PLAYER_OPTIONS: Color[][] = [
  ["red", "yellow"],
  ["red", "green", "yellow"],
  ["red", "green", "yellow", "blue"],
];

export default function LudoGame() {
  const [numPlayers, setNumPlayers] = useState<number | null>(null);
  const [players, setPlayers] = useState<Color[]>([]);
  const [pawns, setPawns] = useState<Pawn[]>([]);
  const [turn, setTurn] = useState(0);
  const [dice, setDice] = useState<number | null>(null);
  const [rolling, setRolling] = useState(false);
  const [moving, setMoving] = useState(false);
  const [movingPawnId, setMovingPawnId] = useState<string | null>(null);
  const [winner, setWinner] = useState<Color | null>(null);
  const [message, setMessage] = useState<string>("");
  const [boardSize, setBoardSize] = useState(600);

  const boardRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const update = () => {
      const vh = window.innerHeight;
      const vw = window.innerWidth;
      // leave room for header (~120) + dice (~140) + margins
      const maxByH = vh - 280;
      const maxByW = vw - 40;
      setBoardSize(Math.max(320, Math.min(maxByH, maxByW, 820)));
    };
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  function startGame(n: number) {
    const colors = PLAYER_OPTIONS[n - 2];
    const newPawns: Pawn[] = [];
    colors.forEach((c) => {
      for (let i = 0; i < 4; i++) {
        newPawns.push({ id: `${c}-${i}`, color: c, state: "yard", step: -1 });
      }
    });
    setNumPlayers(n);
    setPlayers(colors);
    setPawns(newPawns);
    setTurn(0);
    setDice(null);
    setWinner(null);
    setMessage(`C'est au tour du joueur ${COLOR_META[colors[0]].name}`);
  }

  const currentColor = players[turn];

  function rollDice() {
    if (rolling || moving || dice !== null || winner) return;
    setRolling(true);
    let count = 0;
    const interval = setInterval(() => {
      setDice(1 + Math.floor(Math.random() * 6));
      count++;
      if (count > 8) {
        clearInterval(interval);
        const finalVal = 1 + Math.floor(Math.random() * 6);
        setDice(finalVal);
        setRolling(false);
        afterRoll(finalVal);
      }
    }, 70);
  }

  function afterRoll(val: number) {
    const movable = getMovablePawns(pawns, currentColor, val);
    if (movable.length === 0) {
      setMessage(`Aucun coup possible avec un ${val}. Tour suivant…`);
      setTimeout(() => endTurn(val), 900);
    } else if (movable.length === 1) {
      setMessage(`Le pion se déplace de ${val} cases.`);
      setTimeout(() => movePawn(movable[0], val), 350);
    } else {
      setMessage(`Choisis un pion à déplacer (${val} cases).`);
    }
  }

  function getMovablePawns(allPawns: Pawn[], color: Color, val: number): Pawn[] {
    const own = allPawns.filter((p) => p.color === color && p.state !== "finished");
    return own.filter((p) => {
      if (p.state === "yard") return val === 6;
      const newStep = p.step + val;
      if (newStep > 56) return false;
      return true;
    });
  }

  async function movePawn(pawn: Pawn, val: number) {
    setMoving(true);
    setMovingPawnId(pawn.id);

    let workingPawns = [...pawns];
    let curStep = pawn.step;
    let curState = pawn.state;

    if (curState === "yard") {
      // place on start cell
      curState = "track";
      curStep = 0;
      workingPawns = workingPawns.map((p) =>
        p.id === pawn.id ? { ...p, state: "track", step: 0 } : p,
      );
      setPawns(workingPawns);
      await sleep(250);
      // remaining: val - 1 if val == 6 (we used 0), but rule: 6 brings out and you re-roll. So no further movement.
      finalizeMove(workingPawns, pawn.id, val);
      return;
    }

    // step-by-step animation
    for (let i = 1; i <= val; i++) {
      curStep = pawn.step + i;
      workingPawns = workingPawns.map((p) =>
        p.id === pawn.id ? { ...p, step: curStep, state: curStep >= 57 ? "finished" : "track" } : p,
      );
      setPawns(workingPawns);
      await sleep(220);
    }

    finalizeMove(workingPawns, pawn.id, val);
  }

  function finalizeMove(updatedPawns: Pawn[], movedId: string, val: number) {
    const moved = updatedPawns.find((p) => p.id === movedId)!;
    let nextPawns = updatedPawns;

    // capture: if moved pawn is on track, not in home stretch, and not on safe cell
    if (moved.state === "track" && moved.step <= 50) {
      const cellIdx = (START_IDX[moved.color] + moved.step) % 52;
      if (!SAFE_CELLS.has(cellIdx)) {
        nextPawns = updatedPawns.map((p) => {
          if (p.color !== moved.color && p.state === "track" && p.step <= 50) {
            const otherIdx = (START_IDX[p.color] + p.step) % 52;
            if (otherIdx === cellIdx) {
              return { ...p, state: "yard", step: -1 };
            }
          }
          return p;
        });
        setPawns(nextPawns);
      }
    }

    setMoving(false);
    setMovingPawnId(null);

    // win check
    const colorPawns = nextPawns.filter((p) => p.color === moved.color);
    if (colorPawns.every((p) => p.state === "finished")) {
      setWinner(moved.color);
      setMessage(`🎉 ${COLOR_META[moved.color].name} a gagné !`);
      return;
    }

    // 6 → re-roll
    if (val === 6) {
      setDice(null);
      setMessage(`Tu as fait 6 ! Relance le dé.`);
    } else {
      endTurn(val);
    }
  }

  function endTurn(_val: number) {
    setDice(null);
    setMoving(false);
    setMovingPawnId(null);
    setTurn((t) => {
      const next = (t + 1) % players.length;
      setMessage(`C'est au tour du joueur ${COLOR_META[players[next]].name}`);
      return next;
    });
  }

  function onPawnClick(p: Pawn) {
    if (!currentColor || p.color !== currentColor) return;
    if (dice === null || rolling || moving || winner) return;
    const movable = getMovablePawns(pawns, currentColor, dice);
    if (!movable.find((m) => m.id === p.id)) return;
    movePawn(p, dice);
  }

  const cellPx = boardSize / 15;

  const movablePawnIds = useMemo(() => {
    if (!currentColor || dice === null || rolling || moving) return new Set<string>();
    return new Set(getMovablePawns(pawns, currentColor, dice).map((p) => p.id));
  }, [pawns, currentColor, dice, rolling, moving]);

  // pawn count per cell for stacking offsets
  const cellGroups = useMemo(() => {
    const map = new Map<string, Pawn[]>();
    pawns.forEach((p) => {
      const cell = pawnCell(p);
      if (!cell) return;
      const key = `${cell[0]}-${cell[1]}`;
      const arr = map.get(key) ?? [];
      arr.push(p);
      map.set(key, arr);
    });
    return map;
  }, [pawns]);

  if (numPlayers === null) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-slate-100 to-slate-200 p-6">
        <div className="rounded-3xl bg-white p-10 shadow-2xl ring-1 ring-slate-200">
          <h1 className="mb-2 text-center text-4xl font-bold text-slate-800">Ludo</h1>
          <p className="mb-8 text-center text-slate-500">Choisis le nombre de joueurs</p>
          <div className="flex gap-4">
            {[2, 3, 4].map((n) => (
              <button
                key={n}
                onClick={() => startGame(n)}
                className="flex h-28 w-28 flex-col items-center justify-center rounded-2xl bg-gradient-to-br from-indigo-500 to-purple-600 text-white shadow-lg transition-transform hover:scale-105 active:scale-95"
              >
                <span className="text-4xl font-bold">{n}</span>
                <span className="text-xs uppercase tracking-wide">joueurs</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-between gap-3 bg-gradient-to-br from-slate-100 to-slate-200 p-3">
      {/* Top: players */}
      <div className="flex w-full max-w-5xl flex-wrap items-center justify-center gap-3">
        {players.map((c, i) => {
          const isCurrent = i === turn && !winner;
          const finishedCount = pawns.filter((p) => p.color === c && p.state === "finished").length;
          return (
            <div
              key={c}
              className={`flex items-center gap-3 rounded-xl bg-white px-4 py-2 shadow ring-2 transition-all ${
                isCurrent ? `${COLOR_META[c].ring} scale-105` : "ring-transparent opacity-70"
              }`}
            >
              <div className={`h-6 w-6 rounded-full ${COLOR_META[c].bg} ${isCurrent ? "animate-pulse" : ""}`} />
              <div className="flex flex-col leading-tight">
                <span className={`font-semibold ${COLOR_META[c].text}`}>Joueur {COLOR_META[c].name}</span>
                <span className="text-xs text-slate-500">{finishedCount}/4 à la maison</span>
              </div>
            </div>
          );
        })}
        <button
          onClick={() => setNumPlayers(null)}
          className="ml-2 rounded-lg bg-slate-700 px-3 py-2 text-xs text-white shadow hover:bg-slate-800"
        >
          Nouvelle partie
        </button>
      </div>

      {/* Board */}
      <div
        ref={boardRef}
        className="relative rounded-xl bg-white shadow-2xl ring-1 ring-slate-300"
        style={{ width: boardSize, height: boardSize }}
      >
        <BoardGrid />

        {/* Pawns */}
        {pawns.map((p) => {
          let row: number, col: number;
          if (p.state === "yard") {
            const idx = parseInt(p.id.split("-")[1]);
            [row, col] = YARD_SPOTS[p.color][idx];
          } else if (p.state === "finished") {
            // place near center, offset by color
            const offsets: Record<Color, [number, number]> = {
              red: [6.6, 6.6], green: [6.6, 7.4], yellow: [7.4, 7.4], blue: [7.4, 6.6],
            };
            [row, col] = offsets[p.color];
          } else {
            const cell = pawnCell(p)!;
            row = cell[0];
            col = cell[1];
            // stacking offset if multiple pawns on same cell
            const key = `${row}-${col}`;
            const group = cellGroups.get(key) ?? [];
            const idx = group.findIndex((g) => g.id === p.id);
            if (group.length > 1) {
              const angle = (idx / group.length) * Math.PI * 2;
              row += Math.sin(angle) * 0.18;
              col += Math.cos(angle) * 0.18;
            }
          }

          const isMovable = movablePawnIds.has(p.id);
          const isMoving = movingPawnId === p.id;
          const meta = COLOR_META[p.color];

          return (
            <button
              key={p.id}
              onClick={() => onPawnClick(p)}
              disabled={!isMovable}
              className="absolute flex items-center justify-center rounded-full p-0 outline-none"
              style={{
                left: col * cellPx,
                top: row * cellPx,
                width: cellPx,
                height: cellPx,
                transition: "left 0.2s ease, top 0.2s ease",
                cursor: isMovable ? "pointer" : "default",
                zIndex: isMovable || isMoving ? 30 : 10,
              }}
            >
              <div
                className={`relative flex items-center justify-center rounded-full ${meta.bg} shadow-md ring-2 ring-white ${
                  isMovable ? "animate-bounce" : ""
                } ${isMoving ? "animate-jump" : ""}`}
                style={{
                  width: cellPx * 0.7,
                  height: cellPx * 0.7,
                }}
              >
                {isMovable && (
                  <span className={`absolute inset-0 rounded-full ${meta.bg} opacity-40 animate-ping`} />
                )}
                <div className="h-1/2 w-1/2 rounded-full bg-white/40" />
              </div>
            </button>
          );
        })}
      </div>

      {/* Bottom: dice */}
      <div className="flex flex-col items-center gap-2">
        <div className="text-sm font-medium text-slate-600">{message}</div>
        <button
          onClick={rollDice}
          disabled={dice !== null || rolling || moving || !!winner}
          className={`group relative h-20 w-20 rounded-2xl bg-white shadow-xl ring-2 transition-all ${
            currentColor ? COLOR_META[currentColor].ring : "ring-slate-300"
          } ${dice === null && !rolling && !moving && !winner ? "hover:scale-110 active:scale-95" : "opacity-80"}`}
        >
          <DiceFace value={dice ?? 0} rolling={rolling} />
        </button>
        <div className="text-xs text-slate-500">
          {dice === null ? "Clique sur le dé pour lancer" : `Tu as fait ${dice}`}
        </div>
      </div>
    </div>
  );
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

function BoardGrid() {
  // Render 15x15 cells with colored zones, paths, home stretches, center
  const cells = [];
  for (let r = 0; r < 15; r++) {
    for (let c = 0; c < 15; c++) {
      cells.push(<Cell key={`${r}-${c}`} r={r} c={c} />);
    }
  }
  return (
    <div className="grid h-full w-full" style={{ gridTemplateColumns: "repeat(15, 1fr)", gridTemplateRows: "repeat(15, 1fr)" }}>
      {cells}
    </div>
  );
}

function Cell({ r, c }: { r: number; c: number }) {
  // determine cell type
  // yard areas: 6x6 in each corner
  const inRedYard = r < 6 && c < 6;
  const inGreenYard = r < 6 && c > 8;
  const inYellowYard = r > 8 && c > 8;
  const inBlueYard = r > 8 && c < 6;

  // center 3x3
  const inCenter = r >= 6 && r <= 8 && c >= 6 && c <= 8;

  // path cells
  const pathIdx = PATH.findIndex(([pr, pc]) => pr === r && pc === c);
  const onPath = pathIdx >= 0;

  // home stretches
  let homeStretchColor: Color | null = null;
  for (const color of COLORS) {
    if (HOME_STRETCH[color].slice(0, 5).some(([sr, sc]) => sr === r && sc === c)) {
      homeStretchColor = color;
      break;
    }
  }

  // start cells
  const startColor = (Object.entries(START_IDX) as [Color, number][]).find(
    ([, idx]) => PATH[idx][0] === r && PATH[idx][1] === c,
  )?.[0];

  let bg = "bg-white";
  let extra = "";

  if (inRedYard) bg = "bg-red-100";
  else if (inGreenYard) bg = "bg-green-100";
  else if (inYellowYard) bg = "bg-yellow-100";
  else if (inBlueYard) bg = "bg-blue-100";
  else if (inCenter) bg = "bg-slate-50";
  else if (homeStretchColor) bg = COLOR_META[homeStretchColor].soft;
  else if (startColor) {
    bg = COLOR_META[startColor].soft;
    extra = "ring-1 ring-slate-400";
  } else if (onPath) {
    bg = "bg-white";
    extra = "ring-1 ring-slate-300";
  } else {
    bg = "bg-slate-50";
  }

  // inner yard panel: paint only outer ring of yard with color
  const isYardInner =
    (inRedYard && r >= 1 && r <= 4 && c >= 1 && c <= 4) ||
    (inGreenYard && r >= 1 && r <= 4 && c >= 10 && c <= 13) ||
    (inYellowYard && r >= 10 && r <= 13 && c >= 10 && c <= 13) ||
    (inBlueYard && r >= 10 && r <= 13 && c >= 1 && c <= 4);

  if (isYardInner) {
    if (inRedYard) bg = "bg-red-200";
    if (inGreenYard) bg = "bg-green-200";
    if (inYellowYard) bg = "bg-yellow-200";
    if (inBlueYard) bg = "bg-blue-200";
  }

  // colored yard rim
  const isYardOuterRim =
    (inRedYard || inGreenYard || inYellowYard || inBlueYard) && !isYardInner;
  if (isYardOuterRim) {
    if (inRedYard) bg = "bg-red-500";
    if (inGreenYard) bg = "bg-green-500";
    if (inYellowYard) bg = "bg-yellow-400";
    if (inBlueYard) bg = "bg-blue-500";
  }

  return <div className={`${bg} ${extra}`} />;
}

function DiceFace({ value, rolling }: { value: number; rolling: boolean }) {
  const dotPositions: Record<number, [number, number][]> = {
    0: [],
    1: [[1, 1]],
    2: [[0, 0], [2, 2]],
    3: [[0, 0], [1, 1], [2, 2]],
    4: [[0, 0], [0, 2], [2, 0], [2, 2]],
    5: [[0, 0], [0, 2], [1, 1], [2, 0], [2, 2]],
    6: [[0, 0], [0, 2], [1, 0], [1, 2], [2, 0], [2, 2]],
  };
  const dots = dotPositions[value] ?? [];
  return (
    <div className={`grid h-full w-full grid-cols-3 grid-rows-3 gap-1 p-3 ${rolling ? "animate-spin" : ""}`}>
      {Array.from({ length: 9 }).map((_, i) => {
        const r = Math.floor(i / 3);
        const c = i % 3;
        const filled = dots.some(([dr, dc]) => dr === r && dc === c);
        return (
          <div
            key={i}
            className={`rounded-full ${filled ? "bg-slate-800" : "bg-transparent"}`}
          />
        );
      })}
    </div>
  );
}
