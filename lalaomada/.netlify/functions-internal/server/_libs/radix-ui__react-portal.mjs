import { r as reactExports, j as jsxRuntimeExports } from "./react.mjs";
import { r as reactDomExports } from "./react-dom.mjs";
import { P as Primitive } from "./radix-ui__react-primitive.mjs";
import { u as useLayoutEffect2 } from "./@radix-ui/react-use-layout-effect+[...].mjs";
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var Portal = /* @__PURE__ */ reactExports.forwardRef(
  /* @__PURE__ */ __name(function Portal2(props, forwardedRef) {
    const { container: containerProp, ...portalProps } = props;
    const [mounted, setMounted] = reactExports.useState(false);
    useLayoutEffect2(() => setMounted(true), []);
    const container = containerProp || mounted && globalThis?.document?.body;
    return container ? reactDomExports.createPortal(/* @__PURE__ */ jsxRuntimeExports.jsx(Primitive.div, { ...portalProps, ref: forwardedRef }), container) : null;
  }, "Portal")
);
export {
  Portal as P
};
