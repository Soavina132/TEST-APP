import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { P as PhoneVerifyPopup } from "./PhoneVerifyPopup-CibtDuiJ.mjs";
import { aI as ShieldAlert, X } from "../_libs/lucide-react.mjs";
function PhoneVerifyBanner({ stake, phoneVerified }) {
  const [showPopup, setShowPopup] = reactExports.useState(false);
  const [dismissed, setDismissed] = reactExports.useState(false);
  if (stake <= 0 || dismissed || phoneVerified) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => setShowPopup(true),
        className: "w-full flex items-center gap-2 px-3 py-2 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 text-xs font-medium active:scale-[0.98] transition animate-pulse-slow",
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldAlert, { className: "w-4 h-4 shrink-0" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 text-left", children: "Vérifiez votre numéro pour jouer avec mise" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold underline", children: "Vérifier →" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "span",
            {
              role: "button",
              tabIndex: -1,
              onClick: (e) => {
                e.stopPropagation();
                setDismissed(true);
              },
              className: "shrink-0 p-0.5 hover:bg-amber-500/20 rounded-full transition",
              children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3.5 h-3.5" })
            }
          )
        ]
      }
    ),
    showPopup && /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyPopup, { onClose: () => setShowPopup(false) })
  ] });
}
export {
  PhoneVerifyBanner as P
};
