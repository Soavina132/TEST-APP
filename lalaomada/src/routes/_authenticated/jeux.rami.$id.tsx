import { SUITS, SUIT_COLORS, RANKS } from "@/lib/game-constants";
import React from "react";
import { serverNow } from "@/lib/server-time";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, useCallback, useMemo, useRef } from "react";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { LogOut, Copy, Timer, Layers, Trash2, Plus, X, Check, Lightbulb, ChevronLeft, ChevronRight, ArrowLeftRight, Pause, Volume2, VolumeX, Eye, Palette, Sparkles, Crown } from "lucide-react";
import GameSocialFab from "@/components/game/GameSocialFab";
import GamePauseControl from "@/components/game/GamePauseControl";
import GameInstructionsBanner from "@/components/game/GameInstructionsBanner";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import GameBoardSkin from "@/components/game/GameBoardSkin";
import TurnBanner from "@/components/game/TurnBanner";
import { useGameConfig } from "@/hooks/game/use-game-config";
import { useConfirm } from "@/components/ConfirmDialog";
import { useLongPressDrag } from "@/hooks/use-long-press-drag";
import ramiCover from "@/assets/games/rami.asset.json";
import { setMuted as setSfxMuted, isMuted as isSfxMuted, sfx } from "@/lib/game-sounds";
import feltAsset from "@/assets/rami/felt.jpg.asset.json";
import cardBackAsset from "@/assets/rami/card-back.jpg.asset.json";

const FELT_URL = feltAsset.url;
const _CARD_BACK_URL = cardBackAsset.url; // kept for potential future use

export const Route = createFileRoute("/_authenticated/jeux/rami/$id")({
  component: RamiPage,
  head: () => ({ meta: [{ title: "Rami — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

// ── Playing Card SVG Renderer ─────────────────────────────────────────────
// Realistic playing card design with proper suit shapes, ornate court cards,
// and decorative card back pattern.

/** Render a realistic suit symbol (♠♥♦♣) as SVG paths. */
function Pip({ suit, size = 7, flip = false }: { suit: number; size?: number; flip?: boolean }) {
  const s = size;
  const t = flip ? " rotate(180)" : "";
  if (suit === 0) {
    // Spade — refined teardrop + stem
    return <g transform={t} fill="#1a1a2e">
      <path d={`M0,${-s} C${s*0.75},${-s*0.35} ${s*0.95},${s*0.25} ${s*0.3},${s*0.72} C${s*0.18},${s*0.78} ${s*0.08},${s*0.7} ${s*0.12},${s*0.58} C${s*0.16},${s*0.46} ${s*0.3},${s*0.44} ${s*0.4},${s*0.55} L${s*0.4},${s*0.55} C${s*0.35},${s*0.65} ${s*0.22},${s*0.72} ${s*0.1},${s*0.7} L${-s*0.1},${s*0.7} C${-s*0.22},${s*0.72} ${-s*0.35},${s*0.65} ${-s*0.4},${s*0.55} C${-s*0.3},${s*0.44} ${-s*0.16},${s*0.46} ${-s*0.12},${s*0.58} C${-s*0.08},${s*0.7} ${-s*0.18},${s*0.78} ${-s*0.3},${s*0.72} C${-s*0.95},${s*0.25} ${-s*0.75},${-s*0.35} 0,${-s}Z`} />
      <path d={`M${-s*0.14},${s*0.55} L${s*0.14},${s*0.55} L${s*0.08},${s*0.95} L${-s*0.08},${s*0.95} Z`} />
    </g>;
  }
  if (suit === 1) {
    // Heart — smooth scalloped top
    return <g transform={t} fill="#c41e3a">
      <path d={`M0,${s*0.95} C${-s*0.92},${s*0.12} ${-s*0.98},${-s*0.52} ${-s*0.5},${-s*0.78} C${-s*0.25},${-s*0.92} ${-s*0.05},${-s*0.82} 0,${-s*0.5} C${s*0.05},${-s*0.82} ${s*0.25},${-s*0.92} ${s*0.5},${-s*0.78} C${s*0.98},${-s*0.52} ${s*0.92},${s*0.12} 0,${s*0.95}Z`} />
    </g>;
  }
  if (suit === 2) {
    // Diamond — slightly rounded rhombus
    return <g transform={t} fill="#c41e3a">
      <path d={`M0,${-s*0.98} L${s*0.62},0 L0,${s*0.98} L${-s*0.62},0 Z`} />
    </g>;
  }
  // Club — three circles + stem
  return <g transform={t} fill="#1a1a2e">
    <circle r={s*0.38} cy={-s*0.46} />
    <circle r={s*0.38} cx={-s*0.42} cy={s*0.18} />
    <circle r={s*0.38} cx={s*0.42} cy={s*0.18} />
    <path d={`M${-s*0.12},${s*0.45} L${s*0.12},${s*0.45} L${s*0.08},${s*0.95} L${-s*0.08},${s*0.95} Z`} />
  </g>;
}

// Standard pip positions on a playing card (0=Ace, 1=2, ... 9=10)
const PIP_POS: [number, number, boolean][][] = [
  [[50, 70, false]],                                                                                              // A
  [[50, 30, false], [50, 110, true]],                                                                             // 2
  [[50, 30, false], [50, 70, false], [50, 110, true]],                                                            // 3
  [[33, 30, false], [67, 30, false], [33, 110, true], [67, 110, true]],                                           // 4
  [[33, 30, false], [67, 30, false], [50, 70, false], [33, 110, true], [67, 110, true]],                          // 5
  [[33, 30, false], [67, 30, false], [33, 70, false], [67, 70, false], [33, 110, true], [67, 110, true]],        // 6
  [[33, 28, false], [67, 28, false], [50, 49, false], [33, 70, false], [67, 70, false], [33, 110, true], [67, 110, true]], // 7
  [[33, 28, false], [67, 28, false], [50, 46, false], [33, 64, false], [67, 64, false], [50, 94, true], [33, 110, true], [67, 110, true]], // 8
  [[33, 26, false], [67, 26, false], [33, 48, false], [67, 48, false], [50, 70, false], [33, 92, true], [67, 92, true], [33, 114, true], [67, 114, true]], // 9
  [[33, 24, false], [67, 24, false], [50, 36, false], [33, 50, false], [67, 50, false], [33, 90, true], [67, 90, true], [50, 104, true], [33, 116, true], [67, 116, true]], // 10
];

function PipCard({ rank, suit }: { rank: number; suit: number }) {
  const pips = PIP_POS[rank];
  const isAce = rank === 0;
  return <>
    {pips.map(([cx, cy, flip], i) => (
      <g key={i} transform={`translate(${cx},${cy})`}>
        <Pip suit={suit} size={isAce ? 22 : 7.5} flip={flip} />
      </g>
    ))}
  </>;
}

import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";

/** Corner index — rank + suit symbol, like a real playing card corner. */
function CornerIndex({ rank, suit, x, y, flip, color, fontScale = 1 }: {
  rank: number; suit: number; x: number; y: number; flip?: boolean;
  color: string; fontScale?: number;
}) {
  const rot = flip ? `rotate(180 ${x} ${y})` : undefined;
  const fs = 13 * fontScale;
  const ss = 10 * fontScale;
  return (
    <g transform={rot}>
      {/* Rank — bold and clear */}
      <text x={x} y={y} fontSize={fs} fontWeight="800" fill={color}
        fontFamily="'Georgia', 'Times New Roman', serif" textAnchor="start">
        {RANKS[rank]}
      </text>
      {/* Suit symbol — Unicode character, below the rank */}
      <text x={x + 0.5} y={y + ss} fontSize={ss * 0.85} fontWeight="700" fill={color}
        fontFamily="serif" textAnchor="start">
        {SUITS[suit]}
      </text>
    </g>
  );
}

/** Court-card figure (J/Q/K) — detailed ornate vector style. */
function CourtHalf({ rank, suit }: { rank: number; suit: number }) {
  const isRed = suit === 1 || suit === 2;
  const ink = "#1a1a2e";
  const main = isRed ? "#c41e3a" : "#1e3a5f";
  const mainLight = isRed ? "#e76580" : "#3a5f8f";
  const gold = "#c9a227";
  const goldLight = "#e6c84e";
  const skin = "#f0c9a0";
  const skinShade = "#d9b58a";
  const suitColor = isRed ? "#c41e3a" : "#1a1a2e";

  return (
    <g>
      {/* ornate panel background with gradient */}
      <defs>
        <linearGradient id={`bg-${suit}-${rank}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={mainLight} stopOpacity="0.15" />
          <stop offset="100%" stopColor={main} stopOpacity="0.08" />
        </linearGradient>
        <linearGradient id={`robe-${suit}-${rank}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={mainLight} />
          <stop offset="100%" stopColor={main} />
        </linearGradient>
        <linearGradient id={`crown-${suit}-${rank}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={goldLight} />
          <stop offset="100%" stopColor={gold} />
        </linearGradient>
      </defs>
      <rect x="8" y="19" width="84" height="52" fill={`url(#bg-${suit}-${rank})`} />
      {/* decorative border */}
      <rect x="9" y="20" width="82" height="50" fill="none" stroke={gold} strokeWidth="0.4" opacity="0.35" />
      <rect x="11" y="22" width="78" height="46" fill="none" stroke={gold} strokeWidth="0.25" opacity="0.2" />

      {/* ── KING (rank 12) ── */}
      {rank === 12 && (
        <g>
          {/* ornate crown */}
          <path d="M36 34 L36 22 L41 28 L46 19 L50 24 L54 19 L59 28 L64 22 L64 34 Z"
            fill={`url(#crown-${suit}-${rank})`} stroke={ink} strokeWidth="0.5" />
          {/* crown jewels */}
          <circle cx="36" cy="22" r="1.6" fill={main} stroke={ink} strokeWidth="0.3" />
          <circle cx="50" cy="20" r="2" fill="#dc2626" stroke={ink} strokeWidth="0.3" />
          <circle cx="64" cy="22" r="1.6" fill={main} stroke={ink} strokeWidth="0.3" />
          {/* crown band */}
          <rect x="36" y="32" width="28" height="4" fill={main} stroke={ink} strokeWidth="0.4" />
          <circle cx="43" cy="34" r="0.9" fill={goldLight} />
          <circle cx="50" cy="34" r="0.9" fill={goldLight} />
          <circle cx="57" cy="34" r="0.9" fill={goldLight} />
          {/* flowing beard */}
          <path d="M44 48 C43 54, 44 58, 46 62 L54 62 C56 58, 57 54, 56 48 Z"
            fill="#e8e8e8" stroke={ink} strokeWidth="0.4" opacity="0.85" />
          <path d="M47 50 L47 58 M50 50 L50 60 M53 50 L53 58"
            stroke={ink} strokeWidth="0.3" opacity="0.3" />
          {/* head */}
          <ellipse cx="50" cy="44" rx="8" ry="7" fill={skin} stroke={ink} strokeWidth="0.6" />
          {/* eyes — stern */}
          <path d="M45.5 43 L48 43.5" stroke={ink} strokeWidth="0.7" strokeLinecap="round" />
          <path d="M52 43.5 L54.5 43" stroke={ink} strokeWidth="0.7" strokeLinecap="round" />
          {/* mustache */}
          <path d="M44 48 C46 49, 48 48.5, 50 47.5 C52 48.5, 54 49, 56 48"
            fill="none" stroke={ink} strokeWidth="0.8" strokeLinecap="round" />
          {/* royal robe with fur trim */}
          <path d="M30 71 C30 62, 38 57, 50 57 C62 57, 70 62, 70 71 Z"
            fill={`url(#robe-${suit}-${rank})`} stroke={ink} strokeWidth="0.5" />
          {/* fur collar */}
          <path d="M38 58 C42 61, 58 61, 62 58" fill="none" stroke="#e8e8e8" strokeWidth="2.5" strokeLinecap="round" />
          <path d="M40 59 L40 62 M45 60 L45 63 M50 60 L50 63 M55 60 L55 63 M60 59 L60 62"
            stroke={ink} strokeWidth="0.2" opacity="0.3" />
          {/* scepter on left */}
          <line x1="33" y1="55" x2="33" y2="70" stroke={gold} strokeWidth="1.2" />
          <circle cx="33" cy="54" r="2.2" fill={gold} stroke={ink} strokeWidth="0.4" />
          {/* sword on right */}
          <line x1="67" y1="50" x2="67" y2="70" stroke="#c0c0c0" strokeWidth="1.2" />
          <path d="M64 50 L70 50 L67 47 Z" fill={gold} stroke={ink} strokeWidth="0.3" />
          {/* suit emblem on chest */}
          <circle cx="50" cy="67" r="4" fill={gold} stroke={ink} strokeWidth="0.4" opacity="0.9" />
          <text x="50" y="69.5" textAnchor="middle" fontSize="6" fontWeight="700" fill={ink}>{SUITS[suit]}</text>
        </g>
      )}

      {/* ── QUEEN (rank 11) ── */}
      {rank === 11 && (
        <g>
          {/* elegant tiara */}
          <path d="M38 35 C40 27, 60 27, 62 35 L62 36 L38 36 Z"
            fill={`url(#crown-${suit}-${rank})`} stroke={ink} strokeWidth="0.4" />
          {/* tiara peaks with jewels */}
          <path d="M40 35 L42 29 L44 35 Z" fill={gold} stroke={ink} strokeWidth="0.3" />
          <path d="M48 35 L50 26 L52 35 Z" fill={gold} stroke={ink} strokeWidth="0.3" />
          <path d="M56 35 L58 29 L60 35 Z" fill={gold} stroke={ink} strokeWidth="0.3" />
          <circle cx="42" cy="29" r="1" fill="#dc2626" stroke={ink} strokeWidth="0.2" />
          <circle cx="50" cy="26" r="1.3" fill="#dc2626" stroke={ink} strokeWidth="0.2" />
          <circle cx="58" cy="29" r="1" fill="#dc2626" stroke={ink} strokeWidth="0.2" />
          {/* tiara band */}
          <rect x="38" y="35" width="24" height="2" fill={gold} stroke={ink} strokeWidth="0.3" />
          {/* flowing hair */}
          <path d="M40 38 C36 44, 35 52, 37 58 C38 52, 40 46, 42 42 Z"
            fill={isRed ? "#8b2c3a" : "#2a2a3e"} opacity="0.6" />
          <path d="M60 38 C64 44, 65 52, 63 58 C62 52, 60 46, 58 42 Z"
            fill={isRed ? "#8b2c3a" : "#2a2a3e"} opacity="0.6" />
          {/* head */}
          <ellipse cx="50" cy="43" rx="7.5" ry="7" fill={skin} stroke={ink} strokeWidth="0.6" />
          {/* delicate face */}
          <circle cx="46.5" cy="42" r="0.9" fill={ink} />
          <circle cx="53.5" cy="42" r="0.9" fill={ink} />
          {/* eyelashes */}
          <path d="M45 40.5 L46 40 M45.5 41 L46.5 40.5" stroke={ink} strokeWidth="0.3" />
          <path d="M54 40.5 L55 40 M54.5 41 L55.5 40.5" stroke={ink} strokeWidth="0.3" />
          {/* lips */}
          <path d="M47.5 47 C49 48, 51 48, 52.5 47" fill={isRed ? "#c41e3a" : "#8b4f5a"}
            stroke={ink} strokeWidth="0.3" />
          {/* elegant dress */}
          <path d="M32 71 C32 62, 40 57, 50 57 C60 57, 68 62, 68 71 Z"
            fill={`url(#robe-${suit}-${rank})`} stroke={ink} strokeWidth="0.5" />
          {/* necklace */}
          <path d="M42 58 C45 61, 55 61, 58 58" fill="none" stroke={gold} strokeWidth="0.6" />
          <circle cx="50" cy="60" r="1.4" fill="#dc2626" stroke={gold} strokeWidth="0.3" />
          {/* dress trim */}
          <path d="M42 56 L58 56" stroke={gold} strokeWidth="0.5" opacity="0.5" />
          {/* flower on right */}
          <circle cx="65" cy="55" r="2" fill={isRed ? "#e76580" : "#6b8db5"} stroke={ink} strokeWidth="0.3" />
          <circle cx="65" cy="55" r="0.8" fill={gold} />
          {/* suit emblem on chest */}
          <circle cx="50" cy="66" r="3.5" fill={gold} stroke={ink} strokeWidth="0.4" opacity="0.9" />
          <text x="50" y="68.5" textAnchor="middle" fontSize="5.5" fontWeight="700" fill={ink}>{SUITS[suit]}</text>
        </g>
      )}

      {/* ── JACK (rank 10) ── */}
      {rank === 10 && (
        <g>
          {/* feathered cap */}
          <path d="M38 36 C38 28, 62 28, 62 36 L62 37 L38 37 Z"
            fill={main} stroke={ink} strokeWidth="0.4" />
          {/* cap brim */}
          <ellipse cx="50" cy="37" rx="14" ry="2.5" fill={mainLight} stroke={ink} strokeWidth="0.4" />
          {/* feather */}
          <path d="M58 34 C62 28, 66 25, 68 22 C66 28, 64 33, 60 36 Z"
            fill={isRed ? "#e76580" : "#5b7fa8"} stroke={ink} strokeWidth="0.3" />
          <path d="M60 31 L66 24" stroke={ink} strokeWidth="0.25" opacity="0.4" />
          {/* cap badge */}
          <circle cx="50" cy="33" r="1.8" fill={gold} stroke={ink} strokeWidth="0.3" />
          {/* head — young face */}
          <ellipse cx="50" cy="43" rx="7" ry="6.5" fill={skin} stroke={ink} strokeWidth="0.6" />
          {/* hair peeking out */}
          <path d="M43 38 C44 36, 47 36, 48 38" fill={isRed ? "#8b2c3a" : "#2a2a3e"} stroke={ink} strokeWidth="0.3" />
          {/* eyes — alert, youthful */}
          <circle cx="47" cy="42" r="0.9" fill={ink} />
          <circle cx="53" cy="42" r="0.9" fill={ink} />
          {/* slight smile */}
          <path d="M47 46 C48.5 47, 51.5 47, 53 46" fill="none" stroke={ink} strokeWidth="0.5" strokeLinecap="round" />
          {/* military-style tunic */}
          <path d="M34 71 C34 63, 40 58, 50 58 C60 58, 66 63, 66 71 Z"
            fill={`url(#robe-${suit}-${rank})`} stroke={ink} strokeWidth="0.5" />
          {/* collar */}
          <path d="M44 59 L50 62 L56 59" fill="none" stroke={gold} strokeWidth="1" />
          {/* buttons */}
          <circle cx="50" cy="63" r="0.7" fill={gold} />
          <circle cx="50" cy="66" r="0.7" fill={gold} />
          {/* belt */}
          <rect x="38" y="66" width="24" height="2.5" fill={gold} stroke={ink} strokeWidth="0.3" opacity="0.6" />
          {/* sword hilt on left */}
          <line x1="36" y1="56" x2="36" y2="68" stroke="#c0c0c0" strokeWidth="1" />
          <path d="M33 56 L39 56" stroke={gold} strokeWidth="1.2" strokeLinecap="round" />
          {/* suit emblem on chest */}
          <circle cx="50" cy="64" r="3" fill={gold} stroke={ink} strokeWidth="0.4" opacity="0.9" />
          <text x="50" y="66.5" textAnchor="middle" fontSize="5" fontWeight="700" fill={ink}>{SUITS[suit]}</text>
        </g>
      )}
    </g>
  );
}

function FacePortrait({ rank, suit }: { rank: number; suit: number }) {
  const isRed = suit === 1 || suit === 2;
  const frame = isRed ? "#c41e3a" : "#1e3a5f";
  const gold = "#c9a227";
  const uid = `f-${suit}-${rank}`;

  return <>
    {/* ornate frame */}
    <rect x="7" y="18" width="86" height="104" rx="3" fill="#fffcf5" />
    <rect x="7" y="18" width="86" height="104" rx="3" fill="none" stroke={frame} strokeWidth="1.2" opacity="0.6" />
    {/* inner decorative frame */}
    <rect x="9.5" y="19.5" width="81" height="101" rx="2" fill="none" stroke={gold} strokeWidth="0.35" opacity="0.4" />
    {/* corner flourishes */}
    {[[10,21],[90,21],[10,119],[90,119]].map(([cx,cy],i) => (
      <g key={i} transform={`translate(${cx},${cy})`}>
        <path d="M0,0 Q3,0 4,-2 Q0,-3 0,0 Z" fill={gold} opacity="0.4" />
      </g>
    ))}
    {/* top half */}
    <clipPath id={`tc-${uid}`}><rect x="9" y="19" width="82" height="52" /></clipPath>
    <g clipPath={`url(#tc-${uid})`}>
      <CourtHalf rank={rank} suit={suit} />
    </g>
    {/* bottom half (mirrored) */}
    <clipPath id={`bc-${uid}`}><rect x="9" y="69" width="82" height="52" /></clipPath>
    <g clipPath={`url(#bc-${uid})`} transform="rotate(180 50 70)">
      <CourtHalf rank={rank} suit={suit} />
    </g>
    {/* central divider band with ornamental design */}
    <rect x="7" y="66" width="86" height="8" fill="#fffcf5" />
    <line x1="9" y1="70" x2="91" y2="70" stroke={frame} strokeWidth="0.8" opacity="0.5" />
    <line x1="12" y1="68.5" x2="88" y2="68.5" stroke={gold} strokeWidth="0.2" opacity="0.3" />
    <line x1="12" y1="71.5" x2="88" y2="71.5" stroke={gold} strokeWidth="0.2" opacity="0.3" />
    {/* central rank/suit badge — ornate */}
    <rect x="35" y="64.5" width="30" height="11" rx="2.5" fill="#fffcf5" stroke={frame} strokeWidth="0.6" />
    <rect x="36" y="65.5" width="28" height="9" rx="2" fill="none" stroke={gold} strokeWidth="0.25" opacity="0.5" />
    <text x="44" y="72.5" textAnchor="middle" fontSize="8" fontWeight="700" fill={frame}
      fontFamily="'Georgia', serif">{RANKS[rank]}</text>
    <text x="56" y="72.8" textAnchor="middle" fontSize="8" fontWeight="700"
      fill={isRed ? "#c41e3a" : "#1a1a2e"}>{SUITS[suit]}</text>
  </>;
}/** Decorative SVG card back — diamond lattice with center medallion. */
function CardBackSVG() {
  return (
    <svg viewBox="0 0 100 140" xmlns="http://www.w3.org/2000/svg" className="w-full h-full">
      <defs>
        <linearGradient id="cb-grad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#7c1e3f" />
          <stop offset="50%" stopColor="#5a152f" />
          <stop offset="100%" stopColor="#3d0f20" />
        </linearGradient>
        <pattern id="cb-lattice" x="0" y="0" width="14" height="14" patternUnits="userSpaceOnUse">
          <rect width="14" height="14" fill="url(#cb-grad)" />
          <path d="M0 7 L7 0 L14 7 L7 14 Z" fill="none" stroke="#c9a227" strokeWidth="0.3" opacity="0.35" />
          <circle cx="7" cy="7" r="1.2" fill="#c9a227" opacity="0.3" />
        </pattern>
      </defs>
      <rect x="0" y="0" width="100" height="140" rx="6" fill="url(#cb-lattice)" />
      {/* outer border */}
      <rect x="3" y="3" width="94" height="134" rx="4" fill="none" stroke="#c9a227" strokeWidth="0.8" opacity="0.5" />
      <rect x="5" y="5" width="90" height="130" rx="3" fill="none" stroke="#c9a227" strokeWidth="0.4" opacity="0.3" />
      {/* center medallion */}
      <ellipse cx="50" cy="70" rx="22" ry="30" fill="none" stroke="#c9a227" strokeWidth="0.6" opacity="0.45" />
      <ellipse cx="50" cy="70" rx="18" ry="26" fill="none" stroke="#c9a227" strokeWidth="0.3" opacity="0.3" />
      <g transform="translate(50,70)">
        <path d="M0,-12 L3,-4 L11,-4 L5,1 L7,9 L0,5 L-7,9 L-5,1 L-11,-4 L-3,-4 Z"
          fill="#c9a227" opacity="0.4" />
        <circle r="2.5" fill="#c9a227" opacity="0.5" />
      </g>
      {/* corner flourishes */}
      {[8, 92].map(cx => [8, 132].map(cy =>
        <g key={`${cx}-${cy}`} transform={`translate(${cx},${cy})`}>
          <path d="M0,0 L4,0 M0,0 L0,4" stroke="#c9a227" strokeWidth="0.4" opacity="0.4" />
        </g>
      ))}
    </svg>
  );
}

/** Pure-vector jester face — no external image dependency (safe in production). */
function JokerFace({ idx }: { idx: number }) {
  const schemes = ["#c41e3a", "#7c3aed", "#059669", "#b45309"];
  const color = schemes[idx % 4];
  const skin = "#f0c9a0";
  const ink = "#1a1a2e";

  return <>
    <rect x="3" y="3" width="94" height="134" rx="4" fill="#fefce8" />
    <rect x="3" y="3" width="94" height="134" rx="4" fill="none" stroke={color} strokeWidth="1.2" opacity="0.55" />
    <rect x="6" y="6" width="88" height="128" rx="3" fill="none" stroke={color} strokeWidth="0.3" opacity="0.3" />
    {/* corner diamonds */}
    {[[12,12],[88,12],[12,128],[88,128]].map(([x,y],i) => (
      <g key={i} transform={`translate(${x},${y})`}>
        <path d="M0,-3 L2.5,0 L0,3 L-2.5,0 Z" fill={color} opacity="0.55" />
      </g>
    ))}
    <text x="50" y="16" textAnchor="middle" fontSize="7.5" fontWeight="bold"
      fontFamily="serif" fill={color} letterSpacing="2">JOKER</text>

    {/* Jester face — simple vector illustration */}
    <g transform="translate(50,68)">
      {/* jester hat with 3 points + bells */}
      <path d="M-20,-8 C-24,-24 -12,-20 -8,-10 C-4,-24 4,-24 8,-10 C12,-20 24,-24 20,-8 Z" fill={color} />
      <circle cx="-20" cy="-8" r="2.6" fill="#eab308" />
      <circle cx="0" cy="-19" r="2.6" fill="#eab308" />
      <circle cx="20" cy="-8" r="2.6" fill="#eab308" />
      {/* face */}
      <circle cx="0" cy="2" r="14" fill={skin} stroke={ink} strokeWidth="0.8" />
      {/* eyes */}
      <circle cx="-5.5" cy="0" r="1.4" fill={ink} />
      <circle cx="5.5" cy="0" r="1.4" fill={ink} />
      {/* eyebrows */}
      <path d="M-8,-4 C-7,-5.5 -4,-5.5 -3,-4" fill="none" stroke={ink} strokeWidth="0.8" strokeLinecap="round" />
      <path d="M3,-4 C4,-5.5 7,-5.5 8,-4" fill="none" stroke={ink} strokeWidth="0.8" strokeLinecap="round" />
      {/* big grin */}
      <path d="M-8,6 C-4,12 4,12 8,6" fill="none" stroke={ink} strokeWidth="1.1" strokeLinecap="round" />
      {/* nose dot */}
      <circle cx="0" cy="3" r="0.8" fill={ink} opacity="0.5" />
      {/* collar with bells */}
      <path d="M-16,15 C-8,22 8,22 16,15 L16,19 C8,26 -8,26 -16,19 Z" fill={color} />
      <circle cx="-12" cy="20" r="2" fill="#eab308" />
      <circle cx="0" cy="23" r="2" fill="#eab308" />
      <circle cx="12" cy="20" r="2" fill="#eab308" />
    </g>

    <g transform="rotate(180 50 70)">
      <text x="50" y="16" textAnchor="middle" fontSize="7.5" fontWeight="bold"
        fontFamily="serif" fill={color} letterSpacing="2">JOKER</text>
    </g>
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
      <div
        className={`${sizeClass} rounded-md shrink-0 shadow overflow-hidden`}
        style={{
          ...dealStyle,
          ...styleOverride,
          border: "1px solid rgba(100,80,40,0.25)",
        }}
      >
        <CardBackSVG />
      </div>
    );
  }

  const base = c % 56; // 2 paquets : ids 0..55 et 56..111
  const isJoker = base >= 52;
  const suit = isJoker ? 0 : Math.floor(base / 13);
  const rank = isJoker ? 0 : base % 13;
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
        style={{
          ...styleOverride,
          perspective: styleOverride?.width ? "200px" : undefined,
        }}
        className={`${sizeClass} block transition-all duration-150 ease-out
          ${selected ? "-translate-y-3 drop-shadow-lg" : ""}
          ${highlight === "layoff" ? "ring-2 ring-emerald-400 ring-offset-1 scale-105" : ""}
          ${onClick ? "hover:-translate-y-1.5 cursor-pointer active:scale-95 hover:drop-shadow-[0_8px_14px_rgba(0,0,0,0.4)] hover:brightness-105" : "cursor-default"}`}
      >

        <svg viewBox="0 0 100 140" xmlns="http://www.w3.org/2000/svg" className="w-full h-full">
          <defs>
            <linearGradient id={`gloss-${base}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="rgba(255,255,255,0.25)" stopOpacity="0.25" />
              <stop offset="45%" stopColor="rgba(255,255,255,0)" stopOpacity="0" />
              <stop offset="100%" stopColor="rgba(0,0,0,0.08)" stopOpacity="0.08" />
            </linearGradient>
            <filter id={`sh-${base}`}>
              <feDropShadow dx="0" dy="1" stdDeviation="0.5" floodColor="#000" floodOpacity="0.12" />
            </filter>
          </defs>
          {/* Card base — white with subtle warm tint like real card stock */}
          <rect x="0.5" y="0.5" width="99" height="139" rx="7" fill="#fefefe" stroke="#c8c8c8" strokeWidth="0.8" filter={`url(#sh-${base})`} />
          <rect x="2" y="2" width="96" height="136" rx="5" fill="none" stroke="#e8e8e8" strokeWidth="0.4" opacity="0.5" />
          {isJoker ? (
            <JokerFace idx={base - 52} />
          ) : (
            <>
              {/* Top-left corner index */}
              <CornerIndex rank={rank} suit={suit} x={5.5} y={13} color={color} fontScale={rankLabel === "10" ? 0.88 : 1} />
              {/* Bottom-right corner index (rotated) */}
              <g transform="rotate(180 50 70)">
                <CornerIndex rank={rank} suit={suit} x={5.5} y={13} color={color} fontScale={rankLabel === "10" ? 0.88 : 1} />
              </g>
              {/* Center: face portrait or pip layout */}
              {isFace ? (() => {
                const _suitNames = ['spade','heart','diamond','club'];
                const _rankNames = {10:'jack',11:'queen',12:'king'};
                const _imgSrc = `/cards/${_suitNames[suit]}_${_rankNames[rank]}.png`;
                return (
                  <image href={_imgSrc} x="0.5" y="0.5" width="99" height="139"
                    preserveAspectRatio="xMidYMid meet" opacity="0.98" />
                );
              })() : <PipCard rank={rank} suit={suit} />}
            </>
          )}
          {/* Gloss overlay for depth */}
          <rect x="0.5" y="0.5" width="99" height="139" rx="7" fill={`url(#gloss-${base})`} pointerEvents="none" />
        </svg>
        {selected && <div className="absolute inset-0 rounded-md ring-2 ring-emerald-400 pointer-events-none" />}
        {onClick && !selected && (
          <div className="absolute inset-0 rounded-md opacity-0 hover:opacity-100 transition-opacity duration-200 pointer-events-none" style={{ background: "linear-gradient(135deg, rgba(255,255,255,0.12) 0%, transparent 50%, rgba(255,255,255,0.05) 100%)" }} />
        )}
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
const CARD_BASE = (c: number): number => c % 56;

const CARD_POINTS = (c: number): number => {
  const b = CARD_BASE(c);
  if (b >= 52) return 15;
  const r = b % 13;
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
    if (CARD_BASE(c) >= 52) return true;
    if (jokerMode === 'aleatoire' && randomJoker !== null && CARD_BASE(c) === CARD_BASE(randomJoker)) return true;
    return false;
  };

  const jokerCount = cards.filter(isJoker).length;
  const real = cards.filter(c => !isJoker(c));

  const checkSet = (): boolean => {
    if (cards.length > 4) return false;
    // Mirror server rule: at least 2 real cards required (no all-joker melds)
    if (real.length < 2) return false;
    const rank = CARD_BASE(real[0]) % 13;
    if (!real.every(c => CARD_BASE(c) % 13 === rank)) return false;
    const suits = real.map(c => Math.floor(CARD_BASE(c) / 13));
    return new Set(suits).size === suits.length;
  };

  const checkSequence = (): boolean => {
    if (real.length < 2) return false;
    const suit = Math.floor(CARD_BASE(real[0]) / 13);
    if (!real.every(c => Math.floor(CARD_BASE(c) / 13) === suit)) return false;
    const ranks = real.map(c => CARD_BASE(c) % 13).sort((a, b) => a - b);
    let gaps = 0;
    for (let i = 1; i < ranks.length; i++) {
      const diff = ranks[i] - ranks[i - 1];
      if (diff === 0) return false;
      gaps += diff - 1;
    }
    return gaps <= jokerCount;
  };

  if (checkSet() || checkSequence()) return 'valid';
  if (cards.length === 7 && isSevenCombo(cards, jokerMode, randomJoker)) return 'valid';
  return 'invalid';
}

/** Type détecté d'une sélection : carré, trio, escalier ou 7 cartes. */
type MeldKind = 'carre' | 'trio' | 'run' | 'seven' | null;

function meldKind(cards: number[], jokerMode: string, randomJoker: number | null): MeldKind {
  if (cards.length < 3) return null;
  if (cards.length === 7 && isSevenCombo(cards, jokerMode, randomJoker)) return 'seven';
  if (validateMeld(cards, jokerMode, randomJoker) !== 'valid') return null;
  const isJoker = (c: number) =>
    CARD_BASE(c) >= 52 || (jokerMode === 'aleatoire' && randomJoker !== null && CARD_BASE(c) === CARD_BASE(randomJoker));
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
function isSevenCombo(cards: number[], jokerMode: string, randomJoker: number | null): boolean {
  if (cards.length !== 7) return false;
  const baseValid = (sub: number[]): boolean => {
    if (sub.length < 3) return false;
    const isJoker = (c: number) => CARD_BASE(c) >= 52 || (jokerMode === 'aleatoire' && randomJoker !== null && CARD_BASE(c) === CARD_BASE(randomJoker));
    const jokerCount = sub.filter(isJoker).length;
    const real = sub.filter(c => !isJoker(c));
    if (real.length < 2) return false;
    // set
    const rank = CARD_BASE(real[0]) % 13;
    const suits = real.map(c => Math.floor(CARD_BASE(c) / 13));
    if (sub.length <= 4 && real.every(c => CARD_BASE(c) % 13 === rank) && new Set(suits).size === suits.length) return true;
    // run
    const suit = Math.floor(CARD_BASE(real[0]) / 13);
    if (!real.every(c => Math.floor(CARD_BASE(c) / 13) === suit)) return false;
    const ranks = real.map(c => CARD_BASE(c) % 13).sort((a, b) => a - b);
    let gaps = 0;
    for (let i = 1; i < ranks.length; i++) {
      const diff = ranks[i] - ranks[i - 1];
      if (diff === 0) return false;
      gaps += diff - 1;
    }
    return gaps <= jokerCount;
  };
  for (let i = 0; i < 4; i++)
    for (let j = i + 1; j < 5; j++)
      for (let k = j + 1; k < 6; k++)
        for (let l = k + 1; l < 7; l++) {
          const four = [cards[i], cards[j], cards[k], cards[l]];
          const three = cards.filter((_, idx) => idx !== i && idx !== j && idx !== k && idx !== l);
          if (baseValid(four) && baseValid(three)) return true;
        }
  return false;
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
    CARD_BASE(c) >= 52 || (jokerMode === 'aleatoire' && randomJoker !== null && CARD_BASE(c) === CARD_BASE(randomJoker));

  const validity = validateMeld(cards, jokerMode, randomJoker);
  if (validity === 'valid') return { hint: "✓ Combinaison valide — prête à poser", severity: 'ok' };
  if (validity === 'unknown') {
    // 1 or 2 cards — give a hint
    if (cards.length === 1) return { hint: "Sélectionne 2 cartes de plus pour un trio, ou 2+ de même couleur pour un escalier", severity: 'info' };
    const real = cards.filter(c => !isJoker(c));
    if (real.length >= 2) {
      const sameSuit = real.every(c => Math.floor(CARD_BASE(c) / 13) === Math.floor(CARD_BASE(real[0]) / 13));
      const sameRank = real.every(c => CARD_BASE(c) % 13 === CARD_BASE(real[0]) % 13);
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
    const ranks = real.map(c => CARD_BASE(c) % 13).sort((a, b) => a - b);
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
    .playable-glow { animation: glowPulse 1.2s ease-in-out infinite; }
    @keyframes cardFlip3D {
      0%   { transform: rotateY(180deg); }
      100% { transform: rotateY(0deg); }
    }
  `;
  document.head.appendChild(style);
}

// Flying card overlay — animates from source rect to target rect
function FlyingCard({ card, from, to }: { card: number | undefined; from: { x: number; y: number }; to: { x: number; y: number } }) {
  const [pos, setPos] = useState(from);
  const [rot, setRot] = useState(-12);
  React.useEffect(() => {
    const r = requestAnimationFrame(() => { setPos(to); setRot(0); });
    return () => cancelAnimationFrame(r);
  }, [to.x, to.y]);
  return (
    <div
      className="fixed z-[200] pointer-events-none"
      style={{
        left: 0,
        top: 0,
        transform: `translate(${pos.x}px, ${pos.y}px) translate(-50%, -50%) rotate(${rot}deg)`,
        transition: "transform 0.6s cubic-bezier(0.34, 1.56, 0.64, 1)",
        filter: "drop-shadow(0 16px 24px rgba(0,0,0,0.55))",
      }}
    >
      <Card c={card} faceDown={card === undefined} size="lg" styleOverride={{ width: 48, height: 68 }} />
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────
function RamiPage() {
  const { id } = Route.useParams();
  const { profile, isAdmin } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const [game, setGame] = useState<any>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [selected, setSelected] = useState<number[]>([]);
  const [sevenFx, setSevenFx] = useState<string | null>(null);
  const [staged, setStaged] = useState<number[][]>([]);
  const [sortMode, setSortMode] = useState<'none' | 'suit' | 'rank'>('none');
  const [boardTheme, setBoardTheme] = useState<'green' | 'blue' | 'dark'>('green');
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

  // Board theme configuration
  const BOARD_THEMES = {
    green: { border: "#0b3a1f", overlay: "rgba(0,0,0,0.25)", tint: "rgba(15,61,32,0.3)", feltCenter: "#1a6b3a", feltEdge: "#0d4525" },
    blue: { border: "#0c2742", overlay: "rgba(5,20,40,0.3)", tint: "rgba(12,39,66,0.35)", feltCenter: "#1a3a6b", feltEdge: "#0c2742" },
    dark: { border: "#1a1a1a", overlay: "rgba(0,0,0,0.35)", tint: "rgba(10,10,10,0.4)", feltCenter: "#2a2a2a", feltEdge: "#141414" },
  };
  const activeTheme = BOARD_THEMES[boardTheme];

  const load = useCallback(async () => {
    const { data: g } = await supabase.from("rami_games" as any).select("*").eq("id", id).maybeSingle();
    setGame(g);
    const { data: p } = await supabase.from("rami_participants" as any).select("*").eq("game_id", id).order("slot");
    setParts((p as any[]) || []);
  }, [id, profile?.id]);

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

  // cancelled state handled by GameStateMessage below

  // ── Deal animation: trigger when game starts ──
  const prevStatusRef2 = useRef<string>("");
  useEffect(() => {
    if (prevStatusRef2.current !== "playing" && game?.status === "playing") {
      setDealAnimating(true);
      const t = setTimeout(() => setDealAnimating(false), 1200);
      return () => clearTimeout(t);
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
        if (m.type === "seven") {
          const who = p?.display_name || "Un joueur";
          setSevenFx(who);
          setTimeout(() => setSevenFx(null), 3500);
          toast.success(`🎊 ${who} : 7 Cartes — Miverim-bola !`, { duration: 3500 });
        }
        if (p?.is_bot && m.type !== "seven") {
          const kind = m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
          toast.success(`🎯 ${p.display_name || "Bot"} a posé un ${kind} (${m.cards.length} cartes)`, { duration: 2800 });
        }
        // Also notify for human opponents
        if (!p?.is_bot && p && m.type !== "seven") {
          const kind = m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
          toast.info(`🎯 ${p.display_name || "Joueur"} a posé un ${kind} (${m.cards.length} cartes)`, { duration: 2500 });
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
        toast.info(`🎴 ${p.display_name || "Bot"} défausser: ${cardLabel}`, { duration: 2200 });
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

  // Animation d'intro supprimée : la partie démarre directement.


  const me = parts.find(p => p.user_id === profile?.id);
  const isPlayer = !!me;
  const [isSpectating, setIsSpectating] = useState(false);
  const [spectateData, setSpectateData] = useState<any>(null);

  // Spectator mode: if not a player and game is playing, allow spectating
  useEffect(() => {
    if (!isPlayer && game?.status === "playing" && !isSpectating && profile?.id) {
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

  // Poll spectate data every 3s
  useEffect(() => {
    if (!isSpectating) return;
    const t = setInterval(async () => {
      const { data }: any = await supabase.rpc("rami_spectate" as any, { _game_id: id } as any);
      if (data) setSpectateData(data);
    }, 3000);
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
  const gameMode: "bordel" | "naturel" = (game?.game_mode as any) || "bordel";
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

  // Cards in hand that could complete a valid meld with current selection
  const playableCards = useMemo(() => {
    if (!isMyTurn || phase !== "play" || selected.length === 0 || selected.length >= 4) return new Set<number>();
    const result = new Set<number>();
    for (const c of handCards) {
      if (selected.includes(c)) continue;
      const test = [...selected, c];
      const v = validateMeld(test, jokerMode, randomJoker);
      if (v === "valid") result.add(c);
    }
    return result;
  }, [selected, handCards, isMyTurn, phase, jokerMode, randomJoker]);
  const selectionKind = useMemo(() => meldKind(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const selectionFeedback = useMemo(() => getSelectionFeedback(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const stagedValidity = useMemo(() => staged.map(g => validateMeld(g, jokerMode, randomJoker)), [staged, jokerMode, randomJoker]);
  const isSeven = useMemo(() => isSevenCombo(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);

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

  // ── AFK warning state ──
  const [afkWarning, setAfkWarning] = useState(false);
  useEffect(() => {
    if (!isMyTurn || remaining > 10) { setAfkWarning(false); return; }
    if (remaining <= 10 && remaining > 0) {
      if (remaining === 10 || remaining === 5) sfx.ramiWarning();
      setAfkWarning(true);
    }
  }, [remaining, isMyTurn]);

  const toggleSel = (c: number) => {
    setSelected(s => s.includes(c) ? s.filter(x => x !== c) : [...s, c]);
  };

  // Pose directe de la sélection scannée (trio / carré / escalier / 7 cartes)
  const postSelection = async () => {
    const kind = meldKind(selected, jokerMode, randomJoker);
    if (!kind) return toast.error("Sélection invalide");
    const cards = [...selected];
    setBusy(true);
    try {
      const { error } = await supabase.rpc("rami_meld" as any, { _game_id: id, _cards: cards });
      if (error) throw error;
      setSelected([]);
      sfx.ramiMeld();
      if (kind === 'seven') {
        setSevenFx(MELD_LABEL.seven);
        setTimeout(() => setSevenFx(null), 3500);
        toast.success("🎊 7 cartes validées — ta mise t'est remboursée !");
      } else {
        toast.success(`✓ ${MELD_LABEL[kind]} validé`);
      }
    } catch (e: any) {
      toast.error(e.message || "Combinaison invalide");
    } finally { setBusy(false); }
  };

  // ── 7 cartes : le joueur clique lui-même ses combinaisons posées ───────
  const [pickedMelds, setPickedMelds] = useState<number[]>([]);
  const [showDiscardHistory, setShowDiscardHistory] = useState(false);
  const usedExtraTime = !!(profile?.id && (game?.state?.extra_time || {})[profile.id]);

  const toggleMeldPick = (i: number) =>
    setPickedMelds(p => p.includes(i) ? p.filter(x => x !== i) : [...p, i]);

  const alreadySeven = useMemo(
    () => melds.some(m => m.player === profile?.id && (m as { seven?: boolean }).seven === true),
    [melds, profile?.id],
  );

  const canClaimSeven = useMemo(() => {
    if (!profile?.id || alreadySeven || pickedMelds.length < 2) return false;
    const picked = pickedMelds.map(i => melds[i]).filter(Boolean);
    if (picked.some(m => m.player !== profile.id)) return false;
    const combo = picked.flatMap(m => m.cards);
    return combo.length === 7 && isSevenCombo(combo, jokerMode, randomJoker);
  }, [melds, pickedMelds, profile?.id, alreadySeven, jokerMode, randomJoker]);

  const claimSeven = async () => {
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("rami_claim_seven" as any, { _game_id: id } as any);
      if (error) throw error;
      if (data) {
        setPickedMelds([]);
        setSevenFx(MELD_LABEL.seven);
        setTimeout(() => setSevenFx(null), 3500);
        toast.success("🎊 7 cartes validées — ta mise t'est remboursée !");
      } else {
        toast.error("Pas de 7 cartes valide sur tes combinaisons");
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
    sfx.ramiDraw();
    await call("rami_draw", { _game_id: id, _from: "deck" });
    setTimeout(() => setCardFx(null), 650);
  };
  const drawDiscard = async () => {
    const pile = discards[lastDiscardBy] || [];
    const top = pile[pile.length - 1];
    const from = centerOf(discardRefs.current[lastDiscardBy]);
    const to = centerOf(handRef.current);
    setCardFx({ card: top, from, to });
    sfx.ramiDraw();
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
      sfx.ramiMeld();
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
    sfx.ramiDiscard();
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
    sfx.ramiWin();
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
    if (!isMyTurn || phase !== "play") return toast.info("Tu ne peux modifier tes combinaisons que pendant ton tour");
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
    navigate({ to: "/jeux/rami/$id", params: { id: data as string } });
  };

  if (game.status === "cancelled") {
    return <GameStateMessage state="cancelled" gameLabel="Rami" slug="rami" />;
  }

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
        <GameSocialFab gameId={id} gameSlug="rami" participants={parts} />
      </main>
    );
  }

  const drawablePile = (discards[lastDiscardBy] || []).length > 0
    ? discards[lastDiscardBy]
    : (Object.values(discards).find(p => Array.isArray(p) && p.length > 0) || []);
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
    <main
      className="max-w-3xl mx-auto px-3 py-2 space-y-2 h-full overflow-hidden overscroll-none rounded-xl"
      style={{
        backgroundImage: `linear-gradient(rgba(0,0,0,0.25), rgba(0,0,0,0.35)), url(${FELT_URL})`,
        backgroundSize: "cover",
        backgroundPosition: "center",
        boxShadow: "inset 0 0 60px rgba(0,0,0,0.45), 0 0 0 6px #0f3d20, 0 8px 24px rgba(0,0,0,0.4)",
      }}
    >
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      <div className="rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5">
        <div className="flex items-baseline gap-1 min-w-0">
          <span className="text-[8px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
          <span className="text-xs font-extrabold truncate">{Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar</span>
        </div>
        {!me ? (
          <div className="px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1">
            Spectateur
          </div>
        ) : (
          <div className="flex items-center gap-1">
            {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
              <button
                onClick={async () => {
                  const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "rami", _game_id: id } as any);
                  if (error) toast.error(error.message);
                  else toast.success("Partie en pause");
                }}
                className="px-2 py-0.5 rounded-full bg-amber-500 text-white text-[10px] font-semibold flex items-center gap-0.5"
              >
                <Pause className="w-2.5 h-2.5" /> Pause
              </button>
            )}
            <button onClick={() => setBoardTheme(boardTheme === "green" ? "blue" : boardTheme === "blue" ? "dark" : "green")} className="w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition" title="Changer le thème du plateau">
              <Palette className="w-3 h-3" />
            </button>
            <button onClick={() => { const m = !soundOn; setSoundOn(m); setSfxMuted(m); }} className="w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition">
              {soundOn ? <Volume2 className="w-3 h-3" /> : <VolumeX className="w-3 h-3" />}
            </button>
            <button onClick={forfeit} className="px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5">
              <LogOut className="w-2.5 h-2.5" /> Quitter
            </button>
          </div>
        )}
      </div>

      {isSpectating && !isPlayer && (
        <div className="fixed top-14 left-1/2 -translate-x-1/2 z-[140] px-4 py-1.5 rounded-full bg-blue-500/90 text-white text-xs font-bold flex items-center gap-2 shadow-lg">
          <Eye className="w-3.5 h-3.5" /> Mode spectateur
        </div>
      )}
      {afkWarning && isMyTurn && game?.status === "playing" && (
        <div className="fixed top-14 left-1/2 -translate-x-1/2 z-[150] px-4 py-2 rounded-full bg-destructive text-white text-xs font-bold flex items-center gap-2 animate-pulse shadow-lg">
          <Timer className="w-3.5 h-3.5" /> Attention ! Plus que {remaining}s pour jouer
        </div>
      )}
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
          melds={game.state?.melds as { player: string; cards: number[]; type?: string }[]}
        />
      )}

      {lbEntries.length > 0 && (
        <RamiLeaderboard entries={lbEntries} meUserId={profile?.id} onReset={resetLb} />
      )}

      {/* ── PANEL SCORE FLOTTANT ── */}
      {game?.status === "playing" && me && (
        <div className="fixed top-16 right-3 z-50 pointer-events-none">
          <div className="pointer-events-auto rounded-2xl bg-black/75 backdrop-blur-md border border-white/10 shadow-2xl p-2.5 space-y-1.5 w-[140px]">
            <div className="flex items-center justify-between text-[9px] font-bold text-white/50 uppercase tracking-wider">
              <span>Score</span>
              <span className="text-amber-400">Partie</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/70 font-semibold">Pot</span>
              <span className="text-xs font-black text-amber-400">{Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/70 font-semibold">Pioche</span>
              <span className="text-[10px] font-bold text-emerald-400">{deckCount} cartes</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/70 font-semibold">Mes combos</span>
              <span className="text-[10px] font-bold text-blue-400">{melds.filter(m => m.player === profile?.id).length}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/70 font-semibold">Mes points</span>
              <span className="text-[10px] font-bold text-white">{handPoints} pts</span>
            </div>
            <div className="h-px bg-white/10" />
            <div className="flex items-center justify-between">
              <span className="text-[10px] text-white/70 font-semibold">Joueurs</span>
              <span className="text-[10px] font-bold text-white">{parts.length}</span>
            </div>
          </div>
        </div>
      )}

      {/* ── PLATEAU FEUTRE (style classique) ── */}
      {game?.status === "playing" && (() => {
        const sorted = parts.slice().sort((a, b) => a.slot - b.slot);
        const meIdx = sorted.findIndex(p => p.user_id === profile?.id);
        const others = meIdx >= 0
          ? [...sorted.slice(meIdx + 1), ...sorted.slice(0, meIdx)]
          : sorted;
        const seatFor = (i: number): "left" | "top" | "right" => {
          if (others.length === 1) return "top";
          if (others.length === 2) return i === 0 ? "left" : "right";
          return (["left", "top", "right"] as const)[i] ?? "top";
        };
        const keyOf = (p: typeof sorted[number]) => (p.user_id as string) || `bot:${p.slot}`;
        const handLenOf = (uid: string) =>
          Array.isArray(game?.state?.hands?.[uid]) ? game.state.hands[uid].length : 0;

        const TimerRing = ({ seconds, total, turn }: { seconds: number; total: number; turn: boolean }) => {
          if (!turn) return null;
          const pct = Math.max(0, Math.min(1, seconds / total));
          const r = 16;
          const circ = 2 * Math.PI * r;
          const offset = circ * (1 - pct);
          const color = seconds <= 5 ? "#ef4444" : seconds <= 10 ? "#f59e0b" : "#22c55e";
          return (
            <svg className="absolute -inset-1 pointer-events-none" viewBox="0 0 40 40" style={{ width: "100%", height: "100%" }}>
              <circle cx="20" cy="20" r={r} fill="none" stroke="rgba(0,0,0,0.25)" strokeWidth="2.5" />
              <circle
                cx="20" cy="20" r={r} fill="none" stroke={color} strokeWidth="2.5"
                strokeDasharray={circ} strokeDashoffset={offset}
                strokeLinecap="round"
                transform="rotate(-90 20 20)"
                style={{ transition: "stroke-dashoffset 0.5s ease, stroke 0.3s" }}
              />
            </svg>
          );
        };

        const NamePlate = ({ name, count, turn, vertical, timerSec, timerTotal }: { name: string; count: number; turn: boolean; vertical?: boolean; timerSec?: number; timerTotal?: number }) => (
          <div className="relative inline-block">
            {turn && timerSec !== undefined && timerTotal !== undefined && !vertical && (
              <TimerRing seconds={timerSec} total={timerTotal} turn={turn} />
            )}
            <div
              className={`relative px-1.5 py-0.5 rounded-full text-[9px] font-bold whitespace-nowrap border shadow-sm ${
                turn ? "bg-yellow-300 text-black border-yellow-600" : "bg-white/95 text-emerald-950 border-emerald-700"
              }`}
              style={vertical ? { writingMode: "vertical-rl", transform: "rotate(180deg)" } : undefined}
            >
              {name} ({count})
            </div>
            {turn && timerSec !== undefined && timerTotal !== undefined && vertical && (
              <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 text-[8px] font-mono font-bold px-1 rounded-full"
                style={{ color: timerSec <= 5 ? "#ef4444" : timerSec <= 10 ? "#f59e0b" : "#22c55e", background: "rgba(0,0,0,0.6)" }}>
                {timerSec}s
              </div>
            )}
          </div>
        );

        const AvatarBadge = ({ name, isBot, meldCount, turn }: { name: string; isBot: boolean; meldCount: number; turn: boolean }) => {
          const initial = name.charAt(0).toUpperCase();
          const colors = ["#3b82f6", "#ef4444", "#22c55e", "#eab308", "#a855f7", "#ec4899"];
          const colorIdx = name.charCodeAt(0) % colors.length;
          const bg = colors[colorIdx];
          return (
            <div className="flex flex-col items-center gap-0.5">
              <div
                className={`rounded-full flex items-center justify-center font-bold text-white shrink-0 transition-all duration-300 ${
                  turn ? "ring-2 ring-yellow-300 ring-offset-1 ring-offset-emerald-900 shadow-[0_0_12px_rgba(253,224,71,0.6)]" : "ring-1 ring-white/20 shadow-sm"
                }`}
                style={{ width: 28, height: 28, fontSize: 11, background: bg }}
              >
                {isBot ? "🤖" : initial}
              </div>
              {meldCount > 0 && (
                <div className="text-[7px] font-bold text-amber-300 bg-black/50 px-1 rounded-full whitespace-nowrap">
                  {meldCount} combo{meldCount > 1 ? "s" : ""}
                </div>
              )}
            </div>
          );
        };

        const BackFan = ({ n, vertical }: { n: number; vertical?: boolean }) => (
          <div className={`flex ${vertical ? "flex-col" : "flex-row"}`}>
            {Array.from({ length: Math.max(1, Math.min(n, 7)) }).map((_, k) => (
              <div
                key={k}
                className="rounded-[2px] overflow-hidden shrink-0 shadow-sm"
                style={{
                  width: vertical ? 20 : 10,
                  height: vertical ? 10 : 20,
                  marginLeft: !vertical && k > 0 ? -2 : 0,
                  marginTop: vertical && k > 0 ? -2 : 0,
                  border: "0.5px solid rgba(100,80,40,0.3)",
                }}
              >
                <CardBackSVG />
              </div>
            ))}
          </div>
        );

        // Seules MES combinaisons sont visibles ; celles des adversaires restent
        // cachées, sauf un "7 cartes" validé publiquement.
        const nameOfKey = (k: string) => {
          const p = sorted.find(x => ((x.user_id as string) || `bot:${x.slot}`) === k);
          return (p?.display_name || "Joueur").slice(0, 10);
        };
        const isSeven = (m: { type?: string; seven?: boolean }) =>
          m.type === "seven" || m.seven === true;
        const myMelds = melds
          .map((m, i) => ({ m, i }))
          .filter(x => !!profile?.id && x.m.player === profile.id);
        const publicSevenMelds = melds
          .map((m, i) => ({ m, i }))
          .filter(x => (!profile?.id || x.m.player !== profile.id) && isSeven(x.m as any))
          .map(x => ({ ...x, name: nameOfKey(x.m.player) }));


        const MeldRow = ({ m, i, mine }: { m: { player: string; cards: number[]; type?: string }; i: number; mine: boolean }) => {
          const kind = (m.type as Exclude<MeldKind, null>) || meldKind(m.cards, jokerMode, randomJoker);
          const isSevenMeld = kind === "seven" || (m as { seven?: boolean }).seven === true;
          const revealed = mine || isSevenMeld;
          const canLayoff = layoffCandidates.has(i);
          const canBreak = mine && !!isMyTurn && phase === "play" && selected.length === 0 && !busy;
          const picked = pickedMelds.includes(i);
          return (
            <button
              key={`meld-${i}`}
              onClick={() => {
                if (canLayoff) layoff(i);
                else if (mine && !alreadySeven && !canBreak) toggleMeldPick(i);
                else if (canBreak) { if (picked || pickedMelds.length > 0) toggleMeldPick(i); else unmeld(i); }
              }}
              onDoubleClick={() => { if (canBreak) unmeld(i); }}
              disabled={!canLayoff && !mine}
              className={`relative flex rounded-md p-0.5 transition-all ${
                picked
                  ? "ring-2 ring-fuchsia-400 bg-fuchsia-500/10"
                  : isSevenMeld
                    ? "ring-2 ring-amber-400 shadow-[0_0_14px_-4px_rgba(251,191,36,0.9)]"
                    : canLayoff
                      ? "ring-2 ring-emerald-400"
                      : ""

              }`}
            >
              {m.cards.map((c, ci) => (
                <div key={`m-${i}-${ci}`} style={{ marginLeft: ci > 0 ? -16 : 0 }} className="shadow-[2px_0_3px_rgba(0,0,0,0.35)]">
                  <Card c={revealed ? c : undefined} faceDown={!revealed} styleOverride={{ width: 26, height: 38 }} />
                </div>
              ))}
            </button>
          );
        };

        return (
          <div
            className="relative w-full rounded-[22px] overflow-hidden"
            style={{
              height: "46vh",
              minHeight: 300,
              background: `radial-gradient(ellipse at center, ${activeTheme.feltCenter || "#1a6b3a"} 0%, ${activeTheme.feltEdge || "#0b3a1f"} 70%, ${activeTheme.border} 100%)`,
              boxShadow: "inset 0 0 60px rgba(0,0,0,0.45), inset 0 0 100px rgba(0,0,0,0.2), 0 8px 24px rgba(0,0,0,0.3)",
              border: `4px solid ${activeTheme.border}`,
            }}
          >
            {/* Subtle felt markings */}
            <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-[0.08]" preserveAspectRatio="none">
              <ellipse cx="50%" cy="50%" rx="35%" ry="38%" fill="none" stroke="white" strokeWidth="1" />
              <circle cx="50%" cy="50%" r="40" fill="none" stroke="white" strokeWidth="0.5" strokeDasharray="3 5" />
            </svg>
            {/* Subtle vignette overlay for depth */}
            <div className="absolute inset-0 pointer-events-none rounded-[22px]" style={{ background: "radial-gradient(ellipse at center, transparent 30%, rgba(0,0,0,0.25) 100%)" }} />
            {/* Adversaires sur les bords */}
            {others.map((p, i) => {
              const seat = seatFor(i);
              const turn = game.current_turn === p.slot;
              const n = handLenOf(keyOf(p));
              const name = (p.display_name || "Joueur").slice(0, 10);
              const meldCountOf = (uid: string) => melds.filter(m => m.player === uid).length;
              if (seat === "top") {
                return (
                  <div key={keyOf(p)} className="absolute top-1 left-1/2 -translate-x-1/2 flex flex-col items-center gap-0.5">
                    <div className="flex items-center gap-1">
                      <AvatarBadge name={name} isBot={!!p.is_bot} meldCount={meldCountOf(p.user_id || "")} turn={turn} />
                      <BackFan n={n} />
                    </div>
                    {turn ? (
                      <NamePlate name={name} count={n} turn={turn} timerSec={remaining} timerTotal={cfg.turn_timer_seconds} />
                    ) : (
                      <NamePlate name={name} count={n} turn={turn} />
                    )}
                  </div>
                );
              }
              return (
                <div
                  key={keyOf(p)}
                  className={`absolute top-1/2 -translate-y-1/2 flex items-center gap-1 ${seat === "left" ? "left-1" : "right-1 flex-row-reverse"}`}
                >
                  <AvatarBadge name={name} isBot={!!p.is_bot} meldCount={meldCountOf(p.user_id || "")} turn={turn} />
                  <BackFan n={n} vertical />
                  <NamePlate name={name} count={n} turn={turn} vertical timerSec={turn ? remaining : undefined} timerTotal={cfg.turn_timer_seconds} />
                </div>
              );
            })}

            {/* Pioche / Défausse — CENTRE du plateau */}
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <div className="flex items-end gap-3 pointer-events-auto">
                <div className="flex flex-col items-center gap-0.5">
                  <button
                    ref={deckRef}
                    disabled={!isMyTurn || phase !== "draw" || busy || deckCount === 0}
                    onClick={drawDeck}
                    className={`relative rounded-md disabled:opacity-60 active:scale-95 transition-all ${
                      isMyTurn && phase === "draw" && deckCount > 0 ? "ring-2 ring-yellow-300 shadow-lg" : ""
                    }`}
                  >
                    <Card faceDown styleOverride={{ width: 38, height: 55 }} />
                  </button>
                  <div className="flex flex-col items-center gap-0.5">
                      <span className="text-[9px] font-semibold text-white/95 bg-black/60 backdrop-blur px-2 py-0.5 rounded-full">Pioche · {deckCount}</span>
                      <div className="w-12 h-1 rounded-full bg-black/40 overflow-hidden">
                        <div className="h-full bg-amber-400 rounded-full transition-all duration-300" style={{ width: `${Math.min(100, (deckCount / 112) * 100)}%` }} />
                      </div>
                    </div>
                </div>

                <div className="flex flex-col items-center gap-0.5">
                  <div className="flex items-end gap-1">
                    <button
                      disabled={!(isMyTurn && phase === "draw" && !busy && topDiscard !== undefined)}
                      onClick={drawDiscard}
                      className={`relative rounded-md active:scale-95 transition-all ${
                        isMyTurn && phase === "draw" && topDiscard !== undefined ? "ring-2 ring-emerald-300 shadow-lg" : ""
                      } ${flashDiscards.includes(lastDiscardBy) ? "ring-2 ring-amber-400" : ""}`}
                    >
                      <div ref={(el) => { discardRefs.current[lastDiscardBy] = el; if (profile?.id) discardRefs.current[profile.id] = el; }}>
                        {topDiscard !== undefined
                          ? <Card c={topDiscard} styleOverride={{ width: 38, height: 55 }} />
                          : <div className="rounded-md border border-dashed border-white/40" style={{ width: 38, height: 55 }} />}
                      </div>
                    </button>
                    <button
                      onClick={() => setShowDiscardHistory(true)}
                      className="w-5 h-5 rounded-full bg-black/60 text-white text-[10px] font-bold flex items-center justify-center border border-white/30"
                      title="Historique de la défausse"
                    >
                      ⋯
                    </button>
                  </div>
                  <span className="text-[9px] font-semibold text-white/95 bg-black/60 backdrop-blur px-2 py-0.5 rounded-full">Défausse</span>
                </div>

                {randomJoker !== null && (
                  <div className="flex flex-col items-center gap-0.5">
                    <Card c={randomJoker} styleOverride={{ width: 38, height: 55 }} />
                    <span className="text-[9px] font-semibold text-amber-300 bg-black/60 backdrop-blur px-2 py-0.5 rounded-full">Joker</span>
                  </div>
                )}
              </div>
            </div>

            {/* 7 cartes révélés publiquement (adversaires) — en haut */}
            {publicSevenMelds.length > 0 && (
              <div className="absolute top-9 inset-x-2 flex flex-wrap justify-center gap-1.5">
                {publicSevenMelds.map(({ m, i, name }) => (
                  <div key={`pub-${i}`} className="flex flex-col items-center">
                    <span className="text-[8px] font-bold text-amber-300">🎊 {name}</span>
                    <MeldRow m={m} i={i} mine={false} />
                  </div>
                ))}
              </div>
            )}

            {/* Mes combinaisons — sans cadre, au-dessus de ma plaque */}
            <div className="absolute bottom-8 inset-x-2 overflow-x-auto">
              {myMelds.length === 0 ? (
                <div className="text-center text-white/35 text-[9px]">Aucune combinaison posée</div>
              ) : (
                <div className="flex items-end justify-center gap-2 min-w-max px-1">
                  {myMelds.map(({ m, i }) => <MeldRow key={i} m={m} i={i} mine />)}
                </div>
              )}
            </div>


            {/* Ma plaque nom en bas */}
            {me && (
              <div className="absolute bottom-1 left-1/2 -translate-x-1/2 flex items-center gap-1.5">
                <NamePlate
                  name={(profile?.pseudo as string) || "Moi"}
                  count={handCards.length}
                  turn={!!isMyTurn}
                  timerSec={isMyTurn ? remaining : undefined}
                  timerTotal={cfg.turn_timer_seconds}
                />
                {isMyTurn && (
                  <span className={`px-1.5 py-0.5 rounded-full text-[9px] font-mono font-bold ${isUrgent ? "bg-destructive text-white" : "bg-black/70 text-white"}`}>
                    {Math.floor(remaining / 60)}:{String(remaining % 60).padStart(2, "0")}
                    {usedExtraTime ? " · dernière chance" : ""}
                  </span>
                )}
              </div>
            )}
          </div>
        );
      })()}

      {/* Historique de la défausse */}
      {showDiscardHistory && (
        <div
          className="fixed inset-0 z-[200] bg-black/70 flex items-end sm:items-center justify-center p-3"
          onClick={() => setShowDiscardHistory(false)}
        >
          <div
            className="w-full max-w-md rounded-2xl bg-card text-card-foreground p-3 max-h-[70vh] overflow-y-auto space-y-3"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <h3 className="font-bold text-sm">Historique de la défausse</h3>
              <button onClick={() => setShowDiscardHistory(false)} className="text-xs font-bold px-2 py-1 rounded-lg bg-muted">
                Fermer
              </button>
            </div>
            {discardEntries.every(e => e.pile.length === 0) ? (
              <p className="text-xs text-muted-foreground">Aucune carte défaussée pour le moment.</p>
            ) : (
              discardEntries.filter(e => e.pile.length > 0).map(entry => (
                <div key={entry.key} className="space-y-1">
                  <div className="text-[11px] font-bold" style={{ color: entry.color }}>
                    {entry.label} · {entry.pile.length} carte{entry.pile.length > 1 ? "s" : ""}
                  </div>
                  <div className="flex flex-wrap gap-1">
                    {entry.pile.map((c, ci) => (
                      <Card key={`h-${entry.key}-${ci}`} c={c} styleOverride={{ width: 28, height: 40 }} />
                    ))}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      )}


      {/* 7 cartes : sélectionner ses combinaisons posées puis réclamer */}
      {!!me && !alreadySeven && pickedMelds.length > 0 && (
        <div className="flex items-center gap-2">
          <button
            onClick={claimSeven}
            disabled={busy || !canClaimSeven}
            className={`flex-1 rounded-xl px-3 py-2 font-black text-xs text-white shadow-lg active:scale-95 ${
              canClaimSeven
                ? "bg-gradient-to-r from-amber-500 to-fuchsia-600 animate-pulse"
                : "bg-white/15 text-white/60"
            }`}
          >
            {canClaimSeven
              ? "🎊 Valider mes 7 cartes — mise remboursée"
              : `Sélection : ${pickedMelds.reduce((s, i) => s + (melds[i]?.cards.length || 0), 0)}/7 cartes`}
          </button>
          <button
            onClick={() => setPickedMelds([])}
            className="px-2.5 py-2 rounded-xl bg-black/40 text-white text-[11px] font-bold"
          >
            Annuler
          </button>
        </div>
      )}





      {/* ── MY HAND ── */}
      {me && (
        <div className="space-y-2">
          {/* Sort buttons */}
          {handCards.length > 0 && !reorderMode && (
            <div className="flex items-center gap-1.5 px-1">
              <span className="text-[9px] font-bold text-white/50 uppercase tracking-wider">Trier</span>
              <button
                onClick={() => { setSortMode(sortMode === "suit" ? "none" : "suit"); setCustomOrder(null); }}
                className={`px-2 py-0.5 rounded-full text-[10px] font-bold transition-all active:scale-90 ${
                  sortMode === "suit" ? "bg-emerald-500 text-white shadow-md" : "bg-white/15 text-white/70 hover:bg-white/25"
                }`}
              >
                ♠ Par couleur
              </button>
              <button
                onClick={() => { setSortMode(sortMode === "rank" ? "none" : "rank"); setCustomOrder(null); }}
                className={`px-2 py-0.5 rounded-full text-[10px] font-bold transition-all active:scale-90 ${
                  sortMode === "rank" ? "bg-emerald-500 text-white shadow-md" : "bg-white/15 text-white/70 hover:bg-white/25"
                }`}
              >
                7 Par valeur
              </button>
              {sortMode !== "none" && (
                <button
                  onClick={() => { setSortMode("none"); setCustomOrder(null); }}
                  className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-white/10 text-white/50 hover:bg-white/20 active:scale-90"
                >
                  ✕ Annuler
                </button>
              )}
              <div className="flex-1" />
              <button
                onClick={() => { setReorderMode(!reorderMode); if (reorderMode) setCustomOrder(null); }}
                className={`px-2 py-0.5 rounded-full text-[10px] font-bold transition-all active:scale-90 ${
                  reorderMode ? "bg-violet-600 text-white shadow-md" : "bg-white/15 text-white/70 hover:bg-white/25"
                }`}
              >
                {reorderMode ? "✓ Fini" : "✋ Réordonner"}
              </button>
            </div>
          )}

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
                const cw = Math.max(38, Math.min(56, Math.floor((avail - (perRow - 1) * 6) / Math.max(perRow, 1))));
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
                            dealDelay={dealAnimating ? i * 100 : undefined}
                            styleOverride={{ width: `${cw}px`, height: `${ch}px`, pointerEvents: dnd.drag ? "none" : undefined }}
                          />
                          {playableCards.has(c) && !isSel && (
                            <div className="absolute inset-0 rounded-md ring-2 ring-amber-400/70 shadow-[0_0_10px_rgba(251,191,36,0.5)] pointer-events-none animate-pulse" style={{ width: `${cw}px`, height: `${ch}px` }} />
                          )}
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

              {/* Bouton flottant : apparaît dès 3+ cartes sélectionnées */}
              {selected.length >= 3 && (
                <div className="fixed inset-x-0 bottom-4 z-40 flex justify-center px-4 pointer-events-none">
                  <div className="pointer-events-auto flex items-center gap-2 rounded-full bg-black/70 backdrop-blur-md p-1.5 shadow-2xl border border-white/10 animate-scale-in">
                    <button
                      onClick={() => postSelection()}
                      disabled={busy}
                      className={`flex items-center gap-1.5 px-4 py-2.5 rounded-full font-black text-sm active:scale-95 transition-all ${
                        selectionKind === "seven"
                          ? "bg-gradient-to-r from-amber-500 to-fuchsia-600 text-white"
                          : selectionKind
                            ? "bg-emerald-600 text-white"
                            : "bg-white/15 text-white/70"
                      }`}
                    >
                      <Check className="w-4 h-4" />
                      {selectionKind === "seven"
                        ? "7 cartes validé"
                        : selectionKind
                          ? `Valider le ${MELD_LABEL[selectionKind]}`
                          : `Valider (${selected.length})`}
                    </button>
                    <button
                      onClick={() => setSelected([])}
                      className="w-9 h-9 rounded-full bg-white/10 text-white/80 flex items-center justify-center active:scale-95"
                      aria-label="Annuler la sélection"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              )}


              {sevenFx && (
                <div className="fixed inset-x-0 top-20 z-50 flex justify-center pointer-events-none">
                  <div className="px-5 py-3 rounded-2xl bg-gradient-to-r from-amber-500 to-fuchsia-600 text-white font-black text-sm shadow-xl animate-[bounce_1s_ease-in-out_2]">
                    🎊 7 Cartes — Miverim-bola ! <span className="font-semibold opacity-90">({sevenFx})</span>
                  </div>
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
                      {selectionValidity === 'valid' && (
                        <span className="meld-valid-badge px-2 py-0.5 rounded-full bg-emerald-500 text-white text-[10px] font-black shadow-sm">
                          ✓ {selectionKind ? MELD_LABEL[selectionKind] : 'Valide'} — prêt à poser
                        </span>
                      )}
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
                  {isSeven && (
                    <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-gradient-to-r from-amber-500/20 to-fuchsia-500/20 border border-amber-400/40 animate-pulse">
                      <span className="text-lg">🎊</span>
                      <span className="text-[11px] font-black tracking-wide text-amber-300">7 Cartes — Miverim-bola</span>
                    </div>
                  )}
                  <div className="flex gap-2 overflow-x-auto pb-1">
                    {selected.map((c, i) => <Card key={`sel-${c}-${i}`} c={c} size="md" />)}
                  </div>
                  <div className="flex gap-2 flex-wrap">
                    {selected.length >= 3 && (
                      <button onClick={() => postSelection()} disabled={busy}
                        className={`flex items-center gap-1.5 px-4 py-2.5 rounded-xl font-black text-sm shadow-md active:scale-95 transition-all animate-scale-in ${
                          selectionKind === 'seven'
                            ? "bg-gradient-to-r from-amber-500 to-fuchsia-600 text-white shadow-amber-600/30"
                            : "bg-emerald-600 text-white shadow-emerald-600/30 hover:bg-emerald-500"
                        }`}>
                        <Check className="w-4 h-4" />
                        {selectionKind === 'seven'
                          ? "7 cartes validé"
                          : selectionKind
                            ? `Valider le ${MELD_LABEL[selectionKind]}`
                            : "Valider la combinaison"}
                      </button>
                    )}

                    <button onClick={addToStaged} disabled={busy || selected.length < 3}
                      className="flex items-center gap-1.5 px-3 py-2.5 rounded-xl bg-white/8 text-foreground font-semibold text-sm disabled:opacity-40 hover:bg-white/12 active:scale-95 transition-all">
                      <Plus className="w-4 h-4" /> Préparer
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
    </main>

  );
}
