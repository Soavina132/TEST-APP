import { D as Dr, a, h as hr } from "./otplib__core.mjs";
import { Y } from "./otplib__hotp.mjs";
import { i as ie } from "./otplib__totp.mjs";
import { U, x } from "./otplib__uri.mjs";
import { d as d$1 } from "./otplib__plugin-base32-scure.mjs";
import { A } from "./otplib__plugin-crypto-noble.mjs";
function c(t) {
  return { secret: t.secret, strategy: t.strategy ?? "totp", crypto: t.crypto ?? A, base32: t.base32 ?? d$1, algorithm: t.algorithm ?? "sha1", digits: t.digits ?? 6, period: t.period ?? 30, epoch: t.epoch ?? Math.floor(Date.now() / 1e3), t0: t.t0 ?? 0, counter: t.counter, guardrails: t.guardrails ?? hr(), hooks: t.hooks };
}
function O(t) {
  return { ...c(t), token: t.token, epochTolerance: t.epochTolerance ?? 0, counterTolerance: t.counterTolerance ?? 0, afterTimeStep: t.afterTimeStep };
}
function l(t, e, r) {
  if (t === "totp") return r.totp();
  if (t === "hotp") {
    if (e === void 0) throw new a("Counter is required for HOTP strategy. Example: { strategy: 'hotp', counter: 0 }");
    return r.hotp(e);
  }
  throw new a(`Unknown OTP strategy: ${t}. Valid strategies are 'totp' or 'hotp'.`);
}
function I(t) {
  let { crypto: e = A, base32: r = d$1, length: a2 = 20 } = {};
  return Dr({ crypto: e, base32: r, length: a2 });
}
function T(t) {
  let { strategy: e = "totp", issuer: r, label: a2, secret: o, algorithm: i = "sha1", digits: s = 6, period: n = 30, counter: p } = t;
  return l(e, p, { totp: () => x({ issuer: r, label: a2, secret: o, algorithm: i, digits: s, period: n }), hotp: (y) => U({ issuer: r, label: a2, secret: o, algorithm: i, digits: s, counter: y }) });
}
function d(t) {
  let e = O(t), { secret: r, token: a2, crypto: o, base32: i, algorithm: s, digits: n, hooks: p } = e, y = { secret: r, token: a2, crypto: o, base32: i, algorithm: s, digits: n, hooks: p };
  return l(e.strategy, e.counter, { totp: () => ie({ ...y, period: e.period, epoch: e.epoch, t0: e.t0, epochTolerance: e.epochTolerance, afterTimeStep: e.afterTimeStep, guardrails: e.guardrails }), hotp: (f) => Y({ ...y, counter: f, counterTolerance: e.counterTolerance, guardrails: e.guardrails }) });
}
export {
  I,
  T,
  d
};
