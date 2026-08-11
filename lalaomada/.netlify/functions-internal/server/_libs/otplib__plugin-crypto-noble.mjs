import { h as hmac, s as sha1, a as sha256, b as sha512, r as randomBytes } from "./noble__hashes.mjs";
import { t as tr } from "./otplib__core.mjs";
var t = class {
  name = "noble";
  hmac(r, n, a) {
    return hmac(r === "sha1" ? sha1 : r === "sha256" ? sha256 : sha512, n, a);
  }
  randomBytes(r) {
    return randomBytes(r);
  }
  constantTimeEqual(r, n) {
    return tr(r, n);
  }
}, A = Object.freeze(new t());
export {
  A
};
