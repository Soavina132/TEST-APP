import { supabase } from "@/integrations/supabase/client";

const GROUP_NAME_FOR_SLUG: Record<string, string> = {
  ludo: "Groupe Ludo",
  domino: "Groupe Domino",
  chess: "Groupe Échec",
  fanorona: "Groupe Fanorona",
  rami: "Groupe Rami",
};

export const GAME_SHARE_PREFIX = "[[game-share:";

export function parseGameShare(body: string | null | undefined): { slug: string; gameId: string } | null {
  if (!body) return null;
  const m = body.match(/^\[\[game-share:([a-z]+):([0-9a-f-]{36})\]\]$/i);
  return m ? { slug: m[1], gameId: m[2] } : null;
}

export async function shareNewGameInGroup(slug: string, gameId: string): Promise<void> {
  try {
    const { data: u } = await supabase.auth.getUser();
    const userId = u?.user?.id;
    if (!userId) return;
    const groupName = GROUP_NAME_FOR_SLUG[slug];
    if (!groupName) return;
    const { data: room } = await supabase
      .from("chat_rooms" as any)
      .select("id, enabled")
      .eq("type", "global")
      .eq("name", groupName)
      .maybeSingle();
    if (!room || (room as any).enabled === false) return;
    const roomId = (room as any).id;
    const marker = `${GAME_SHARE_PREFIX}${slug}:${gameId}]]`;
    const { data: existing } = await supabase
      .from("chat_messages" as any)
      .select("id")
      .eq("room_id", roomId)
      .eq("body", marker)
      .limit(1);
    if (existing && (existing as any[]).length > 0) return;
    await supabase.from("chat_messages" as any).insert({
      room_id: roomId,
      user_id: userId,
      body: marker,
    } as any);
  } catch {
    // never block game creation on share failure
  }
}
