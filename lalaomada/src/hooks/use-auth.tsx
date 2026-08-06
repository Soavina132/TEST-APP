import { createContext, useContext, useEffect, useState, ReactNode } from "react";
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

  const loadProfile = async (uid: string) => {
    const { data: p } = await supabase.from("profiles").select("*").eq("id", uid).maybeSingle();
    setProfile(p as Profile | null);
    const { data: roles } = await supabase.from("user_roles").select("role").eq("user_id", uid);
    setIsAdmin(!!roles?.some((r: any) => r.role === "admin"));
  };

  // Auth session bootstrap + change listener
  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((evt, s) => {
      // Redirect to reset-password page when recovering password via email link
      if (evt === "PASSWORD_RECOVERY") {
        window.location.href = "/reset-password";
        return;
      }
      setSession(s);
      setUser(s?.user ?? null);
      if (s?.user) {
        setTimeout(() => { loadProfile(s.user.id); }, 0);
      } else {
        setProfile(null); setIsAdmin(false);
      }
    });

    supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s);
      setUser(s?.user ?? null);
      if (s?.user) {
        loadProfile(s.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    return () => { sub.subscription.unsubscribe(); };
  }, []);

  // Realtime balance/profile sync — re-subscribed whenever the user changes,
  // plus a transactions INSERT safety net so any credit/debit flushes the profile
  // even if a profiles UPDATE event is missed.
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
  }, [user?.id]);


  const refreshProfile = async () => { if (user) await loadProfile(user.id); };
  const signOut = async () => { await supabase.auth.signOut(); };

  return <Ctx.Provider value={{ user, session, profile, isAdmin, loading, refreshProfile, signOut }}>{children}</Ctx.Provider>;
}

export const useAuth = () => {
  const c = useContext(Ctx);
  if (!c) throw new Error("useAuth must be used inside AuthProvider");
  return c;
};
