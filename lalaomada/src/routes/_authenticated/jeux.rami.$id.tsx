import { SUITS, SUIT_COLORS, RANKS } from "@/lib/game-constants";
import React from "react";
import { serverNow } from "@/lib/server-time";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, useCallback, useMemo, useRef } from "react";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";
import { supabase } from "@/integrations/supabase/client";
import SpectatorLeaveButton from "@/components/game/SpectatorLeaveButton";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { LogOut, Trash2, X, Check, ChevronLeft, ChevronRight, Pause, Volume2, VolumeX, Eye, Sparkles, ShieldAlert, Plus } from "lucide-react";
import GameSocialFab from "@/components/game/GameSocialFab";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import { useGameConfig } from "@/hooks/game/use-game-config";
import { useConfirm } from "@/components/ConfirmDialog";
import { useLongPressDrag } from "@/hooks/use-long-press-drag";
import ramiCover from "@/assets/games/rami.asset.json";
import { GameLoader } from "@/components/game/GameLoader";
// ── Haptic feedback helper ──
function haptic(pattern: number | number[]) {
  try { if (typeof navigator !== "undefined" && navigator.vibrate) navigator.vibrate(pattern); } catch {}
}

import { setMuted as setSfxMuted, isMuted as isSfxMuted, sfx } from "@/lib/game-sounds";
// Felt and card back images removed — now using pure CSS gradients for performance

export const Route = createFileRoute("/_authenticated/jeux/rami/$id")({
  component: RamiPage,
  head: () => ({ meta: [{ title: "Rami — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

// ── Playing Card SVG Renderer ─────────────────────────────────────────────
// Realistic playing card design with proper suit shapes, ornate court cards,
// and decorative card back pattern.

// ── Pure HTML/CSS Card System (zero SVG) ──────────────────────────────────
// Each card is a simple div with Unicode characters. No SVG elements at all.
// This is dramatically lighter on mobile — no SVG rendering contexts.

const SUIT_CHARS = ["♠", "♥", "♦", "♣"];
const RANK_CHARS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
const SUIT_HEX = ["#1a1a2e", "#c41e3a", "#c41e3a", "#1a1a2e"];

// Pip positions in % for CSS absolute positioning (x, y, rotate)
const PIP_CSS: [number, number, boolean][][] = [
  [[50, 50, false]],                                                        // A
  [[50, 22, false], [50, 78, true]],                                        // 2
  [[50, 22, false], [50, 50, false], [50, 78, true]],                       // 3
  [[33, 22, false], [67, 22, false], [33, 78, true], [67, 78, true]],       // 4
  [[33, 22, false], [67, 22, false], [50, 50, false], [33, 78, true], [67, 78, true]], // 5
  [[33, 22, false], [67, 22, false], [33, 50, false], [67, 50, false], [33, 78, true], [67, 78, true]], // 6
  [[33, 20, false], [67, 20, false], [50, 36, false], [33, 50, false], [67, 50, false], [33, 80, true], [67, 80, true]], // 7
  [[33, 20, false], [67, 20, false], [50, 34, false], [33, 46, false], [67, 46, false], [50, 68, true], [33, 80, true], [67, 80, true]], // 8
  [[33, 18, false], [67, 18, false], [33, 35, false], [67, 35, false], [50, 50, false], [33, 66, true], [67, 66, true], [33, 82, true], [67, 82, true]], // 9
  [[33, 16, false], [67, 16, false], [50, 26, false], [33, 36, false], [67, 36, false], [33, 64, true], [67, 64, true], [50, 74, true], [33, 84, true], [67, 84, true]], // 10
];

const CardBackCSS = React.memo(function CardBackCSS() {
  return (
    <div className="w-full h-full rounded-md flex items-center justify-center"
      style={{
        background: 'linear-gradient(135deg, #5a152f 0%, #7c1e3f 50%, #3d0f20 100%)',
        border: '1.5px solid rgba(201,162,39,0.3)',
        borderRadius: '5px',
      }}>
      <span style={{ fontSize: '55%', color: 'rgba(201,162,39,0.4)', fontWeight: 'bold', lineHeight: 1 }}>★</span>
    </div>
  );
});

const Card = React.memo(function Card({
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

  // Set fontSize on the card container so that % font-sizes inside are
  // proportional to the card width — prevents distortion on web/desktop
  // where card dimensions differ from mobile.
  const cardFontSize = styleOverride?.width
    ? (typeof styleOverride.width === "number"
        ? styleOverride.width
        : parseInt(String(styleOverride.width).replace(/px$/, ""), 10) || 48)
    : size === "sm" ? 36
    : size === "lg" ? 64
    : size === "xl" ? 80
    : 48;

  const dealStyle: React.CSSProperties = dealDelay !== undefined ? {
    animationDelay: `${dealDelay}ms`,
    opacity: 0,
    animation: `dealCard 0.25s ease-out ${dealDelay}ms forwards`,
  } : {};

  if (faceDown || c === undefined) {
    return (
      <div className={`${sizeClass} shrink-0 overflow-hidden`}
        style={{ ...dealStyle, ...styleOverride, border: '1px solid rgba(100,80,40,0.25)', borderRadius: '5px', fontSize: `${cardFontSize}px` }}>
        <CardBackCSS />
      </div>
    );
  }

  const base = c % 56;
  const isJoker = base >= 52;
  const suit = isJoker ? 0 : Math.floor(base / 13);
  const rank = isJoker ? 0 : base % 13;
  const rankChar = isJoker ? "★" : RANK_CHARS[rank];
  const suitChar = isJoker ? "" : SUIT_CHARS[suit];
  const color = isJoker ? "#7c3aed" : SUIT_HEX[suit];
  const isFace = !isJoker && rank >= 10;
  const isAce = rank === 0 && !isJoker;

  // Render card face as pure HTML/CSS
  const cardFace = (() => {
    if (isJoker) {
      return (
        <div className="w-full h-full flex flex-col items-center justify-center"
          style={{ background: '#fefce8', borderRadius: '5px', border: `1px solid ${color}55` }}>
          <span style={{ fontSize: '20%', fontWeight: 'bold', color, lineHeight: 1 }}>JOKER</span>
          <span style={{ fontSize: '40%', color, opacity: 0.6, lineHeight: 1.5 }}>★</span>
          <span style={{ fontSize: '20%', fontWeight: 'bold', color, lineHeight: 1 }}>JOKER</span>
        </div>
      );
    }
    if (isFace) {
      return (
        <div className="w-full h-full flex flex-col items-center justify-center relative"
          style={{ background: '#fefefe', borderRadius: '5px', border: '0.5px solid #c8c8c8' }}>
          {/* Top-left corner */}
          <span className="absolute top-[3%] left-[6%]" style={{ fontSize: '16%', fontWeight: 800, color, lineHeight: 1, fontFamily: 'Georgia, serif' }}>{rankChar}</span>
          <span className="absolute top-[16%] left-[6%]" style={{ fontSize: '12%', color, lineHeight: 1 }}>{suitChar}</span>
          {/* Bottom-right corner (rotated) */}
          <span className="absolute bottom-[3%] right-[6%]" style={{ fontSize: '16%', fontWeight: 800, color, lineHeight: 1, fontFamily: 'Georgia, serif', transform: 'rotate(180deg)' }}>{rankChar}</span>
          <span className="absolute bottom-[16%] right-[6%]" style={{ fontSize: '12%', color, lineHeight: 1, transform: 'rotate(180deg)' }}>{suitChar}</span>
          {/* Center: large rank + suit */}
          <span style={{ fontSize: '40%', fontWeight: 800, color, opacity: 0.85, lineHeight: 1, fontFamily: 'Georgia, serif' }}>{rankChar}</span>
          <span style={{ fontSize: '22%', color, opacity: 0.7, lineHeight: 1.2 }}>{suitChar}</span>
        </div>
      );
    }
    // Number cards with pips
    return (
      <div className="w-full h-full relative"
        style={{ background: '#fefefe', borderRadius: '5px', border: '0.5px solid #c8c8c8' }}>
        {/* Top-left corner */}
        <span className="absolute top-[3%] left-[6%]" style={{ fontSize: '16%', fontWeight: 800, color, lineHeight: 1, fontFamily: 'Georgia, serif' }}>{rankChar}</span>
        <span className="absolute top-[16%] left-[6%]" style={{ fontSize: '12%', color, lineHeight: 1 }}>{suitChar}</span>
        {/* Bottom-right corner (rotated) */}
        <span className="absolute bottom-[3%] right-[6%]" style={{ fontSize: '16%', fontWeight: 800, color, lineHeight: 1, fontFamily: 'Georgia, serif', transform: 'rotate(180deg)' }}>{rankChar}</span>
        <span className="absolute bottom-[16%] right-[6%]" style={{ fontSize: '12%', color, lineHeight: 1, transform: 'rotate(180deg)' }}>{suitChar}</span>
        {/* Center pips */}
        {isAce ? (
          <span className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
            style={{ fontSize: '55%', color, lineHeight: 1 }}>{suitChar}</span>
        ) : (
          PIP_CSS[rank].map(([px, py, flip], i) => (
            <span key={i} className="absolute"
              style={{
                left: `${px}%`, top: `${py}%`,
                transform: `translate(-50%,-50%) ${flip ? 'rotate(180deg)' : ''}`,
                fontSize: '8%', color, lineHeight: 1, fontWeight: 700,
              }}>{suitChar}</span>
          ))
        )}
      </div>
    );
  })();

  return (
    <div className="relative shrink-0" style={dealStyle}>
      <button
        onClick={onClick}
        disabled={!onClick}
        style={{ ...styleOverride, fontSize: `${cardFontSize}px`, borderRadius: '5px' }}
        className={`${sizeClass} block transition-transform duration-100 ease-out contain-strict
          ${selected ? "-translate-y-3 ring-2 ring-emerald-400 ring-offset-2 ring-offset-transparent" : ""}
          ${highlight === "layoff" ? "ring-2 ring-emerald-400 ring-offset-1 ring-offset-transparent scale-105" : ""}
          ${onClick ? "cursor-pointer active:scale-95" : "cursor-default"}`}>
        {cardFace}
      </button>
      {onRemove && (
        <button onClick={onRemove}
          className="absolute -top-2 -right-2 w-5 h-5 rounded-full bg-destructive text-white flex items-center justify-center z-10 shadow">
          <X className="w-3 h-3" />
        </button>
      )}
    </div>
  );
});


// ── Optimal play suggester ────────────────────────────────────────────────
const CARD_BASE = (c: number): number => c % 56;

const CARD_POINTS = (c: number): number => {
  const b = CARD_BASE(c);
  if (b >= 52) return 15;
  const r = b % 13;
  if (r === 0) return 11;
  if (r >= 10) return 10;
  return r + 1;
};

// ── Joker detection — mirrors backend _rami_is_joker ──────────────────────
// Card encoding: 0-51 deck A, 52-53 jokers deck A (2 jokers), 56-107 deck B, 108-109 jokers deck B (2 jokers)
// base = c % 56, so physical jokers always have base 52-55
function isJokerCard(c: number, jokerMode: string, randomJoker: number | null): boolean {
  const base = CARD_BASE(c);
  // Physical jokers (cards 52,53 — 2 per deck) — in classique/double
  if (base >= 52 && (jokerMode === 'classique' || jokerMode === 'double')) return true;
  // Color-opposite jokers — only in aleatoire/double
  if ((jokerMode === 'aleatoire' || jokerMode === 'double') && randomJoker !== null) {
    const rjBase = CARD_BASE(randomJoker);
    if (base < 52 && rjBase < 52) {
      const cardRank = base % 13;
      const jokerRank = rjBase % 13;
      const cardSuit = Math.floor(base / 13);
      const jokerSuit = Math.floor(rjBase / 13);
      if (cardRank === jokerRank && cardSuit !== jokerSuit) {
        const cardColor = (cardSuit === 0 || cardSuit === 3) ? 0 : 1; // ♠♣ black, ♥♦ red
        const jokerColor = (jokerSuit === 0 || jokerSuit === 3) ? 0 : 1;
        if (cardColor !== jokerColor) return true;
      }
    }
  }
  return false;
}

// Dead card: same rank AND same color as the random joker card (but different suit)
// This card is INVALID for ALL combinations (cannot be used in any meld)
function isDeadCard(c: number, jokerMode: string, randomJoker: number | null): boolean {
  const base = CARD_BASE(c);
  if (base >= 52) return false; // physical jokers are never dead cards
  if ((jokerMode !== 'aleatoire' && jokerMode !== 'double') || randomJoker === null) return false;
  const rjBase = CARD_BASE(randomJoker);
  if (rjBase >= 52) return false;
  const cardRank = base % 13;
  const jokerRank = rjBase % 13;
  const cardSuit = Math.floor(base / 13);
  const jokerSuit = Math.floor(rjBase / 13);
  if (cardRank === jokerRank && cardSuit !== jokerSuit) {
    const cardColor = (cardSuit === 0 || cardSuit === 3) ? 0 : 1;
    const jokerColor = (jokerSuit === 0 || jokerSuit === 3) ? 0 : 1;
    if (cardColor === jokerColor) return true; // SAME color = dead card
  }
  return false;
}


// Check if a joker card is in its natural position (used as itself, not as wildcard)
// For a SET: same rank as other cards, unique suit
// For a RUN: same suit as other cards, rank fits the consecutive sequence
function isJokerNatural(c: number, cards: number[], jokerMode: string, randomJoker: number | null): boolean {
  if (!isJokerCard(c, jokerMode, randomJoker)) return true;
  const base = CARD_BASE(c);
  if (base >= 52) return false; // physical jokers are never natural
  const cardRank = base % 13;
  const cardSuit = Math.floor(base / 13);
  const n = cards.length;

  // Collect other real (non-joker, non-dead) cards
  const others = cards.filter(x => x !== c && !isJokerCard(x, jokerMode, randomJoker) && !isDeadCard(x, jokerMode, randomJoker));
  if (others.length < 2) return false;

  const otherRanks = others.map(x => CARD_BASE(x) % 13);
  const otherSuits = others.map(x => Math.floor(CARD_BASE(x) / 13));

  // Check SET (trio/carre): all others same rank = joker's rank, joker's suit unique
  if (n === 3 || n === 4) {
    const allSameRank = otherRanks.every(r => r === cardRank);
    if (allSameRank && !otherSuits.includes(cardSuit)) {
      return true;
    }
  }

  // Check RUN: all others same suit = joker's suit, consecutive with joker's rank
  const allSameSuit = otherSuits.every(s => s === cardSuit);
  if (allSameSuit) {
    const allRanks = [...otherRanks, cardRank];
    if (new Set(allRanks).size === allRanks.length) {
      // Try As-low and As-high
      for (let tryHigh = 0; tryHigh < 2; tryHigh++) {
        const rs = tryHigh === 1 ? allRanks.map(r => r === 0 ? 13 : r) : [...allRanks];
        const minR = Math.min(...rs);
        const maxR = Math.max(...rs);
        if (maxR - minR + 1 === allRanks.length) return true;
      }
    }
  }

  return false;
}



// Calcule le nombre de "trous" (cartes manquantes) dans un escalier, en essayant
// l'As bas (valeur 0) ET l'As haut (valeur 13, après le Roi — ex: J-Q-K-A).
// Retourne le minimum de trous entre les deux interprétations, en respectant
// la même logique que le backend (_rami_meld_type).
function computeRunGaps(ranks: number[]): number {
  const calcGaps = (rs: number[]): number | null => {
    const sorted = [...rs].sort((a, b) => a - b);
    let gaps = 0;
    for (let i = 1; i < sorted.length; i++) {
      const diff = sorted[i] - sorted[i - 1];
      if (diff === 0) return null; // doublon = invalide
      gaps += diff - 1;
    }
    return gaps;
  };
  const normal = calcGaps(ranks);
  let best = normal === null ? Infinity : normal;
  if (ranks.includes(0)) {
    const aceHigh = ranks.map(r => (r === 0 ? 13 : r));
    const aceHighGaps = calcGaps(aceHigh);
    if (aceHighGaps !== null && aceHighGaps < best) best = aceHighGaps;
  }
  return best;
}

type MeldValidity = 'valid' | 'invalid' | 'unknown';

function validateMeld(
  cards: number[],
  jokerMode: string,
  randomJoker: number | null,
  sevenCardsEnabled: boolean = true,
): MeldValidity {
  if (cards.length < 3) return 'unknown';

  const isJoker = (c: number) => isJokerCard(c, jokerMode, randomJoker);
  const isDead = (c: number) => isDeadCard(c, jokerMode, randomJoker);
  const isNatural = (c: number) => isJokerNatural(c, cards, jokerMode, randomJoker);

  // Dead card (same color as random joker) = INVALID for ALL combinations
  if (cards.some(isDead)) return 'invalid';

  // Jokers used as wildcards (not in natural position) count as jokers
  // Natural jokers are treated as real cards
  const wildcardJokers = cards.filter(c => isJoker(c) && !isNatural(c));
  const naturalJokers = cards.filter(c => isJoker(c) && isNatural(c));
  const jokerCount = wildcardJokers.length;
  const real = cards.filter(c => !isJoker(c)).concat(naturalJokers);

  const checkSet = (): boolean => {
    if (cards.length > 4) return false;
    // Au moins 1 vraie carte (relâché de 2→1 pour le mode aléatoire)
    if (real.length < 1) return false;
    const rank = CARD_BASE(real[0]) % 13;
    if (!real.every(c => CARD_BASE(c) % 13 === rank)) return false;
    const suits = real.map(c => Math.floor(CARD_BASE(c) / 13));
    return new Set(suits).size === suits.length;
  };

  const checkSequence = (): boolean => {
    if (real.length < 1) return false;
    const suit = Math.floor(CARD_BASE(real[0]) / 13);
    if (!real.every(c => Math.floor(CARD_BASE(c) / 13) === suit)) return false;
    const ranks = real.map(c => CARD_BASE(c) % 13);
    if (new Set(ranks).size !== ranks.length) return false; // doublon
    return computeRunGaps(ranks) <= jokerCount;
  };

  if (checkSet() || checkSequence()) return 'valid';
  if (cards.length === 7 && isSevenCombo(cards, jokerMode, randomJoker, sevenCardsEnabled)) return 'valid';
  return 'invalid';
}

/** Type détecté d'une sélection : carré, trio, escalier ou 7 cartes. */
type MeldKind = 'carre' | 'trio' | 'run' | 'seven' | null;

function meldKind(cards: number[], jokerMode: string, randomJoker: number | null, sevenCardsEnabled: boolean = true): MeldKind {
  if (cards.length < 3) return null;
  if (cards.length === 7 && isSevenCombo(cards, jokerMode, randomJoker, sevenCardsEnabled)) return 'seven';
  if (validateMeld(cards, jokerMode, randomJoker, sevenCardsEnabled) !== 'valid') return null;
  const isJoker = (c: number) => isJokerCard(c, jokerMode, randomJoker);
  const real = cards.filter(c => !isJoker(c));
  const sameRank = real.length > 0 && real.every(c => CARD_BASE(c) % 13 === CARD_BASE(real[0]) % 13);
  if (sameRank && cards.length <= 4) return cards.length === 4 ? 'carre' : 'trio';
  return 'run';
}

const MELD_LABEL: Record<Exclude<MeldKind, null>, string> = {
  carre: "Carré",
  trio: "Trio",
  run: "Escalier",
  seven: "7 Cartes (Miverim-bola)",
};

/**
 * "7 Cartes - Miverim-bola" : carré (4 identiques) + brelan (3 identiques),
 * ou suite de 4 de la même couleur + brelan.
 */
/**
 * "7 Cartes - Miverim-bola" (règle PUR : aucun Joker).
 *
 * 3 compositions autorisées :
 *  1. Tri (3 même valeur) + Escalier (4 consécutives, même couleur)
 *  2. Tri (3 même valeur) + Carré (4 même valeur, couleurs différentes)
 *  3. Escalier (3 consécutives, même couleur) + Carré (4 même valeur)
 *
 * Règle essentielle : 100% PUR — aucun Joker n'est accepté.
 */
function isSevenCombo(cards: number[], jokerMode: string, randomJoker: number | null, sevenCardsEnabled: boolean = true): boolean {
  if (cards.length !== 7) return false;

  // 7 cartes = 100% PUR: aucun Joker non-naturel, aucune dead card
  const isJoker = (c: number) => isJokerCard(c, jokerMode, randomJoker);
  const isDead = (c: number) => isDeadCard(c, jokerMode, randomJoker);
  const isNatural = (c: number) => isJokerNatural(c, cards, jokerMode, randomJoker);
  // Reject dead cards and non-natural jokers
  if (cards.some(c => isDead(c) || (isJoker(c) && !isNatural(c)))) return false;

  // Tri pur : 3 cartes de même valeur, couleurs toutes différentes (jokers naturels OK)
  const isPureTrio = (sub: number[]): boolean => {
    if (sub.length !== 3 || sub.some(c => isDead(c) || (isJoker(c) && !isNatural(c)))) return false;
    const rank = CARD_BASE(sub[0]) % 13;
    if (!sub.every(c => CARD_BASE(c) % 13 === rank)) return false;
    const suits = sub.map(c => Math.floor(CARD_BASE(c) / 13));
    return new Set(suits).size === suits.length;
  };

  // Carré pur : 4 cartes de même valeur, couleurs toutes différentes (jokers naturels OK)
  const isPureCarre = (sub: number[]): boolean => {
    if (sub.length !== 4 || sub.some(c => isDead(c) || (isJoker(c) && !isNatural(c)))) return false;
    const rank = CARD_BASE(sub[0]) % 13;
    if (!sub.every(c => CARD_BASE(c) % 13 === rank)) return false;
    const suits = sub.map(c => Math.floor(CARD_BASE(c) / 13));
    return new Set(suits).size === suits.length;
  };

  // Escalier pur : cartes consécutives de même couleur, sans Joker non-naturel ni trou
  const isPureRun = (sub: number[]): boolean => {
    if (sub.length < 3 || sub.some(c => isDead(c) || (isJoker(c) && !isNatural(c)))) return false;
    const suit = Math.floor(CARD_BASE(sub[0]) / 13);
    if (!sub.every(c => Math.floor(CARD_BASE(c) / 13) === suit)) return false;
    const ranks = sub.map(c => CARD_BASE(c) % 13);
    if (new Set(ranks).size !== ranks.length) return false;
    return computeRunGaps(ranks) === 0;
  };

  // Toutes les partitions 3+4 des 7 cartes
  for (let i = 0; i < 5; i++)
    for (let j = i + 1; j < 6; j++)
      for (let k = j + 1; k < 7; k++) {
        const three = [cards[i], cards[j], cards[k]];
        const four = cards.filter((_, idx) => idx !== i && idx !== j && idx !== k);

        // Comp. 1 : Tri + Escalier de 4
        if (isPureTrio(three) && isPureRun(four)) return true;
        // Comp. 2 : Tri + Carré
        if (isPureTrio(three) && isPureCarre(four)) return true;
        // Comp. 3 : Escalier de 3 + Carré
        if (isPureRun(three) && isPureCarre(four)) return true;
        // Comp. 4 : Escalier de 3 + Escalier de 4
        if (isPureRun(three) && isPureRun(four)) return true;
      }
  return false;
}

// Find all valid melds (3–7 cards) in a hand
function findAllValidMelds(hand: number[], jokerMode: string, randomJoker: number | null, sevenCardsEnabled: boolean = true): number[][] {
  const melds: number[][] = [];
  const n = hand.length;
  for (let i = 0; i < n; i++)
    for (let j = i + 1; j < n; j++)
      for (let k = j + 1; k < n; k++) {
        const trio = [hand[i], hand[j], hand[k]];
        if (validateMeld(trio, jokerMode, randomJoker, sevenCardsEnabled) === 'valid') melds.push(trio);
        for (let l = k + 1; l < n; l++) {
          const quad = [hand[i], hand[j], hand[k], hand[l]];
          if (validateMeld(quad, jokerMode, randomJoker, sevenCardsEnabled) === 'valid') melds.push(quad);
          for (let m = l + 1; m < n; m++) {
            const five = [hand[i], hand[j], hand[k], hand[l], hand[m]];
            if (validateMeld(five, jokerMode, randomJoker, sevenCardsEnabled) === 'valid') melds.push(five);
            for (let o = m + 1; o < n; o++) {
              const six = [hand[i], hand[j], hand[k], hand[l], hand[m], hand[o]];
              if (validateMeld(six, jokerMode, randomJoker, sevenCardsEnabled) === 'valid') melds.push(six);
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

function suggestOptimalPlay(hand: number[], jokerMode: string, randomJoker: number | null, sevenCardsEnabled: boolean = true): OptimalPlay | null {
  const allMelds = findAllValidMelds(hand, jokerMode, randomJoker, sevenCardsEnabled);
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
  sevenCardsEnabled: boolean = true,
): { hint: string; severity: 'ok' | 'warn' | 'error' | 'info' } {
  if (cards.length === 0) return { hint: "", severity: 'info' };

  const isJoker = (c: number) => isJokerCard(c, jokerMode, randomJoker);

  const validity = validateMeld(cards, jokerMode, randomJoker, sevenCardsEnabled);
  if (validity === 'valid') return { hint: "✓ Combinaison valide — prête à poser", severity: 'ok' };
  if (validity === 'unknown') {
    // 1 or 2 cards — give a hint
    if (cards.length === 1) return { hint: "Sélectionne 2 cartes de plus pour un trio, ou 2+ de même couleur pour un escalier", severity: 'info' };
    const real = cards.filter(c => !isJoker(c));
    if (real.length >= 2) {
      const sameSuit = real.every(c => Math.floor(CARD_BASE(c) / 13) === Math.floor(CARD_BASE(real[0]) / 13));
      const sameRank = real.every(c => CARD_BASE(c) % 13 === CARD_BASE(real[0]) % 13);
      if (sameSuit) {
        const suitName = ["♠ Pique", "♥ Cœur", "♦ Carreau", "♣ Trèfle"][Math.floor(CARD_BASE(real[0]) / 13)];
        return { hint: `Escalier ${suitName} en cours — ajoute une carte adjacente`, severity: 'info' };
      }
      if (sameRank) {
        const rankName = RANKS[CARD_BASE(real[0]) % 13];
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

  const allSameSuit = real.every(c => Math.floor(CARD_BASE(c) / 13) === Math.floor(CARD_BASE(real[0]) / 13));
  const allSameRank = real.every(c => CARD_BASE(c) % 13 === CARD_BASE(real[0]) % 13);

  if (!allSameSuit && !allSameRank) {
    return { hint: "Cartes mixtes — sélectionne soit même valeur (trio), soit même couleur (escalier)", severity: 'error' };
  }

  if (allSameRank) {
    // Check for duplicate suits
    const suits = real.map(c => Math.floor(CARD_BASE(c) / 13));
    if (new Set(suits).size < suits.length) {
      return { hint: "Deux cartes de même couleur dans le trio — retire-en une", severity: 'error' };
    }
    if (cards.length > 4) {
      return { hint: "Un trio/carré ne peut pas dépasser 4 cartes", severity: 'error' };
    }
  }

  if (allSameSuit) {
    const ranks = real.map(c => CARD_BASE(c) % 13);
    if (new Set(ranks).size !== ranks.length) {
      return { hint: "Deux cartes identiques dans l'escalier", severity: 'error' };
    }
    const gaps = computeRunGaps(ranks);
    if (gaps > jokerCount) {
      return { hint: `Trou trop grand dans l'escalier (${gaps} manquant${gaps > 1 ? 's' : ''}, ${jokerCount} Joker${jokerCount > 1 ? 's' : ''} disponible${jokerCount > 1 ? 's' : ''})`, severity: 'warn' };
    }
  }

  return { hint: "Combinaison invalide", severity: 'error' };
}

// ── Pure meld detection (no jokers used) ──────────────────────────────────
function isPureMeld(cards: number[], jokerMode: string, randomJoker: number | null): boolean {
  return cards.length >= 3 && !cards.some(c => isJokerCard(c, jokerMode, randomJoker));
}

// ── Layoff candidates ─────────────────────────────────────────────────────
function getLayoffCandidates(
  melds: { player: string; cards: number[] }[],
  selected: number[],
  jokerMode: string,
  randomJoker: number | null,
  sevenCardsEnabled: boolean = true,
): Set<number> {
  const candidates = new Set<number>();
  melds.forEach((m, i) => {
    for (const card of selected) {
      // Try prepending or appending
      if (
        validateMeld([card, ...m.cards], jokerMode, randomJoker, sevenCardsEnabled) === 'valid' ||
        validateMeld([...m.cards, card], jokerMode, randomJoker, sevenCardsEnabled) === 'valid'
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
function RamiScoreSummary({ parts, hands, winnerId, pot, commissionPct, melds }: {
  parts: any[];
  hands: Record<string, number[]>;
  winnerId: string | null;
  pot?: number;
  commissionPct?: number;
  melds?: { player: string; cards: number[]; type?: string }[];
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
    if (CARD_BASE(c) >= 52) return { rank: "★", suit: "", color: "#7c3aed" };
    const s = Math.floor(CARD_BASE(c) / 13);
    const r = CARD_BASE(c) % 13;
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
                      <div key={ci} className="relative w-9 h-14 bg-white border border-gray-300 shadow font-bold flex flex-col p-0.5 text-[10px]" style={{ color: lbl.color, borderRadius: '5px' }}>
                        <div className="leading-none">{lbl.rank}<div>{lbl.suit}</div></div>
                        <div className="absolute bottom-0.5 right-0.5 text-[9px] bg-black/10 rounded px-0.5 font-mono">{pts}</div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="text-xs text-emerald-600 dark:text-emerald-400 font-semibold">Main vide — a posé toutes ses cartes !</div>
              )}
              {(melds || []).filter(m => m.player === p.user_id).length > 0 && (
                <div className="mt-1.5 pt-1.5 border-t border-white/6">
                  <div className="text-[10px] font-bold text-muted-foreground mb-1">Combinaisons posées :</div>
                  <div className="flex gap-1 flex-wrap">
                    {(melds || []).filter(m => m.player === p.user_id).map((m, mi) => (
                      <div key={mi} className="flex gap-0.5 px-1 py-0.5 rounded bg-primary/10 border border-primary/20">
                        {m.cards.map((c, ci) => {
                          const lbl = cardLabel(c);
                          return <span key={ci} className="text-[9px] font-bold" style={{ color: lbl.color }}>{lbl.rank}{lbl.suit}</span>;
                        })}
                      </div>
                    ))}
                  </div>
                </div>
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
      0%   { opacity: 0; transform: translateY(-60px) translateX(20px) scale(0.5) rotate(-12deg); }
      60%  { opacity: 1; transform: translateY(5px) translateX(0) scale(1.05) rotate(2deg); }
      100% { opacity: 1; transform: translateY(0) translateX(0) scale(1) rotate(0deg); }
    }
    @keyframes timerUrgent {
      0%, 100% { box-shadow: 0 0 0 0 rgba(220,38,38,0.5); }
      50%       { box-shadow: 0 0 0 6px rgba(220,38,38,0); }
    }
    .timer-urgent { box-shadow: 0 0 0 2px rgba(220,38,38,0.4); }
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
    @keyframes cardLift {
      0%   { transform: translateY(0) rotateX(0) scale(1); }
      100% { transform: translateY(-6px) rotateX(8deg) scale(1.04); }
    }
    @keyframes meldPulse {
      0%, 100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(16,185,129,0); }
      50%      { transform: scale(1.05); box-shadow: 0 0 20px 4px rgba(16,185,129,0.35); }
    }
    .meld-valid-badge { animation: meldPulse 0.8s ease-in-out 2; }
    @keyframes slideInRight {
      from { opacity: 0; transform: translateX(30px); }
      to   { opacity: 1; transform: translateX(0); }
    }
    .action-toast { animation: slideInRight 0.3s ease-out; }
    @keyframes glowPulse {
      0%, 100% { opacity: 0.4; }
      50%      { opacity: 0.8; }
    }
    .playable-glow { box-shadow: 0 0 0 2px rgba(251,191,36,0.5); }
    @keyframes cardFlip3D {
      0%   { transform: rotateY(180deg); }
      100% { transform: rotateY(0deg); }
    }
    @keyframes cardArrive {
      0%   { opacity: 0; transform: translateY(-40px) scale(0.6) rotate(-8deg); }
      50%  { opacity: 1; transform: translateY(4px) scale(1.08) rotate(2deg); }
      100% { opacity: 1; transform: translateY(0) scale(1) rotate(0deg); }
    }
    .card-arrive { animation: cardArrive 0.45s ease-out; }
    @keyframes turnPulse {
      0%, 100% { box-shadow: 0 0 0 0 rgba(251, 191, 36, 0.6), 0 0 20px rgba(251, 191, 36, 0.3); }
      50%      { box-shadow: 0 0 0 8px rgba(251, 191, 36, 0), 0 0 30px rgba(251, 191, 36, 0.5); }
    }
    .turn-active-pulse { animation: turnPulse 1.5s ease-in-out infinite; }
  `;
  document.head.appendChild(style);
}

// Flying card overlay — animates from source rect to target rect
// FlyingCard component removed for performance

// ── Main component ────────────────────────────────────────────────────────

// ── Detect available combos in hand (trio, escalier, carré) ──
type ComboHint = {
  type: 'trio' | 'escalier' | 'carré';
  cards: number[];
  label: string;
};

function detectCombos(hand: number[], jokerMode: string, randomJoker: number | null): ComboHint[] {
  if (hand.length < 3) return [];
  const hints: ComboHint[] = [];
  const realCards = hand.filter(c => !isJokerCard(c, jokerMode, randomJoker));
  const jokerCount = hand.length - realCards.length;

  // Group by rank for trios/carrés
  const byRank: Record<number, number[]> = {};
  for (const c of realCards) {
    const r = CARD_BASE(c) % 13;
    if (!byRank[r]) byRank[r] = [];
    byRank[r].push(c);
  }

  // Trios (3 of same rank, considering jokers)
  for (const [rankStr, cards] of Object.entries(byRank)) {
    const r = Number(rankStr);
    const rankName = RANKS[r];
    if (cards.length === 2 && jokerCount > 0) {
      hints.push({ type: 'trio', cards, label: `Trio de ${rankName} (avec Joker)` });
    } else if (cards.length === 3) {
      hints.push({ type: 'trio', cards, label: `Trio de ${rankName}` });
    } else if (cards.length >= 4) {
      hints.push({ type: 'carré', cards: cards.slice(0, 4), label: `Carré de ${rankName}` });
    }
  }

  // Escaliers (runs of same suit, 3+ consecutive, considering jokers and ace-high)
  const bySuit: Record<number, number[]> = {};
  for (const c of realCards) {
    const s = Math.floor(CARD_BASE(c) / 13);
    if (!bySuit[s]) bySuit[s] = [];
    bySuit[s].push(c);
  }

  for (const [suitStr, cards] of Object.entries(bySuit)) {
    const s = Number(suitStr);
    const suitName = SUITS[s];
    // Get unique ranks
    const ranks = [...new Set(cards.map(c => CARD_BASE(c) % 13))];
    if (ranks.length < 2 && jokerCount === 0) continue;

    // Try all windows of 3+ consecutive ranks
    for (let start = 0; start <= 13; start++) {
      for (let len = 3; len <= 5; len++) {
        // Check if we can form a run of `len` starting at `start` (ace-low: 0-12)
        let needed = 0;
        const have: number[] = [];
        for (let i = 0; i < len; i++) {
          const targetRank = (start + i) % 13;
          if (ranks.includes(targetRank)) {
            const card = cards.find(c => CARD_BASE(c) % 13 === targetRank)!;
            have.push(card);
          } else {
            needed++;
          }
        }
        if (needed <= jokerCount && needed > 0 && needed < len && have.length >= 2) {
          // Only show if start..start+len-1 is a valid window (not wrapping)
          if (start + len <= 14) { // 0-12 for ace-low, or 0-13 for ace-high (rank 13 = ace high)
            hints.push({ type: 'escalier', cards: have, label: `Escalier ${suitName} (${len} cartes, ${needed} Joker)` });
          }
        } else if (needed === 0 && have.length >= 3 && len >= 3) {
          // Full run without jokers — only show if it's a minimal window (not a subset of a larger one)
          if (start + len <= 14) {
            // Avoid duplicates: only add if not already a subset of a longer run
            const isSubset = hints.some(h =>
              h.type === 'escalier' && h.cards.length > have.length &&
              h.cards.every(c => have.includes(c) || !cards.includes(c))
            );
            if (!isSubset) {
              hints.push({ type: 'escalier', cards: have, label: `Escalier ${suitName} (${len} cartes)` });
            }
          }
        }
      }
    }
  }

  // Deduplicate and limit to top 5
  const seen = new Set<string>();
  const unique = hints.filter(h => {
    const key = h.type + ':' + h.cards.slice().sort((a,b) => a-b).join(',');
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return unique.slice(0, 5);
}

function RamiPage() {
  const { id } = Route.useParams();
  const { profile, isAdmin, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const [game, setGame] = useState<any>(null);
  const [gameNumber, setGameNumber] = useState<string | null>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [avatarsMap, setAvatarsMap] = useState<Record<string, string | null>>({});
  const [selected, setSelected] = useState<number[]>([]);
  // sevenFx removed for performance
  const [staged, setStaged] = useState<number[][]>([]);
  const [stagedMoving, setStagedMoving] = useState<{ gi: number; idx: number } | null>(null);
  const [sortMode, setSortMode] = useState<'none' | 'suit' | 'rank'>('none');
  const [boardTheme, setBoardTheme] = useState<'green' | 'blue' | 'dark'>('green');
  // Custom hand order for drag-reorder
  const [customOrder, setCustomOrder] = useState<number[] | null>(null);
  const [reorderMode, setReorderMode] = useState(false);
  const [movingIdx, setMovingIdx] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [optimalPlay, setOptimalPlay] = useState<OptimalPlay | null>(null);
  const [showOptimal, setShowOptimal] = useState(false);
  // cardFx removed for performance
  const deckRef = React.useRef<HTMLButtonElement | null>(null);
  const handRef = React.useRef<HTMLDivElement | null>(null);
  const discardRefs = React.useRef<Record<string, HTMLDivElement | null>>({});
  const centerOf = (el: HTMLElement | null | undefined) => {
    if (!el) return { x: window.innerWidth / 2, y: window.innerHeight / 2 };
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  };
  const [intro, setIntro] = useState<{ phase: "shuffle" | "joker" | "first" | "done"; pickName?: string } | null>(null);
  // dealAnimating removed for performance
  const [newCard, setNewCard] = useState<number | null>(null);
  const prevHandRef = useRef<number[]>([]);
  const { entries: lbEntries, recordRound, reset: resetLb } = useRamiLeaderboard(id);

  // Inject CSS keyframes once

  // Fetch game number from game_registrations
  useEffect(() => {
    if (!id) return;
    supabase.from("game_registrations")
      .select("game_number")
      .eq("game_id", id)
      .maybeSingle()
      .then(({ data }: any) => {
        if (data?.game_number) {
          setGameNumber('#' + String(data.game_number).padStart(8, '0'));
        }
      });
  }, [id]);

  useEffect(() => { ensureDealKeyframes(); }, []);

  // Board theme configuration
  const BOARD_THEMES = {
    green: { border: "#0b3a1f", overlay: "rgba(0,0,0,0.25)", tint: "rgba(15,61,32,0.3)", feltCenter: "#1a6b3a", feltEdge: "#0d4525" },
    blue: { border: "#0c2742", overlay: "rgba(5,20,40,0.3)", tint: "rgba(12,39,66,0.35)", feltCenter: "#1a3a6b", feltEdge: "#0c2742" },
    dark: { border: "#1a1a1a", overlay: "rgba(0,0,0,0.35)", tint: "rgba(10,10,10,0.4)", feltCenter: "#2a2a2a", feltEdge: "#141414" },
  };
  const activeTheme = BOARD_THEMES[boardTheme];

  const load = useCallback(async () => {
    // Fetch game + participants in parallel instead of sequentially — halves the
    // network round-trip time on every refresh.
    const [{ data: g }, { data: p }] = await Promise.all([
      supabase.from("rami_games" as any).select("id,status,state,current_turn,turn_phase,turn_deadline,winner_id,stake,pot,commission_pct,max_players,is_private,room_code,created_by,created_at,started_at,finished_at,paused,pause_deadline,pause_used,afk_warning,afk_pause_for,afk_pause_name,afk_warnings,spectators_count,game_mode,joker_mode,random_joker,seven_cards,turn_skips,tournament_match_id,winner_name").eq("id", id).maybeSingle(),
      supabase.from("rami_participants" as any).select("*").eq("game_id", id).order("slot"),
    ]);
    setGame(g);
    setParts((p as any[]) || []);
  }, [id, profile?.id]);

  // Fetch real avatars for human participants (bots use a diamond icon instead)
  useEffect(() => {
    const humanIds = Array.from(new Set(
      parts.filter(p => !p.is_bot && p.user_id).map(p => p.user_id as string)
    )).filter(uid => !(uid in avatarsMap));
    if (humanIds.length === 0) return;
    (async () => {
      const { data } = await supabase.from("profiles" as any).select("id,avatar_url").in("id", humanIds);
      if (!data) return;
      const next: Record<string, string | null> = {};
      (data as any[]).forEach(row => { next[row.id] = row.avatar_url || null; });
      setAvatarsMap(prev => ({ ...prev, ...next }));
    })();
  }, [parts, avatarsMap]);

  useEffect(() => {
    load();
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
    const debouncedLoad = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => load(), 300);
    };
    let heartbeat: ReturnType<typeof setInterval> | null = null;
    const ch = supabase.channel("rami-" + id)
      .on("postgres_changes", { event: "*", schema: "public", table: "rami_games", filter: `id=eq.${id}` }, (payload: any) => {
        if (payload.eventType !== "DELETE" && payload.new) {
          setGame(prev => {
            if (!prev) return payload.new;
            // Only accept newer events (updated_at guard)
            const prevUp = (prev as any).updated_at;
            const newUp = (payload.new as any).updated_at;
            if (prevUp && newUp && newUp < prevUp) return prev;
            return payload.new;
          });
        } else { debouncedLoad(); }
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "rami_participants", filter: `game_id=eq.${id}` }, (payload: any) => {
        if (payload.eventType === "INSERT" && payload.new) {
          setParts(prev => prev.some(p => p.id === payload.new.id) ? prev : [...prev, payload.new]);
        } else if (payload.eventType === "UPDATE" && payload.new) {
          setParts(prev => prev.map(p => p.id === payload.new.id ? payload.new : p));
        } else if (payload.eventType === "DELETE" && payload.old) {
          setParts(prev => prev.filter(p => p.id !== payload.old.id));
        } else { debouncedLoad(); }
      })
      .subscribe((status: string) => {
        if (status === "SUBSCRIBED") {
          if (heartbeat) clearInterval(heartbeat);
          heartbeat = setInterval(() => load(), 10_000);
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          if (heartbeat) { clearInterval(heartbeat); heartbeat = null; }
          setTimeout(() => load(), 300);
        }
      });
    return () => { supabase.removeChannel(ch); if (debounceTimer) clearTimeout(debounceTimer); if (heartbeat) clearInterval(heartbeat); };
  }, [id, load]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });

  const recordedRef = React.useRef(false);
  useEffect(() => {
    if (game?.status === "finished" && game.state?.hands && !recordedRef.current) {
      recordedRef.current = true;
      recordRound(parts, game.state.hands as Record<string, number[]>, game.winner_id);
    }
  }, [game?.status, game?.state?.hands, game?.winner_id, parts, recordRound]);

  // cancelled state handled by GameStateMessage below

  // ── Deal animation: trigger when game starts ──
  const prevStatusRef2 = useRef<string>("");
  useEffect(() => {
    if (prevStatusRef2.current !== "playing" && game?.status === "playing") {
      // dealAnimating removed
      // dealAnimating removed
      return;
    }
    prevStatusRef2.current = game?.status || "";
  }, [game?.status]);

  // ── Turn change sound ──
  const prevTurnSlot = useRef<number | null>(null);
  useEffect(() => {
    if (!game || game.status !== "playing") return;
    const cur = game.current_turn;
    if (prevTurnSlot.current !== null && prevTurnSlot.current !== cur) {
      sfx.ramiTurnChange();
    }
    prevTurnSlot.current = cur;
  }, [game?.current_turn, game?.status]);

  // ── Win sound for opponent winning ──
  const prevStatusRef = useRef<string>("");
  useEffect(() => {
    if (prevStatusRef.current === "playing" && game?.status === "finished") {
      sfx.ramiWin();
    }
    if (game?.status) prevStatusRef.current = game.status;
  }, [game?.status]);

  // ── Bot-action feedback: highlight new melds / discards + toast ──
  // flashMelds/flashDiscards removed for performance
  const botFxRef = React.useRef<{ meldsLen: number; discardKey: string; discardTop?: number; init: boolean }>({ meldsLen: 0, discardKey: "", discardTop: undefined, init: false });
  useEffect(() => {
    if (!game) return;
    const currentMelds: { player: string; cards: number[]; type?: string }[] = game?.state?.melds || [];
    const currentDiscards: Record<string, number[]> = {};
    const lastBy: string = "";
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
        // Toast Miverim-bola supprimé : déjà géré par le toast ⭐7 plus bas
        if (p?.is_bot && m.type !== "seven") {
          const kind = m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
          // REMOVED: bot meld toast
        }
        // Also notify for human opponents
        if (!p?.is_bot && p && m.type !== "seven") {
          const kind = m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
          // REMOVED: toast for human opponent melds
        }
      }
    }

    const newDiscardKeys: string[] = [];
    if ((prev.discardKey !== lastBy || prev.discardTop !== top) && top !== undefined && lastBy !== "_seed") {
      newDiscardKeys.push(lastBy);
      const p = parts.find(pp => pp.user_id === lastBy);
      if (p?.is_bot) {
        const cardLabel = top !== undefined ? (() => {
          const b = top % 56;
          if (b >= 52) return "Joker";
          const s = Math.floor(b / 13);
          const r = b % 13;
          const suitSym = ["♠", "♥", "♦", "♣"][s];
          return `${RANKS[r]}${suitSym}`;
        })() : "une carte";
        // REMOVED: bot discard toast
      }
    }

    botFxRef.current = { meldsLen: currentMelds.length, discardKey: lastBy, discardTop: top, init: true };

    if (newMeldIdxs.length) {
    // Flash effects removed for performance
    }
    if (newDiscardKeys.length) {
    // Flash discards removed
    }
  }, [game?.state?.melds, game?.state?.discard, parts, profile?.id]);

  // ── Intro overlay: show who starts first ──
  const [showFirstPlayerIntro, setShowFirstPlayerIntro] = useState(false);
  // 7-card melds from other players: show for 10 seconds then auto-hide
  const [visibleSevenMelds, setVisibleSevenMelds] = useState<Set<string>>(new Set());
  const [shownSevenMelds, setShownSevenMelds] = useState<Set<string>>(new Set());
  const [firstPlayerName, setFirstPlayerName] = useState("");
  const [showDiscardHistory, setShowDiscardHistory] = useState(false);
  const prevStatusRef3 = useRef<string>("");

  useEffect(() => {
    if (prevStatusRef3.current !== "playing" && game?.status === "playing" && game?.state?.first_player !== undefined) {
      const firstSlot = game.state.first_player;
      const firstPlayer = parts.find(p => p.slot === firstSlot);
      const name = firstPlayer?.display_name || (firstPlayer?.is_bot ? "Bot" : "Joueur");
      setFirstPlayerName(name);
      setShowFirstPlayerIntro(true);
      // Auto-hide after 2.5s
      setTimeout(() => setShowFirstPlayerIntro(false), 2500);
      // Also show toast
      if (firstPlayer?.user_id === profile?.id) {
        toast.success("🎲 Tu commences la partie ! Organise tes cartes et défausse-en une.");
      } else {
        toast.info(`🎲 ${name} commence la partie`);
      }
    }
    prevStatusRef3.current = game?.status || "";
  }, [game?.status, game?.state?.first_player, parts, profile?.id]);


  const me = parts.find(p => p.user_id === profile?.id);
  const isPlayer = !!me;
  const [isSpectating, setIsSpectating] = useState(false);
  const [spectateData, setSpectateData] = useState<any>(null);

  // Spectator mode: if not a player and game is playing, allow spectating
  // Only trigger after parts have loaded to avoid race condition with realtime
  useEffect(() => {
    if (!isPlayer && parts.length > 0 && game?.status === "playing" && !isSpectating && profile?.id) {
      void supabase.rpc("rami_spectate" as any, { _game_id: id } as any).then(({ data }: any) => {
        if (data) {
          setIsSpectating(true);
          setSpectateData(data);
          void supabase.rpc("rami_spectate" as any, { _game_id: id } as any).then(({ data: d2 }: any) => {
            if (d2) setSpectateData(d2);
          }, () => {});
        }
      }, () => {});
    }
  }, [isPlayer, game?.status, id, profile?.id, isSpectating]);

  // Reset spectator mode if user is actually a player (fixes race condition)
  useEffect(() => {
    if (isPlayer && isSpectating) {
      setIsSpectating(false);
      void supabase.rpc("rami_spectate_leave" as any, { _game_id: id } as any).then(() => {}, () => {});
    }
  }, [isPlayer, isSpectating, id]);

  // Poll spectate data every 3s
  useEffect(() => {
    if (!isSpectating) return;
    const t = setInterval(async () => {
      const { data }: any = await supabase.rpc("rami_spectate" as any, { _game_id: id } as any);
      if (data) setSpectateData(data);
    }, 5000);
    return () => clearInterval(t);
  }, [isSpectating, id]);

  // Leave spectation on unmount
  useEffect(() => {
    return () => {
      if (isSpectating) {
        void supabase.rpc("rami_spectate_leave" as any, { _game_id: id } as any).then(() => {}, () => {});
      }
    };
  }, []);
  const isMyTurn = game?.status === "playing" && me && game.current_turn === me.slot;
  const phase = game?.turn_phase;
  const myHand: number[] = useMemo(() => {
    const h = game?.state?.hands?.[profile?.id || ""];
    return Array.isArray(h) ? h : [];
  }, [game?.state?.hands, profile?.id]);
  // ═══ SYSTÈME SIMPLIFIÉ: discard (int[]) = seule source de vérité ═══
  const flatDiscard: number[] = useMemo(() => {
    const raw = game?.state?.discard;
    return Array.isArray(raw) ? (raw as number[]) : [];
  }, [game?.state?.discard]);

  const topDiscard = flatDiscard.length > 0 ? flatDiscard[flatDiscard.length - 1] : undefined;
  const deckCount: number = (game?.state?.deck || []).length;
  const melds: { player: string; cards: number[]; type?: string }[] = game?.state?.melds || [];
  const jokerMode: string = game?.joker_mode || "classique";
  const gameMode: "bordel" | "naturel" = (game?.game_mode as any) || "bordel";
  const randomJoker: number | null = game?.random_joker ?? null;
  const sevenCardsEnabled = (game as any)?.seven_cards !== false; // default true if undefined
  const cfg = useGameConfig("rami");
  const MAX_LIVES = cfg.max_turn_skips || 3;
  const livesOf = (uid: string) => {
    const skips = (game as any)?.turn_skips;
    if (!skips) return MAX_LIVES;
    const used = skips[uid] || 0;
    return Math.max(0, MAX_LIVES - used);
  };
  const myLives = profile?.id ? livesOf(profile.id) : MAX_LIVES;
  const refunded: Record<string, boolean> = game?.state?.refunded || {};
  const myRefunded = !!(profile?.id && refunded[profile.id]);

  // Action log from game state
  const actionLog: any[] = useMemo(() => {
    const log = game?.state?.action_log;
    if (!Array.isArray(log)) return [];
    return log.slice(-10).reverse();
  }, [game?.state?.action_log]);

  // 1er tour: 0 melds + action_log quasi vide
  const isFirstTurn = false; // Plus besoin — le 1er joueur commence en phase 'play'

  // Track 7-card melds from other players — show for 10s then auto-hide
  // Only show toast for actual players (not spectators), and only once per meld
  useEffect(() => {
    if (!melds || !profile?.id) return;
    const newSeven: string[] = [];
    melds.forEach((m: any, i: number) => {
      if (m.player !== profile.id && m.seven === true) {
        const meldKey = `${m.player}-${i}`;
        if (!shownSevenMelds.has(meldKey)) {
          newSeven.push(meldKey);
        }
      }
    });
    if (newSeven.length > 0) {
      // Show them to everyone (players + spectators can see the melds)
      setVisibleSevenMelds(prev => {
        const next = new Set(prev);
        newSeven.forEach(k => next.add(k));
        return next;
      });
      setShownSevenMelds(prev => {
        const next = new Set(prev);
        newSeven.forEach(k => next.add(k));
        return next;
      });
      // Toast: ONLY for actual players (not spectators) — one toast, not two
      if (isPlayer) {
        const claimerMeld = melds.find((m: any, i: number) => {
          const meldKey = `${m.player}-${i}`;
          return newSeven.includes(meldKey);
        });
        const claimer = parts.find(p => (p.user_id as string) === claimerMeld?.player || `bot:${p.slot}` === claimerMeld?.player);
        const claimerName = claimer?.display_name || "Un joueur";
        toast.info(`⭐7 ${claimerName} a validé ses 7 cartes !`, { duration: 10000 });
      }
      // Auto-hide after 10 seconds
      newSeven.forEach(key => {
        setTimeout(() => {
          setVisibleSevenMelds(prev => {
            const next = new Set(prev);
            next.delete(key);
            return next;
          });
        }, 10000);
      });
    }
  }, [melds, profile?.id, isPlayer]);


  const stagedFlat = useMemo(() => staged.flat(), [staged]);
  const handCards = useMemo(() => myHand.filter(c => !stagedFlat.includes(c)), [myHand, stagedFlat]);
  const handPoints = useMemo(() => handCards.reduce((s, card) => s + CARD_POINTS(card), 0), [handCards]);

  // Apply custom order or sort mode
  const orderedHandCards = useMemo(() => {
    // If user has a custom order AND no sort mode active, respect it
    if (customOrder !== null && sortMode === 'none') {
      const inOrder = customOrder.filter(c => handCards.includes(c));
      const extras = handCards.filter(c => !inOrder.includes(c));
      return [...inOrder, ...extras];
    }
    // If sort mode is active, sort everything (including new cards) into position
    const cards = [...handCards];
    if (sortMode === 'suit') {
      cards.sort((a, b) => {
        const sA = CARD_BASE(a) >= 52 ? 4 : Math.floor(CARD_BASE(a) / 13);
        const sB = CARD_BASE(b) >= 52 ? 4 : Math.floor(CARD_BASE(b) / 13);
        return sA !== sB ? sA - sB : (CARD_BASE(a) % 13) - (CARD_BASE(b) % 13);
      });
    } else if (sortMode === 'rank') {
      cards.sort((a, b) => {
        if (CARD_BASE(a) >= 52) return 1;
        if (CARD_BASE(b) >= 52) return -1;
        const rA = CARD_BASE(a) % 13, rB = CARD_BASE(b) % 13;
        return rA !== rB ? rA - rB : Math.floor(CARD_BASE(a) / 13) - Math.floor(CARD_BASE(b) / 13);
      });
    }
    return cards;
  }, [handCards, sortMode, reorderMode, customOrder]);

  // Initialize custom order once (or after it was explicitly cleared by the
  // sort buttons). Do NOT reset it on every hand-size change — that wiped the
  // player's manual arrangement on every draw/discard, making the hand look
  // "disordered" again. orderedHandCards already appends new cards to the end
  // and drops removed ones automatically, preserving the rest of the order.
  const prevHandLenRef = useRef(0);
  useEffect(() => {
    if (prevHandLenRef.current !== myHand.length) {
      prevHandLenRef.current = myHand.length;
      if (customOrder === null && handCards.length > 0) {
        setCustomOrder([...handCards]);
      } else if (handCards.length === 0) {
        setCustomOrder(null);
      }
    }
  }, [myHand.length, handCards, customOrder]);

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

  const selectionValidity = useMemo(() => validateMeld(selected, jokerMode, randomJoker, sevenCardsEnabled), [selected, jokerMode, randomJoker, sevenCardsEnabled]);

  // Cards in hand that could complete a valid meld with current selection
  const playableCards = useMemo(() => {
    if (!isMyTurn || phase !== "play" || selected.length === 0 || selected.length >= 4) return new Set<number>();
    const result = new Set<number>();
    for (const c of handCards) {
      if (selected.includes(c)) continue;
      const test = [...selected, c];
      const v = validateMeld(test, jokerMode, randomJoker, sevenCardsEnabled);
      if (v === "valid") result.add(c);
    }
    return result;
  }, [selected, handCards, isMyTurn, phase, jokerMode, randomJoker]);
  const selectionKind = useMemo(() => meldKind(selected, jokerMode, randomJoker, sevenCardsEnabled), [selected, jokerMode, randomJoker, sevenCardsEnabled]);
  // ── Auto-detect available combos in hand ──
  const availableCombos = useMemo(() => {
    if (!isPlayer || game?.status !== 'playing') return [];
    return detectCombos(handCards, jokerMode, randomJoker);
  }, [handCards, jokerMode, randomJoker, isPlayer, game?.status]);
  const selectionFeedback = useMemo(() => getSelectionFeedback(selected, jokerMode, randomJoker, sevenCardsEnabled), [selected, jokerMode, randomJoker, sevenCardsEnabled]);
  const stagedValidity = useMemo(() => staged.map(g => validateMeld(g, jokerMode, randomJoker, sevenCardsEnabled)), [staged, jokerMode, randomJoker, sevenCardsEnabled]);
  const isSeven = useMemo(() => isSevenCombo(selected, jokerMode, randomJoker, sevenCardsEnabled), [selected, jokerMode, randomJoker, sevenCardsEnabled]);

  // Compute which melds can accept the selected cards (for layoff highlighting)
  const layoffCandidates = useMemo(() => {
    if (!isMyTurn || phase !== "play" || selected.length === 0) return new Set<number>();
    return getLayoffCandidates(melds, selected, jokerMode, randomJoker, sevenCardsEnabled);
  }, [melds, selected, isMyTurn, phase, jokerMode, randomJoker]);

  const [remaining, setRemaining] = useState(cfg.turn_timer_seconds);
  useEffect(() => {
    if (!game?.turn_deadline || game.status !== "playing") { setRemaining(cfg.turn_timer_seconds); return; }
    let fired = false;
    let lastSec = -1;
    let tickAtZero = 0;
    let inFlight = false;

    const fireTick = async () => {
      if (inFlight) return;
      inFlight = true;
      try {
        await supabase.rpc("rami_tick" as any, { _game_id: id } as any);
      } finally {
        inFlight = false;
      }
    };

    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      const s = Math.max(0, Math.ceil(ms / 1000));
      if (s !== lastSec) {
        lastSec = s;
        setRemaining(s);
      }
      if (s === 0 && !fired) {
        fired = true;
        tickAtZero = 0;
        fireTick();
      }
      // Keep retrying every 3s indefinitely while stuck at 0 — a server-side
      // cron job (rami_bot_tick_all, every 5s) also acts as a safety net,
      // but we never want the client to permanently give up here.
      if (s === 0 && fired) {
        tickAtZero++;
        if (tickAtZero % 3 === 0) {
          fireTick();
        }
      }
    };
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, id, cfg.turn_timer_seconds]);

  const isUrgent = remaining <= 10 && isMyTurn;

  // ── AFK warning state ──
  const [afkWarning, setAfkWarning] = useState(false);
  useEffect(() => {
    if (!isMyTurn || remaining > 10) { setAfkWarning(false); return; }
    if (remaining <= 10 && remaining > 0) {
      if (remaining === 10 || remaining === 5) sfx.ramiWarning();
      setAfkWarning(true);
    }
  }, [remaining, isMyTurn]);
  // Note: remaining changes every second, but setAfkWarning(true) is idempotent

  const toggleSel = useCallback((c: number) => {
    haptic(8);
    setSelected(s => s.includes(c) ? s.filter(x => x !== c) : [...s, c]);
  }, []);

  // Pose directe de la sélection scannée (trio / carré / escalier / 7 cartes)
  const postSelection = async () => {
    const kind = meldKind(selected, jokerMode, randomJoker, sevenCardsEnabled);
    if (!kind) return toast.error("Sélection invalide");
    const cards = [...selected];
    sfx.ramiMeld();
    setSelected([]);
    if (kind === 'seven') {
      toast.success("✓ 7 cartes posées — clique « Valider 7 » pour réclamer");
    } else {
      toast.success(`✓ ${MELD_LABEL[kind]} validé`);
    }
    haptic(30);
    try {
      const { error } = await supabase.rpc("rami_meld" as any, { _game_id: id, _cards: cards });
      if (error) throw error;
    } catch (e: any) {
      toast.error(e.message || "Combinaison invalide");
    } finally { setBusy(false); }
  };

  // ── 7 cartes : le joueur clique lui-même ses combinaisons posées ───────
  const [pickedMelds, setPickedMelds] = useState<number[]>([]);
  const [showActionLog, setShowActionLog] = useState(false);
  const usedExtraTime = !!(profile?.id && (game?.state?.extra_time || {})[profile.id]);

  const toggleMeldPick = (i: number) =>
    setPickedMelds(p => p.includes(i) ? p.filter(x => x !== i) : [...p, i]);

  // seven_claimed_by: si un joueur (n'importe qui) a déjà réclamé le 7 cartes dans cette partie
  const sevenClaimedBy = (game as any)?.state?.seven_claimed_by as string | undefined;

  const alreadySeven = useMemo(
    () => melds.some(m => m.player === profile?.id && (m as { seven?: boolean }).seven === true)
      || !!(profile?.id && (game as any)?.state?.refunded?.[profile?.id]),
    [melds, profile?.id, game],
  );

  // Auto-detect 7 cards: check single 'seven' meld OR pairs of melds for a valid 7-card combo
  // MAIS: si un joueur a déjà réclamé le 7 cartes dans cette partie, le bouton ne s'affiche plus jamais
  const canClaimSeven = useMemo(() => {
    if (!profile?.id || alreadySeven) return false;
    // Un seul joueur par partie peut réclamer le 7 cartes
    if (sevenClaimedBy) return false;
    const mine = melds.map((m, i) => ({ m, i })).filter(x => x.m.player === profile?.id);
    if (mine.length < 1) return false;
    // Single 7-card meld (type 'seven')
    for (const { m } of mine) {
      if (m.cards.length === 7 && isSevenCombo(m.cards, jokerMode, randomJoker, sevenCardsEnabled)) return true;
    }
    // Two melds combining to 7 cards
    if (mine.length >= 2) {
      for (let a = 0; a < mine.length; a++) {
        for (let b = a + 1; b < mine.length; b++) {
          const combo = [...mine[a].m.cards, ...mine[b].m.cards];
          if (combo.length === 7 && isSevenCombo(combo, jokerMode, randomJoker, sevenCardsEnabled)) return true;
        }
      }
    }
    return false;
  }, [melds, profile?.id, alreadySeven, sevenClaimedBy, jokerMode, randomJoker, sevenCardsEnabled]);

  const claimSeven = async () => {
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("rami_claim_seven" as any, { _game_id: id } as any);
      if (error) throw error;
      setPickedMelds([]);
      const numPlayers = parts.filter(p => !p.forfeited).length || game?.max_players || 0;
      if (numPlayers <= 2) {
        toast.success("⭐7 validé ! 50% de mise remboursée (partie à 2)");
      } else {
        toast.success(`⭐7 validé ! Mise remboursée (${numPlayers} joueurs)`);
      }
    } catch (e: any) {
      toast.error(e.message || "Action impossible");
    } finally { setBusy(false); }
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

  // Tap a card in a staged combo to pick it up, then tap another card in the
  // same combo to swap their positions — a simpler alternative to long-press
  // drag for reorganizing a combo you already built.
  const handleStagedTap = (gi: number, idx: number) => {
    if (stagedMoving === null) {
      setStagedMoving({ gi, idx });
    } else if (stagedMoving.gi === gi && stagedMoving.idx === idx) {
      setStagedMoving(null);
    } else if (stagedMoving.gi === gi) {
      setStaged(prev => {
        const next = prev.map(g => [...g]);
        const arr = next[gi];
        [arr[stagedMoving.idx], arr[idx]] = [arr[idx], arr[stagedMoving.idx]];
        return next;
      });
      setStagedMoving(null);
    } else {
      setStagedMoving({ gi, idx });
    }
  };

  const call = async (fn: string, payload: any) => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc(fn as any, payload);
      if (error) throw error;
      setSelected([]);
      // Realtime can lag or drop an event on some connections, so we still
      // force a fresh fetch — but in the background. Awaiting it here made
      // the button stay disabled for a whole extra network round-trip after
      // the action already succeeded, which felt like a multi-second freeze.
      void load();
    } catch (e: any) { toast.error(e.message || "Action invalide"); }
    finally { setBusy(false); }
  };

  const drawDeck = async () => {
    sfx.ramiDraw();
    haptic(10);
    try {
      const { error } = await supabase.rpc("rami_draw" as any, { _game_id: id, _from: "deck" } as any);
      if (error) throw error;
    } catch (e: any) {
      toast.error(e.message || "Erreur tirage");
    }
  };
  const drawDiscard = async () => {
    if (flatDiscard.length === 0) {
      toast.error("La défausse est vide");
      return;
    }
    sfx.ramiDraw();
    haptic(10);
    try {
      const { error } = await supabase.rpc("rami_draw" as any, { _game_id: id, _from: "discard" } as any);
      if (error) throw error;
    } catch (e: any) {
      toast.error(e.message || "Erreur tirage");
    }
  };

  const submitStagedMeld = async (groupIdx: number) => {
    const cards = staged[groupIdx];
    if (!cards || cards.length < 3) return toast.error("Il faut au moins 3 cartes");
    sfx.ramiMeld();
    setStaged(prev => prev.filter((_, i) => i !== groupIdx));
    toast.success("Combinaison posée !");
    try {
      const { error } = await supabase.rpc("rami_meld" as any, { _game_id: id, _cards: cards });
      if (error) throw error;
    } catch (e: any) {
      toast.error(e.message || "Combinaison invalide");
    } finally { setBusy(false); }
  };

  const submitAllStaged = async () => {
    if (staged.length === 0) return;
    setBusy(true);
    try {
      let anyError = false;
      for (const cards of staged) {
        const { error } = await supabase.rpc("rami_meld" as any, { _game_id: id, _cards: cards });
        if (error) { toast.error(error.message || "Combinaison invalide"); anyError = true; break; }
      }
      if (!anyError) { setStaged([]); toast.success("Toutes les combinaisons posées !"); }
    } catch (e: any) {
      toast.error(e.message || "Erreur réseau, réessaie");
    } finally {
      setBusy(false);
    }
  };

  const discardOne = async () => {
    if (selected.length !== 1) return toast.error("Sélectionne exactement 1 carte à défausser");
    const card = selected[0];
    const myKey = profile?.id || "";
    sfx.ramiDiscard();
    haptic(15);
    setSelected([]);
    try {
      const { error } = await supabase.rpc("rami_discard" as any, { _game_id: id, _card: card } as any);
      if (error) throw error;
    } catch (e: any) {
      toast.error(e.message || "Erreur défausse");
    }
  };

  // Valider toute la main d'un coup : staged = groupes, selected[0] = carte à défausser
  const validateHand = async () => {
    if (staged.length === 0) return toast.error("Prépare tes combinaisons avant de valider");
    if (selected.length !== 1) return toast.error("Sélectionne 1 carte à défausser");
    const layout = staged.map(g => [...g]);
    const discardCard = selected[0];
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("rami_validate_hand" as any, {
        _game_id: id,
        _layout: layout as any,
        _discard_card: discardCard,
      });
      if (error) { toast.error(error.message || "Combinaisons invalides"); return; }
      // Check if the player actually won (won=false means melds were saved but hand not empty)
      const won = (data as any)?.won === true;
      if (won) {
        toast.success("🏆 Bravo, tu gagnes la partie !");
        sfx.ramiWin();
        haptic([0, 40, 30, 40, 30, 60]);
      } else {
        toast.info("✅ Combinaisons posées — continue à jouer");
        haptic(20);
      }
      setStaged([]); setSelected([]);
      // Refresh in the background — don't make the player wait an extra
      // round-trip for this, the action already succeeded.
      void load();
    } catch (e: any) {
      toast.error(e.message || "Erreur réseau, réessaie");
    } finally {
      setBusy(false);
    }
  };


  // ── Auto-arranger: just re-sort the hand so detected combos sit next to
  // each other (side by side) — it does NOT stage/pose anything anymore.
  const autoArrange = () => {
    if (!isMyTurn || phase !== "play") return;
    const combos = detectCombos(handCards, jokerMode, randomJoker);
    const usedCards = new Set<number>();
    const groups: number[][] = [];
    for (const combo of combos) {
      // Skip if any card already used in a previous group
      if (combo.cards.some(c => usedCards.has(c))) continue;
      const valid = validateMeld(combo.cards, jokerMode, randomJoker, sevenCardsEnabled);
      if (valid === 'valid') {
        groups.push([...combo.cards]);
        combo.cards.forEach(c => usedCards.add(c));
      }
    }
    if (groups.length === 0) {
      toast.info("Aucune combinaison détectée dans ta main");
      haptic(20);
      return;
    }
    const leftover = handCards.filter(c => !usedCards.has(c));
    setSortMode('none');
    setCustomOrder([...groups.flat(), ...leftover]);
    setSelected([]);
    haptic([0, 20, 10, 20]);
    toast.success(`✨ Main réorganisée · ${groups.length} combinaison${groups.length > 1 ? "s" : ""} groupée${groups.length > 1 ? "s" : ""}`);
  };

  // Optimal play suggester
  const triggerOptimalSuggest = () => {
    const result = suggestOptimalPlay(handCards, jokerMode, randomJoker, sevenCardsEnabled);
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

  const hasPosedMeld = useMemo(
    () => !!profile?.id && melds.some(m => m.player === profile.id),
    [melds, profile?.id],
  );

  const layoff = (meldIdx: number) => {
    if (selected.length < 1) return toast.error("Sélectionne au moins 1 carte");
    if (gameMode === "naturel" && !hasPosedMeld)
      return toast.info("Mode Naturel : pose d'abord ta propre combinaison (brelan ou suite de 3+)");
    call("rami_layoff", { _game_id: id, _meld_index: meldIdx, _cards: selected });
  };

  // Casser une de ses propres combinaisons : les cartes reviennent en main
  const unmeld = async (meldIdx: number) => {
    if (!isMyTurn) return toast.info("Tu ne peux modifier tes combinaisons que pendant ton tour");
    setBusy(true);
    try {
      const { error } = await supabase.rpc("rami_unmeld" as any, { _game_id: id, _meld_index: meldIdx });
      if (error) throw error;
      setSelected([]);
      toast.success("Combinaison reprise en main");
    } catch (e: any) {
      toast.error(e.message || "Impossible de casser cette combinaison");
    } finally { setBusy(false); }
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

  const dnd = useLongPressDrag({ delay: 250, onDrop: handleDrop });

  if (!game) return <GameLoader />;


  const replayRami = async () => {
    const hadBots = parts.some((p: any) => p.is_bot);
    if (hadBots) {
      const { data, error } = await supabase.rpc("rami_start_solo_bot" as any, {
        _max_players: game.max_players,
        _difficulty: "medium",
        _joker_mode: game.joker_mode || "classique",
        _game_mode: game.game_mode || "bordel",
      } as any);
      if (error) { toast.error(error.message); return; }
      refreshProfile();
      navigate({ to: "/jeux/rami/$id", params: { id: data as string } });
    } else {
      const { data, error } = await supabase.rpc("rami_create" as any, {
        _stake: Number(game.stake) || 0,
        _max: game.max_players,
        _private: !!game.is_private,
        _commission: Number(game.commission_pct) || 10,
        _game_mode: game.game_mode || "bordel",
        _joker_mode: game.joker_mode || "classique",
        _seven_cards: game.seven_cards !== false,
      } as any);
      if (error) { toast.error(error.message); return; }
      refreshProfile();
      navigate({ to: "/jeux/rami/$id", params: { id: data as string } });
    }
  };

  if (game.status === "cancelled") {
    return <GameStateMessage state="cancelled" gameLabel="Rami" slug="rami" />;
  }

  if (game.status === "open" || game.status === "waiting") {
    if (Number(game.stake) > 0 && profile?.phone_verified !== true) {
      return (
        <main className="max-w-md mx-auto px-4 py-8 flex flex-col items-center justify-center gap-3 text-center">
          <ShieldAlert className="w-10 h-10 text-amber-500" />
          <p className="text-sm font-semibold">Numéro non vérifié</p>
          <p className="text-xs text-muted-foreground">Vérifiez votre numéro de téléphone pour rejoindre cette partie payante.</p>
          <button onClick={() => navigate({ to: "/securite" })} className="px-4 py-2 rounded-full bg-primary text-primary-foreground text-xs font-semibold">Vérifier mon numéro</button>
        </main>
      );
    }
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
          gameStatus={game.status}
          gameId={id}
          hostId={game.created_by}
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
        <GameSocialFab gameId={id} gameSlug="rami" participants={parts} />
      </main>
    );
  }

  // ── FINISHED: early return to avoid computing game board variables that can crash ──
  if (game.status === "finished") {
    // Find winner: use winner_id first, fall back to winner_name match, then non-forfeited
    const _winnerSlot = game.winner_id
      ? parts.find(p => p.user_id === game.winner_id)?.slot
      : (game as any).winner_name
        ? parts.find(p => p.display_name === (game as any).winner_name || !p.forfeited)?.slot ?? null
        : parts.find(p => !p.forfeited)?.slot ?? null;
    // Pass winner_name to GameEndScreen as extra for bot wins
    const _botWinnerName = !game.winner_id ? (game as any).winner_name : null;
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4 min-h-screen flex flex-col items-center justify-center">
        <GameEndScreen
          slug="rami"
          meUserId={profile?.id}
          winnerId={game.winner_id}
          winnerSlot={_winnerSlot}
          participants={parts}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          commissionPct={Number(game.commission_pct) || 10}
          onReplay={replayRami}
          botWinnerName={_botWinnerName}
        />

        <GameSocialFab gameId={id} gameSlug="rami" participants={parts} />
      </main>
    );
  }

  // ═══ SYSTÈME SIMPLIFIÉ: canDrawDiscard = phase 'draw' + défausse non vide ═══
  const canDrawDiscard = isMyTurn && !busy && topDiscard !== undefined && phase === "draw";
  const firstPlayerNoDiscard = false;


  // Affichage simple: une seule défausse (flat array)
  const discardEntries: { key: string; label: string; color: string; pile: number[]; isMe: boolean }[] = [
    { key: "pile", label: "Défausse", color: "#94a3b8", pile: flatDiscard, isMe: false },
  ];

  return (
    <main
      className="max-w-3xl mx-auto px-2.5 py-1.5 flex flex-col gap-1.5 h-full overflow-hidden overscroll-none rounded-xl"
      style={{
        background: `linear-gradient(rgba(0,0,0,0.25), rgba(0,0,0,0.35)), radial-gradient(ellipse at center, ${activeTheme.feltCenter || "#1a6b3a"} 0%, ${activeTheme.feltEdge || "#0b3a1f"} 70%, ${activeTheme.border} 100%)`,
        backgroundSize: "cover",
        backgroundPosition: "center",
        boxShadow: "inset 0 0 60px rgba(0,0,0,0.45), 0 0 0 6px #0f3d20, 0 8px 24px rgba(0,0,0,0.4)",
      }}
    >
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      <PhoneVerifyBanner stake={Number(game?.stake) || 0} phoneVerified={profile?.phone_verified === true} />
      {/* ── Top bar: pot + deck info + controls, all in one line ── */}
      <div className="rounded-xl bg-card/95 px-2.5 py-1 border border-border shadow-sm flex items-center justify-between gap-2">
        <div className="flex items-center gap-2.5 min-w-0">
          <span className="text-[10px] font-bold text-amber-500 whitespace-nowrap">
            🏆 {Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar
          </span>
          {gameNumber && <span className="text-[10px] font-mono font-bold text-primary/80">{gameNumber}</span>}
        </div>
        {!me ? (
          <div className="px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1">
            Spectateur
          </div>
        ) : (
          <div className="flex items-center gap-1 shrink-0">
            {/* Pause button removed for free games */}
            <button onClick={() => { const m = !soundOn; setSoundOn(m); setSfxMuted(m); }} className="w-6 h-6 rounded-full bg-secondary/80 text-secondary-foreground flex items-center justify-center active:scale-90 transition">
              {soundOn ? <Volume2 className="w-3 h-3" /> : <VolumeX className="w-3 h-3" />}
            </button>
            <button onClick={forfeit} className="px-1.5 py-0.5 rounded-full bg-destructive/90 text-white text-[9px] font-bold flex items-center gap-0.5 active:scale-90 transition">
              <LogOut className="w-2.5 h-2.5" /> Quitter
            </button>
          </div>
        )}
      </div>


      {/* ── PLATEAU FEUTRE (style classique) ── */}
      {game?.status === "playing" && (() => {
        const sorted = parts.slice().sort((a, b) => a.slot - b.slot);
        const meIdx = sorted.findIndex(p => p.user_id === profile?.id);
        const others = meIdx >= 0
          ? [...sorted.slice(meIdx + 1), ...sorted.slice(0, meIdx)]
          : sorted;

        const keyOf = (p: typeof sorted[number]) => (p.user_id as string) || `bot:${p.slot}`;
        const handLenOf = (uid: string) =>
          Array.isArray(game?.state?.hands?.[uid]) ? game.state.hands[uid].length : 0;

        // ── Opponent avatar card: compact with timer ring ──
        const OppBadge = React.memo(function OppBadge({ p, turn, n, meldCount, hasSeven, isLast, avatarUrl, lives }: {
          p: typeof sorted[number]; turn: boolean; n: number; meldCount: number; hasSeven: boolean; isLast: boolean; avatarUrl?: string | null; lives: number
        }) {
          const name = (p.display_name || "Joueur").slice(0, 10);
          const initial = name.charAt(0).toUpperCase();
          const gradients = [
            "linear-gradient(145deg,#60a5fa,#2563eb)",
            "linear-gradient(145deg,#f87171,#dc2626)",
            "linear-gradient(145deg,#4ade80,#16a34a)",
            "linear-gradient(145deg,#fbbf24,#d97706)",
            "linear-gradient(145deg,#c084fc,#9333ea)",
            "linear-gradient(145deg,#f472b6,#db2777)",
          ];
          const bg = gradients[name.charCodeAt(0) % gradients.length];
          const fanCount = Math.min(n, 5);
          const totalSeconds = cfg.turn_timer_seconds || 30;
          const ringPct = turn ? (remaining / totalSeconds) * 100 : 0;
          const ringColor = remaining <= 5 ? "#ef4444" : remaining <= 10 ? "#f59e0b" : "#22c55e";
          return (
            <div className={`flex flex-col items-center gap-0.5 px-1 py-0.5 rounded-xl shrink-0 transition-all ${
              turn ? "bg-amber-500/10" : ""
            }`}>
              <div className="flex items-center gap-1.5">
                {/* Avatar with timer ring */}
                <div className="relative" style={{ width: 32, height: 32 }}>
                  {turn && (
                    <svg className="absolute inset-0 -rotate-90" width="32" height="32" viewBox="0 0 32 32">
                      <circle cx="16" cy="16" r="14" fill="none" stroke="rgba(0,0,0,0.3)" strokeWidth="2.5" />
                      <circle cx="16" cy="16" r="14" fill="none" stroke={ringColor} strokeWidth="2.5"
                        strokeDasharray={`${2 * Math.PI * 14 * ringPct / 100} ${2 * Math.PI * 14}`}
                        strokeLinecap="round"
                        style={{ transition: "stroke-dasharray 1s linear" }}
                      />
                    </svg>
                  )}
                  <div
                    className={`rounded-full flex items-center justify-center font-bold text-white shrink-0 absolute inset-0 m-0.5 overflow-hidden ${
                      turn ? "ring-1 ring-amber-400/50" : ""
                    }`}
                    style={{ fontSize: 11, background: bg }}
                  >
                    {p.is_bot
                      ? "◆"
                      : avatarUrl
                        ? <img src={avatarUrl} alt="" width={28} height={28} loading="lazy" decoding="async" className="w-full h-full object-cover" />
                        : initial}
                  </div>
                </div>
                <div className="flex flex-col leading-tight">
                  <span className="text-[10px] font-bold text-white/95">{name}</span>
                  <div className="flex items-center gap-1">
                    <span className="text-[9px] text-white/55 font-semibold">{n} cartes</span>
                    {meldCount > 0 && <span className="text-[8px] text-amber-300/90 font-bold">✦{meldCount}</span>}
                    {hasSeven && <span className="text-[8px] text-amber-400 font-bold animate-pulse">⭐7</span>}
                  </div>
                  <div className="flex items-center gap-0.5 mt-0.5">
                    {Array.from({ length: MAX_LIVES }).map((_, i) => (
                      <span key={i} className={`text-[7px] ${i < lives ? "opacity-100" : "opacity-25"}`}>❤️</span>
                    ))}
                  </div>
                </div>
              </div>
              {/* Mini fanned card-back hand */}
              <div className="relative h-[18px] flex items-end justify-center mt-0.5" style={{ width: 32 + fanCount * 3 }}>
                {Array.from({ length: fanCount }).map((_, i) => {
                  const mid = (fanCount - 1) / 2;
                  const rot = (i - mid) * 10;
                  return (
                    <div key={i} className="absolute bottom-0 rounded-[2px] border border-white/20"
                      style={{
                        width: 12, height: 17,
                        left: `calc(50% + ${(i - mid) * 6}px - 6px)`,
                        transform: `rotate(${rot}deg)`,
                        background: "linear-gradient(135deg,#1e3a8a,#1e40af)",
                        zIndex: i,
                      }}
                    />
                  );
                })}
              </div>
            </div>
          );
        });

        const meldCountOf = (uid: string) => melds.filter(m => m.player === uid).length;
        const hasSevenOf = (uid: string) => {
          // Only show ⭐7 badge on the player who actually claimed the 7 cartes
          const claimedBy = (game as any)?.state?.seven_claimed_by as string | undefined;
          if (!claimedBy) return false;
          return uid === claimedBy || `bot:${uid}` === claimedBy;
        };
        const isSeven = (m: { type?: string; seven?: boolean }) =>
          m.type === "seven" || m.seven === true;
        const myMelds = melds
          .map((m, i) => ({ m, i }))
          .filter(x => !!profile?.id && x.m.player === profile.id);
        const publicSevenMelds = melds
          .map((m, i) => ({ m, i }))
          .filter(x => (!profile?.id || x.m.player !== profile.id) && isSeven(x.m as any))
          .map(x => ({ ...x, name: ((p: typeof sorted[number]) => (p?.display_name || "Joueur").slice(0, 10))(sorted.find(s => ((s.user_id as string) || `bot:${s.slot}`) === x.m.player)) }));

        const MeldRow = ({ m, i, mine }: { m: { player: string; cards: number[]; type?: string }; i: number; mine: boolean }) => {
          const kind = (m.type as Exclude<MeldKind, null>) || meldKind(m.cards, jokerMode, randomJoker, sevenCardsEnabled);
          const isSevenMeld = kind === "seven" || (m as { seven?: boolean }).seven === true;
          const revealed = mine || isSevenMeld;
          const canLayoff = layoffCandidates.has(i);
          const canBreak = mine && !!isMyTurn && (phase === "play" || phase === "draw") && !busy;
          const picked = false; // auto-detect: no manual picking
          const pure = !isSevenMeld && isPureMeld(m.cards, jokerMode, randomJoker);
          return (
            <div key={`meld-wrap-${i}`} className="relative flex flex-col items-center gap-0.5">
              <div
                key={`meld-${i}`}
                className={`relative flex rounded-lg p-1 transition-all shrink-0 bg-black/10 ${
                  picked
                    ? "ring-2 ring-fuchsia-400 bg-fuchsia-500/10"
                    : isSevenMeld
                      ? "ring-2 ring-amber-400 shadow-[0_0_14px_-4px_rgba(251,191,36,0.9)]"
                      : canLayoff
                        ? "ring-2 ring-emerald-400"
                        : canBreak
                          ? "ring-2 ring-orange-400 cursor-pointer hover:scale-105"
                          : pure
                            ? "ring-1 ring-cyan-400/50"
                            : "ring-1 ring-white/10"
                }`}
                style={{ boxShadow: "0 2px 5px rgba(0,0,0,0.3)" }}
              >
                {m.cards.map((c, ci) => {
                  const actionable = canLayoff || canBreak;
                  const onCardClick = actionable
                    ? () => { if (canLayoff) layoff(i); else if (canBreak) unmeld(i); }
                    : undefined;
                  return (
                    <div key={`m-${i}-${ci}`} style={{ marginLeft: ci > 0 ? 2 : 0, filter: "drop-shadow(1px 0 1.5px rgba(0,0,0,0.4))" }}>
                      <Card c={revealed ? c : undefined} faceDown={!revealed} styleOverride={{ width: 25, height: 35 }} onClick={onCardClick} />
                    </div>
                  );
                })}
              </div>
              {isSevenMeld && (
                <span className="text-[7px] font-bold px-1 py-0.5 rounded-full bg-amber-500/20 text-amber-300 whitespace-nowrap">
                  7 Cartes
                </span>
              )}
            </div>
          );
        };

        // ═══ ZONE 1: Opponents strip (above the felt, clean horizontal) ═══
        const oppStrip = (
          <div className="flex items-center justify-center gap-2.5 px-3 py-1.5 rounded-t-xl"
            style={{ background: `linear-gradient(180deg, ${activeTheme.feltEdge || "#0b3a1f"}ee, transparent)` }}>
            {others.map((p, i) => (
              <OppBadge key={keyOf(p)} p={p} turn={game.current_turn === p.slot}
                n={handLenOf(keyOf(p))} meldCount={meldCountOf(p.user_id || "")}
                hasSeven={hasSevenOf(p.user_id || "")}
                isLast={i === others.length - 1}
                avatarUrl={p.user_id ? avatarsMap[p.user_id] : null}
                lives={livesOf(keyOf(p))} />
            ))}
          </div>
        );

        // ═══ ZONE 2: Clean center felt (pioche + défausse + joker only) ═══
        const centerFelt = (
          <div className="relative flex-1 flex items-center justify-center gap-5 px-3 py-2 min-h-0 overflow-hidden"
            style={{
              background: `radial-gradient(ellipse at center, ${activeTheme.feltCenter || "#1a6b3a"} 0%, ${activeTheme.feltEdge || "#0b3a1f"} 80%)`,
              boxShadow: "inset 0 0 50px rgba(0,0,0,0.45), inset 0 0 2px rgba(255,255,255,0.06)",
            }}>


            {/* Pioche + Joker aléatoire à gauche de la pioche */}
            <div className="flex flex-col items-center gap-0.5">
              <div className="relative isolate" style={{ width: 60, height: 84, overflow: 'visible' }}>
                {/* Joker aléatoire : juste un petit coin visible à gauche, le reste bien caché sous la pioche */}
                {randomJoker !== null && (
                  <div
                    className="absolute pointer-events-none"
                    style={{
                      top: '50%',
                      left: '0px',
                      transform: 'translate(-50%, -50%) rotate(-90deg)',
                      transformOrigin: 'center center',
                      zIndex: 0,
                      filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.5))",
                    }}
                  >
                    <Card c={randomJoker} styleOverride={{ width: 44, height: 62 }} />
                  </div>
                )}
                <button
                  ref={deckRef}
                  disabled={!isMyTurn || phase !== "draw" || busy || deckCount === 0}
                  onClick={drawDeck}
                  className={`relative rounded-[6px] active:scale-95 transition-transform ${
                    isMyTurn && phase === "draw" && deckCount > 0 ? "ring-2 ring-yellow-300 shadow-lg turn-active-pulse" : ""
                  }`}
                  style={{
                    filter: isMyTurn && phase === "draw" && deckCount > 0
                      ? "drop-shadow(0 4px 8px rgba(250,204,21,0.5)) saturate(1.3)"
                      : "drop-shadow(0 4px 6px rgba(0,0,0,0.45)) saturate(1.3)",
                    zIndex: 10,
                  }}
                >
                  <Card faceDown styleOverride={{ width: 60, height: 84 }} />
                  {deckCount > 0 && deckCount <= 10 && (
                    <div className="absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full bg-amber-500 flex items-center justify-center text-[8px] font-bold text-white animate-pulse">
                      !
                    </div>
                  )}
                </button>
              </div>
              <span className={`text-[10px] font-semibold px-2.5 py-1 rounded-full ${
                isMyTurn && phase === "draw" && deckCount > 0
                  ? "bg-yellow-500 text-black animate-pulse font-bold"
                  : deckCount === 0 ? "bg-red-900/80 text-red-300" : deckCount <= 10 ? "bg-amber-900/80 text-amber-300" : "bg-black/60 text-white/90"
              }`}>
                {`Pioche · ${deckCount}`}
              </span>
            </div>

            {/* Défausse */}
            <div className="flex flex-col items-center gap-0.5">
              <div className="flex items-end gap-1">
                <div
                  ref={(el) => { discardRefs.current["pile"] = el; }}
                  className={`relative rounded-[6px] transition-transform ${
                    canDrawDiscard ? "ring-2 ring-emerald-300 shadow-lg turn-active-pulse" : "opacity-50"
                  }`}
                >
                  {topDiscard !== undefined
                    ? <Card c={topDiscard} styleOverride={{ width: 58, height: 82 }} onClick={canDrawDiscard ? drawDiscard : undefined} />
                    : <div className="border border-dashed border-white/40" style={{ width: 58, height: 82, borderRadius: '5px' }} />}
                </div>
              </div>
              <div className="flex items-center gap-1">
                <span className={`text-[10px] font-semibold px-2.5 py-1 rounded-full ${
                  canDrawDiscard
                    ? "bg-emerald-500 text-black animate-pulse font-bold"
                    : "text-white/90 bg-black/60"
                }`}>Défausse</span>
                {flatDiscard.length > 1 && (
                  <button
                    onClick={() => setShowDiscardHistory(true)}
                    className="text-[9px] font-semibold px-1.5 py-1 rounded-full bg-black/50 text-white/70 hover:bg-black/70 hover:text-white active:scale-95 transition"
                    title="Voir l'historique des défausses"
                  >
                    👁 <span className="hidden sm:inline">Historique</span>
                  </button>
                )}
              </div>
            </div>
          </div>
        );


        // ═══ ZONE 3: Melds strip — mes melds + 7 cartes des autres (10s) ═══
        const allMelds = melds
          .map((m, i) => ({ m, i, mine: !!profile?.id && m.player === profile.id }))
          .filter(({ m, i, mine }) => {
            if (mine) return true; // toujours mes melds
            // 7 cartes des autres: seulement si visible (10s)
            const isSeven = m.type === "seven" || (m as any).seven === true;
            if (!isSeven) return false; // cacher les melds normaux des autres
            const meldKey = `${m.player}-${i}`;
            return visibleSevenMelds.has(meldKey);
          });
        const myMeldsStrip = allMelds.length > 0 ? (
          <div className="flex flex-wrap items-center justify-center gap-1.5 px-2 py-1.5 min-h-[44px] max-h-[110px] overflow-y-auto"
            style={{ background: `linear-gradient(0deg, ${activeTheme.feltEdge || "#0b3a1f"}ee, transparent)` }}>
            {allMelds.map(({ m, i, mine }) => {
              // For 7-card melds from others, show player name
              const isSevenMeld = m.type === "seven" || (m as any).seven === true;
              const showName = !mine && isSevenMeld;
              const playerName = showName
                ? (sorted.find(s => ((s.user_id as string) || `bot:${s.slot}`) === m.player)?.display_name || "Joueur").slice(0, 10)
                : null;
              return (
                <div key={i} className="flex flex-col items-center gap-0.5">
                  {showName && playerName && (
                    <span className="text-[8px] font-bold text-amber-300 animate-pulse">⭐ {playerName}</span>
                  )}
                  <MeldRow m={m} i={i} mine={mine} />
                </div>
              );
            })}
          </div>
        ) : null;

        // ═══ Combine zones into one clean board ═══
        return (
          <div className="rounded-2xl flex-[1.4_1_0%] min-h-[32vh] flex flex-col p-[5px]"
            style={{
              background: "repeating-linear-gradient(100deg, #7a4a26 0px, #8a5a34 3px, #6e4322 6px, #85532f 9px)",
              boxShadow: "0 6px 20px rgba(0,0,0,0.4), inset 0 0 0 1px rgba(0,0,0,0.3)",
            }}>
            <div className="rounded-xl overflow-hidden border flex-1 flex flex-col min-h-0"
              style={{ borderColor: activeTheme.border, boxShadow: "inset 0 2px 6px rgba(0,0,0,0.5)" }}>
              {oppStrip}
              {centerFelt}
              {myMeldsStrip}
            </div>
          </div>
        );
      })()}

      {/* Historique de la défausse — overlay plein écran */}
      {showDiscardHistory && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
          style={{ background: "rgba(0,0,0,0.7)" }}
          onClick={() => setShowDiscardHistory(false)}
        >
          <div
            className="bg-zinc-900 rounded-2xl border border-white/10 max-w-md w-full max-h-[80vh] flex flex-col"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-white/10">
              <h3 className="text-sm font-bold text-white flex items-center gap-2">
                <Eye className="w-4 h-4" /> Historique de la défausse
              </h3>
              <button
                onClick={() => setShowDiscardHistory(false)}
                className="w-7 h-7 rounded-full bg-white/10 hover:bg-white/20 flex items-center justify-center text-white/70 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
            <div className="px-4 py-2 text-[10px] text-white/50 bg-white/5">
              Cartes de la plus ancienne à la plus récente · Seule la dernière est récupérable
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              {flatDiscard.length === 0 ? (
                <p className="text-center text-white/40 text-xs py-8">Aucune carte défaussée</p>
              ) : (
                <div className="flex flex-wrap gap-2 justify-center">
                  {flatDiscard.map((card: number, idx: number) => {
                    const isTop = idx === flatDiscard.length - 1;
                    return (
                      <div key={idx} className="flex flex-col items-center gap-1">
                        <div className={isTop ? "ring-2 ring-emerald-400 rounded-md" : "opacity-60"}>
                          <Card c={card} styleOverride={{ width: 44, height: 62 }} />
                        </div>
                        <span className={`text-[8px] ${isTop ? "text-emerald-400 font-bold" : "text-white/40"}`}>
                          {isTop ? "↑ Récupérable" : `#${idx + 1}`}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
            <div className="p-3 border-t border-white/10">
              <button
                onClick={() => setShowDiscardHistory(false)}
                className="w-full py-2 rounded-xl bg-white/10 hover:bg-white/20 text-white/80 text-xs font-semibold"
              >
                Fermer
              </button>
            </div>
          </div>
        </div>
      )}


      


      {/* ── MY HAND ── */}
      {me && (
        <div className="space-y-1 shrink-0">
      {isMyTurn && game?.status === "playing" && (() => {
        const totalSeconds = cfg.turn_timer_seconds || 30;
        const ringPct = (remaining / totalSeconds) * 100;
        const ringColor = remaining <= 5 ? "#ef4444" : remaining <= 10 ? "#f59e0b" : "#22c55e";
        const myName = (profile?.pseudo || "Moi").slice(0, 10);
        const initial = myName.charAt(0).toUpperCase();
        const gradients = [
          "linear-gradient(145deg,#60a5fa,#2563eb)",
          "linear-gradient(145deg,#f87171,#dc2626)",
          "linear-gradient(145deg,#4ade80,#16a34a)",
        ];
        const bg = gradients[myName.charCodeAt(0) % gradients.length];
        return (
          <div className="flex items-center gap-1.5 px-1 mb-0.5">
            <div className="relative" style={{ width: 28, height: 28 }}>
              <svg className="absolute inset-0 -rotate-90" width="28" height="28" viewBox="0 0 28 28">
                <circle cx="14" cy="14" r="12" fill="none" stroke="rgba(0,0,0,0.3)" strokeWidth="2.5" />
                <circle cx="14" cy="14" r="12" fill="none" stroke={ringColor} strokeWidth="2.5"
                  strokeDasharray={`${2 * Math.PI * 12 * ringPct / 100} ${2 * Math.PI * 12}`}
                  strokeLinecap="round"
                  style={{ transition: "stroke-dasharray 1s linear" }}
                />
              </svg>
              <div className="rounded-full flex items-center justify-center font-bold text-white absolute inset-0 m-0.5 overflow-hidden"
                style={{ fontSize: 10, background: bg }}>
                {profile?.avatar_url
                  ? <img src={profile.avatar_url} alt="" width={24} height={24} loading="lazy" decoding="async" className="w-full h-full object-cover" />
                  : initial}
              </div>
            </div>
            <div className="flex flex-col leading-tight">
              <span className="text-[10px] font-bold text-emerald-400 animate-pulse">À toi de jouer — {remaining}s</span>
              <div className="flex items-center gap-0.5">
                {Array.from({ length: MAX_LIVES }).map((_, i) => (
                  <span key={i} className={`text-[9px] ${i < myLives ? "opacity-100" : "opacity-25"}`}>❤️</span>
                ))}
              </div>
            </div>
          </div>
        );
      })()}


          {/* Hand — 2 rows so cards stay large without overlap */}
          <div className={reorderMode ? "overflow-x-auto" : ""}>
            <div
              ref={handRef}
              className={`${reorderMode ? "flex gap-2 min-w-max" : "flex flex-col gap-1"} px-1 py-1`}
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
                const cw = Math.max(44, Math.min(56, Math.floor((avail - (perRow - 1) * 4) / Math.max(perRow, 1))));
                const ch = Math.round(cw * 1.35);
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
                          className="relative transition-transform duration-100 ease-out select-none"
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
                            boxShadow: isBeingDragged
                              ? "0 2px 8px rgba(0,0,0,0.2)"
                              : isSel
                              ? "0 8px 16px rgba(0,0,0,0.45)"
                              : "0 3px 6px rgba(0,0,0,0.35)",
                            filter: isBeingDragged ? "grayscale(0.6)" : undefined,
                          }}
                        >
                          {dropSide === "before" && (
                            <div className="absolute -left-1 top-1 bottom-1 w-1 rounded-full bg-primary pointer-events-none" />
                          )}
                          {dropSide === "after" && (
                            <div className="absolute -right-1 top-1 bottom-1 w-1 rounded-full bg-primary pointer-events-none" />
                          )}
                          {showQuickDiscard && (
                            <button
                              onClick={(e) => { e.stopPropagation(); discardOne(); }}
                              className="absolute -top-11 left-1/2 -translate-x-1/2 z-[999] px-3 py-1 rounded-full bg-destructive text-white text-[11px] font-extrabold shadow-lg shadow-destructive/40 flex items-center gap-1 whitespace-nowrap animate-scale-in hover:bg-destructive/90 active:scale-95"
                            >
                              <Trash2 className="w-3 h-3" /> Défausser
                            </button>
                          )}
                          <Card
                            c={c}
                            selected={isSel}
                            onClick={() => { if (!dnd.drag) toggleSel(c); }}
                            
                            styleOverride={{ width: `${cw}px`, height: `${ch}px`, pointerEvents: dnd.drag ? "none" : undefined }}
                          />
                          {playableCards.has(c) && !isSel && (
                            <div className="absolute -inset-1.5 ring-2 ring-amber-400/70 pointer-events-none" style={{ width: `${cw + 12}px`, height: `${ch + 12}px`, borderRadius: '8px' }} />
                          )}
                          {newCard === c && (
                            <>
                              <div className="absolute -inset-1.5 ring-2 ring-amber-400 pointer-events-none card-arrive" style={{ borderRadius: '8px' }} />
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
            <div className="space-y-1">
      {/* Floating validate removed — use action bar instead */}


              {/* sevenFx animation removed for performance */}

              {/* ── Always-visible action bar ── */}
              {isMyTurn && phase === "play" && !reorderMode && selected.length === 0 && staged.length === 0 && (
                <div className="flex items-center gap-1.5">
                  {canClaimSeven && sevenCardsEnabled ? (
                  <button
                    onClick={claimSeven}
                    disabled={busy}
                    className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-500 text-black font-black text-xs shadow-md shadow-amber-500/40 animate-pulse active:scale-95 transition-all disabled:opacity-40"
                  >
                    <Check className="w-3.5 h-3.5" /> Valider le 7 cartes
                  </button>
                  ) : (
                  <button
                    onClick={autoArrange}
                    disabled={busy}
                    className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white font-black text-xs shadow-md active:scale-95 transition-all disabled:opacity-40"
                  >
                    <Sparkles className="w-3.5 h-3.5" /> Auto-arranger
                  </button>
                  )}
                  <button
                    onClick={discardOne}
                    disabled={busy || (selected.length as number) !== 1 || !isMyTurn || phase !== "play"}
                    className="flex items-center justify-center gap-1 px-3 py-2 rounded-lg bg-destructive text-white font-bold text-xs disabled:opacity-30 active:scale-95 transition-all"
                  >
                    <Trash2 className="w-3.5 h-3.5" /> Défausser
                  </button>
                </div>
              )}

              {/* ── Compact action bar: single row, contextual ── */}
              {selected.length > 0 && (
                <div className={`rounded-xl border p-2 space-y-1.5 transition-all ${
                  selectionValidity === 'valid' ? 'border-emerald-500/30 bg-emerald-500/5'
                  : selectionValidity === 'invalid' ? 'border-destructive/30 bg-destructive/5'
                  : 'border-primary/20 bg-primary/5'
                }`}>
                  {/* Status + hint in one line */}
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-1.5 min-w-0">
                      <div className={`w-1.5 h-1.5 rounded-full shrink-0 ${selectionValidity === 'valid' ? 'bg-emerald-400' : selectionValidity === 'invalid' ? 'bg-destructive' : 'bg-primary'}`} />
                      {selectionValidity === 'valid' && (
                        <span className="px-1.5 py-0.5 rounded-full bg-emerald-500 text-white text-[9px] font-black shrink-0">
                          ✓ {selectionKind ? MELD_LABEL[selectionKind] : 'Valide'}
                        </span>
                      )}
                      <span className="text-[10px] font-bold truncate">
                        {selected.length} carte{selected.length > 1 ? "s" : ""}
                      </span>
                      {isSeven && <span className="text-[9px] font-black text-amber-400 shrink-0">🎊 7 cartes!</span>}
                    </div>
                    {selectionFeedback.hint && (
                      <span className={`text-[9px] font-semibold px-1.5 py-0.5 rounded-full shrink-0 ${
                        selectionFeedback.severity === 'ok' ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300'
                        : selectionFeedback.severity === 'error' ? 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300'
                        : selectionFeedback.severity === 'warn' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300'
                        : 'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300'
                      }`}>
                        {selectionFeedback.hint}
                      </span>
                    )}
                  </div>
                  {/* Single action row */}
                  <div className="flex items-center gap-1.5">
                    {selected.length >= 3 && (
                      <button onClick={() => postSelection()} disabled={busy}
                        className={`flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg font-black text-xs shadow-md active:scale-95 transition-all ${
                          selectionKind === 'seven'
                            ? "bg-gradient-to-r from-amber-500 to-fuchsia-600 text-white"
                            : selectionKind
                              ? "bg-emerald-600 text-white hover:bg-emerald-500"
                              : "bg-emerald-600/80 text-white"
                        }`}>
                        <Check className="w-3.5 h-3.5" />
                        {selectionKind === 'seven' ? "7 cartes" : selectionKind ? `Valider ${MELD_LABEL[selectionKind]}` : "Valider"}
                      </button>
                    )}
                    <button onClick={discardOne} disabled={busy || (selected.length as number) !== 1 || !isMyTurn || phase !== "play"}
                      className="flex items-center justify-center gap-1 px-3 py-2 rounded-lg bg-destructive text-white font-bold text-xs disabled:opacity-30 active:scale-95 transition-all">
                      <Trash2 className="w-3.5 h-3.5" /> Défausser
                    </button>
                    <button onClick={() => setSelected([])}
                      className="flex items-center justify-center gap-1 px-2.5 py-2 rounded-lg bg-white/8 text-muted-foreground font-semibold text-xs active:scale-95 transition-all">
                      <X className="w-3.5 h-3.5" />
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
                <div className="rounded-xl p-2 bg-gradient-to-r from-amber-500/15 via-yellow-500/10 to-amber-500/15 border border-amber-500/40 shadow-lg">
                  <button
                    onClick={validateHand}
                    disabled={busy || staged.length === 0 || selected.length !== 1}
                    className="w-full flex items-center justify-center gap-2 px-3 py-2.5 rounded-xl bg-gradient-to-r from-amber-500 to-yellow-500 text-black font-black text-sm shadow-md shadow-amber-500/40 disabled:opacity-40 hover:brightness-110 active:scale-[0.98] transition-all"
                  >
                    <Check className="w-5 h-5" />
                    {selected.length === 1
                      ? `Valider ma main (${staged.length} combo${staged.length > 1 ? 's' : ''} + 1 défausse)`
                      : "Valider ma main"}
                  </button>
                </div>
              )}

              {/* Staging zone */}
              {staged.length > 0 && (
                <div className="rounded-xl bg-emerald-500/6 border border-emerald-500/20 p-2 space-y-2 shadow-sm">
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
                  {stagedMoving && (
                    <div className="text-[9px] text-violet-500 font-semibold px-1">
                      Touche une autre carte de la combo pour l'échanger de place
                    </div>
                  )}
                  <div className="space-y-1.5">
                    {staged.map((group, gi) => (
                      <div key={gi} className={`rounded-lg p-2 flex items-center gap-2 transition-all border ${
                        stagedValidity[gi] === 'valid' ? 'bg-emerald-500/5 border-emerald-500/25 shadow-sm'
                        : stagedValidity[gi] === 'invalid' ? 'bg-destructive/5 border-destructive/25'
                        : 'bg-white/4 border-white/8'
                      }`}>
                        <div className="flex gap-1.5 overflow-x-auto flex-1 pb-1" data-drop-target={`staged-end:${gi}`}>
                          {group.map((c, ci) => {
                            const srcId = `staged:${gi}:${c}`;
                            const isBeingDragged = dnd.isDraggingId(srcId);
                            const dropSide = dnd.isTargetId(srcId);
                            const isPicked = stagedMoving?.gi === gi && stagedMoving?.idx === ci;
                            return (
                              <div
                                key={`stage-${gi}-${ci}`}
                                className="relative select-none"
                                data-drop-target={srcId}
                                {...dnd.getSourceProps(srcId)}
                                style={{
                                  opacity: isBeingDragged ? 0.55 : 1,
                                  transform: isBeingDragged ? "translateY(-10px) scale(1.06)" : isPicked ? "translateY(-6px) scale(1.08)" : undefined,
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
                                <Card c={c} size="md" selected={isPicked} onClick={() => handleStagedTap(gi, ci)} onRemove={() => removeFromStaged(gi, c)} />
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


      <GameSocialFab gameId={id} gameSlug="rami" participants={parts} />

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
          {!isPlayer && game?.status === "playing" && (
        <div className="fixed bottom-4 right-4 z-40">
          <SpectatorLeaveButton className="px-4 py-2 text-sm shadow-lg" />
        </div>
      )}
    </main>

  );
}
