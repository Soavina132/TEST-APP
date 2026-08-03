import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";

export type AdminPending = {
  finance: number;   // pending deposits + withdrawals
  bugs:    number;   // open + in_progress bug reports
  total:   number;   // sum
};

export function useAdminPending(): AdminPending {
  const { isAdmin } = useAuth();
  const [state, setState] = useState<AdminPending>({ finance: 0, bugs: 0, total: 0 });

  useEffect(() => {
    if (!isAdmin) return;

    async function load() {
      const [{ count: dep }, { count: wit }, { count: bug }] = await Promise.all([
        supabase
          .from("deposits")
          .select("*", { count: "exact", head: true })
          .eq("status", "pending"),
        supabase
          .from("withdrawals")
          .select("*", { count: "exact", head: true })
          .eq("status", "pending"),
        (supabase as any)
          .from("bug_reports")
          .select("*", { count: "exact", head: true })
          .in("status", ["open", "in_progress"]),
      ]);
      const finance = (dep ?? 0) + (wit ?? 0);
      const bugs    = bug ?? 0;
      setState({ finance, bugs, total: finance + bugs });
    }

    load();

    const ch = supabase
      .channel("admin-pending-counts")
      .on("postgres_changes", { event: "*", schema: "public", table: "deposits" },    load)
      .on("postgres_changes", { event: "*", schema: "public", table: "withdrawals" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "bug_reports" }, load)
      .subscribe();

    return () => { supabase.removeChannel(ch); };
  }, [isAdmin]);

  return state;
}
