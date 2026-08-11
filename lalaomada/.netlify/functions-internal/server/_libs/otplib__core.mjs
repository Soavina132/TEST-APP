var i = class extends Error {
  constructor(e, t) {
    super(e, t), this.name = "OTPError";
  }
}, x = class extends i {
  constructor(e) {
    super(e), this.name = "SecretError";
  }
}, h = class extends x {
  constructor(e, t) {
    super(`Secret must be at least ${e} bytes (${e * 8} bits), got ${t} bytes`), this.name = "SecretTooShortError";
  }
}, P = class extends x {
  constructor(e, t) {
    super(`Secret must not exceed ${e} bytes, got ${t} bytes`), this.name = "SecretTooLongError";
  }
}, m = class extends i {
  constructor(e) {
    super(e), this.name = "CounterError";
  }
}, O = class extends m {
  constructor() {
    super("Counter must be non-negative"), this.name = "CounterNegativeError";
  }
}, T = class extends m {
  constructor() {
    super("Counter exceeds maximum safe integer value"), this.name = "CounterOverflowError";
  }
}, b = class extends m {
  constructor() {
    super("Counter must be a finite integer"), this.name = "CounterNotIntegerError";
  }
}, A = class extends i {
  constructor(e) {
    super(e), this.name = "TimeError";
  }
}, C = class extends A {
  constructor() {
    super("Time must be non-negative"), this.name = "TimeNegativeError";
  }
}, S = class extends A {
  constructor() {
    super("Time must be a finite number"), this.name = "TimeNotFiniteError";
  }
}, B = class extends i {
  constructor(e) {
    super(e), this.name = "PeriodError";
  }
}, w = class extends B {
  constructor(e) {
    super(`Period must be at least ${e} second(s)`), this.name = "PeriodTooSmallError";
  }
}, _ = class extends B {
  constructor(e) {
    super(`Period must not exceed ${e} seconds`), this.name = "PeriodTooLargeError";
  }
}, R = class extends i {
  constructor(e) {
    super(e), this.name = "TokenError";
  }
}, I = class extends R {
  constructor(e, t) {
    super(`Token must be ${e} digits, got ${t}`), this.name = "TokenLengthError";
  }
}, M = class extends R {
  constructor() {
    super("Token must contain only digits"), this.name = "TokenFormatError";
  }
}, N = class extends i {
  constructor(e, t) {
    super(e, t), this.name = "CryptoError";
  }
}, c = class extends N {
  constructor(e, t) {
    super(`HMAC computation failed: ${e}`, t), this.name = "HMACError";
  }
}, v = class extends N {
  constructor(e, t) {
    super(`Random byte generation failed: ${e}`, t), this.name = "RandomBytesError";
  }
}, g = class extends i {
  constructor(e) {
    super(e), this.name = "CounterToleranceError";
  }
}, U = class extends g {
  constructor(e, t) {
    super(`Counter tolerance validation failed: total checks (${t}) exceeds MAX_WINDOW (${e})`), this.name = "CounterToleranceTooLargeError";
  }
}, X = class extends g {
  constructor() {
    super("Counter tolerance cannot contain negative values"), this.name = "CounterToleranceNegativeError";
  }
}, E = class extends i {
  constructor(e) {
    super(e), this.name = "EpochToleranceError";
  }
}, k = class extends E {
  constructor() {
    super("Epoch tolerance cannot contain negative values"), this.name = "EpochToleranceNegativeError";
  }
}, q = class extends E {
  constructor(e, t) {
    super(`Epoch tolerance must not exceed ${e} seconds, got ${t}. Large tolerances can cause performance issues.`), this.name = "EpochToleranceTooLargeError";
  }
}, G = class extends i {
  constructor(e) {
    super(e), this.name = "PluginError";
  }
}, Y = class extends G {
  constructor() {
    super("Crypto plugin is required."), this.name = "CryptoPluginMissingError";
  }
}, L = class extends G {
  constructor() {
    super("Base32 plugin is required."), this.name = "Base32PluginMissingError";
  }
}, a = class extends i {
  constructor(e) {
    super(e), this.name = "ConfigurationError";
  }
}, W = class extends a {
  constructor() {
    super("Secret is required. Use generateSecret() to create one, or provide via { secret: 'YOUR_BASE32_SECRET' }"), this.name = "SecretMissingError";
  }
}, f = class extends i {
  constructor(e) {
    super(e), this.name = "AfterTimeStepError";
  }
}, J = class extends f {
  constructor() {
    super("afterTimeStep must be >= 0"), this.name = "AfterTimeStepNegativeError";
  }
}, Q = class extends f {
  constructor() {
    super("Invalid afterTimeStep: non-integer value"), this.name = "AfterTimeStepNotIntegerError";
  }
}, Z = class extends f {
  constructor() {
    super("Invalid afterTimeStep: cannot be greater than current time step plus window"), this.name = "AfterTimeStepRangeExceededError";
  }
};
var yr = new TextEncoder();
new TextDecoder();
var or = 16, sr = 64, ir = 20, ar = 1, ur = 3600, cr = 30, pr = Number.MAX_SAFE_INTEGER, lr = 99, er = /* @__PURE__ */ Symbol("otplib.guardrails.override");
var d = Object.freeze({ MIN_SECRET_BYTES: or, MAX_SECRET_BYTES: sr, MIN_PERIOD: ar, MAX_PERIOD: ur, MAX_COUNTER: pr, MAX_WINDOW: lr, [er]: false });
function hr(r) {
  return d;
}
function Or(r, e = d) {
  if (r.length < e.MIN_SECRET_BYTES) throw new h(e.MIN_SECRET_BYTES, r.length);
  if (r.length > e.MAX_SECRET_BYTES) throw new P(e.MAX_SECRET_BYTES, r.length);
}
function br(r, e = d) {
  if (typeof r == "number") {
    if (!Number.isFinite(r) || !Number.isInteger(r)) throw new b();
    if (!Number.isSafeInteger(r)) throw new T();
  }
  let t = typeof r == "bigint" ? r : BigInt(r);
  if (t < 0n) throw new O();
  if (t > BigInt(e.MAX_COUNTER)) throw new T();
}
function Ar(r) {
  if (!Number.isFinite(r)) throw new S();
  if (r < 0) throw new C();
}
function Cr(r, e = d) {
  if (!Number.isInteger(r) || r < e.MIN_PERIOD) throw new w(e.MIN_PERIOD);
  if (r > e.MAX_PERIOD) throw new _(e.MAX_PERIOD);
}
function Sr(r, e) {
  if (r.length !== e) throw new I(e, r.length);
  if (!/^\d+$/.test(r)) throw new M();
}
function Br(r, e = d) {
  let [t, o] = Er(r);
  if (!Number.isSafeInteger(t) || !Number.isSafeInteger(o)) throw new g("Counter tolerance values must be safe integers");
  if (t < 0 || o < 0) throw new X();
  let n = t + o + 1;
  if (n > e.MAX_WINDOW) throw new U(e.MAX_WINDOW, n);
}
function wr(r, e = cr, t = d) {
  let [o, n] = Array.isArray(r) ? r : [r, r];
  if (!Number.isSafeInteger(o) || !Number.isSafeInteger(n)) throw new E("Epoch tolerance values must be safe integers");
  if (o < 0 || n < 0) throw new k();
  let s = (t.MAX_WINDOW - 1) * e, u = o + n;
  if (u > s) throw new q(s, u);
}
function _r(r) {
  let e = typeof r == "bigint" ? r : BigInt(r), t = new ArrayBuffer(8);
  return new DataView(t).setBigUint64(0, e, false), new Uint8Array(t);
}
function Rr(r) {
  let e = r[r.length - 1] & 15;
  return (r[e] & 127) << 24 | r[e + 1] << 16 | r[e + 2] << 8 | r[e + 3];
}
function Ir(r, e) {
  let t = 10 ** e;
  return (r % t).toString().padStart(e, "0");
}
function gr(r, e) {
  return r.length === e.length;
}
function tr(r, e) {
  let t = rr(r), o = rr(e);
  if (!gr(t, o)) return false;
  let n = 0;
  for (let s = 0; s < t.length; s++) n |= t[s] ^ o[s];
  return n === 0;
}
function rr(r) {
  return typeof r == "string" ? yr.encode(r) : r;
}
function vr(r, e) {
  return typeof r == "string" ? (nr(e), e.decode(r)) : r;
}
function Dr(r) {
  let { crypto: e, base32: t, length: o = ir } = r;
  dr(e), nr(t);
  let n = e.randomBytes(o);
  return t.encode(n, { padding: false });
}
function Er(r = 0) {
  return Array.isArray(r) ? r : [0, r];
}
function Ur(r = 0) {
  return Array.isArray(r) ? r : [r, r];
}
function dr(r) {
  if (!r) throw new Y();
}
function nr(r) {
  if (!r) throw new L();
}
function Xr(r) {
  if (!r) throw new W();
}
var K = class {
  constructor(e) {
    this.crypto = e;
  }
  get plugin() {
    return this.crypto;
  }
  async hmac(e, t, o) {
    try {
      let n = this.crypto.hmac(e, t, o);
      return n instanceof Promise ? await n : n;
    } catch (n) {
      let s = n instanceof Error ? n.message : String(n);
      throw new c(s, { cause: n });
    }
  }
  hmacSync(e, t, o) {
    try {
      let n = this.crypto.hmac(e, t, o);
      if (n instanceof Promise) throw new c("Crypto plugin does not support synchronous HMAC operations");
      return n;
    } catch (n) {
      if (n instanceof c) throw n;
      let s = n instanceof Error ? n.message : String(n);
      throw new c(s, { cause: n });
    }
  }
  randomBytes(e) {
    try {
      return this.crypto.randomBytes(e);
    } catch (t) {
      let o = t instanceof Error ? t.message : String(t);
      throw new v(o, { cause: t });
    }
  }
};
function Wr(r) {
  return new K(r);
}
export {
  Ar as A,
  Br as B,
  Cr as C,
  Dr as D,
  Er as E,
  Ir as I,
  J,
  Or as O,
  Q,
  Rr as R,
  Sr as S,
  Ur as U,
  Wr as W,
  Xr as X,
  Z,
  _r as _,
  a,
  br as b,
  dr as d,
  hr as h,
  tr as t,
  vr as v,
  wr as w
};
