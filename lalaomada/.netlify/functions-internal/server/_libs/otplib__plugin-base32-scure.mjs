import { b as base32 } from "./scure__base.mjs";
var r = class {
  name = "scure";
  encode(o, e = {}) {
    let { padding: t = false } = e, n = base32.encode(o);
    return t ? n : n.replace(/=+$/, "");
  }
  decode(o) {
    try {
      let e = o.toUpperCase(), t = e.padEnd(Math.ceil(e.length / 8) * 8, "=");
      return base32.decode(t);
    } catch (e) {
      throw new Error(`Invalid Base32 string: ${e.message}`);
    }
  }
}, d = Object.freeze(new r());
export {
  d
};
