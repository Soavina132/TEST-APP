import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { a as useT } from "./router-CRCBvenY.mjs";
function AdminRenameDialog({ open, defaultName, onCancel, onConfirm }) {
  const { t } = useT();
  const [name, setName] = reactExports.useState(defaultName);
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4", onClick: onCancel, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-3xl p-6 max-w-md w-full space-y-4", onClick: (e) => e.stopPropagation(), children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("h2", { className: "text-xl font-extrabold", children: [
      "👑 ",
      t("game_name_title")
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: t("game_name_desc") }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "input",
      {
        autoFocus: true,
        value: name,
        onChange: (e) => setName(e.target.value),
        maxLength: 24,
        placeholder: t("player_pseudo_placeholder"),
        className: "w-full px-4 py-3 rounded-2xl bg-secondary outline-none text-base"
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 justify-end", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onCancel, className: "px-4 py-2 rounded-full bg-secondary font-semibold", children: t("cancel_btn") }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => name.trim().length >= 2 && onConfirm(name.trim()),
          disabled: name.trim().length < 2,
          className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold disabled:opacity-50",
          children: "Continuer"
        }
      )
    ] })
  ] }) });
}
export {
  AdminRenameDialog as A
};
