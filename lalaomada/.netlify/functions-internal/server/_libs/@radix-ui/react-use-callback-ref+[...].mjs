import { r as reactExports } from "../react.mjs";
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
function useCallbackRef(callback) {
  const callbackRef = reactExports.useRef(callback);
  reactExports.useEffect(() => {
    callbackRef.current = callback;
  });
  return reactExports.useMemo(() => ((...args) => callbackRef.current?.(...args)), []);
}
__name(useCallbackRef, "useCallbackRef");
export {
  useCallbackRef as u
};
