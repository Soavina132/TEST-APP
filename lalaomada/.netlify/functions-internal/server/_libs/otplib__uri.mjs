function m(r) {
  let { type: e, label: s, params: t } = r, i = s.split(":").map((c) => encodeURIComponent(c)).join(":"), o = `otpauth://${e}/${i}?`, n = [];
  return t.secret && n.push(`secret=${encodeURIComponent(t.secret)}`), t.issuer && n.push(`issuer=${encodeURIComponent(t.issuer)}`), t.algorithm && t.algorithm !== "sha1" && n.push(`algorithm=${t.algorithm.toUpperCase()}`), t.digits && t.digits !== 6 && n.push(`digits=${t.digits}`), e === "hotp" && t.counter !== void 0 && n.push(`counter=${t.counter}`), e === "totp" && t.period !== void 0 && t.period !== 30 && n.push(`period=${t.period}`), o += n.join("&"), o;
}
function x(r) {
  let { issuer: e, label: s, secret: t, algorithm: i = "sha1", digits: o = 6, period: n = 30 } = r, c = e ? `${e}:${s}` : s;
  return m({ type: "totp", label: c, params: { secret: t, issuer: e, algorithm: i, digits: o, period: n } });
}
function U(r) {
  let { issuer: e, label: s, secret: t, counter: i = 0, algorithm: o = "sha1", digits: n = 6 } = r, c = e ? `${e}:${s}` : s;
  return m({ type: "hotp", label: c, params: { secret: t, issuer: e, algorithm: o, digits: n, counter: i } });
}
export {
  U,
  x
};
