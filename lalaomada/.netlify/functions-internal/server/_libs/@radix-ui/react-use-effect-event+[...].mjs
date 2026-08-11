import { u as useLayoutEffect2 } from "./react-use-layout-effect+[...].mjs";
import { r as reactExports, b as React } from "../react.mjs";
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var useReactEffectEvent = React[" useEffectEvent ".trim().toString()];
var useReactInsertionEffect = React[" useInsertionEffect ".trim().toString()];
function useEffectEvent(callback) {
  if (typeof useReactEffectEvent === "function") {
    return useReactEffectEvent(callback);
  }
  const ref = reactExports.useRef(() => {
    throw new Error("Cannot call an event handler while rendering.");
  });
  if (typeof useReactInsertionEffect === "function") {
    useReactInsertionEffect(() => {
      ref.current = callback;
    });
  } else {
    useLayoutEffect2(() => {
      ref.current = callback;
    });
  }
  return reactExports.useMemo(() => ((...args) => ref.current?.(...args)), []);
}
__name(useEffectEvent, "useEffectEvent");
export {
  useEffectEvent as u
};
