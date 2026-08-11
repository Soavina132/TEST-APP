import { X as Xr, d as dr, v as vr, O as Or, b as br, S as Sr, B as Br, E as Er, R as Rr, I as Ir, _ as _r, W as Wr, h as hr } from "./otplib__core.mjs";
function v(u) {
  let { secret: t, counter: e, algorithm: r = "sha1", digits: i = 6, crypto: n, base32: o, guardrails: a, hooks: s } = u;
  Xr(t), dr(n);
  let c = vr(t, o);
  Or(c, a), br(e, a);
  let p = Wr(n), l = _r(e);
  return { ctx: p, algorithm: r, digits: i, secretBytes: c, counterBytes: l, hooks: s };
}
function F(u) {
  let { ctx: t, algorithm: e, digits: r, secretBytes: i, counterBytes: n, hooks: o } = v(u), a = t.hmacSync(e, i, n), s = o?.truncateDigest ? o.truncateDigest(a) : Rr(a);
  return o?.encodeToken ? o.encodeToken(s, r) : Ir(s, r);
}
function G(u) {
  let { secret: t, counter: e, token: r, algorithm: i = "sha1", digits: n = 6, crypto: o, base32: a, counterTolerance: s = 0, guardrails: c = hr(), hooks: p } = u;
  Xr(t), dr(o);
  let l = vr(t, a);
  Or(l, c), br(e, c), p?.validateToken ? p.validateToken(r, n) : Sr(r, n), Br(s, c);
  let V = typeof e == "bigint" ? Number(e) : e, [f, d] = Er(s), R = f + d + 1;
  return { token: r, counterNum: V, past: f, future: d, totalChecks: R, crypto: o, getGenerateOptions: (B) => ({ secret: l, counter: B, algorithm: i, digits: n, crypto: o, guardrails: c, hooks: p }) };
}
function Y(u) {
  let { token: t, counterNum: e, past: r, totalChecks: i, crypto: n, getGenerateOptions: o } = G(u), a = Math.max(0, r - e);
  for (let s = a; s < i; s++) {
    let c = s - r, p = e + c, l = F(o(p));
    if (n.constantTimeEqual(l, t)) return { valid: true, delta: c | 0 };
  }
  return { valid: false };
}
export {
  F,
  Y
};
