import { ReactNode } from "react";
import { useAuth } from "@/hooks/use-auth";
import { Shield } from "lucide-react";

/**
 * AdminSecurityGate — sécurité admin désactivée à la demande.
 * Laisse passer tout utilisateur avec le rôle admin, sans MFA/approbation/lockout.
 */
export default function AdminSecurityGate({ children }: { children: ReactNode }) {
  const { isAdmin, loading } = useAuth();

  if (loading) return null;

  if (!isAdmin) {
    return (
      <main className="min-h-screen flex items-center justify-center p-6">
        <div className="text-center space-y-2">
          <Shield className="w-10 h-10 mx-auto text-muted-foreground" />
          <p className="font-semibold">Accès réservé aux administrateurs</p>
        </div>
      </main>
    );
  }

  return <>{children}</>;
}
