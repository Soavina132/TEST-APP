import React from "react";
import { serverNow } from "@/lib/server-time";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, useCallback, useMemo, useRef } from "react";
import { useGameConnection } from "@/hooks/use-game-connection";
import { GameReconnectOverlay } from "@/components/GameReconnectOverlay";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { LogOut, Copy, Timer, Layers, Trash2, Plus, X, Check, Lightbulb, ChevronLeft, ChevronRight, ArrowLeftRight } from "lucide-react";
import GameChatDrawer from "@/components/GameChatDrawer";
import GamePauseControl from "@/components/GamePauseControl";
import GameInstructionsBanner from "@/components/GameInstructionsBanner";
import GameEndScreen from "@/components/GameEndScreen";
import GameWaitingRoom from "@/components/GameWaitingRoom";
import GameBoardSkin from "@/components/GameBoardSkin";
import TurnBanner from "@/components/TurnBanner";
import { useGameConfig } from "@/hooks/use-game-config";
import { useConfirm } from "@/components/ConfirmDialog";
import { useLongPressDrag } from "@/hooks/use-long-press-drag";
import ramiCover from "@/assets/games/rami.asset.json";

export const Route = createFileRoute("/_authenticated/rami/$id")({
  component: RamiPage,
  head: () => ({ meta: [{ title: "Rami — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

// ── Playing Card SVG Renderer ─────────────────────────────────────────────
const SUITS = ["♠", "♥", "♦", "♣"];
const SUIT_COLORS = ["#111827", "#dc2626", "#dc2626", "#111827"];
const RANKS = ["A","2","3","4","5","6","7","8","9","10","J","Q","K"];

function Pip({ suit, size = 7, flip = false }: { suit: number; size?: number; flip?: boolean }) {
  const s = size;
  const t = flip ? " rotate(180)" : "";
  if (suit === 0) {
    return <g transform={t} fill="#111827">
      <path d={`M0,${-s} C${s*.6},${-s*.3} ${s},${s*.4} ${s*.45},${s*.55} C${s*.8},${s*.55} ${s*.9},${s*.85} ${s*.65},${s} L${-s*.65},${s} C${-s*.9},${s*.85} ${-s*.8},${s*.55} ${-s*.45},${s*.55} C${-s},${s*.4} ${-s*.6},${-s*.3} 0,${-s}Z`} />
    </g>;
  }
  if (suit === 1) {
    return <g transform={t} fill="#dc2626">
      <path d={`M0,${s} C${-s*.9},${s*.1} ${-s},${-s*.55} ${-s*.55},${-s*.8} Q${-s*.15},${-s} 0,${-s*.45} Q${s*.15},${-s} ${s*.55},${-s*.8} C${s},${-s*.55} ${s*.9},${s*.1} 0,${s}Z`} />
    </g>;
  }
  if (suit === 2) {
    return <g transform={t} fill="#dc2626">
      <path d={`M0,${-s} L${s*.72},0 L0,${s} L${-s*.72},0Z`} />
    </g>;
  }
  return <g transform={t} fill="#111827">
    <circle r={s*.41} cy={-s*.48}/>
    <circle r={s*.41} cx={-s*.44} cy={s*.2}/>
    <circle r={s*.41} cx={s*.44} cy={s*.2}/>
    <rect x={-s*.14} y={s*.38} width={s*.28} height={s*.62}/>
    <rect x={-s*.48} y={s*.92} width={s*.96} height={s*.15}/>
  </g>;
}

const PIP_POS: [number, number, boolean][][] = [
  [[50, 70, false]],
  [[50, 31, false], [50, 109, true]],
  [[50, 31, false], [50, 70, false], [50, 109, true]],
  [[33, 31, false], [67, 31, false], [33, 109, true], [67, 109, true]],
  [[33, 31, false], [67, 31, false], [50, 70, false], [33, 109, true], [67, 109, true]],
  [[33, 31, false], [67, 31, false], [33, 70, false], [67, 70, false], [33, 109, true], [67, 109, true]],
  [[33, 31, false], [67, 31, false], [50, 49, false], [33, 70, false], [67, 70, false], [33, 109, true], [67, 109, true]],
  [[33, 31, false], [67, 31, false], [50, 49, false], [33, 70, false], [67, 70, false], [50, 91, true], [33, 109, true], [67, 109, true]],
  [[33, 28, false], [67, 28, false], [33, 54, false], [67, 54, false], [50, 70, false], [33, 86, true], [67, 86, true], [33, 112, true], [67, 112, true]],
  [[33, 28, false], [67, 28, false], [50, 41, false], [33, 55, false], [67, 55, false], [33, 85, true], [67, 85, true], [50, 99, true], [33, 112, true], [67, 112, true]],
];

function PipCard({ rank, suit }: { rank: number; suit: number }) {
  const pips = PIP_POS[rank];
  const isAce = rank === 0;
  return <>
    {pips.map(([cx, cy, flip], i) => (
      <g key={i} transform={`translate(${cx},${cy})`}>
        <Pip suit={suit} size={isAce ? 19 : 7} flip={flip} />
      </g>
    ))}
  </>;
}

import jackAsset from "@/assets/rami/jack.png.asset.json";
import queenAsset from "@/assets/rami/queen.png.asset.json";
import kingAsset from "@/assets/rami/king.png.asset.json";
import joker0Asset from "@/assets/rami/joker-0.png.asset.json";
import joker1Asset from "@/assets/rami/joker-1.png.asset.json";
import joker2Asset from "@/assets/rami/joker-2.png.asset.json";
import joker3Asset from "@/assets/rami/joker-3.png.asset.json";

const FACE_ART: Record<number, string> = {
  10: jackAsset.url,  // J
  11: queenAsset.url, // Q
  12: kingAsset.url,  // K
};
const JOKER_ART = [joker0Asset.url, joker1Asset.url, joker2Asset.url, joker3Asset.url];

function FacePortrait({ rank, suit }: { rank: number; suit: number }) {
  const isRed = suit === 1 || suit === 2;
  const frame = isRed ? "#b91c1c" : "#1e3a5f";
  const robe = isRed ? "#dc2626" : "#1e40af";
  const robeDark = isRed ? "#7f1d1d" : "#1e3a8a";
  const skin = "#f5d0a9";
  const gold = "#eab308";
  const goldDark = "#a16207";
  const uid = `${suit}-${rank}`;

  // Draw a stylized figure top / rotated bottom
  const Figure = () => (
    <g>
      {/* robe / shoulders */}
      <path d={`M20,58 Q20,44 50,44 Q80,44 80,58 L80,68 L20,68 Z`} fill={robe} />
      <path d={`M20,58 Q20,44 50,44 Q80,44 80,58 L80,60 L20,60 Z`} fill={robeDark} opacity="0.55" />
      {/* collar V */}
      <path d="M42,44 L50,54 L58,44 Z" fill={skin} />
      {/* neck */}
      <rect x="46" y="40" width="8" height="6" fill={skin} />
      {/* face */}
      <ellipse cx="50" cy="34" rx="10" ry="11" fill={skin} />
      {/* hair / beard hints per rank */}
      {rank === 12 && (
        // King: full beard + moustache
        <>
          <path d="M40,34 Q40,44 50,46 Q60,44 60,34 L60,40 Q50,50 40,40 Z" fill="#4b3218" />
          <path d="M44,34 Q50,37 56,34" stroke="#4b3218" strokeWidth="1.4" fill="none" />
        </>
      )}
      {rank === 11 && (
        // Queen: long hair falling on shoulders
        <>
          <path d="M38,32 Q36,50 44,58 L44,44 Z" fill="#5b3a1e" />
          <path d="M62,32 Q64,50 56,58 L56,44 Z" fill="#5b3a1e" />
          <path d="M40,26 Q50,20 60,26 Q60,32 50,30 Q40,32 40,26 Z" fill="#5b3a1e" />
        </>
      )}
      {rank === 10 && (
        // Jack: youthful, hat feather cap
        <>
          <path d="M40,30 Q50,20 60,30 L58,26 Q50,22 42,26 Z" fill="#4b3218" />
          <path d="M60,26 Q68,20 66,14 L60,22 Z" fill={isRed ? "#f59e0b" : "#f59e0b"} />
        </>
      )}
      {/* eyes */}
      <circle cx="46" cy="33" r="0.9" fill="#111827" />
      <circle cx="54" cy="33" r="0.9" fill="#111827" />
      {/* Crown */}
      <g>
        <path d="M36,22 L42,14 L46,20 L50,12 L54,20 L58,14 L64,22 L64,26 L36,26 Z" fill={gold} stroke={goldDark} strokeWidth="0.6" />
        <rect x="36" y="24" width="28" height="2.2" fill={goldDark} />
        <circle cx="42" cy="14" r="1.1" fill="#fca5a5" />
        <circle cx="50" cy="12" r="1.3" fill="#86efac" />
        <circle cx="58" cy="14" r="1.1" fill="#93c5fd" />
      </g>
      {/* suit medallion on chest */}
      <circle cx="50" cy="62" r="4.2" fill={isRed ? "#fee2e2" : "#dbeafe"} stroke={frame} strokeWidth="0.6" />
      <text x="50" y="64.5" textAnchor="middle" fontSize="6" fontWeight="900" fill={isRed ? "#dc2626" : "#111827"}>{SUITS[suit]}</text>
    </g>
  );

  return <>
    {/* card interior panel */}
    <rect x="7" y="19" width="86" height="102" rx="4" fill={isRed ? "#fef2f2" : "#eff6ff"} />
    <rect x="7" y="19" width="86" height="102" rx="4" fill="none" stroke={frame} strokeWidth="1" opacity="0.55" />
    {/* separator */}
    <line x1="10" y1="70" x2="90" y2="70" stroke={frame} strokeWidth="0.4" opacity="0.35" />
    {/* top figure */}
    <clipPath id={`tc-${uid}`}><rect x="7" y="19" width="86" height="51" /></clipPath>
    <g clipPath={`url(#tc-${uid})`}>
      <Figure />
    </g>
    {/* bottom mirrored figure */}
    <clipPath id={`bc-${uid}`}><rect x="7" y="70" width="86" height="51" /></clipPath>
    <g clipPath={`url(#bc-${uid})`} transform="rotate(180 50 70)">
      <Figure />
    </g>
    {/* corner rank label (letter of the face card in the centre band) */}
    <g>
      <rect x="42" y="66" width="16" height="8" rx="1.5" fill={frame} />
      <text x="50" y="72.5" textAnchor="middle" fontSize="6.4" fontWeight="900" fill={gold} fontFamily="Georgia, serif" letterSpacing="1">
        {RANKS[rank]}
      </text>
    </g>
  </>;
}


function JokerFace({ idx }: { idx: number }) {
  const schemes = ["#dc2626", "#7c3aed", "#059669", "#b45309"];
  const color = schemes[idx % 4];
  const href = JOKER_ART[idx % 4];
  return <>
    <rect x="3" y="3" width="94" height="134" rx="4" fill="#fefce8" />
    <rect x="3" y="3" width="94" height="134" rx="4" fill="none" stroke={color} strokeWidth="1.2" opacity="0.55" />
    <text x="50" y="14" textAnchor="middle" fontSize="7" fontWeight="bold" fontFamily="serif" fill={color} letterSpacing="2">JOKER</text>
    <g transform="rotate(180 50 70)">
      <text x="50" y="14" textAnchor="middle" fontSize="7" fontWeight="bold" fontFamily="serif" fill={color} letterSpacing="2">JOKER</text>
    </g>
    <image href={href} x="12" y="18" width="76" height="104" preserveAspectRatio="xMidYMid meet" />
  </>;
}

function Card({
  c, selected, onClick, size = "md", faceDown, onRemove, highlight, dealDelay, styleOverride,
}: {
  c?: number; selected?: boolean; onClick?: () => void;
  size?: "sm" | "md" | "lg" | "xl"; faceDown?: boolean; onRemove?: () => void;
  highlight?: "layoff" | "none"; dealDelay?: number;
  styleOverride?: React.CSSProperties;
}) {
  const sizeClass = styleOverride ? "" :
    size === "sm" ? "w-9 h-14" :
    size === "lg" ? "w-16 h-24" :
    size === "xl" ? "w-20 h-28" :
    "w-12 h-[72px]";


  const dealStyle: React.CSSProperties = dealDelay !== undefined ? {
    animationDelay: `${dealDelay}ms`,
    opacity: 0,
    animation: `dealCard 0.35s ease-out ${dealDelay}ms forwards`,
  } : {};

  if (faceDown || c === undefined) {
    return (
      <div className={`${sizeClass} rounded-md shrink-0 shadow overflow-hidden`} style={{ ...dealStyle, ...styleOverride }}>

        <svg viewBox="0 0 100 140" className="w-full h-full">
          <rect x="0" y="0" width="100" height="140" rx="6" fill="#1e40af" />
          <rect x="4" y="4" width="92" height="132" rx="5" fill="none" stroke="#93c5fd" strokeWidth="1" />
          {Array.from({ length: 7 }, (_, i) => i).map(row =>
            Array.from({ length: 5 }, (_, col) => (
              <path key={`${row}-${col}`}
                d={`M${10 + col * 16 + (row % 2 === 0 ? 8 : 0)},${12 + row * 18} l6,-8 l6,8 l-6,8Z`}
                fill="#1d4ed8" stroke="#3b82f6" strokeWidth="0.3" />
            ))
          )}
        </svg>
      </div>
    );
  }

  const isJoker = c >= 52;
  const suit = isJoker ? 0 : Math.floor(c / 13);
  const rank = isJoker ? 0 : c % 13;
  const rankLabel = isJoker ? "★" : RANKS[rank];
  const suitSymbol = isJoker ? "" : SUITS[suit];
  const color = isJoker ? "#7c3aed" : SUIT_COLORS[suit];
  const isFace = !isJoker && rank >= 10;
  const fontSize = rankLabel === "10" ? 9.5 : 11;

  return (
    <div className="relative shrink-0" style={dealStyle}>
      <button
        onClick={onClick}
        disabled={!onClick}
        style={styleOverride}
        className={`${sizeClass} block transition-transform duration-100
          ${selected ? "-translate-y-3 drop-shadow-lg" : ""}
          ${highlight === "layoff" ? "ring-2 ring-emerald-400 ring-offset-1 scale-105" : ""}
          ${onClick ? "hover:-translate-y-1 cursor-pointer active:scale-95" : "cursor-default"}`}
      >

        <svg viewBox="0 0 100 140" xmlns="http://www.w3.org/2000/svg" className="w-full h-full drop-shadow">
          <rect x="0.5" y="0.5" width="99" height="139" rx="6" fill="white" stroke="#d1d5db" strokeWidth="1" />
          {isJoker ? (
            <JokerFace idx={c - 52} />
          ) : (
            <>
              <text x="5.5" y="14" fontSize={fontSize} fontWeight="900" fill={color} fontFamily="Georgia, serif">{rankLabel}</text>
              <g transform="translate(5.5,14.5)">
                <g transform="translate(3.5,5)"><Pip suit={suit} size={5} /></g>
              </g>
              <g transform="rotate(180,50,70)">
                <text x="5.5" y="14" fontSize={fontSize} fontWeight="900" fill={color} fontFamily="Georgia, serif">{rankLabel}</text>
                <g transform="translate(5.5,14.5)">
                  <g transform="translate(3.5,5)"><Pip suit={suit} size={5} /></g>
                </g>
              </g>
              {isFace ? <FacePortrait rank={rank} suit={suit} /> : <PipCard rank={rank} suit={suit} />}
            </>
          )}
        </svg>
        {selected && <div className="absolute inset-0 rounded-md ring-2 ring-emerald-400 pointer-events-none" />}
      </button>

      {onRemove && (
        <button onClick={onRemove}
          className="absolute -top-2 -right-2 w-5 h-5 rounded-full bg-destructive text-white flex items-center justify-center z-10 shadow">
          <X className="w-3 h-3" />
        </button>
      )}
    </div>
  );
}


// ── Optimal play suggester ────────────────────────────────────────────────
const CARD_POINTS = (c: number): number => {
  if (c >= 52) return 15;
  const r = c % 13;
  if (r === 0) return 11;
  if (r >= 10) return 10;
  return r + 1;
};

type MeldValidity = 'valid' | 'invalid' | 'unknown';

function validateMeld(
  cards: number[],
  jokerMode: string,
  randomJoker: number | null,
): MeldValidity {
  if (cards.length < 3) return 'unknown';

  const isJoker = (c: number) => {
    if (c >= 52) return true;
    if (jokerMode === 'aleatoire' && randomJoker !== null && c === randomJoker) return true;
    return false;
  };

  const jokerCount = cards.filter(isJoker).length;
  const real = cards.filter(c => !isJoker(c));

  const checkSet = (): boolean => {
    if (cards.length > 4) return false;
    // Mirror server rule: at least 2 real cards required (no all-joker melds)
    if (real.length < 2) return false;
    const rank = real[0] % 13;
    if (!real.every(c => c % 13 === rank)) return false;
    const suits = real.map(c => Math.floor(c / 13));
    return new Set(suits).size === suits.length;
  };

  const checkSequence = (): boolean => {
    if (real.length < 2) return false;
    const suit = Math.floor(real[0] / 13);
    if (!real.every(c => Math.floor(c / 13) === suit)) return false;
    const ranks = real.map(c => c % 13).sort((a, b) => a - b);
    let gaps = 0;
    for (let i = 1; i < ranks.length; i++) {
      const diff = ranks[i] - ranks[i - 1];
      if (diff === 0) return false;
      gaps += diff - 1;
    }
    return gaps <= jokerCount;
  };

  return checkSet() || checkSequence() ? 'valid' : 'invalid';
}

// Find all valid melds (3–7 cards) in a hand
function findAllValidMelds(hand: number[], jokerMode: string, randomJoker: number | null): number[][] {
  const melds: number[][] = [];
  const n = hand.length;
  for (let i = 0; i < n; i++)
    for (let j = i + 1; j < n; j++)
      for (let k = j + 1; k < n; k++) {
        const trio = [hand[i], hand[j], hand[k]];
        if (validateMeld(trio, jokerMode, randomJoker) === 'valid') melds.push(trio);
        for (let l = k + 1; l < n; l++) {
          const quad = [hand[i], hand[j], hand[k], hand[l]];
          if (validateMeld(quad, jokerMode, randomJoker) === 'valid') melds.push(quad);
          for (let m = l + 1; m < n; m++) {
            const five = [hand[i], hand[j], hand[k], hand[l], hand[m]];
            if (validateMeld(five, jokerMode, randomJoker) === 'valid') melds.push(five);
            for (let o = m + 1; o < n; o++) {
              const six = [hand[i], hand[j], hand[k], hand[l], hand[m], hand[o]];
              if (validateMeld(six, jokerMode, randomJoker) === 'valid') melds.push(six);
            }
          }
        }
      }
  // Sort: bigger melds first, then by total points desc
  melds.sort((a, b) => b.length !== a.length ? b.length - a.length
    : b.reduce((s, c) => s + CARD_POINTS(c), 0) - a.reduce((s, c) => s + CARD_POINTS(c), 0));
  return melds;
}

interface OptimalPlay {
  melds: number[][];
  leftover: number[];
  totalMelded: number;
  savedPoints: number;
}

function suggestOptimalPlay(hand: number[], jokerMode: string, randomJoker: number | null): OptimalPlay | null {
  const allMelds = findAllValidMelds(hand, jokerMode, randomJoker);
  if (allMelds.length === 0) return null;

  let bestMelds: number[][] = [];
  let bestCovered = 0;
  let bestSaved = 0;

  // Backtracking: find the set of non-overlapping melds maximising cards melded
  // then minimising leftover points
  function backtrack(idx: number, used: Set<number>, current: number[][]): void {
    const covered = used.size;
    const saved = [...used].reduce((s, c) => s + CARD_POINTS(c), 0);
    if (covered > bestCovered || (covered === bestCovered && saved > bestSaved)) {
      bestCovered = covered;
      bestSaved = saved;
      bestMelds = current.map(m => [...m]);
    }
    if (idx >= allMelds.length) return;
    for (let i = idx; i < allMelds.length; i++) {
      const meld = allMelds[i];
      if (meld.some(c => used.has(c))) continue;
      // Pruning: even if we take all remaining melds, can we beat best?
      meld.forEach(c => used.add(c));
      backtrack(i + 1, used, [...current, meld]);
      meld.forEach(c => used.delete(c));
    }
  }

  backtrack(0, new Set(), []);

  if (bestMelds.length === 0) return null;
  const usedSet = new Set(bestMelds.flat());
  const leftover = hand.filter(c => !usedSet.has(c));

  return {
    melds: bestMelds,
    leftover,
    totalMelded: usedSet.size,
    savedPoints: bestSaved,
  };
}

// ── Selection feedback ────────────────────────────────────────────────────
function getSelectionFeedback(
  cards: number[],
  jokerMode: string,
  randomJoker: number | null,
): { hint: string; severity: 'ok' | 'warn' | 'error' | 'info' } {
  if (cards.length === 0) return { hint: "", severity: 'info' };

  const isJoker = (c: number) =>
    c >= 52 || (jokerMode === 'aleatoire' && randomJoker !== null && c === randomJoker);

  const validity = validateMeld(cards, jokerMode, randomJoker);
  if (validity === 'valid') return { hint: "✓ Combinaison valide — prête à poser", severity: 'ok' };
  if (validity === 'unknown') {
    // 1 or 2 cards — give a hint
    if (cards.length === 1) return { hint: "Sélectionne 2 cartes de plus pour un trio, ou 2+ de même couleur pour un escalier", severity: 'info' };
    const real = cards.filter(c => !isJoker(c));
    if (real.length >= 2) {
      const sameSuit = real.every(c => Math.floor(c / 13) === Math.floor(real[0] / 13));
      const sameRank = real.every(c => c % 13 === real[0] % 13);
      if (sameSuit) {
        const suitName = ["♠ Pique", "♥ Cœur", "♦ Carreau", "♣ Trèfle"][Math.floor(real[0] / 13)];
        return { hint: `Escalier ${suitName} en cours — ajoute une carte adjacente`, severity: 'info' };
      }
      if (sameRank) {
        const rankName = RANKS[real[0] % 13];
        const missingCount = 3 - cards.length;
        return { hint: `Trio de ${rankName} — ajoute encore ${missingCount} carte${missingCount > 1 ? 's' : ''} de même valeur`, severity: 'info' };
      }
    }
    return { hint: "Ajoute une carte pour compléter la combinaison", severity: 'info' };
  }

  // Invalid — explain why
  const real = cards.filter(c => !isJoker(c));
  const jokerCount = cards.filter(c => isJoker(c)).length;

  if (real.length === 0) return { hint: "Uniquement des Jokers — ajoute des cartes réelles", severity: 'error' };

  const allSameSuit = real.every(c => Math.floor(c / 13) === Math.floor(real[0] / 13));
  const allSameRank = real.every(c => c % 13 === real[0] % 13);

  if (!allSameSuit && !allSameRank) {
    return { hint: "Cartes mixtes — sélectionne soit même valeur (trio), soit même couleur (escalier)", severity: 'error' };
  }

  if (allSameRank) {
    // Check for duplicate suits
    const suits = real.map(c => Math.floor(c / 13));
    if (new Set(suits).size < suits.length) {
      return { hint: "Deux cartes de même couleur dans le trio — retire-en une", severity: 'error' };
    }
    if (cards.length > 4) {
      return { hint: "Un trio/carré ne peut pas dépasser 4 cartes", severity: 'error' };
    }
  }

  if (allSameSuit) {
    const ranks = real.map(c => c % 13).sort((a, b) => a - b);
    let gaps = 0;
    for (let i = 1; i < ranks.length; i++) {
      const diff = ranks[i] - ranks[i - 1];
      if (diff === 0) return { hint: "Deux cartes identiques dans l'escalier", severity: 'error' };
      gaps += diff - 1;
    }
    if (gaps > jokerCount) {
      return { hint: `Trou trop grand dans l'escalier (${gaps} manquant${gaps > 1 ? 's' : ''}, ${jokerCount} Joker${jokerCount > 1 ? 's' : ''} disponible${jokerCount > 1 ? 's' : ''})`, severity: 'warn' };
    }
  }

  return { hint: "Combinaison invalide", severity: 'error' };
}

// ── Layoff candidates ─────────────────────────────────────────────────────
function getLayoffCandidates(
  melds: { player: string; cards: number[] }[],
  selected: number[],
  jokerMode: string,
  randomJoker: number | null,
): Set<number> {
  const candidates = new Set<number>();
  melds.forEach((m, i) => {
    for (const card of selected) {
      // Try prepending or appending
      if (
        validateMeld([card, ...m.cards], jokerMode, randomJoker) === 'valid' ||
        validateMeld([...m.cards, card], jokerMode, randomJoker) === 'valid'
      ) {
        candidates.add(i);
        break;
      }
    }
  });
  return candidates;
}


// ── Session Leaderboard ────────────────────────────────────────────────────
interface LeaderboardEntry {
  userId: string;
  displayName: string;
  wins: number;
  totalPts: number;
  gamesPlayed: number;
}

const LB_KEY = "rami_leaderboard_v1";

function useRamiLeaderboard(gameId: string) {
  const storageKey = LB_KEY + "_" + gameId.slice(0, 8);

  const load = (): LeaderboardEntry[] => {
    try { return JSON.parse(localStorage.getItem(storageKey) || "[]"); }
    catch { return []; }
  };

  const [entries, setEntries] = React.useState<LeaderboardEntry[]>(load);

  const recordRound = React.useCallback(
    (parts: any[], hands: Record<string, number[]>, winnerId: string | null) => {
      setEntries(prev => {
        const next = [...prev];
        parts.filter(p => !p.forfeited).forEach(p => {
          const hand: number[] = hands?.[p.user_id] ?? [];
          const pts = hand.reduce((s, c) => s + CARD_POINTS(c), 0);
          const idx = next.findIndex(e => e.userId === p.user_id);
          if (idx >= 0) {
            next[idx] = { ...next[idx], wins: next[idx].wins + (p.user_id === winnerId ? 1 : 0), totalPts: next[idx].totalPts + pts, gamesPlayed: next[idx].gamesPlayed + 1 };
          } else {
            next.push({ userId: p.user_id, displayName: p.display_name, wins: p.user_id === winnerId ? 1 : 0, totalPts: pts, gamesPlayed: 1 });
          }
        });
        try { localStorage.setItem(storageKey, JSON.stringify(next)); } catch {}
        return next;
      });
    },
    [storageKey],
  );

  const reset = React.useCallback(() => {
    localStorage.removeItem(storageKey);
    setEntries([]);
  }, [storageKey]);

  return { entries, recordRound, reset };
}

function RamiLeaderboard({ entries, meUserId, onReset }: { entries: LeaderboardEntry[]; meUserId?: string; onReset: () => void }) {
  if (entries.length === 0) return null;
  const sorted = [...entries].sort((a, b) => b.wins !== a.wins ? b.wins - a.wins : a.totalPts - b.totalPts);

  return (
    <div className="rounded-2xl bg-card border border-border p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-xs font-bold uppercase text-muted-foreground tracking-wide">🏆 Classement de session</div>
        <button onClick={onReset} className="text-[10px] text-muted-foreground hover:text-destructive transition-colors px-2 py-0.5 rounded-full border border-transparent hover:border-destructive/30">Réinitialiser</button>
      </div>
      <div className="space-y-2">
        {sorted.map((e, idx) => {
          const isMe = e.userId === meUserId;
          const avgPts = e.gamesPlayed > 0 ? Math.round(e.totalPts / e.gamesPlayed) : 0;
          const medals = ["🥇", "🥈", "🥉"];
          return (
            <div key={e.userId} className={`flex items-center gap-3 rounded-xl px-3 py-2.5 border transition-all ${
              isMe ? "bg-primary/8 border-primary/20 ring-1 ring-primary/20"
              : idx === 0 ? "bg-amber-500/8 border-amber-500/20"
              : "bg-white/4 border-white/6"
            }`}>
              <div className={`w-8 h-8 rounded-full flex items-center justify-center text-base shrink-0 font-bold ${idx === 0 ? "bg-amber-500/20" : "bg-white/8"}`}>
                {medals[idx] ?? (idx + 1)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="font-bold text-sm truncate">{e.displayName}{isMe ? <span className="text-primary/60 text-[10px] font-normal ml-1">(vous)</span> : ""}</div>
                <div className="text-[10px] text-muted-foreground/60">{e.gamesPlayed} partie{e.gamesPlayed > 1 ? "s" : ""} · moy. {avgPts} pts</div>
              </div>
              <div className="text-right shrink-0">
                <div className="font-extrabold text-sm text-emerald-500">{e.wins}V</div>
                <div className="text-[10px] text-muted-foreground/50 font-mono">{e.totalPts} pts</div>
              </div>
            </div>
          );
        })}
      </div>
      <div className="text-[10px] text-muted-foreground border-t border-border pt-1">
        Classement par victoires, puis total de points (moins = mieux) — sauvegardé dans ce navigateur
      </div>
    </div>
  );
}

// ── Score Summary with Ar gain/loss ───────────────────────────────────────
function RamiScoreSummary({ parts, hands, winnerId, pot, commissionPct }: {
  parts: any[];
  hands: Record<string, number[]>;
  winnerId: string | null;
  pot?: number;
  commissionPct?: number;
}) {
  const commission = commissionPct ?? 10;
  const netPot = pot ? Math.round(pot * (1 - commission / 100)) : 0;
  const activeParts = parts.filter(p => !p.forfeited);
  const stakePerPlayer = pot && activeParts.length > 0 ? Math.round(pot / activeParts.length) : 0;

  const rows = activeParts.map(p => {
    const hand: number[] = hands?.[p.user_id] ?? [];
    const pts = hand.reduce((s, c) => s + CARD_POINTS(c), 0);
    const isWinner = p.user_id === winnerId;
    const arDelta = isWinner ? netPot - stakePerPlayer : -stakePerPlayer;
    return { ...p, hand, pts, arDelta };
  }).sort((a, b) => a.pts - b.pts);

  const minPts = rows[0]?.pts ?? 0;

  const cardLabel = (c: number) => {
    if (c >= 52) return { rank: "★", suit: "", color: "#7c3aed" };
    const s = Math.floor(c / 13);
    const r = c % 13;
    return { rank: RANKS[r], suit: SUITS[s], color: SUIT_COLORS[s] };
  };

  return (
    <div className="rounded-2xl border border-white/8 overflow-hidden">
      <div className="px-4 py-3 bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border-b border-white/6 flex items-center gap-2">
        <span className="text-base">📊</span>
        <div className="font-bold text-sm">Bilan de la manche</div>
        {pot !== undefined && pot > 0 && (
          <div className="ml-auto text-xs font-semibold text-emerald-500 bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20">
            Pot {pot.toLocaleString("fr-FR")} Ar
          </div>
        )}
      </div>
      <div className="p-3 space-y-2 bg-card">
        {rows.map((p, idx) => {
          const isWinner = p.user_id === winnerId;
          const isLowest = p.pts === minPts;
          return (
            <div key={p.id} className={`rounded-xl p-3 space-y-2 border transition-all ${isWinner ? "bg-emerald-500/8 border-emerald-500/25 shadow-md shadow-emerald-500/10" : idx === rows.length-1 ? "bg-destructive/5 border-destructive/15" : "bg-white/4 border-white/6"}`}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${isWinner ? "bg-emerald-500/20 text-emerald-400 ring-1 ring-emerald-500/30" : "bg-white/8 text-muted-foreground ring-1 ring-white/10"}`}>
                    {isWinner ? "🏆" : idx === 0 ? "🥈" : ""}
                    {!isWinner && idx > 0 ? (p.display_name || "?").slice(0,2).toUpperCase() : ""}
                  </div>
                  <span className="font-bold text-sm">{p.display_name}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className={`text-base font-extrabold ${isWinner ? "text-emerald-400" : isLowest ? "text-primary" : "text-destructive/80"}`}>
                    {p.pts} pts
                  </span>
                  {/* Ar gain/loss */}
                  {pot !== undefined && pot > 0 && (
                    <span className={`text-xs font-bold px-2 py-0.5 rounded-full ${p.arDelta > 0 ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/20" : "bg-destructive/10 text-destructive border border-destructive/15"}`}>
                      {p.arDelta > 0 ? "+" : ""}{p.arDelta.toLocaleString("fr-FR")} Ar
                    </span>
                  )}
                </div>
              </div>
              {p.hand.length > 0 ? (
                <div className="flex gap-1 flex-wrap">
                  {p.hand.map((c: number, ci: number) => {
                    const lbl = cardLabel(c);
                    const pts = CARD_POINTS(c);
                    return (
                      <div key={ci} className="relative w-9 h-14 rounded-md bg-white border border-gray-300 shadow font-bold flex flex-col p-0.5 text-[10px]" style={{ color: lbl.color }}>
                        <div className="leading-none">{lbl.rank}<div>{lbl.suit}</div></div>
                        <div className="absolute bottom-0.5 right-0.5 text-[9px] bg-black/10 rounded px-0.5 font-mono">{pts}</div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="text-xs text-emerald-600 dark:text-emerald-400 font-semibold">Main vide — a posé toutes ses cartes !</div>
              )}
            </div>
          );
        })}
      </div>
        <div className="mt-3 pt-3 border-t border-white/6 space-y-1">
          {pot !== undefined && pot > 0 && (
            <div className="text-[10px] text-muted-foreground/60 flex items-center gap-1">
              <span>Pot {pot.toLocaleString("fr-FR")} Ar</span><span className="opacity-30">·</span>
              <span>Commission {commission}% = {Math.round(pot * commission / 100).toLocaleString("fr-FR")} Ar</span><span className="opacity-30">·</span>
              <span className="text-emerald-500 font-semibold">Net {netPot.toLocaleString("fr-FR")} Ar</span>
            </div>
          )}
          <div className="text-[10px] text-muted-foreground/40">A=11 · J/Q/K=10 · Joker=15 · autres=valeur</div>
        </div>
      </div>
  );
}

// ── Deal animation CSS (injected once) ───────────────────────────────────
const DEAL_STYLE_ID = "rami-deal-keyframes";
function ensureDealKeyframes() {
  if (typeof document === "undefined" || document.getElementById(DEAL_STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = DEAL_STYLE_ID;
  style.textContent = `
    @keyframes dealCard {
      from { opacity: 0; transform: translateY(-40px) scale(0.7) rotate(-8deg); }
      to   { opacity: 1; transform: translateY(0) scale(1) rotate(0deg); }
    }
    @keyframes timerUrgent {
      0%, 100% { box-shadow: 0 0 0 0 rgba(220,38,38,0.5); }
      50%       { box-shadow: 0 0 0 6px rgba(220,38,38,0); }
    }
    .timer-urgent { animation: timerUrgent 0.6s ease-in-out infinite; }
    @keyframes flyToHand {
      0%   { opacity: 0; transform: translate(-50%, -50%) scale(0.5) rotate(-20deg); }
      15%  { opacity: 1; transform: translate(-50%, -50%) scale(1.15) rotate(0deg); }
      100% { opacity: 0; transform: translate(-50%, 60vh) scale(0.9) rotate(6deg); }
    }
    @keyframes flyToDiscard {
      0%   { opacity: 0; transform: translate(-50%, 40vh) scale(0.9) rotate(4deg); }
      20%  { opacity: 1; transform: translate(-50%, 20vh) scale(1.1) rotate(2deg); }
      100% { opacity: 0; transform: translate(-50%, -30vh) scale(0.7) rotate(-8deg); }
    }
  `;
  document.head.appendChild(style);
}

// Flying card overlay — animates from source rect to target rect
function FlyingCard({ card, from, to }: { card: number | undefined; from: { x: number; y: number }; to: { x: number; y: number } }) {
  const [pos, setPos] = useState(from);
  React.useEffect(() => {
    const r = requestAnimationFrame(() => setPos(to));
    return () => cancelAnimationFrame(r);
  }, [to.x, to.y]);
  return (
    <div
      className="fixed z-[60] pointer-events-none"
      style={{
        left: 0,
        top: 0,
        transform: `translate(${pos.x}px, ${pos.y}px) translate(-50%, -50%)`,
        transition: "transform 0.55s cubic-bezier(0.4, 0.0, 0.2, 1)",
        filter: "drop-shadow(0 12px 18px rgba(0,0,0,0.45))",
      }}
    >
      <Card c={card} faceDown={card === undefined} size="md" />
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────
function RamiPage() {
  const { id } = Route.useParams();
  const { profile, isAdmin } = useAuth();
  const navigate = useNavigate();
  const [game, setGame] = useState<any>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [selected, setSelected] = useState<number[]>([]);
  const [staged, setStaged] = useState<number[][]>([]);
  const [sortMode, setSortMode] = useState<'none' | 'suit' | 'rank'>('none');
  // Custom hand order for drag-reorder
  const [customOrder, setCustomOrder] = useState<number[] | null>(null);
  const [reorderMode, setReorderMode] = useState(false);
  const [movingIdx, setMovingIdx] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [optimalPlay, setOptimalPlay] = useState<OptimalPlay | null>(null);
  const [showOptimal, setShowOptimal] = useState(false);
  const [cardFx, setCardFx] = useState<{ card: number | undefined; from: { x: number; y: number }; to: { x: number; y: number } } | null>(null);
  const deckRef = React.useRef<HTMLButtonElement | null>(null);
  const handRef = React.useRef<HTMLDivElement | null>(null);
  const discardRefs = React.useRef<Record<string, HTMLDivElement | null>>({});
  const centerOf = (el: HTMLElement | null | undefined) => {
    if (!el) return { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  };
  const [intro, setIntro] = useState<{ phase: "shuffle" | "joker" | "first" | "done"; pickName?: string } | null>(null);
  const [dealAnimating, setDealAnimating] = useState(false);
  const [newCard, setNewCard] = useState<number | null>(null);
  const prevHandRef = useRef<number[]>([]);
  const { entries: lbEntries, recordRound, reset: resetLb } = useRamiLeaderboard(id);

  // Inject CSS keyframes once
  useEffect(() => { ensureDealKeyframes(); }, []);

  const load = useCallback(async () => {
    const { data: g } = await supabase.from("rami_games" as any).select("*").eq("id", id).maybeSingle();
    setGame(g);
    const { data: p } = await supabase.from("rami_participants" as any).select("*").eq("game_id", id).order("slot");
    setParts((p as any[]) || []);
  }, [id]);

  useEffect(() => {
    load();
    const ch = supabase.channel("rami-" + id)
      .on("postgres_changes", { event: "*", schema: "public", table: "rami_games", filter: `id=eq.${id}` }, () => load())
      .on("postgres_changes", { event: "*", schema: "public", table: "rami_participants", filter: `game_id=eq.${id}` }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });

  const recordedRef = React.useRef(false);
  useEffect(() => {
    if (game?.status === "finished" && game.state?.hands && !recordedRef.current) {
      recordedRef.current = true;
      recordRound(parts, game.state.hands as Record<string, number[]>, game.winner_id);
    }
  }, [game?.status, game?.state?.hands, game?.winner_id, parts, recordRound]);

  useEffect(() => {
    if (game?.status === "cancelled") {
      toast.info("Invitation expirée — mise remboursée");
      const t = setTimeout(() => navigate({ to: "/jeux/$slug", params: { slug: "rami" }, search: {} }), 1500);
      return () => clearTimeout(t);
    }
  }, [game?.status, navigate]);

  // ── Bot-action feedback: highlight new melds / discards + toast ──
  const [flashMelds, setFlashMelds] = useState<number[]>([]);
  const [flashDiscards, setFlashDiscards] = useState<string[]>([]);
  const botFxRef = React.useRef<{ meldsLen: number; discardKey: string; discardTop?: number; init: boolean }>({ meldsLen: 0, discardKey: "", discardTop: undefined, init: false });
  useEffect(() => {
    if (!game) return;
    const currentMelds: { player: string; cards: number[]; type?: string }[] = game?.state?.melds || [];
    const currentDiscards: Record<string, number[]> = (game?.state?.discards && typeof game.state.discards === "object")
      ? game.state.discards : {};
    const lastBy: string = game?.state?.last_discard_by || "_seed";
    const top = (currentDiscards[lastBy] || [])[((currentDiscards[lastBy] || []).length) - 1];
    const prev = botFxRef.current;

    if (!prev.init) {
      botFxRef.current = { meldsLen: currentMelds.length, discardKey: lastBy, discardTop: top, init: true };
      return;
    }

    const newMeldIdxs: number[] = [];
    if (currentMelds.length > prev.meldsLen) {
      for (let i = prev.meldsLen; i < currentMelds.length; i++) {
        newMeldIdxs.push(i);
        const m = currentMelds[i];
        const p = parts.find(pp => pp.user_id === m.player);
        if (p?.is_bot) {
          const kind = m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
          toast.info(`🤖 ${p.display_name || "Bot"} a posé une ${kind} (${m.cards.length} cartes)`, { duration: 2500 });
        }
      }
    }

    const newDiscardKeys: string[] = [];
    if ((prev.discardKey !== lastBy || prev.discardTop !== top) && top !== undefined && lastBy !== "_seed") {
      newDiscardKeys.push(lastBy);
      const p = parts.find(pp => pp.user_id === lastBy);
      if (p?.is_bot) {
        toast.info(`🤖 ${p.display_name || "Bot"} a défaussé une carte`, { duration: 2000 });
      }
    }

    botFxRef.current = { meldsLen: currentMelds.length, discardKey: lastBy, discardTop: top, init: true };

    if (newMeldIdxs.length) {
      setFlashMelds(f => [...f, ...newMeldIdxs]);
      setTimeout(() => setFlashMelds(f => f.filter(i => !newMeldIdxs.includes(i))), 2800);
    }
    if (newDiscardKeys.length) {
      setFlashDiscards(f => [...f, ...newDiscardKeys]);
      setTimeout(() => setFlashDiscards(f => f.filter(k => !newDiscardKeys.includes(k))), 2800);
    }
  }, [game?.state?.melds, game?.state?.discards, game?.state?.last_discard_by, parts]);

  // Intro animation (deal cards with stagger)
  useEffect(() => {
    if (game?.status !== "playing" || !game?.started_at) return;
    const elapsed = serverNow() - new Date(game.started_at).getTime();
    if (elapsed > 9000) return;
    const firstSlot = game?.state?.first_player;
    const firstPart = parts.find((p: any) => p.slot === firstSlot);
    setIntro({ phase: "shuffle" });
    setDealAnimating(true);
    const t1 = setTimeout(() => setIntro({ phase: "joker" }), 3000);
    const t2 = setTimeout(() => setIntro({ phase: "first", pickName: firstPart?.display_name || `Joueur ${(firstSlot ?? 0) + 1}` }), 5500);
    const t3 = setTimeout(() => { setIntro(null); setDealAnimating(false); }, 9000);
    return () => { clearTimeout(t1); clearTimeout(t2); clearTimeout(t3); };
  }, [game?.status, game?.started_at, game?.state?.first_player, parts]);

  const me = parts.find(p => p.user_id === profile?.id);
  const isPlayer = !!me;
  const isMyTurn = game?.status === "playing" && me && game.current_turn === me.slot;
  const phase = game?.turn_phase;
  const myHand: number[] = useMemo(() => {
    const h = game?.state?.hands?.[profile?.id || ""];
    return Array.isArray(h) ? h : [];
  }, [game, profile?.id]);
  const discards: Record<string, number[]> = useMemo(() => {
    const d = game?.state?.discards;
    if (d && typeof d === "object") return d as Record<string, number[]>;
    const legacy = game?.state?.discard;
    return Array.isArray(legacy) && legacy.length > 0 ? { _seed: legacy } : {};
  }, [game?.state?.discards, game?.state?.discard]);
  const lastDiscardBy: string = game?.state?.last_discard_by || "_seed";
  const deckCount: number = (game?.state?.deck || []).length;
  const melds: { player: string; cards: number[]; type?: string }[] = game?.state?.melds || [];
  const jokerMode: string = game?.joker_mode || "classique";
  const randomJoker: number | null = game?.random_joker ?? null;
  const refunded: Record<string, boolean> = game?.state?.refunded || {};
  const myRefunded = !!(profile?.id && refunded[profile.id]);

  // Action log from game state
  const actionLog: string[] = useMemo(() => {
    const log = game?.state?.action_log;
    if (!Array.isArray(log)) return [];
    return log.slice(-6).reverse();
  }, [game?.state?.action_log]);

  const stagedFlat = useMemo(() => staged.flat(), [staged]);
  const handCards = useMemo(() => myHand.filter(c => !stagedFlat.includes(c)), [myHand, stagedFlat]);
  const handPoints = useMemo(() => handCards.reduce((s, card) => s + CARD_POINTS(card), 0), [handCards]);

  // Apply custom order or sort mode
  const orderedHandCards = useMemo(() => {
    if (customOrder !== null) {
      // Keep user's custom order; append any newly drawn cards not yet in the order
      const inOrder = customOrder.filter(c => handCards.includes(c));
      const extras = handCards.filter(c => !inOrder.includes(c));
      return [...inOrder, ...extras];
    }
    const cards = [...handCards];
    if (sortMode === 'suit') {
      cards.sort((a, b) => {
        const sA = a >= 52 ? 4 : Math.floor(a / 13);
        const sB = b >= 52 ? 4 : Math.floor(b / 13);
        return sA !== sB ? sA - sB : (a % 13) - (b % 13);
      });
    } else if (sortMode === 'rank') {
      cards.sort((a, b) => {
        if (a >= 52) return 1;
        if (b >= 52) return -1;
        const rA = a % 13, rB = b % 13;
        return rA !== rB ? rA - rB : Math.floor(a / 13) - Math.floor(b / 13);
      });
    }
    return cards;
  }, [handCards, sortMode, reorderMode, customOrder]);

  // Reset custom order when hand changes
  useEffect(() => {
    setCustomOrder(handCards.length > 0 ? [...handCards] : null);
  }, [myHand.length]);

  // Detect newly drawn card to show a "NEW" mark
  useEffect(() => {
    const prev = prevHandRef.current;
    const added = handCards.filter(c => !prev.includes(c));
    if (added.length === 1 && prev.length > 0 && handCards.length === prev.length + 1) {
      setNewCard(added[0]);
    }
    prevHandRef.current = handCards;
  }, [handCards]);

  // Clear the "NEW" mark once the player interacts (select, discard, phase change)
  useEffect(() => {
    if (newCard !== null && (phase !== "play" || selected.length > 0)) {
      setNewCard(null);
    }
  }, [phase, selected.length, newCard]);

  const selectionValidity = useMemo(() => validateMeld(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const selectionFeedback = useMemo(() => getSelectionFeedback(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const stagedValidity = useMemo(() => staged.map(g => validateMeld(g, jokerMode, randomJoker)), [staged, jokerMode, randomJoker]);

  // Compute which melds can accept the selected cards (for layoff highlighting)
  const layoffCandidates = useMemo(() => {
    if (!isMyTurn || phase !== "play" || selected.length === 0) return new Set<number>();
    return getLayoffCandidates(melds, selected, jokerMode, randomJoker);
  }, [melds, selected, isMyTurn, phase, jokerMode, randomJoker]);

  const cfg = useGameConfig("rami");
  const [remaining, setRemaining] = useState(cfg.turn_timer_seconds);
  useEffect(() => {
    if (!game?.turn_deadline || game.status !== "playing") { setRemaining(cfg.turn_timer_seconds); return; }
    let fired = false;
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      const s = Math.max(0, Math.ceil(ms / 1000));
      setRemaining(s);
      if (s === 0 && !fired) {
        fired = true;
        supabase.rpc("rami_tick" as any, { _game_id: id } as any);
      }
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, id, cfg.turn_timer_seconds]);

  const isUrgent = remaining <= 10 && isMyTurn;

  const toggleSel = (c: number) => {
    setSelected(s => s.includes(c) ? s.filter(x => x !== c) : [...s, c]);
  };

  const addToStaged = () => {
    if (selected.length < 3) return toast.error("Sélectionne au moins 3 cartes pour former une combinaison");
    setStaged(prev => [...prev, [...selected]]);
    setSelected([]);
  };

  const removeFromStaged = (groupIdx: number, card: number) => {
    setStaged(prev => {
      const next = prev.map((g, i) => i === groupIdx ? g.filter(c => c !== card) : g);
      return next.filter(g => g.length > 0);
    });
  };

  const removeStagedGroup = (groupIdx: number) => {
    setStaged(prev => prev.filter((_, i) => i !== groupIdx));
  };

  const call = async (fn: string, payload: any) => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc(fn as any, payload);
      if (error) throw error;
      setSelected([]);
    } catch (e: any) { toast.error(e.message || "Action invalide"); }
    finally { setBusy(false); }
  };

  const drawDeck = async () => {
    const from = centerOf(deckRef.current);
    const to = centerOf(handRef.current);
    setCardFx({ card: undefined, from, to });
    await call("rami_draw", { _game_id: id, _from: "deck" });
    setTimeout(() => setCardFx(null), 650);
  };
  const drawDiscard = async () => {
    const pile = discards[lastDiscardBy] || [];
    const top = pile[pile.length - 1];
    const from = centerOf(discardRefs.current[lastDiscardBy]);
    const to = centerOf(handRef.current);
    setCardFx({ card: top, from, to });
    await call("rami_draw", { _game_id: id, _from: "discard" });
    setTimeout(() => setCardFx(null), 650);
  };

  const submitStagedMeld = async (groupIdx: number) => {
    const cards = staged[groupIdx];
    if (!cards || cards.length < 3) return toast.error("Il faut au moins 3 cartes");
    setBusy(true);
    try {
      const { error } = await supabase.rpc("rami_meld" as any, { _game_id: id, _cards: cards });
      if (error) throw error;
      setStaged(prev => prev.filter((_, i) => i !== groupIdx));
      toast.success("Combinaison posée !");
    } catch (e: any) { toast.error(e.message || "Combinaison invalide"); }
    finally { setBusy(false); }
  };

  const submitAllStaged = async () => {
    if (staged.length === 0) return;
    setBusy(true);
    let anyError = false;
    for (const cards of staged) {
      const { error } = await supabase.rpc("rami_meld" as any, { _game_id: id, _cards: cards });
      if (error) { toast.error(error.message || "Combinaison invalide"); anyError = true; break; }
    }
    if (!anyError) { setStaged([]); toast.success("Toutes les combinaisons posées !"); }
    setBusy(false);
  };

  const discardOne = async () => {
    if (selected.length !== 1) return toast.error("Sélectionne exactement 1 carte à défausser");
    const card = selected[0];
    const myKey = profile?.id || "";
    const from = centerOf(handRef.current);
    const to = centerOf(discardRefs.current[myKey]);
    setCardFx({ card, from, to });
    await call("rami_discard", { _game_id: id, _card: card });
    setTimeout(() => setCardFx(null), 650);
  };

  // Valider toute la main d'un coup : staged = groupes, selected[0] = carte à défausser
  const validateHand = async () => {
    if (staged.length === 0) return toast.error("Prépare tes combinaisons avant de valider");
    if (selected.length !== 1) return toast.error("Sélectionne 1 carte à défausser");
    const layout = staged.map(g => [...g]);
    const discardCard = selected[0];
    setBusy(true);
    const { data, error } = await supabase.rpc("rami_validate_hand" as any, {
      _game_id: id,
      _layout: layout as any,
      _discard_card: discardCard,
    });
    setBusy(false);
    if (error) { toast.error(error.message || "Combinaisons invalides"); return; }
    toast.success("🏆 Bravo, tu gagnes la partie !");
    setStaged([]); setSelected([]);
  };

  // Optimal play suggester
  const triggerOptimalSuggest = () => {
    const result = suggestOptimalPlay(handCards, jokerMode, randomJoker);
    if (!result) { toast.info("Aucune combinaison valide dans ta main"); return; }
    setOptimalPlay(result);
    setShowOptimal(true);
    // Auto-select first suggested meld
    if (result.melds.length > 0) setSelected(result.melds[0]);
  };

  // Apply one meld from optimal suggestion to staging
  const stageOptimalMeld = (meldCards: number[]) => {
    setStaged(prev => [...prev, [...meldCards]]);
    setSelected([]);
    setShowOptimal(false);
  };

  const layoff = (meldIdx: number) => {
    if (selected.length < 1) return toast.error("Sélectionne au moins 1 carte");
    call("rami_layoff", { _game_id: id, _meld_index: meldIdx, _cards: selected });
  };

  const confirm = useConfirm();
  const forfeit = async () => {
    const stake = Number(game?.stake) || 0;
    if (game?.status !== "waiting" && game?.status !== "open") {
      const ok = await confirm({
        title: "Quitter la partie ?",
        description: stake > 0
          ? <>Si tu quittes, tu perdras automatiquement et ta mise sera définitivement perdue. <b>{stake.toLocaleString("fr-FR")} Ar</b>.</>
          : "Si tu quittes, tu perdras automatiquement la partie.",
        confirmLabel: "Confirmer quitter",
        destructive: true,
      });
      if (!ok) return;
    }
    await supabase.rpc("rami_forfeit" as any, { _game_id: id } as any);
    navigate({ to: "/jeux" });
  };

  // ── Drag reorder helpers ──────────────────────────────────────────────
  const moveCard = (fromIdx: number, toIdx: number) => {
    setCustomOrder(prev => {
      const arr = prev ? [...prev] : [...orderedHandCards];
      const [item] = arr.splice(fromIdx, 1);
      arr.splice(toIdx, 0, item);
      return arr;
    });
    setMovingIdx(null);
  };

  const handleReorderTap = (cardIdx: number) => {
    if (movingIdx === null) {
      setMovingIdx(cardIdx);
    } else if (movingIdx === cardIdx) {
      setMovingIdx(null);
    } else {
      moveCard(movingIdx, cardIdx);
    }
  };

  // ── Long-press drag & drop ────────────────────────────────────────────
  // Source/target id format:
  //   "hand:<cardNum>"          — a card in the hand
  //   "staged:<gi>:<cardNum>"   — a card in staged group gi
  //   "staged-end:<gi>"         — end of a staged group (drop after last card)
  //   "hand-end"                — end of hand
  const parseId = (id: string) => {
    if (id === "hand-end") return { kind: "hand-end" as const };
    if (id.startsWith("hand:")) return { kind: "hand" as const, card: Number(id.slice(5)) };
    if (id.startsWith("staged-end:")) return { kind: "staged-end" as const, gi: Number(id.slice(11)) };
    if (id.startsWith("staged:")) {
      const [, gi, card] = id.split(":");
      return { kind: "staged" as const, gi: Number(gi), card: Number(card) };
    }
    return { kind: "unknown" as const };
  };

  const insertAt = (arr: number[], card: number, refCard: number | null, side: "before" | "after") => {
    const clean = arr.filter(c => c !== card);
    if (refCard === null) return [...clean, card];
    const idx = clean.indexOf(refCard);
    if (idx < 0) return [...clean, card];
    const pos = side === "before" ? idx : idx + 1;
    return [...clean.slice(0, pos), card, ...clean.slice(pos)];
  };

  // Manual mode: drop simply reorders the hand — no auto-meld detection.
  // The player composes their combinations and taps "Valider ma main".
  const autoStageFromOrder = useCallback((order: number[]) => {
    setCustomOrder(order);
  }, []);


  const handleDrop = useCallback((sourceId: string, targetId: string, side: "before" | "after") => {
    const src = parseId(sourceId);
    const tgt = parseId(targetId);
    if (src.kind === "unknown" || tgt.kind === "unknown") return;

    // Compute target hand & target staged groups after removing source
    let nextHand = [...orderedHandCards];
    let nextStaged = staged.map(g => [...g]);
    let movingCard: number | null = null;

    if (src.kind === "hand") {
      movingCard = src.card;
      nextHand = nextHand.filter(c => c !== movingCard);
    } else if (src.kind === "staged") {
      movingCard = src.card;
      nextStaged[src.gi] = nextStaged[src.gi].filter(c => c !== movingCard);
    }
    if (movingCard === null) return;

    // Insert at target
    if (tgt.kind === "hand") {
      nextHand = insertAt(nextHand, movingCard, tgt.card, side);
    } else if (tgt.kind === "hand-end") {
      nextHand = insertAt(nextHand, movingCard, null, "after");
    } else if (tgt.kind === "staged") {
      nextStaged[tgt.gi] = insertAt(nextStaged[tgt.gi], movingCard, tgt.card, side);
    } else if (tgt.kind === "staged-end") {
      nextStaged[tgt.gi] = insertAt(nextStaged[tgt.gi], movingCard, null, "after");
    }

    // Un-stage any group that dropped below 3 cards (return to hand)
    const dropped: number[] = [];
    nextStaged = nextStaged.filter(g => {
      if (g.length < 3) { dropped.push(...g); return false; }
      return true;
    });
    if (dropped.length > 0) nextHand = [...nextHand, ...dropped];

    setStaged(nextStaged);
    // If the moved card ended up in the hand, run auto-detection
    if (tgt.kind === "hand" || tgt.kind === "hand-end" || dropped.length > 0) {
      autoStageFromOrder(nextHand);
    } else {
      setCustomOrder(nextHand);
    }
  }, [orderedHandCards, staged, autoStageFromOrder]);

  const dnd = useLongPressDrag({ delay: 380, onDrop: handleDrop });

  if (!game) return <div className="p-6 text-center">Chargement…</div>;


  const replayRami = async () => {
    const { data, error } = await supabase.rpc("rami_create" as any, {
      _stake: Number(game.stake) || 0,
      _max: game.max_players,
      _private: !!game.is_private,
      _commission: Number(game.commission_pct) || 10,
    } as any);
    if (error) { toast.error(error.message); return; }
    navigate({ to: "/rami/$id", params: { id: data as string } });
  };

  if (game.status === "open" || game.status === "waiting") {
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="rami"
          gameLabel={`Rami · ${game.max_players} joueurs`}
          parts={parts}
          maxPlayers={game.max_players}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          roomCode={game.is_private ? game.room_code : null}
          shareSlug="rami"
          meUserId={profile?.id}
          isParticipant={!!me}
          createdAt={game.created_at}
          onQuit={forfeit}
          onToggleReady={async (ready) => {
            const { error } = await supabase.rpc("rami_set_ready" as any, { _game_id: id, _ready: ready } as any);
            if (error) toast.error(error.message);
          }}
        />
        {((isAdmin || (Number(game.stake) === 0 && !!me)) && parts.length < game.max_players) && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("rami_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
              if (error) toast.error(error.message); else toast.success("Bot ajouté");
            }}
            className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2"
          >
            <Plus className="w-4 h-4" /> Ajouter un bot
          </button>
        )}
        <GameChatDrawer gameId={id} />
      </main>
    );
  }

  const drawablePile = discards[lastDiscardBy] || [];
  const topDiscard = drawablePile.length > 0 ? drawablePile[drawablePile.length - 1] : undefined;

  // Build discard entries: one per participant + seed (if still present)
  const _discardColors = ["#ef4444", "#3b82f6", "#22c55e", "#eab308", "#a855f7", "#ec4899"];
  const discardEntries: { key: string; label: string; color: string; pile: number[]; isMe: boolean }[] = [];
  if ((discards["_seed"] || []).length > 0) {
    discardEntries.push({ key: "_seed", label: "1re", color: "#94a3b8", pile: discards["_seed"], isMe: false });
  }
  parts.slice().sort((a, b) => a.slot - b.slot).forEach((p, i) => {
    const key: string = (p.user_id as string) || `bot:${p.slot}`;
    const isMe = p.user_id === profile?.id;
    discardEntries.push({
      key,
      label: isMe ? "Moi" : (p.display_name || "Joueur").slice(0, 8),
      color: _discardColors[i % _discardColors.length],
      pile: discards[key] || [],
      isMe,
    });
  });

  return (
    <main className="max-w-3xl mx-auto px-3 py-2 space-y-2 pb-3" style={{ background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.06) 0%, transparent 60%)" }}>
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      {cardFx && (
        <FlyingCard card={cardFx.card} from={cardFx.from} to={cardFx.to} />
      )}
      {game.status === "finished" && (
        <GameEndScreen slug="rami" meUserId={profile?.id} winnerId={game.winner_id}
          participants={parts} stake={Number(game.stake)} pot={Number(game.pot)}
          commissionPct={Number(game.commission_pct) || 10}
          onReplay={replayRami} />
      )}

      {game.status === "finished" && game.state?.hands && (
        <RamiScoreSummary
          parts={parts}
          hands={game.state.hands as Record<string, number[]>}
          winnerId={game.winner_id}
          pot={Number(game.pot)}
          commissionPct={Number(game.commission_pct) || 10}
        />
      )}

      {lbEntries.length > 0 && (
        <RamiLeaderboard entries={lbEntries} meUserId={profile?.id} onReset={resetLb} />
      )}

      {/* Turn banner */}
      {game?.status === "playing" && (() => {
        const currentPart = parts.find(p => p.slot === game.current_turn);
        const currentName = currentPart?.user_id === profile?.id ? "À toi de jouer !" : `Au tour de ${currentPart?.display_name || "…"}`;
        return (
          <div className={`rounded-2xl px-3 py-2 flex items-center gap-3 border transition-all ${
            isMyTurn
              ? "bg-gradient-to-r from-emerald-500/15 via-emerald-400/10 to-transparent border-emerald-500/40 shadow-md shadow-emerald-500/20 animate-pulse"
              : "bg-white/5 border-white/10"
          }`}>
            <div className={`w-9 h-9 rounded-full flex items-center justify-center text-sm font-extrabold shrink-0 ${
              isMyTurn ? "bg-emerald-500/25 text-emerald-300 ring-2 ring-emerald-400/60" : "bg-white/10 text-foreground ring-1 ring-white/20"
            }`}>
              {(currentPart?.display_name || "?").slice(0, 2).toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <div className={`text-xs font-black tracking-wide truncate ${isMyTurn ? "text-emerald-300" : "text-foreground/90"}`}>
                {currentName}
              </div>
              <div className="text-[10px] text-muted-foreground">
                Phase : <span className="font-bold uppercase">{phase === "draw" ? "Pioche" : "Jeu"}</span>
              </div>
            </div>
            <div className={`px-3 py-1.5 rounded-xl font-mono font-black text-base tabular-nums ${
              isUrgent ? "bg-destructive text-destructive-foreground timer-urgent" : isMyTurn ? "bg-emerald-500 text-white" : "bg-white/10 text-foreground"
            }`}>
              {remaining}s
            </div>
          </div>
        );
      })()}

      {/* Compact players strip: turn indicator + remaining cards per player */}
      {game?.status === "playing" && parts.length > 0 && (
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1">

          {parts.slice().sort((a, b) => a.slot - b.slot).map((p) => {
            const isTurn = game.current_turn === p.slot;
            const isMe = p.user_id === profile?.id;
            const handLen = Array.isArray(game?.state?.hands?.[p.user_id]) ? game.state.hands[p.user_id].length : 0;
            const initials = (p.display_name || "?").slice(0, 2).toUpperCase();
            const playerMelds = melds.filter(m => m.player === p.user_id);
            const meldsCount = playerMelds.length;
            const meldedCards = playerMelds.reduce((s, m) => s + m.cards.length, 0);
            const hasPosed = meldsCount > 0;
            return (
              <div
                key={p.user_id}
                className={`shrink-0 flex items-center gap-1.5 pl-1 pr-2 py-1 rounded-full border bg-white/5 transition-all ${
                  isTurn
                    ? "border-primary/60 ring-1 ring-primary/40 shadow-sm shadow-primary/20"
                    : "border-white/10"
                }`}
              >
                <div className={`relative w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold bg-white/10 text-foreground ${isTurn ? "ring-1 ring-primary/60" : ""}`}>
                  {initials}
                  {isTurn && (
                    <span className="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-emerald-400 ring-2 ring-background animate-pulse" />
                  )}
                </div>
                <div className="flex flex-col leading-tight">
                  <span className="text-[10px] font-semibold truncate max-w-[70px]">
                    {isMe ? "Moi" : (p.display_name || "Joueur")}
                  </span>
                  <span className="flex items-center gap-1 text-[9px] text-muted-foreground">
                    <Layers className="w-2.5 h-2.5" />
                    <span className="font-mono font-bold">{handLen}</span>
                    {isTurn && (
                      <span className={`ml-1 font-mono font-bold ${isUrgent ? "text-destructive" : "text-primary"}`}>
                        {remaining}s
                      </span>
                    )}
                  </span>
                </div>
                {/* Meld status: minimal dot */}
                <span
                  title={hasPosed ? `${meldsCount} combinaison${meldsCount > 1 ? "s" : ""} · ${meldedCards} cartes` : "Pas encore posé"}
                  className={`ml-0.5 w-1.5 h-1.5 rounded-full ${hasPosed ? "bg-emerald-400" : "bg-amber-400/60"}`}
                />
              </div>
            );
          })}
        </div>
      )}

      {/* Table: deck + per-seat discard piles */}
      <div className="game-table-light" style={{ height: "46vh" }}>
        <div
          className="relative w-full h-full rounded-3xl overflow-hidden p-3 sm:p-4"
          style={{
            background: "#123a86",
            boxShadow: "inset 0 0 60px rgba(0,0,0,0.25), 0 12px 30px rgba(0,0,0,0.35)",
          }}
        >

          {(() => {
            // Split entries: seed (center), me (bottom-left), opponents (top row)
            const seedEntry = discardEntries.find(e => e.key === "_seed");
            const meEntry = discardEntries.find(e => e.isMe);
            // Rotate opponents so seat order starts at my LEFT (next slot after me)
            const rawOpps = discardEntries.filter(e => !e.isMe && e.key !== "_seed");
            const meIdx = discardEntries.findIndex(e => e.isMe);
            const nonSeed = discardEntries.filter(e => e.key !== "_seed");
            const meNonSeedIdx = Math.max(0, nonSeed.findIndex(e => e.isMe));
            const oppEntries = meIdx < 0
              ? rawOpps
              : nonSeed.slice(meNonSeedIdx + 1).concat(nonSeed.slice(0, meNonSeedIdx)).filter(e => !e.isMe);

            // Anchor positions per opponent count (relative to me at bottom)
            const oppAnchors: Array<React.CSSProperties> =
              oppEntries.length <= 1
                ? [{ top: "6%", right: "8%" }]
                : oppEntries.length === 2
                ? [
                    { top: "6%", left: "8%" },
                    { top: "6%", right: "8%" },
                  ]
                : [
                    // 3 opponents (4-player game): left, top, right
                    { top: "50%", left: "4%", transform: "translateY(-50%)" },
                    { top: "6%", left: "50%", transform: "translateX(-50%)" },
                    { top: "50%", right: "4%", transform: "translateY(-50%)" },
                  ];



            const renderPile = (e: typeof discardEntries[number]) => {
              const top = e.pile.length > 0 ? e.pile[e.pile.length - 1] : undefined;
              const drawable = isMyTurn && phase === "draw" && !busy && e.key === lastDiscardBy && top !== undefined;
              const isFlash = flashDiscards.includes(e.key);
              const initials = (e.label || "?").replace(/\s+/g, "").slice(0, 2).toUpperCase();
              return (
                <button
                  disabled={!drawable}
                  onClick={drawDiscard}
                  className={`flex flex-col items-center gap-1 disabled:opacity-80 transition-all active:scale-95 ${drawable ? "hover:-translate-y-1.5" : ""} ${isFlash ? "-translate-y-1" : ""}`}
                  title={`Défausse — ${e.label}`}
                >
                  {/* Title */}
                  <div className="text-[8px] text-white/50 font-semibold uppercase tracking-widest leading-none">
                    Défausse
                  </div>
                  <div ref={(el) => { discardRefs.current[e.key] = el; }} className={`relative rounded-md transition-all ${isFlash ? "ring-2 ring-amber-400 ring-offset-1 ring-offset-black/50 shadow-lg shadow-amber-500/40 animate-scale-in" : drawable ? "ring-2 ring-emerald-400 ring-offset-1 ring-offset-black/50 animate-pulse" : ""}`} style={{ boxShadow: `0 0 0 2px ${e.color}55` }}>
                    {top !== undefined
                      ? <Card c={top} size="sm" />
                      : <div className="w-11 h-16 rounded-md border-2 border-dashed flex items-center justify-center text-white/30 text-lg" style={{ borderColor: `${e.color}66` }}>⊘</div>}
                    {/* Owner badge (initials) — top-left of the card */}
                    <span
                      className="absolute -top-2 -left-2 min-w-[18px] h-[18px] px-1 rounded-full flex items-center justify-center text-[9px] font-extrabold text-white shadow ring-1 ring-black/40"
                      style={{ background: e.color }}
                    >
                      {e.isMe ? "moi" : initials}
                    </span>
                    {e.pile.length > 1 && (
                      <span className="absolute -top-1 -right-1 text-[9px] font-mono font-bold bg-black/70 text-white rounded-full px-1 leading-tight">
                        {e.pile.length}
                      </span>
                    )}
                    {isFlash && (
                      <span className="absolute -bottom-2 left-1/2 -translate-x-1/2 text-[9px] font-bold bg-amber-500 text-black rounded-full px-1.5 py-0.5 shadow animate-pulse whitespace-nowrap">🤖 défausse</span>
                    )}
                  </div>
                  <div className="flex items-center gap-1 max-w-[72px] px-1.5 py-0.5 rounded-full bg-black/50 border border-white/10">
                    <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: e.color }} />
                    <span className="text-[9px] text-white/90 font-semibold truncate uppercase tracking-wide">{e.label}</span>
                  </div>
                </button>
              );

            };

            return (
              <div className="relative w-full h-full" style={{ minHeight: "calc(46vh - 32px)" }}>
                {/* Opponents' discards — anchored to seat position */}
                {oppEntries.map((e, i) => (
                  <div key={e.key} className="absolute z-30" style={oppAnchors[i]}>
                    {renderPile(e)}
                  </div>
                ))}

                {/* Deck — centre du plateau (couche basse pour ne jamais recouvrir les défausses) */}
                <div className="absolute z-10" style={{ top: "50%", left: "50%", transform: "translate(-50%, -50%)" }}>
                  <div className="flex flex-col items-center gap-1">
                    <div className="relative">
                      <button
                        ref={deckRef}
                        disabled={!isMyTurn || phase !== "draw" || busy || deckCount === 0}
                        onClick={drawDeck}
                        className="relative z-10 disabled:opacity-40 transition-all hover:-translate-y-2 hover:shadow-2xl active:scale-95"
                      >
                        <Card faceDown size="sm" />
                      </button>
                    </div>
                    <div className="px-2 py-0.5 rounded-full bg-white/10 text-white text-[10px] font-mono font-bold">
                      {deckCount} sisa
                    </div>
                    {randomJoker !== null && (
                      <div className="mt-1" title="Faux Joker">
                        <Card c={randomJoker} size="sm" />
                      </div>
                    )}
                  </div>
                </div>

                {/* My discard — bottom-left */}
                {meEntry && (
                  <div className="absolute z-30" style={{ bottom: "8%", left: "6%" }}>
                    {renderPile(meEntry)}
                  </div>
                )}

              </div>
            );
          })()}
        </div>
      </div>



      {/* Refund button */}
      {Number(game.stake) > 0 && !myRefunded && (
        <button
          onClick={async () => {
            setBusy(true);
            const { error } = await supabase.rpc("rami_request_refund" as any, { _game_id: id } as any);
            setBusy(false);
            if (error) toast.error(error.message);
            else toast.success("Mise remboursée — tu peux continuer la partie");
          }}
          disabled={busy}
          className="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl bg-amber-500/8 text-amber-600 dark:text-amber-300 font-semibold text-sm border border-amber-500/15 hover:bg-amber-500/12 active:scale-[0.98] transition-all disabled:opacity-50">
          <span>💰</span>
          <span>Demander retour de mise</span>
          <span className="text-[10px] opacity-60 font-normal">(Carré + Escalier ≥3 ou Trio + Escalier ≥4)</span>
        </button>
      )}

      {/* Intro animation overlay */}
      {intro && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-6" style={{ background: "radial-gradient(ellipse at center, rgba(0,0,0,0.92) 0%, rgba(0,0,0,0.98) 100%)", backdropFilter: "blur(12px)" }}>
          <div className="text-center text-white space-y-6 max-w-sm w-full">
            {intro.phase === "shuffle" && (
              <>
                <div className="text-6xl mb-2" style={{ animation: "dealCard 0.5s ease-out" }}>🎴</div>
                <div className="text-2xl font-extrabold tracking-tight">Mélange des cartes…</div>
                <div className="text-sm text-white/50">Préparation de la partie</div>
                <div className="flex justify-center gap-2 mt-4">
                  {Array.from({ length: 5 }).map((_, i) => (
                    <div key={i}
                      className="w-10 h-14 rounded-lg shadow-xl"
                      style={{ background: "linear-gradient(135deg,#1d4ed8,#7c3aed)", border:"1px solid rgba(255,255,255,0.2)", animation: `dealCard 0.4s ease-out ${i * 100}ms both` }} />
                  ))}
                </div>
              </>
            )}
            {intro.phase === "joker" && (
              <>
                <div className="text-3xl font-extrabold">{randomJoker !== null ? "🃏 Tirage du Joker" : "🃏 Distribution"}</div>
                {randomJoker !== null ? (
                  <div className="flex justify-center" style={{ animation: "dealCard 0.5s ease-out" }}>
                    <Card c={randomJoker} size="lg" />
                  </div>
                ) : (
                  <div className="flex justify-center gap-1.5">
                    {Array.from({ length: 7 }).map((_, i) => (
                      <Card key={i} faceDown size="sm" dealDelay={i * 70} />
                    ))}
                  </div>
                )}
                <div className="text-sm text-white/60 font-medium">13 cartes par joueur</div>
              </>
            )}
            {intro.phase === "first" && (
              <>
                <div className="text-5xl mb-2">🎲</div>
                <div className="text-base text-white/50 uppercase tracking-widest font-semibold">Premier joueur</div>
                <div className="text-3xl font-extrabold">{intro.pickName}</div>
                <div className="mt-4 inline-flex items-center gap-2 px-5 py-2 rounded-full bg-primary/20 border border-primary/30 text-primary text-sm font-bold">
                  🃏 Commence la partie !
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {/* Melds on table — masqué à la demande */}

      {/* ── MY HAND ── */}
      {me && (
        <div className="space-y-2">
          {/* Optimal play panel supprimé */}

          {/* Hand — 2 rows so cards stay large without overlap */}
          <div className={reorderMode ? "overflow-x-auto" : ""}>
            <div
              ref={handRef}
              className={`${reorderMode ? "flex gap-2 min-w-max" : "flex flex-col gap-2"} px-1 py-2`}
            >
              {reorderMode ? (
                orderedHandCards.map((c, i) => {
                  const isGrabbed = movingIdx === i;
                  return (
                    <div key={`ro-${c}-${i}`} className="relative flex flex-col items-center gap-0.5 shrink-0">
                      <div className={`flex items-center gap-0.5 mb-1 ${isGrabbed ? "opacity-100" : "opacity-0"}`}>
                        <button onClick={() => i > 0 && moveCard(i, i - 1)} className="w-5 h-5 rounded-full bg-violet-600 text-white flex items-center justify-center">
                          <ChevronLeft className="w-3 h-3" />
                        </button>
                        <button onClick={() => i < orderedHandCards.length - 1 && moveCard(i, i + 1)} className="w-5 h-5 rounded-full bg-violet-600 text-white flex items-center justify-center">
                          <ChevronRight className="w-3 h-3" />
                        </button>
                      </div>
                      <Card c={c} size="lg" selected={isGrabbed} onClick={() => handleReorderTap(i)} />
                      {isGrabbed && <div className="text-[9px] text-violet-600 font-bold mt-0.5">saisie</div>}
                    </div>
                  );
                })
              ) : (() => {
                const n = orderedHandCards.length;
                const perRow = Math.ceil(n / 2);
                const rows = [orderedHandCards.slice(0, perRow), orderedHandCards.slice(perRow)];
                const avail = (typeof window !== "undefined" ? Math.min(window.innerWidth, 480) : 360) - 24;
                const cw = Math.max(56, Math.min(84, Math.floor((avail - (perRow - 1) * 6) / Math.max(perRow, 1))));
                const ch = Math.round(cw * 1.42);
                let globalIdx = 0;
                return rows.map((row, ri) => (
                  <div key={`row-${ri}`} className="flex justify-center items-end gap-1.5" data-drop-target="hand-end">
                    {row.map((c) => {
                      const i = globalIdx++;
                      const isSel = selected.includes(c);
                      const showQuickDiscard = isSel && isMyTurn && phase === "play" && selected.length === 1 && !busy;
                      const srcId = `hand:${c}`;
                      const isBeingDragged = dnd.isDraggingId(srcId);
                      const dropSide = dnd.isTargetId(srcId);
                      return (
                        <div
                          key={`${c}-${i}`}
                          className="relative transition-all duration-200 ease-out select-none"
                          data-drop-target={srcId}
                          {...dnd.getSourceProps(srcId)}
                          style={{
                            zIndex: isBeingDragged ? 1 : isSel ? 100 + i : i,
                            transform: isBeingDragged
                              ? undefined
                              : isSel
                              ? "translateY(-14px) scale(1.05)"
                              : undefined,
                            opacity: isBeingDragged ? 0.25 : 1,
                            touchAction: "none",
                            filter: isBeingDragged
                              ? "grayscale(0.6)"
                              : isSel
                              ? "drop-shadow(0 10px 16px rgba(0,0,0,0.45))"
                              : "drop-shadow(0 4px 6px rgba(0,0,0,0.35))",
                          }}
                        >
                          {dropSide === "before" && (
                            <div className="absolute -left-1 top-1 bottom-1 w-1 rounded-full bg-primary shadow-[0_0_10px_hsl(var(--primary))] animate-pulse pointer-events-none" />
                          )}
                          {dropSide === "after" && (
                            <div className="absolute -right-1 top-1 bottom-1 w-1 rounded-full bg-primary shadow-[0_0_10px_hsl(var(--primary))] animate-pulse pointer-events-none" />
                          )}
                          {showQuickDiscard && (
                            <button
                              onClick={(e) => { e.stopPropagation(); discardOne(); }}
                              className="absolute -top-8 left-1/2 -translate-x-1/2 z-[999] px-3 py-1 rounded-full bg-destructive text-white text-[11px] font-extrabold shadow-lg shadow-destructive/40 flex items-center gap-1 whitespace-nowrap animate-scale-in hover:bg-destructive/90 active:scale-95"
                            >
                              <Trash2 className="w-3 h-3" /> Défausser
                            </button>
                          )}
                          <Card
                            c={c}
                            selected={isSel}
                            onClick={() => { if (!dnd.drag) toggleSel(c); }}
                            dealDelay={dealAnimating ? i * 80 : undefined}
                            styleOverride={{ width: `${cw}px`, height: `${ch}px`, pointerEvents: dnd.drag ? "none" : undefined }}
                          />
                          {newCard === c && (
                            <>
                              <div className="absolute inset-0 rounded-lg ring-2 ring-amber-400 shadow-[0_0_14px_rgba(251,191,36,0.7)] pointer-events-none animate-pulse" />
                              <div className="absolute -top-2 -right-1 z-[60] px-1.5 py-0.5 rounded-full bg-amber-400 text-black text-[9px] font-extrabold shadow-md pointer-events-none animate-scale-in">
                                NEW
                              </div>
                            </>
                          )}
                        </div>
                      );
                    })}
                  </div>
                ));

              })()}
              {handCards.length === 0 && (
                <div className="flex flex-col items-center gap-1 p-8 self-center text-center">
                  <div className="text-2xl">🎉</div>
                  <div className="text-xs text-emerald-400 font-bold">Main vide !</div>
                  <div className="text-[10px] text-muted-foreground/60">Tu as posé toutes tes cartes</div>
                </div>
              )}
            </div>
          </div>




          {/* Action bar during play phase */}
          {isMyTurn && phase === "play" && !reorderMode && (
            <div className="space-y-2">
              {/* Quick actions row */}
              {selected.length > 0 && (
                <div className="flex items-center gap-2">
                  <button onClick={() => setSelected([])} className="flex items-center gap-1 px-3 py-2 rounded-full bg-secondary text-foreground font-semibold text-xs">
                    <X className="w-3.5 h-3.5" /> Tout désélectionner
                  </button>
                </div>
              )}

              {/* Selected cards preview + feedback */}
              {selected.length > 0 && (
                <div className={`rounded-2xl border p-3 space-y-2.5 transition-all ${
                  selectionValidity === 'valid' ? 'border-emerald-500/30 bg-emerald-500/5 shadow-sm shadow-emerald-500/10'
                  : selectionValidity === 'invalid' ? 'border-destructive/30 bg-destructive/5'
                  : 'border-primary/20 bg-primary/5'
                }`}>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className={`w-2 h-2 rounded-full ${selectionValidity === 'valid' ? 'bg-emerald-400' : selectionValidity === 'invalid' ? 'bg-destructive' : 'bg-primary'}`} />
                      <div className="text-xs font-bold">
                        {selected.length} carte{selected.length > 1 ? "s" : ""} sélectionnée{selected.length > 1 ? "s" : ""}
                      </div>
                    </div>
                    {selectionFeedback.hint && (
                      <div className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${
                        selectionFeedback.severity === 'ok' ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300'
                        : selectionFeedback.severity === 'error' ? 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300'
                        : selectionFeedback.severity === 'warn' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300'
                        : 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300'
                      }`}>
                        {selectionFeedback.hint}
                      </div>
                    )}
                  </div>
                  <div className="flex gap-2 overflow-x-auto pb-1">
                    {selected.map((c, i) => <Card key={`sel-${c}-${i}`} c={c} size="md" />)}
                  </div>
                  <div className="flex gap-2 flex-wrap">
                    <button onClick={addToStaged} disabled={busy || selected.length < 3}
                      className="flex items-center gap-1.5 px-4 py-2.5 rounded-xl bg-emerald-600 text-white font-bold text-sm disabled:opacity-40 shadow-md shadow-emerald-600/25 hover:bg-emerald-500 active:scale-95 transition-all">
                      <Plus className="w-4 h-4" /> Ajouter au plateau
                    </button>
                    <button onClick={discardOne} disabled={busy || selected.length !== 1}
                      className="flex items-center gap-1.5 px-4 py-2.5 rounded-xl bg-destructive text-white font-bold text-sm disabled:opacity-40 shadow-md shadow-destructive/25 hover:bg-destructive/90 active:scale-95 transition-all">
                      <Trash2 className="w-4 h-4" /> Défausser
                    </button>
                    <button onClick={() => setSelected([])}
                      className="flex items-center gap-1.5 px-3 py-2.5 rounded-xl bg-white/8 text-muted-foreground font-semibold text-sm hover:bg-white/12 active:scale-95 transition-all">
                      <X className="w-4 h-4" /> Annuler
                    </button>
                  </div>
                  {/* Layoff hint */}
                  {layoffCandidates.size > 0 && (
                    <div className="flex items-center gap-1.5 text-[10px] text-emerald-400 font-semibold px-2 py-1 rounded-lg bg-emerald-500/8 border border-emerald-500/15">
                      ↑ {layoffCandidates.size} combinaison{layoffCandidates.size > 1 ? 's' : ''} sur table accepte{layoffCandidates.size > 1 ? 'nt' : ''} ces cartes
                    </div>
                  )}
                </div>
              )}

              {/* Bouton Valider ma main — CTA doré */}
              {isMyTurn && game?.turn_phase === "play" && staged.length > 0 && (
                <div className="rounded-2xl p-3 bg-gradient-to-r from-amber-500/15 via-yellow-500/10 to-amber-500/15 border border-amber-500/40 shadow-lg">
                  <button
                    onClick={validateHand}
                    disabled={busy || staged.length === 0 || selected.length !== 1}
                    className="w-full flex items-center justify-center gap-2 px-4 py-3.5 rounded-xl bg-gradient-to-r from-amber-500 to-yellow-500 text-black font-black text-base shadow-md shadow-amber-500/40 disabled:opacity-40 hover:brightness-110 active:scale-[0.98] transition-all"
                  >
                    <Check className="w-5 h-5" />
                    {selected.length === 1
                      ? `Valider ma main (${staged.length} combo${staged.length > 1 ? 's' : ''} + 1 défausse)`
                      : "Valider ma main — sélectionne 1 carte à défausser"}
                  </button>
                  <p className="text-[10px] text-center text-amber-200/80 mt-1.5">
                    Le serveur vérifie toutes tes combinaisons. Si tout est valide, tu gagnes.
                  </p>
                </div>
              )}

              {/* Staging zone */}
              {staged.length > 0 && (
                <div className="rounded-2xl bg-emerald-500/6 border border-emerald-500/20 p-3 space-y-3 shadow-sm">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                      <div className="text-xs font-bold text-emerald-600 dark:text-emerald-400">
                        Zone de pose · {staged.length} combinaison{staged.length > 1 ? "s" : ""}
                      </div>
                    </div>
                    {staged.length > 1 && (
                      <button onClick={submitAllStaged} disabled={busy}
                        className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-600 text-white font-bold text-xs disabled:opacity-40 shadow-sm hover:bg-emerald-500 active:scale-95 transition-all">
                        <Check className="w-3.5 h-3.5" /> Tout poser
                      </button>
                    )}
                  </div>
                  <div className="space-y-2">
                    {staged.map((group, gi) => (
                      <div key={gi} className={`rounded-xl p-2.5 flex items-center gap-2 transition-all border ${
                        stagedValidity[gi] === 'valid' ? 'bg-emerald-500/5 border-emerald-500/25 shadow-sm'
                        : stagedValidity[gi] === 'invalid' ? 'bg-destructive/5 border-destructive/25'
                        : 'bg-white/4 border-white/8'
                      }`}>
                        <div className="flex gap-1.5 overflow-x-auto flex-1 pb-1" data-drop-target={`staged-end:${gi}`}>
                          {group.map((c, ci) => {
                            const srcId = `staged:${gi}:${c}`;
                            const isBeingDragged = dnd.isDraggingId(srcId);
                            const dropSide = dnd.isTargetId(srcId);
                            return (
                              <div
                                key={`stage-${gi}-${ci}`}
                                className="relative select-none"
                                data-drop-target={srcId}
                                {...dnd.getSourceProps(srcId)}
                                style={{
                                  opacity: isBeingDragged ? 0.55 : 1,
                                  transform: isBeingDragged ? "translateY(-10px) scale(1.06)" : undefined,
                                  transition: "transform 0.15s ease-out",
                                  touchAction: "none",
                                }}
                              >
                                {dropSide === "before" && (
                                  <div className="absolute -left-1 top-0 bottom-0 w-1 rounded-full bg-primary shadow-[0_0_10px_hsl(var(--primary))] animate-pulse pointer-events-none" />
                                )}
                                {dropSide === "after" && (
                                  <div className="absolute -right-1 top-0 bottom-0 w-1 rounded-full bg-primary shadow-[0_0_10px_hsl(var(--primary))] animate-pulse pointer-events-none" />
                                )}
                                <Card c={c} size="md" onRemove={() => removeFromStaged(gi, c)} />
                              </div>
                            );
                          })}
                        </div>

                        <div className="flex flex-col gap-1.5 shrink-0 items-end">
                          {stagedValidity[gi] !== 'unknown' && (
                            <span className={`text-[10px] font-bold ${stagedValidity[gi] === 'valid' ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'}`}>
                              {stagedValidity[gi] === 'valid' ? '✓ Valide' : '✗ Invalide'}
                            </span>
                          )}
                          <button onClick={() => submitStagedMeld(gi)} disabled={busy || group.length < 3 || stagedValidity[gi] === 'invalid'}
                            className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-emerald-600 text-white text-xs font-bold disabled:opacity-40 hover:bg-emerald-500 active:scale-95 transition-all">
                            <Check className="w-3 h-3" /> Poser
                          </button>
                          <button onClick={() => removeStagedGroup(gi)}
                            className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-white/8 text-muted-foreground text-xs font-bold hover:bg-white/12 active:scale-95 transition-all">
                            <X className="w-3 h-3" /> ✕
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {selected.length === 0 && staged.length === 0 && null}
            </div>
          )}

        </div>
      )}

      <GamePauseControl
        slug="rami"
        gameId={id}
        game={game}
        remaining={remaining}
        totalSeconds={cfg.turn_timer_seconds}
        isMyTurn={!!isMyTurn}
        isPlayer={isPlayer}
        myUserId={profile?.id ?? null}
      />
      <GameChatDrawer gameId={id} />

      {/* Drag ghost — real card following the finger */}
      {dnd.drag && (() => {
        const parts = dnd.drag.sourceId.split(":");
        const cardNum = Number(parts[parts.length - 1]);
        if (!Number.isFinite(cardNum)) return null;
        return (
          <div
            className="fixed pointer-events-none z-[9999]"
            style={{
              left: dnd.drag.x - dnd.drag.ox,
              top: dnd.drag.y - dnd.drag.oy,
              width: dnd.drag.w,
              height: dnd.drag.h,
              transform: "translate3d(0,0,0) scale(1.12) rotate(-4deg)",
              transformOrigin: `${dnd.drag.ox}px ${dnd.drag.oy}px`,
              filter: "drop-shadow(0 18px 24px rgba(0,0,0,0.55)) drop-shadow(0 0 12px hsl(var(--primary)/0.55))",
              willChange: "left, top, transform",
              transition: "transform 120ms ease-out",
            }}
          >
            <Card c={cardNum} styleOverride={{ width: "100%", height: "100%" }} />
          </div>
        );
      })()}
    </main>

  );
}
