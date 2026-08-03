import { createContext, useContext, useEffect, useRef, useState, ReactNode } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { Session, User } from "@supabase/supabase-js";

export type Profile = {
  id: string;
  pseudo: string;
  email: string;
  balance_ar: number;
  referral_code: string;
  referred_by: string | null;
  avatar_url: string | null;
  unique_code: string | null;
  banned: boolean;
  status: string;
  phone?: string | null;
  phone_verified?: boolean;
  phone_verification_code?: string | null;
  terms_accepted_at?: string | null;
  referral_unlocked?: boolean;
  is_premium?: boolean;
};

type AuthCtx = {
  user: User | null;
  session: Session | null;
  profile: Profile | null;
  isAdmin: boolean;
  loading: boolean;
  refreshProfile: () => Promise<void>;
  signOut: () => Promise<void>;
};

const Ctx = createContext<AuthCtx | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);

  // Track whether getSession() has resolved — we only setLoading(false)
  // after that point to avoid a blank flash from an early onAuthStateChange
  // event that fires before the real session is known.
  const sessionResolved = useRef(false);

  const loadProfile = async (uid: string, retries = 5): Promise<void> => {
    const { data: p } = await supabase.from("profiles").select("*").eq("id", uid).maybeSingle();
    if (!p && retries > 0) {
      // Profile not created yet (trigger delay) — retry after short delay
      await new Promise(r => setTimeout(r, 800));
      return loadProfile(uid, retries - 1);
    }
    setProfile(p as Profile | null);
    const { data: roles } = await supabase.from("user_roles").select("role").eq("user_id", uid);
    setIsAdmin(!!roles?.some((r: any) => r.role === "admin"));
  };

  // Auth session bootstrap + change listener
  useEffect(() => {
    // 1. Subscribe to future auth changes (sign-in, sign-out, token refresh…)
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, s) => {
      setSession(s);
      setUser(s?.user ?? null);

      if (s?.user) {
        // Use setTimeout(0) to avoid Supabase deadlock inside the callback
        setTimeout(() => {
          loadProfile(s.user.id).finally(() => {
            // Only unblock the UI once getSession() has already resolved.
            // If it hasn't yet, getSession() will call setLoading(false) itself.
            if (sessionResolved.current) setLoading(false);
          });
        }, 0);
      } else {
        setProfile(null);
        setIsAdmin(false);
        // Same guard: only release loading after getSession() resolved
        if (sessionResolved.current) setLoading(false);
      }
    });

    // 2. Authoritative initial session fetch — this MUST be the source of truth
    //    for the very first render. Once it resolves we mark sessionResolved so
    //    the onAuthStateChange listener above can also call setLoading(false)
    //    for future events (sign-out, token refresh, etc.).
    supabase.auth.getSession().then(({ data: { session: s } }) => {
      sessionResolved.current = true;
      setSession(s);
      setUser(s?.user ?? null);
      if (s?.user) {
        loadProfile(s.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    return () => { sub.subscription.unsubscribe(); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Realtime balance/profile sync
  useEffect(() => {
    if (!user?.id) return;
    const uid = user.id;
    const ch = supabase
      .channel(`profile-live:${uid}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "profiles", filter: `id=eq.${uid}` },
        (payload) => {
          setProfile(prev => prev ? { ...prev, ...(payload.new as Profile) } : (payload.new as Profile));
        }
      )
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "transactions", filter: `user_id=eq.${uid}` },
        () => { loadProfile(uid); }
      )
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const refreshProfile = async () => { if (user) await loadProfile(user.id); };
  const signOut = async () => { await supabase.auth.signOut(); };

  return <Ctx.Provider value={{ user, session, profile, isAdmin, loading, refreshProfile, signOut }}>{children}</Ctx.Provider>;
}

export const useAuth = () => {
  const c = useContext(Ctx);
  if (!c) throw new Error("useAuth must be used inside AuthProvider");
  return c;
};
