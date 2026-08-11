import { s as supabase } from "./client-4UYFom1R.mjs";
const GROUP_NAME_FOR_SLUG = {
  ludo: "Groupe Ludo",
  domino: "Groupe Domino",
  chess: "Groupe Échec",
  fanorona: "Groupe Fanorona",
  rami: "Groupe Rami"
};
const GAME_SHARE_PREFIX = "[[game-share:";
function parseGameShare(body) {
  if (!body) return null;
  const m = body.match(/^\[\[game-share:([a-z]+):([0-9a-f-]{36})\]\]$/i);
  return m ? { slug: m[1], gameId: m[2] } : null;
}
async function shareNewGameInGroup(slug, gameId) {
  try {
    const { data: u } = await supabase.auth.getUser();
    const userId = u?.user?.id;
    if (!userId) return;
    const groupName = GROUP_NAME_FOR_SLUG[slug];
    if (!groupName) return;
    const { data: room } = await supabase.from("chat_rooms").select("id, enabled").eq("type", "global").eq("name", groupName).maybeSingle();
    if (!room || room.enabled === false) return;
    const roomId = room.id;
    const marker = `${GAME_SHARE_PREFIX}${slug}:${gameId}]]`;
    const { data: existing } = await supabase.from("chat_messages").select("id").eq("room_id", roomId).eq("body", marker).limit(1);
    if (existing && existing.length > 0) return;
    await supabase.from("chat_messages").insert({
      room_id: roomId,
      user_id: userId,
      body: marker
    });
  } catch {
  }
}
export {
  parseGameShare as p,
  shareNewGameInGroup as s
};
