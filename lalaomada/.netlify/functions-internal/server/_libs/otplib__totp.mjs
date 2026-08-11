import { X as Xr, d as dr, v as vr, O as Or, A as Ar, C as Cr, S as Sr, w as wr, U as Ur, J, Q, Z as Z$1, h as hr } from "./otplib__core.mjs";
import { F } from "./otplib__hotp.mjs";
function k(r) {
  let { secret: e, epoch: n = Math.floor(Date.now() / 1e3), t0: o = 0, period: i = 30, algorithm: s = "sha1", digits: l = 6, crypto: a, base32: u, guardrails: c = hr(), hooks: t } = r;
  Xr(e), dr(a);
  let p = vr(e, u);
  Or(p, c), Ar(n), Cr(i, c);
  let f = Math.floor((n - o) / i);
  return { secret: p, counter: f, algorithm: s, digits: l, crypto: a, guardrails: c, hooks: t };
}
function Z(r) {
  let e = k(r);
  return F(e);
}
function _(r, e) {
  if (r !== void 0) {
    if (r < 0) throw new J();
    if (!Number.isSafeInteger(r)) throw new Q();
    if (r > e) throw new Z$1();
  }
}
function w(r, e) {
  return e !== void 0 && r <= e;
}
function R(r) {
  let { secret: e, token: n, epoch: o = Math.floor(Date.now() / 1e3), t0: i = 0, period: s = 30, algorithm: l = "sha1", digits: a = 6, crypto: u, base32: c, epochTolerance: t = 0, afterTimeStep: p, guardrails: f = hr(), hooks: T } = r;
  Xr(e), dr(u);
  let m = vr(e, c);
  Or(m, f), Ar(o), Cr(s, f), T?.validateToken ? T.validateToken(n, a) : Sr(n, a), wr(t, s, f);
  let M = Math.floor((o - i) / s), [I, q] = Ur(t), A = Math.max(0, Math.floor((o - I - i) / s)), S = Math.floor((o + q - i) / s);
  return _(p, S), { token: n, crypto: u, minCounter: A, maxCounter: S, currentCounter: M, t0: i, period: s, afterTimeStep: p, getGenerateOptions: (D) => ({ secret: m, epoch: D * s + i, t0: i, period: s, algorithm: l, digits: a, crypto: u, guardrails: f, hooks: T }) };
}
function ie(r) {
  let { token: e, crypto: n, minCounter: o, maxCounter: i, currentCounter: s, t0: l, period: a, afterTimeStep: u, getGenerateOptions: c } = R(r);
  for (let t = o; t <= i; t++) {
    if (w(t, u)) continue;
    let p = Z(c(t));
    if (n.constantTimeEqual(p, e)) return { valid: true, delta: t - s, epoch: t * a + l, timeStep: t };
  }
  return { valid: false };
}
export {
  ie as i
};
