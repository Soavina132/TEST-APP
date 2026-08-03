import { Loader2, WifiOff, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";

interface Props {
  isConnected: boolean;
  isReconnecting: boolean;
  onRetry: () => void;
}

/**
 * Full-screen overlay shown when a player loses network during a game.
 * Returns null when connected — zero render cost during normal play.
 */
export function GameReconnectOverlay({ isConnected, isReconnecting, onRetry }: Props) {
  if (isConnected && !isReconnecting) return null;

  return (
    <div className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-5 bg-background/90 backdrop-blur-md">
      {isReconnecting ? (
        <>
          <Loader2 className="h-14 w-14 animate-spin text-primary" />
          <div className="text-center">
            <p className="text-xl font-bold">Reconnexion en cours…</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Reprise de la partie dans un instant
            </p>
          </div>
        </>
      ) : (
        <>
          <div className="rounded-full bg-destructive/10 p-5">
            <WifiOff className="h-12 w-12 text-destructive" />
          </div>
          <div className="text-center">
            <p className="text-xl font-bold">Connexion perdue</p>
            <p className="mt-1 max-w-xs text-sm text-muted-foreground">
              Votre partie est en pause. La reconnexion se fera automatiquement
              dès que le réseau revient.
            </p>
          </div>
          <Button
            variant="outline"
            className="mt-2 gap-2"
            onClick={onRetry}
          >
            <RefreshCw className="h-4 w-4" />
            Réessayer maintenant
          </Button>
        </>
      )}
    </div>
  );
}
