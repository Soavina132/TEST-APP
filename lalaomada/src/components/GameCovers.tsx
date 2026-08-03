import React from "react";

export type GameSlug = "ludo" | "domino" | "fanorona" | "chess" | "rami" | "poker";

// ─────────────────────────────────────────────────────────────────────────────
// Covers CSS — 0 octet réseau, chargement instantané
// ─────────────────────────────────────────────────────────────────────────────
export function LudoCover() {
  return (
    <div className="w-full h-full grid grid-cols-2 grid-rows-2">
      {/* 4 quadrants colorés */}
      <div className="bg-red-500 relative flex items-center justify-center">
        <div className="w-5 h-5 rounded-full bg-red-200 border-2 border-red-700 shadow-inner" />
      </div>
      <div className="bg-green-600 relative flex items-center justify-center">
        <div className="w-5 h-5 rounded-full bg-green-200 border-2 border-green-800 shadow-inner" />
      </div>
      <div className="bg-blue-600 relative flex items-center justify-center">
        <div className="w-5 h-5 rounded-full bg-blue-200 border-2 border-blue-800 shadow-inner" />
      </div>
      <div className="bg-yellow-400 relative flex items-center justify-center">
        <div className="w-5 h-5 rounded-full bg-yellow-100 border-2 border-yellow-600 shadow-inner" />
      </div>
      {/* Centre blanc */}
      <div className="absolute inset-[30%] bg-white rounded-sm shadow flex items-center justify-center">
        <div className="w-3 h-3 rounded-full bg-gray-200 border border-gray-300" />
      </div>
    </div>
  );
}

export function DominoCover() {
  return (
    <div className="w-full h-full bg-gradient-to-br from-gray-900 to-gray-800 flex items-center justify-center gap-1.5 p-2">
      {/* Tuile 1 penchée */}
      <div className="rotate-[-12deg] bg-white rounded-sm shadow-lg flex flex-col overflow-hidden" style={{ width: 24, height: 46 }}>
        <div className="flex-1 flex items-center justify-center">
          <div className="w-2 h-2 rounded-full bg-gray-800" />
        </div>
        <div className="h-px bg-gray-300" />
        <div className="flex-1 flex items-center justify-around px-1">
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
        </div>
      </div>
      {/* Tuile 2 droite */}
      <div className="bg-white rounded-sm shadow-lg flex flex-col overflow-hidden" style={{ width: 24, height: 46 }}>
        <div className="flex-1 grid grid-cols-2 gap-0.5 p-1.5">
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
        </div>
        <div className="h-px bg-gray-300" />
        <div className="flex-1 grid grid-cols-3 gap-0.5 p-1">
          <div className="w-1 h-1 rounded-full bg-gray-800" />
          <div className="w-1 h-1 rounded-full bg-gray-800" />
          <div className="w-1 h-1 rounded-full bg-gray-800" />
        </div>
      </div>
      {/* Tuile 3 penchée autre sens */}
      <div className="rotate-[10deg] bg-white rounded-sm shadow-lg flex flex-col overflow-hidden" style={{ width: 24, height: 46 }}>
        <div className="flex-1 grid grid-cols-2 gap-0.5 p-1.5">
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
          <div className="w-1.5 h-1.5 rounded-full bg-gray-800" />
        </div>
        <div className="h-px bg-gray-300" />
        <div className="flex-1 flex items-center justify-center">
          <div className="w-2 h-2 rounded-full bg-red-500" />
        </div>
      </div>
    </div>
  );
}

export function FanoronaCover() {
  // Plateau 5×5 simplifié avec pierres
  const dots = [
    [0,0,0,0,0],
    [0,1,0,2,0],
    [0,0,1,0,0],
    [0,2,0,1,0],
    [0,0,0,0,0],
  ];
  return (
    <div className="w-full h-full bg-gradient-to-br from-amber-800 to-amber-950 flex items-center justify-center p-3">
      <div className="grid gap-0" style={{ gridTemplateColumns: "repeat(5,1fr)", gridTemplateRows: "repeat(5,1fr)", width: "100%", height: "100%", maxWidth: 72, maxHeight: 72 }}>
        {dots.flat().map((v, i) => (
          <div key={i} className="relative flex items-center justify-center">
            {/* Lignes de grille via bordures */}
            <div className="absolute inset-0 border-r border-b border-amber-600/50" />
            {v === 1 && <div className="w-3 h-3 rounded-full bg-stone-900 border border-stone-700 shadow z-10" />}
            {v === 2 && <div className="w-3 h-3 rounded-full bg-amber-100 border border-amber-300 shadow z-10" />}
          </div>
        ))}
      </div>
    </div>
  );
}

export function ChessCover() {
  // Damier 4×4 avec quelques pièces unicode
  const pieces: Record<string, string> = {
    "0-0": "♜", "0-3": "♜",
    "1-1": "♟", "1-2": "♟",
    "2-1": "♙", "2-2": "♙",
    "3-0": "♖", "3-3": "♖",
  };
  return (
    <div className="w-full h-full bg-amber-800 flex items-center justify-center p-1">
      <div className="grid grid-cols-4 grid-rows-4 w-full h-full">
        {Array.from({ length: 16 }, (_, i) => {
          const row = Math.floor(i / 4), col = i % 4;
          const isLight = (row + col) % 2 === 0;
          const piece = pieces[`${row}-${col}`];
          return (
            <div key={i} className={`flex items-center justify-center ${isLight ? "bg-amber-100" : "bg-amber-800"}`}>
              {piece && (
                <span className={`text-[11px] leading-none select-none ${isLight ? "text-amber-900" : "text-amber-100"}`}>{piece}</span>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function RamiCover() {
  // Fond tapis vert + 3 cartes en éventail
  const cards = [
    { symbol: "♠", value: "A", color: "text-gray-900", rot: "-15deg", left: "10%", z: 1 },
    { symbol: "♥", value: "K", color: "text-red-600",  rot: "0deg",   left: "28%", z: 2 },
    { symbol: "♦", value: "Q", color: "text-red-600",  rot: "15deg",  left: "46%", z: 1 },
    { symbol: "♣", value: "J", color: "text-gray-900", rot: "30deg",  left: "64%", z: 0 },
  ];
  return (
    <div className="w-full h-full bg-gradient-to-br from-emerald-800 to-emerald-950 relative flex items-center justify-center overflow-hidden">
      {/* Texture tapis */}
      <div className="absolute inset-0 opacity-10"
        style={{ backgroundImage: "repeating-linear-gradient(45deg, #fff 0, #fff 1px, transparent 0, transparent 50%)", backgroundSize: "8px 8px" }} />
      {/* Cartes */}
      {cards.map((c, i) => (
        <div key={i} className="absolute bottom-3"
          style={{ left: c.left, transform: `rotate(${c.rot})`, zIndex: c.z }}>
          <div className="bg-white rounded-md shadow-lg flex flex-col items-center justify-between p-0.5"
            style={{ width: 22, height: 34, fontSize: 8 }}>
            <div className={`font-black leading-none ${c.color}`}>{c.value}</div>
            <div className={`text-base leading-none ${c.color}`}>{c.symbol}</div>
            <div className={`font-black leading-none rotate-180 ${c.color}`}>{c.value}</div>
          </div>
        </div>
      ))}
    </div>
  );
}

export function PokerCover() {
  const suits = [
    { s: "♠", c: "text-white" }, { s: "♣", c: "text-white" },
    { s: "♥", c: "text-red-400" }, { s: "♦", c: "text-red-400" },
  ];
  return (
    <div className="w-full h-full bg-gradient-to-br from-green-900 via-green-800 to-emerald-900 flex flex-col items-center justify-center gap-1">
      <div className="flex gap-2">
        {suits.map(s => (
          <span key={s.s} className={`text-2xl leading-none select-none ${s.c}`}>{s.s}</span>
        ))}
      </div>
      <div className="text-white text-[10px] font-black tracking-widest mt-1">POKER</div>
    </div>
  );
}

// Map slug → composant cover
export const COVER_COMPONENTS: Record<GameSlug, () => React.ReactElement> = {
  ludo:     LudoCover,
  domino:   DominoCover,
  fanorona: FanoronaCover,
  chess:    ChessCover,
  rami:     RamiCover,
  poker:    PokerCover,
};

// ─────────────────────────────────────────────────────────────────────────────
// Définition des jeux
// ─────────────────────────────────────────────────────────────────────────────
export type GameDef = { slug: GameSlug; label: string; desc: string; emoji: string };
export const GAME_DEFS: GameDef[] = [
  { slug: "ludo",     label: "Ludo",     desc: "2-4 joueurs", emoji: "🎲" },
  { slug: "domino",   label: "Domino",   desc: "2-4 joueurs", emoji: "🁣" },
  { slug: "fanorona", label: "Fanorona", desc: "2 joueurs",   emoji: "⚫" },
  { slug: "chess",    label: "Échecs",   desc: "2 joueurs",   emoji: "♟️" },
  { slug: "rami",     label: "Rami",     desc: "2-4 joueurs", emoji: "🃏" },
  { slug: "poker",    label: "Poker",    desc: "2-9 joueurs", emoji: "🂡" },
];
