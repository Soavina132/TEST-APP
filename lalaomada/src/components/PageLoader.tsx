import * as React from "react";

// ═══════════════════════════════════════════════════════════════════════════
// PageLoader — branded loading system for Lalao MADA
// Uses the real Ludo-dot logo with 3D-flip animation, shimmer brand name,
// and a sleek indeterminate progress bar.
// ═══════════════════════════════════════════════════════════════════════════

type Variant = "splash" | "overlay" | "inline";

interface PageLoaderProps {
  variant?: Variant;
  label?: string;
}

function LudoMark({ size = 48 }: { size?: number }) {
  const dot = Math.floor(size * 0.22);
  return (
    <div
      className="lm-mark"
      style={{ width: size, height: size }}
      aria-hidden
    >
      <div className="lm-mark__inner">
        <span className="lm-dot lm-dot--red" style={{ width: dot, height: dot }} />
        <span className="lm-dot lm-dot--green" style={{ width: dot, height: dot }} />
        <span className="lm-dot lm-dot--blue" style={{ width: dot, height: dot }} />
        <span className="lm-dot lm-dot--yellow" style={{ width: dot, height: dot }} />
      </div>
      <div className="lm-mark__glow" />
    </div>
  );
}

function ProgressBar({ width = 140 }: { width?: number }) {
  return (
    <div className="lm-bar" style={{ width }}>
      <div className="lm-bar__fill" />
    </div>
  );
}

function BrandText({ subtitle }: { subtitle?: string }) {
  return (
    <div className="lm-brand">
      <h1 className="lm-brand__title">Lalao MADA</h1>
      {subtitle && <p className="lm-brand__sub">{subtitle}</p>}
    </div>
  );
}

export function PageLoader({ variant = "overlay", label }: PageLoaderProps) {
  if (variant === "splash") {
    return (
      <div className="lm-splash">
        <div className="lm-splash__content">
          <LudoMark size={72} />
          <BrandText subtitle={label ?? "Jouez. Gagnez. Retirez en Ariary."} />
          <div className="lm-splash__dots">
            <span /><span /><span />
          </div>
        </div>
        <div className="lm-splash__shimmer" />
      </div>
    );
  }

  if (variant === "inline") {
    return (
      <div className="lm-inline">
        <LudoMark size={36} />
        <ProgressBar width={100} />
      </div>
    );
  }

  // overlay — used for route transitions
  return (
    <div className="lm-overlay">
      <div className="lm-overlay__content">
        <LudoMark size={52} />
        <BrandText />
        <ProgressBar width={120} />
      </div>
    </div>
  );
}

// Default export for lazy imports
export default PageLoader;

// Hook: returns a boolean that flips true after `delay` ms while `pending` is true
export function useDelayedPending(pending: boolean, delay = 200) {
  const [show, setShow] = React.useState(false);
  React.useEffect(() => {
    if (!pending) {
      setShow(false);
      return;
    }
    const t = setTimeout(() => setShow(true), delay);
    return () => clearTimeout(t);
  }, [pending]);
  return show;
}
