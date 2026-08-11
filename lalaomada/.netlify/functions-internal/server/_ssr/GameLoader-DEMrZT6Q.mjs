import { j as jsxRuntimeExports } from "../_libs/react.mjs";
import { a as useT } from "./router-CRCBvenY.mjs";
function GameLoader({ retryFn }) {
  const { t } = useT();
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "min-h-[60vh] flex flex-col items-center justify-center gap-4 px-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative w-16 h-16", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 rounded-full border-4 border-muted" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 rounded-full border-4 border-primary border-t-transparent animate-spin" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground font-medium", children: t("loading") }),
    retryFn && /* @__PURE__ */ jsxRuntimeExports.jsx(
      "button",
      {
        onClick: retryFn,
        className: "px-5 py-2.5 rounded-full bg-primary text-primary-foreground text-sm font-semibold active:scale-95 transition",
        children: "Réessayer"
      }
    )
  ] });
}
export {
  GameLoader as G
};
