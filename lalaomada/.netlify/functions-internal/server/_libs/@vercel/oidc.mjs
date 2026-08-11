import require$$0 from "path";
import require$$1 from "fs";
import require$$2 from "os";
import { g as getDefaultExportFromCjs } from "../react.mjs";
function _mergeNamespaces(n, m) {
  for (var i = 0; i < m.length; i++) {
    const e = m[i];
    if (typeof e !== "string" && !Array.isArray(e)) {
      for (const k in e) {
        if (k !== "default" && !(k in n)) {
          const d = Object.getOwnPropertyDescriptor(e, k);
          if (d) {
            Object.defineProperty(n, k, d.get ? d : {
              enumerable: true,
              get: function() {
                return e[k];
              }
            });
          }
        }
      }
    }
  }
  return Object.freeze(n);
}
var getContext_1;
var hasRequiredGetContext;
function requireGetContext() {
  if (hasRequiredGetContext) return getContext_1;
  hasRequiredGetContext = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var get_context_exports = {};
  __export(get_context_exports, {
    SYMBOL_FOR_REQ_CONTEXT: () => SYMBOL_FOR_REQ_CONTEXT,
    getContext: () => getContext
  });
  getContext_1 = __toCommonJS(get_context_exports);
  const SYMBOL_FOR_REQ_CONTEXT = /* @__PURE__ */ Symbol.for("@vercel/request-context");
  function getContext() {
    const fromSymbol = globalThis;
    return fromSymbol[SYMBOL_FOR_REQ_CONTEXT]?.get?.() ?? {};
  }
  return getContext_1;
}
var tokenError;
var hasRequiredTokenError;
function requireTokenError() {
  if (hasRequiredTokenError) return tokenError;
  hasRequiredTokenError = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var token_error_exports = {};
  __export(token_error_exports, {
    VercelOidcTokenError: () => VercelOidcTokenError
  });
  tokenError = __toCommonJS(token_error_exports);
  class VercelOidcTokenError extends Error {
    constructor(message, cause) {
      super(message);
      this.name = "VercelOidcTokenError";
      this.cause = cause;
    }
    toString() {
      if (this.cause) {
        return `${this.name}: ${this.message}: ${this.cause}`;
      }
      return `${this.name}: ${this.message}`;
    }
  }
  return tokenError;
}
var getVercelOidcToken_1;
var hasRequiredGetVercelOidcToken;
function requireGetVercelOidcToken() {
  if (hasRequiredGetVercelOidcToken) return getVercelOidcToken_1;
  hasRequiredGetVercelOidcToken = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var get_vercel_oidc_token_exports = {};
  __export(get_vercel_oidc_token_exports, {
    getVercelOidcToken: () => getVercelOidcToken,
    getVercelOidcTokenSync: () => getVercelOidcTokenSync
  });
  getVercelOidcToken_1 = __toCommonJS(get_vercel_oidc_token_exports);
  var import_get_context = requireGetContext();
  var import_token_error = requireTokenError();
  async function getVercelOidcToken(options) {
    let token2 = "";
    let err;
    try {
      token2 = getVercelOidcTokenSync();
    } catch (error) {
      err = error;
    }
    try {
      const [{ getTokenPayload, isExpired }, { refreshToken }] = await Promise.all([
        await Promise.resolve().then(function() {
          return tokenUtil$1;
        }),
        await Promise.resolve().then(function() {
          return token$1;
        })
      ]);
      if (!token2 || isExpired(getTokenPayload(token2), options?.expirationBufferMs)) {
        await refreshToken(options);
        token2 = getVercelOidcTokenSync();
      }
    } catch (error) {
      let message = err instanceof Error ? err.message : "";
      if (error instanceof Error) {
        message = `${message}
${error.message}`;
      }
      if (message) {
        throw new import_token_error.VercelOidcTokenError(message);
      }
      throw error;
    }
    return token2;
  }
  function getVercelOidcTokenSync() {
    const token2 = (0, import_get_context.getContext)().headers?.["x-vercel-oidc-token"] ?? process.env.VERCEL_OIDC_TOKEN;
    if (!token2) {
      throw new Error(
        `The 'x-vercel-oidc-token' header is missing from the request. Do you have the OIDC option enabled in the Vercel project settings?`
      );
    }
    return token2;
  }
  return getVercelOidcToken_1;
}
var authErrors;
var hasRequiredAuthErrors;
function requireAuthErrors() {
  if (hasRequiredAuthErrors) return authErrors;
  hasRequiredAuthErrors = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var auth_errors_exports = {};
  __export(auth_errors_exports, {
    AccessTokenMissingError: () => AccessTokenMissingError,
    RefreshAccessTokenFailedError: () => RefreshAccessTokenFailedError
  });
  authErrors = __toCommonJS(auth_errors_exports);
  class AccessTokenMissingError extends Error {
    constructor() {
      super(
        "No authentication found. Please log in with the Vercel CLI (vercel login)."
      );
      this.name = "AccessTokenMissingError";
    }
  }
  class RefreshAccessTokenFailedError extends Error {
    constructor(cause) {
      super("Failed to refresh authentication token.", { cause });
      this.name = "RefreshAccessTokenFailedError";
    }
  }
  return authErrors;
}
var tokenIo;
var hasRequiredTokenIo;
function requireTokenIo() {
  if (hasRequiredTokenIo) return tokenIo;
  hasRequiredTokenIo = 1;
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var token_io_exports = {};
  __export(token_io_exports, {
    findRootDir: () => findRootDir,
    getUserDataDir: () => getUserDataDir
  });
  tokenIo = __toCommonJS(token_io_exports);
  var import_path2 = __toESM(require$$0);
  var import_fs2 = __toESM(require$$1);
  var import_os2 = __toESM(require$$2);
  var import_token_error = requireTokenError();
  function findRootDir() {
    try {
      let dir = process.cwd();
      while (dir !== import_path2.default.dirname(dir)) {
        const pkgPath = import_path2.default.join(dir, ".vercel");
        if (import_fs2.default.existsSync(pkgPath)) {
          return dir;
        }
        dir = import_path2.default.dirname(dir);
      }
    } catch (e) {
      throw new import_token_error.VercelOidcTokenError(
        "Token refresh only supported in node server environments"
      );
    }
    return null;
  }
  function getUserDataDir() {
    if (process.env.XDG_DATA_HOME) {
      return process.env.XDG_DATA_HOME;
    }
    switch (import_os2.default.platform()) {
      case "darwin":
        return import_path2.default.join(import_os2.default.homedir(), "Library/Application Support");
      case "linux":
        return import_path2.default.join(import_os2.default.homedir(), ".local/share");
      case "win32":
        if (process.env.LOCALAPPDATA) {
          return process.env.LOCALAPPDATA;
        }
        return null;
      default:
        return null;
    }
  }
  return tokenIo;
}
var authConfig;
var hasRequiredAuthConfig;
function requireAuthConfig() {
  if (hasRequiredAuthConfig) return authConfig;
  hasRequiredAuthConfig = 1;
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var auth_config_exports = {};
  __export(auth_config_exports, {
    isValidAccessToken: () => isValidAccessToken,
    readAuthConfig: () => readAuthConfig,
    writeAuthConfig: () => writeAuthConfig
  });
  authConfig = __toCommonJS(auth_config_exports);
  var fs = __toESM(require$$1);
  var path = __toESM(require$$0);
  var import_token_util = requireTokenUtil();
  function getAuthConfigPath() {
    const dataDir = (0, import_token_util.getVercelDataDir)();
    if (!dataDir) {
      throw new Error(
        `Unable to find Vercel CLI data directory. Your platform: ${process.platform}. Supported: darwin, linux, win32.`
      );
    }
    return path.join(dataDir, "auth.json");
  }
  function readAuthConfig() {
    try {
      const authPath = getAuthConfigPath();
      if (!fs.existsSync(authPath)) {
        return null;
      }
      const content = fs.readFileSync(authPath, "utf8");
      if (!content) {
        return null;
      }
      return JSON.parse(content);
    } catch (error) {
      return null;
    }
  }
  function writeAuthConfig(config) {
    const authPath = getAuthConfigPath();
    const authDir = path.dirname(authPath);
    if (!fs.existsSync(authDir)) {
      fs.mkdirSync(authDir, { mode: 504, recursive: true });
    }
    fs.writeFileSync(authPath, JSON.stringify(config, null, 2), { mode: 384 });
  }
  function isValidAccessToken(authConfig2, expirationBufferMs = 0) {
    if (!authConfig2.token)
      return false;
    if (typeof authConfig2.expiresAt !== "number")
      return true;
    const nowInSeconds = Math.floor(Date.now() / 1e3);
    const bufferInSeconds = expirationBufferMs / 1e3;
    return authConfig2.expiresAt >= nowInSeconds + bufferInSeconds;
  }
  return authConfig;
}
var oauth;
var hasRequiredOauth;
function requireOauth() {
  if (hasRequiredOauth) return oauth;
  hasRequiredOauth = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var oauth_exports = {};
  __export(oauth_exports, {
    processTokenResponse: () => processTokenResponse,
    refreshTokenRequest: () => refreshTokenRequest
  });
  oauth = __toCommonJS(oauth_exports);
  var import_os2 = require$$2;
  const VERCEL_ISSUER = "https://vercel.com";
  const VERCEL_CLI_CLIENT_ID = "cl_HYyOPBNtFMfHhaUn9L4QPfTZz6TP47bp";
  const userAgent = `@vercel/oidc node-${process.version} ${(0, import_os2.platform)()} (${(0, import_os2.arch)()}) ${(0, import_os2.hostname)()}`;
  let _tokenEndpoint = null;
  async function getTokenEndpoint() {
    if (_tokenEndpoint) {
      return _tokenEndpoint;
    }
    const discoveryUrl = `${VERCEL_ISSUER}/.well-known/openid-configuration`;
    const response = await fetch(discoveryUrl, {
      headers: { "user-agent": userAgent }
    });
    if (!response.ok) {
      throw new Error("Failed to discover OAuth endpoints");
    }
    const metadata = await response.json();
    if (!metadata || typeof metadata.token_endpoint !== "string") {
      throw new Error("Invalid OAuth discovery response");
    }
    const endpoint = metadata.token_endpoint;
    _tokenEndpoint = endpoint;
    return endpoint;
  }
  async function refreshTokenRequest(options) {
    const tokenEndpoint = await getTokenEndpoint();
    return await fetch(tokenEndpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "user-agent": userAgent
      },
      body: new URLSearchParams({
        client_id: VERCEL_CLI_CLIENT_ID,
        grant_type: "refresh_token",
        ...options
      })
    });
  }
  async function processTokenResponse(response) {
    const json = await response.json();
    if (!response.ok) {
      const errorMsg = typeof json === "object" && json && "error" in json ? String(json.error) : "Token refresh failed";
      return [new Error(errorMsg)];
    }
    if (typeof json !== "object" || json === null) {
      return [new Error("Invalid token response")];
    }
    if (typeof json.access_token !== "string") {
      return [new Error("Missing access_token in response")];
    }
    if (json.token_type !== "Bearer") {
      return [new Error("Invalid token_type in response")];
    }
    if (typeof json.expires_in !== "number") {
      return [new Error("Missing expires_in in response")];
    }
    return [null, json];
  }
  return oauth;
}
var tokenUtil$2;
var hasRequiredTokenUtil;
function requireTokenUtil() {
  if (hasRequiredTokenUtil) return tokenUtil$2;
  hasRequiredTokenUtil = 1;
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var token_util_exports = {};
  __export(token_util_exports, {
    assertVercelOidcTokenResponse: () => assertVercelOidcTokenResponse,
    findProjectInfo: () => findProjectInfo,
    getTokenPayload: () => getTokenPayload,
    getVercelDataDir: () => getVercelDataDir,
    getVercelOidcToken: () => getVercelOidcToken,
    getVercelToken: () => getVercelToken,
    isExpired: () => isExpired,
    loadToken: () => loadToken,
    saveToken: () => saveToken
  });
  tokenUtil$2 = __toCommonJS(token_util_exports);
  var path = __toESM(require$$0);
  var fs = __toESM(require$$1);
  var import_token_error = requireTokenError();
  var import_token_io = requireTokenIo();
  var import_auth_config = requireAuthConfig();
  var import_oauth = requireOauth();
  var import_auth_errors = requireAuthErrors();
  function getVercelDataDir() {
    const vercelFolder = "com.vercel.cli";
    const dataDir = (0, import_token_io.getUserDataDir)();
    if (!dataDir) {
      return null;
    }
    return path.join(dataDir, vercelFolder);
  }
  async function getVercelToken(options) {
    const authConfig2 = (0, import_auth_config.readAuthConfig)();
    if (!authConfig2?.token) {
      throw new import_auth_errors.AccessTokenMissingError();
    }
    if ((0, import_auth_config.isValidAccessToken)(authConfig2, options?.expirationBufferMs)) {
      return authConfig2.token;
    }
    if (!authConfig2.refreshToken) {
      (0, import_auth_config.writeAuthConfig)({});
      throw new import_auth_errors.RefreshAccessTokenFailedError("No refresh token available");
    }
    try {
      const tokenResponse = await (0, import_oauth.refreshTokenRequest)({
        refresh_token: authConfig2.refreshToken
      });
      const [tokensError, tokens] = await (0, import_oauth.processTokenResponse)(tokenResponse);
      if (tokensError || !tokens) {
        (0, import_auth_config.writeAuthConfig)({});
        throw new import_auth_errors.RefreshAccessTokenFailedError(tokensError);
      }
      const updatedConfig = {
        token: tokens.access_token,
        expiresAt: Math.floor(Date.now() / 1e3) + tokens.expires_in
      };
      if (tokens.refresh_token) {
        updatedConfig.refreshToken = tokens.refresh_token;
      }
      (0, import_auth_config.writeAuthConfig)(updatedConfig);
      return updatedConfig.token;
    } catch (error) {
      (0, import_auth_config.writeAuthConfig)({});
      if (error instanceof import_auth_errors.AccessTokenMissingError || error instanceof import_auth_errors.RefreshAccessTokenFailedError) {
        throw error;
      }
      throw new import_auth_errors.RefreshAccessTokenFailedError(error);
    }
  }
  async function getVercelOidcToken(authToken, projectId, teamId) {
    const url = `https://api.vercel.com/v1/projects/${projectId}/token?source=vercel-oidc-refresh${teamId ? `&teamId=${teamId}` : ""}`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${authToken}`
      }
    });
    if (!res.ok) {
      throw new import_token_error.VercelOidcTokenError(
        `Failed to refresh OIDC token: ${res.statusText}`
      );
    }
    const tokenRes = await res.json();
    assertVercelOidcTokenResponse(tokenRes);
    return tokenRes;
  }
  function assertVercelOidcTokenResponse(res) {
    if (!res || typeof res !== "object") {
      throw new TypeError(
        "Vercel OIDC token is malformed. Expected an object. Please run `vc env pull` and try again"
      );
    }
    if (!("token" in res) || typeof res.token !== "string") {
      throw new TypeError(
        "Vercel OIDC token is malformed. Expected a string-valued token property. Please run `vc env pull` and try again"
      );
    }
  }
  function findProjectInfo() {
    const dir = (0, import_token_io.findRootDir)();
    if (!dir) {
      throw new import_token_error.VercelOidcTokenError(
        "Unable to find project root directory. Have you linked your project with `vc link?`"
      );
    }
    const prjPath = path.join(dir, ".vercel", "project.json");
    if (!fs.existsSync(prjPath)) {
      throw new import_token_error.VercelOidcTokenError(
        "project.json not found, have you linked your project with `vc link?`"
      );
    }
    const prj = JSON.parse(fs.readFileSync(prjPath, "utf8"));
    if (typeof prj.projectId !== "string" && typeof prj.orgId !== "string") {
      throw new TypeError(
        "Expected a string-valued projectId property. Try running `vc link` to re-link your project."
      );
    }
    return { projectId: prj.projectId, teamId: prj.orgId };
  }
  function saveToken(token2, projectId) {
    const dir = (0, import_token_io.getUserDataDir)();
    if (!dir) {
      throw new import_token_error.VercelOidcTokenError(
        "Unable to find user data directory. Please reach out to Vercel support."
      );
    }
    const tokenPath = path.join(dir, "com.vercel.token", `${projectId}.json`);
    const tokenJson = JSON.stringify(token2);
    fs.mkdirSync(path.dirname(tokenPath), { mode: 504, recursive: true });
    fs.writeFileSync(tokenPath, tokenJson);
    fs.chmodSync(tokenPath, 432);
    return;
  }
  function loadToken(projectId) {
    const dir = (0, import_token_io.getUserDataDir)();
    if (!dir) {
      throw new import_token_error.VercelOidcTokenError(
        "Unable to find user data directory. Please reach out to Vercel support."
      );
    }
    const tokenPath = path.join(dir, "com.vercel.token", `${projectId}.json`);
    if (!fs.existsSync(tokenPath)) {
      return null;
    }
    const token2 = JSON.parse(fs.readFileSync(tokenPath, "utf8"));
    assertVercelOidcTokenResponse(token2);
    return token2;
  }
  function getTokenPayload(token2) {
    const tokenParts = token2.split(".");
    if (tokenParts.length !== 3) {
      throw new import_token_error.VercelOidcTokenError(
        "Invalid token. Please run `vc env pull` and try again"
      );
    }
    const base64 = tokenParts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(
      base64.length + (4 - base64.length % 4) % 4,
      "="
    );
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  }
  function isExpired(token2, bufferMs = 0) {
    return token2.exp * 1e3 < Date.now() + bufferMs;
  }
  return tokenUtil$2;
}
var dist;
var hasRequiredDist;
function requireDist() {
  if (hasRequiredDist) return dist;
  hasRequiredDist = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var src_exports = {};
  __export(src_exports, {
    AccessTokenMissingError: () => import_auth_errors.AccessTokenMissingError,
    RefreshAccessTokenFailedError: () => import_auth_errors.RefreshAccessTokenFailedError,
    getContext: () => import_get_context.getContext,
    getVercelOidcToken: () => import_get_vercel_oidc_token.getVercelOidcToken,
    getVercelOidcTokenSync: () => import_get_vercel_oidc_token.getVercelOidcTokenSync,
    getVercelToken: () => import_token_util.getVercelToken
  });
  dist = __toCommonJS(src_exports);
  var import_get_vercel_oidc_token = requireGetVercelOidcToken();
  var import_get_context = requireGetContext();
  var import_auth_errors = requireAuthErrors();
  var import_token_util = requireTokenUtil();
  return dist;
}
var distExports = requireDist();
var tokenUtilExports = requireTokenUtil();
const tokenUtil = /* @__PURE__ */ getDefaultExportFromCjs(tokenUtilExports);
const tokenUtil$1 = /* @__PURE__ */ _mergeNamespaces({
  __proto__: null,
  default: tokenUtil
}, [tokenUtilExports]);
var token$2;
var hasRequiredToken;
function requireToken() {
  if (hasRequiredToken) return token$2;
  hasRequiredToken = 1;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);
  var token_exports = {};
  __export(token_exports, {
    refreshToken: () => refreshToken
  });
  token$2 = __toCommonJS(token_exports);
  var import_token_error = requireTokenError();
  var import_token_util = requireTokenUtil();
  async function refreshToken(options) {
    let projectId = options?.project;
    let teamId = options?.team;
    if (!projectId && !teamId) {
      const projectInfo = (0, import_token_util.findProjectInfo)();
      projectId = projectInfo.projectId;
      teamId = projectInfo.teamId;
    } else if (!projectId || !teamId) {
      const projectInfo = (0, import_token_util.findProjectInfo)();
      projectId = projectId ?? projectInfo.projectId;
      teamId = teamId ?? projectInfo.teamId;
    }
    if (!projectId) {
      throw new import_token_error.VercelOidcTokenError(
        "Failed to refresh OIDC token: No project specified. Try re-linking your project with `vc link`"
      );
    }
    let maybeToken = (0, import_token_util.loadToken)(projectId);
    if (!maybeToken || (0, import_token_util.isExpired)((0, import_token_util.getTokenPayload)(maybeToken.token), options?.expirationBufferMs)) {
      const authToken = await (0, import_token_util.getVercelToken)({
        expirationBufferMs: options?.expirationBufferMs
      });
      maybeToken = await (0, import_token_util.getVercelOidcToken)(authToken, projectId, teamId);
      if (!maybeToken) {
        throw new import_token_error.VercelOidcTokenError("Failed to refresh OIDC token");
      }
      (0, import_token_util.saveToken)(maybeToken, projectId);
    }
    process.env.VERCEL_OIDC_TOKEN = maybeToken.token;
    return;
  }
  return token$2;
}
var tokenExports = requireToken();
const token = /* @__PURE__ */ getDefaultExportFromCjs(tokenExports);
const token$1 = /* @__PURE__ */ _mergeNamespaces({
  __proto__: null,
  default: token
}, [tokenExports]);
export {
  distExports as d
};
