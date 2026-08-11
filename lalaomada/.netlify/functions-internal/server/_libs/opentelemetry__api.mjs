import { c as commonjsGlobal } from "./react.mjs";
var src = {};
var utils$1 = {};
var diag = {};
var ComponentLogger = {};
var globalUtils = {};
var version = {};
var hasRequiredVersion;
function requireVersion() {
  if (hasRequiredVersion) return version;
  hasRequiredVersion = 1;
  Object.defineProperty(version, "__esModule", { value: true });
  version.VERSION = void 0;
  version.VERSION = "1.9.1";
  return version;
}
var semver = {};
var hasRequiredSemver;
function requireSemver() {
  if (hasRequiredSemver) return semver;
  hasRequiredSemver = 1;
  Object.defineProperty(semver, "__esModule", { value: true });
  semver.isCompatible = semver._makeCompatibilityCheck = void 0;
  const version_1 = /* @__PURE__ */ requireVersion();
  const re = /^(\d+)\.(\d+)\.(\d+)(-(.+))?$/;
  function _makeCompatibilityCheck(ownVersion) {
    const acceptedVersions = /* @__PURE__ */ new Set([ownVersion]);
    const rejectedVersions = /* @__PURE__ */ new Set();
    const myVersionMatch = ownVersion.match(re);
    if (!myVersionMatch) {
      return () => false;
    }
    const ownVersionParsed = {
      major: +myVersionMatch[1],
      minor: +myVersionMatch[2],
      patch: +myVersionMatch[3],
      prerelease: myVersionMatch[4]
    };
    if (ownVersionParsed.prerelease != null) {
      return function isExactmatch(globalVersion) {
        return globalVersion === ownVersion;
      };
    }
    function _reject(v) {
      rejectedVersions.add(v);
      return false;
    }
    function _accept(v) {
      acceptedVersions.add(v);
      return true;
    }
    return function isCompatible(globalVersion) {
      if (acceptedVersions.has(globalVersion)) {
        return true;
      }
      if (rejectedVersions.has(globalVersion)) {
        return false;
      }
      const globalVersionMatch = globalVersion.match(re);
      if (!globalVersionMatch) {
        return _reject(globalVersion);
      }
      const globalVersionParsed = {
        major: +globalVersionMatch[1],
        minor: +globalVersionMatch[2],
        patch: +globalVersionMatch[3],
        prerelease: globalVersionMatch[4]
      };
      if (globalVersionParsed.prerelease != null) {
        return _reject(globalVersion);
      }
      if (ownVersionParsed.major !== globalVersionParsed.major) {
        return _reject(globalVersion);
      }
      if (ownVersionParsed.major === 0) {
        if (ownVersionParsed.minor === globalVersionParsed.minor && ownVersionParsed.patch <= globalVersionParsed.patch) {
          return _accept(globalVersion);
        }
        return _reject(globalVersion);
      }
      if (ownVersionParsed.minor <= globalVersionParsed.minor) {
        return _accept(globalVersion);
      }
      return _reject(globalVersion);
    };
  }
  semver._makeCompatibilityCheck = _makeCompatibilityCheck;
  semver.isCompatible = _makeCompatibilityCheck(version_1.VERSION);
  return semver;
}
var hasRequiredGlobalUtils;
function requireGlobalUtils() {
  if (hasRequiredGlobalUtils) return globalUtils;
  hasRequiredGlobalUtils = 1;
  Object.defineProperty(globalUtils, "__esModule", { value: true });
  globalUtils.unregisterGlobal = globalUtils.getGlobal = globalUtils.registerGlobal = void 0;
  const version_1 = /* @__PURE__ */ requireVersion();
  const semver_1 = /* @__PURE__ */ requireSemver();
  const major = version_1.VERSION.split(".")[0];
  const GLOBAL_OPENTELEMETRY_API_KEY = /* @__PURE__ */ Symbol.for(`opentelemetry.js.api.${major}`);
  const _global = typeof globalThis === "object" ? globalThis : typeof self === "object" ? self : typeof window === "object" ? window : typeof commonjsGlobal === "object" ? commonjsGlobal : {};
  function registerGlobal(type, instance, diag2, allowOverride = false) {
    var _a;
    const api = _global[GLOBAL_OPENTELEMETRY_API_KEY] = (_a = _global[GLOBAL_OPENTELEMETRY_API_KEY]) !== null && _a !== void 0 ? _a : {
      version: version_1.VERSION
    };
    if (!allowOverride && api[type]) {
      const err = new Error(`@opentelemetry/api: Attempted duplicate registration of API: ${type}`);
      diag2.error(err.stack || err.message);
      return false;
    }
    if (api.version !== version_1.VERSION) {
      const err = new Error(`@opentelemetry/api: Registration of version v${api.version} for ${type} does not match previously registered API v${version_1.VERSION}`);
      diag2.error(err.stack || err.message);
      return false;
    }
    api[type] = instance;
    diag2.debug(`@opentelemetry/api: Registered a global for ${type} v${version_1.VERSION}.`);
    return true;
  }
  globalUtils.registerGlobal = registerGlobal;
  function getGlobal(type) {
    var _a, _b;
    const globalVersion = (_a = _global[GLOBAL_OPENTELEMETRY_API_KEY]) === null || _a === void 0 ? void 0 : _a.version;
    if (!globalVersion || !(0, semver_1.isCompatible)(globalVersion)) {
      return;
    }
    return (_b = _global[GLOBAL_OPENTELEMETRY_API_KEY]) === null || _b === void 0 ? void 0 : _b[type];
  }
  globalUtils.getGlobal = getGlobal;
  function unregisterGlobal(type, diag2) {
    diag2.debug(`@opentelemetry/api: Unregistering a global for ${type} v${version_1.VERSION}.`);
    const api = _global[GLOBAL_OPENTELEMETRY_API_KEY];
    if (api) {
      delete api[type];
    }
  }
  globalUtils.unregisterGlobal = unregisterGlobal;
  return globalUtils;
}
var hasRequiredComponentLogger;
function requireComponentLogger() {
  if (hasRequiredComponentLogger) return ComponentLogger;
  hasRequiredComponentLogger = 1;
  Object.defineProperty(ComponentLogger, "__esModule", { value: true });
  ComponentLogger.DiagComponentLogger = void 0;
  const global_utils_1 = /* @__PURE__ */ requireGlobalUtils();
  class DiagComponentLogger {
    constructor(props) {
      this._namespace = props.namespace || "DiagComponentLogger";
    }
    debug(...args) {
      return logProxy("debug", this._namespace, args);
    }
    error(...args) {
      return logProxy("error", this._namespace, args);
    }
    info(...args) {
      return logProxy("info", this._namespace, args);
    }
    warn(...args) {
      return logProxy("warn", this._namespace, args);
    }
    verbose(...args) {
      return logProxy("verbose", this._namespace, args);
    }
  }
  ComponentLogger.DiagComponentLogger = DiagComponentLogger;
  function logProxy(funcName, namespace, args) {
    const logger = (0, global_utils_1.getGlobal)("diag");
    if (!logger) {
      return;
    }
    return logger[funcName](namespace, ...args);
  }
  return ComponentLogger;
}
var logLevelLogger = {};
var types = {};
var hasRequiredTypes;
function requireTypes() {
  if (hasRequiredTypes) return types;
  hasRequiredTypes = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.DiagLogLevel = void 0;
    (function(DiagLogLevel) {
      DiagLogLevel[DiagLogLevel["NONE"] = 0] = "NONE";
      DiagLogLevel[DiagLogLevel["ERROR"] = 30] = "ERROR";
      DiagLogLevel[DiagLogLevel["WARN"] = 50] = "WARN";
      DiagLogLevel[DiagLogLevel["INFO"] = 60] = "INFO";
      DiagLogLevel[DiagLogLevel["DEBUG"] = 70] = "DEBUG";
      DiagLogLevel[DiagLogLevel["VERBOSE"] = 80] = "VERBOSE";
      DiagLogLevel[DiagLogLevel["ALL"] = 9999] = "ALL";
    })(exports.DiagLogLevel || (exports.DiagLogLevel = {}));
  })(types);
  return types;
}
var hasRequiredLogLevelLogger;
function requireLogLevelLogger() {
  if (hasRequiredLogLevelLogger) return logLevelLogger;
  hasRequiredLogLevelLogger = 1;
  Object.defineProperty(logLevelLogger, "__esModule", { value: true });
  logLevelLogger.createLogLevelDiagLogger = void 0;
  const types_1 = /* @__PURE__ */ requireTypes();
  function createLogLevelDiagLogger(maxLevel, logger) {
    if (maxLevel < types_1.DiagLogLevel.NONE) {
      maxLevel = types_1.DiagLogLevel.NONE;
    } else if (maxLevel > types_1.DiagLogLevel.ALL) {
      maxLevel = types_1.DiagLogLevel.ALL;
    }
    logger = logger || {};
    function _filterFunc(funcName, theLevel) {
      const theFunc = logger[funcName];
      if (typeof theFunc === "function" && maxLevel >= theLevel) {
        return theFunc.bind(logger);
      }
      return function() {
      };
    }
    return {
      error: _filterFunc("error", types_1.DiagLogLevel.ERROR),
      warn: _filterFunc("warn", types_1.DiagLogLevel.WARN),
      info: _filterFunc("info", types_1.DiagLogLevel.INFO),
      debug: _filterFunc("debug", types_1.DiagLogLevel.DEBUG),
      verbose: _filterFunc("verbose", types_1.DiagLogLevel.VERBOSE)
    };
  }
  logLevelLogger.createLogLevelDiagLogger = createLogLevelDiagLogger;
  return logLevelLogger;
}
var hasRequiredDiag;
function requireDiag() {
  if (hasRequiredDiag) return diag;
  hasRequiredDiag = 1;
  Object.defineProperty(diag, "__esModule", { value: true });
  diag.DiagAPI = void 0;
  const ComponentLogger_1 = /* @__PURE__ */ requireComponentLogger();
  const logLevelLogger_1 = /* @__PURE__ */ requireLogLevelLogger();
  const types_1 = /* @__PURE__ */ requireTypes();
  const global_utils_1 = /* @__PURE__ */ requireGlobalUtils();
  const API_NAME = "diag";
  class DiagAPI {
    /** Get the singleton instance of the DiagAPI API */
    static instance() {
      if (!this._instance) {
        this._instance = new DiagAPI();
      }
      return this._instance;
    }
    /**
     * Private internal constructor
     * @private
     */
    constructor() {
      function _logProxy(funcName) {
        return function(...args) {
          const logger = (0, global_utils_1.getGlobal)("diag");
          if (!logger)
            return;
          return logger[funcName](...args);
        };
      }
      const self2 = this;
      const setLogger = (logger, optionsOrLogLevel = { logLevel: types_1.DiagLogLevel.INFO }) => {
        var _a, _b, _c;
        if (logger === self2) {
          const err = new Error("Cannot use diag as the logger for itself. Please use a DiagLogger implementation like ConsoleDiagLogger or a custom implementation");
          self2.error((_a = err.stack) !== null && _a !== void 0 ? _a : err.message);
          return false;
        }
        if (typeof optionsOrLogLevel === "number") {
          optionsOrLogLevel = {
            logLevel: optionsOrLogLevel
          };
        }
        const oldLogger = (0, global_utils_1.getGlobal)("diag");
        const newLogger = (0, logLevelLogger_1.createLogLevelDiagLogger)((_b = optionsOrLogLevel.logLevel) !== null && _b !== void 0 ? _b : types_1.DiagLogLevel.INFO, logger);
        if (oldLogger && !optionsOrLogLevel.suppressOverrideMessage) {
          const stack = (_c = new Error().stack) !== null && _c !== void 0 ? _c : "<failed to generate stacktrace>";
          oldLogger.warn(`Current logger will be overwritten from ${stack}`);
          newLogger.warn(`Current logger will overwrite one already registered from ${stack}`);
        }
        return (0, global_utils_1.registerGlobal)("diag", newLogger, self2, true);
      };
      self2.setLogger = setLogger;
      self2.disable = () => {
        (0, global_utils_1.unregisterGlobal)(API_NAME, self2);
      };
      self2.createComponentLogger = (options) => {
        return new ComponentLogger_1.DiagComponentLogger(options);
      };
      self2.verbose = _logProxy("verbose");
      self2.debug = _logProxy("debug");
      self2.info = _logProxy("info");
      self2.warn = _logProxy("warn");
      self2.error = _logProxy("error");
    }
  }
  diag.DiagAPI = DiagAPI;
  return diag;
}
var baggageImpl = {};
var hasRequiredBaggageImpl;
function requireBaggageImpl() {
  if (hasRequiredBaggageImpl) return baggageImpl;
  hasRequiredBaggageImpl = 1;
  Object.defineProperty(baggageImpl, "__esModule", { value: true });
  baggageImpl.BaggageImpl = void 0;
  class BaggageImpl {
    constructor(entries) {
      this._entries = entries ? new Map(entries) : /* @__PURE__ */ new Map();
    }
    getEntry(key) {
      const entry = this._entries.get(key);
      if (!entry) {
        return void 0;
      }
      return Object.assign({}, entry);
    }
    getAllEntries() {
      return Array.from(this._entries.entries());
    }
    setEntry(key, entry) {
      const newBaggage = new BaggageImpl(this._entries);
      newBaggage._entries.set(key, entry);
      return newBaggage;
    }
    removeEntry(key) {
      const newBaggage = new BaggageImpl(this._entries);
      newBaggage._entries.delete(key);
      return newBaggage;
    }
    removeEntries(...keys) {
      const newBaggage = new BaggageImpl(this._entries);
      for (const key of keys) {
        newBaggage._entries.delete(key);
      }
      return newBaggage;
    }
    clear() {
      return new BaggageImpl();
    }
  }
  baggageImpl.BaggageImpl = BaggageImpl;
  return baggageImpl;
}
var symbol = {};
var hasRequiredSymbol;
function requireSymbol() {
  if (hasRequiredSymbol) return symbol;
  hasRequiredSymbol = 1;
  Object.defineProperty(symbol, "__esModule", { value: true });
  symbol.baggageEntryMetadataSymbol = void 0;
  symbol.baggageEntryMetadataSymbol = /* @__PURE__ */ Symbol("BaggageEntryMetadata");
  return symbol;
}
var hasRequiredUtils$1;
function requireUtils$1() {
  if (hasRequiredUtils$1) return utils$1;
  hasRequiredUtils$1 = 1;
  Object.defineProperty(utils$1, "__esModule", { value: true });
  utils$1.baggageEntryMetadataFromString = utils$1.createBaggage = void 0;
  const diag_1 = /* @__PURE__ */ requireDiag();
  const baggage_impl_1 = /* @__PURE__ */ requireBaggageImpl();
  const symbol_1 = /* @__PURE__ */ requireSymbol();
  const diag2 = diag_1.DiagAPI.instance();
  function createBaggage(entries = {}) {
    return new baggage_impl_1.BaggageImpl(new Map(Object.entries(entries)));
  }
  utils$1.createBaggage = createBaggage;
  function baggageEntryMetadataFromString(str) {
    if (typeof str !== "string") {
      diag2.error(`Cannot create baggage metadata from unknown type: ${typeof str}`);
      str = "";
    }
    return {
      __TYPE__: symbol_1.baggageEntryMetadataSymbol,
      toString() {
        return str;
      }
    };
  }
  utils$1.baggageEntryMetadataFromString = baggageEntryMetadataFromString;
  return utils$1;
}
var context$1 = {};
var hasRequiredContext$1;
function requireContext$1() {
  if (hasRequiredContext$1) return context$1;
  hasRequiredContext$1 = 1;
  Object.defineProperty(context$1, "__esModule", { value: true });
  context$1.ROOT_CONTEXT = context$1.createContextKey = void 0;
  function createContextKey(description) {
    return Symbol.for(description);
  }
  context$1.createContextKey = createContextKey;
  class BaseContext {
    /**
     * Construct a new context which inherits values from an optional parent context.
     *
     * @param parentContext a context from which to inherit values
     */
    constructor(parentContext) {
      const self2 = this;
      self2._currentContext = parentContext ? new Map(parentContext) : /* @__PURE__ */ new Map();
      self2.getValue = (key) => self2._currentContext.get(key);
      self2.setValue = (key, value) => {
        const context2 = new BaseContext(self2._currentContext);
        context2._currentContext.set(key, value);
        return context2;
      };
      self2.deleteValue = (key) => {
        const context2 = new BaseContext(self2._currentContext);
        context2._currentContext.delete(key);
        return context2;
      };
    }
  }
  context$1.ROOT_CONTEXT = new BaseContext();
  return context$1;
}
var consoleLogger = {};
var hasRequiredConsoleLogger;
function requireConsoleLogger() {
  if (hasRequiredConsoleLogger) return consoleLogger;
  hasRequiredConsoleLogger = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.DiagConsoleLogger = exports._originalConsoleMethods = void 0;
    const consoleMap = [
      { n: "error", c: "error" },
      { n: "warn", c: "warn" },
      { n: "info", c: "info" },
      { n: "debug", c: "debug" },
      { n: "verbose", c: "trace" }
    ];
    exports._originalConsoleMethods = {};
    if (typeof console !== "undefined") {
      const keys = [
        "error",
        "warn",
        "info",
        "debug",
        "trace",
        "log"
      ];
      for (const key of keys) {
        if (typeof console[key] === "function") {
          exports._originalConsoleMethods[key] = console[key];
        }
      }
    }
    class DiagConsoleLogger {
      constructor() {
        function _consoleFunc(funcName) {
          return function(...args) {
            let theFunc = exports._originalConsoleMethods[funcName];
            if (typeof theFunc !== "function") {
              theFunc = exports._originalConsoleMethods["log"];
            }
            if (typeof theFunc !== "function" && console) {
              theFunc = console[funcName];
              if (typeof theFunc !== "function") {
                theFunc = console.log;
              }
            }
            if (typeof theFunc === "function") {
              return theFunc.apply(console, args);
            }
          };
        }
        for (let i = 0; i < consoleMap.length; i++) {
          this[consoleMap[i].n] = _consoleFunc(consoleMap[i].c);
        }
      }
    }
    exports.DiagConsoleLogger = DiagConsoleLogger;
  })(consoleLogger);
  return consoleLogger;
}
var NoopMeter = {};
var hasRequiredNoopMeter;
function requireNoopMeter() {
  if (hasRequiredNoopMeter) return NoopMeter;
  hasRequiredNoopMeter = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.createNoopMeter = exports.NOOP_OBSERVABLE_UP_DOWN_COUNTER_METRIC = exports.NOOP_OBSERVABLE_GAUGE_METRIC = exports.NOOP_OBSERVABLE_COUNTER_METRIC = exports.NOOP_UP_DOWN_COUNTER_METRIC = exports.NOOP_HISTOGRAM_METRIC = exports.NOOP_GAUGE_METRIC = exports.NOOP_COUNTER_METRIC = exports.NOOP_METER = exports.NoopObservableUpDownCounterMetric = exports.NoopObservableGaugeMetric = exports.NoopObservableCounterMetric = exports.NoopObservableMetric = exports.NoopHistogramMetric = exports.NoopGaugeMetric = exports.NoopUpDownCounterMetric = exports.NoopCounterMetric = exports.NoopMetric = exports.NoopMeter = void 0;
    class NoopMeter2 {
      constructor() {
      }
      /**
       * @see {@link Meter.createGauge}
       */
      createGauge(_name, _options) {
        return exports.NOOP_GAUGE_METRIC;
      }
      /**
       * @see {@link Meter.createHistogram}
       */
      createHistogram(_name, _options) {
        return exports.NOOP_HISTOGRAM_METRIC;
      }
      /**
       * @see {@link Meter.createCounter}
       */
      createCounter(_name, _options) {
        return exports.NOOP_COUNTER_METRIC;
      }
      /**
       * @see {@link Meter.createUpDownCounter}
       */
      createUpDownCounter(_name, _options) {
        return exports.NOOP_UP_DOWN_COUNTER_METRIC;
      }
      /**
       * @see {@link Meter.createObservableGauge}
       */
      createObservableGauge(_name, _options) {
        return exports.NOOP_OBSERVABLE_GAUGE_METRIC;
      }
      /**
       * @see {@link Meter.createObservableCounter}
       */
      createObservableCounter(_name, _options) {
        return exports.NOOP_OBSERVABLE_COUNTER_METRIC;
      }
      /**
       * @see {@link Meter.createObservableUpDownCounter}
       */
      createObservableUpDownCounter(_name, _options) {
        return exports.NOOP_OBSERVABLE_UP_DOWN_COUNTER_METRIC;
      }
      /**
       * @see {@link Meter.addBatchObservableCallback}
       */
      addBatchObservableCallback(_callback, _observables) {
      }
      /**
       * @see {@link Meter.removeBatchObservableCallback}
       */
      removeBatchObservableCallback(_callback) {
      }
    }
    exports.NoopMeter = NoopMeter2;
    class NoopMetric {
    }
    exports.NoopMetric = NoopMetric;
    class NoopCounterMetric extends NoopMetric {
      add(_value, _attributes) {
      }
    }
    exports.NoopCounterMetric = NoopCounterMetric;
    class NoopUpDownCounterMetric extends NoopMetric {
      add(_value, _attributes) {
      }
    }
    exports.NoopUpDownCounterMetric = NoopUpDownCounterMetric;
    class NoopGaugeMetric extends NoopMetric {
      record(_value, _attributes) {
      }
    }
    exports.NoopGaugeMetric = NoopGaugeMetric;
    class NoopHistogramMetric extends NoopMetric {
      record(_value, _attributes) {
      }
    }
    exports.NoopHistogramMetric = NoopHistogramMetric;
    class NoopObservableMetric {
      addCallback(_callback) {
      }
      removeCallback(_callback) {
      }
    }
    exports.NoopObservableMetric = NoopObservableMetric;
    class NoopObservableCounterMetric extends NoopObservableMetric {
    }
    exports.NoopObservableCounterMetric = NoopObservableCounterMetric;
    class NoopObservableGaugeMetric extends NoopObservableMetric {
    }
    exports.NoopObservableGaugeMetric = NoopObservableGaugeMetric;
    class NoopObservableUpDownCounterMetric extends NoopObservableMetric {
    }
    exports.NoopObservableUpDownCounterMetric = NoopObservableUpDownCounterMetric;
    exports.NOOP_METER = new NoopMeter2();
    exports.NOOP_COUNTER_METRIC = new NoopCounterMetric();
    exports.NOOP_GAUGE_METRIC = new NoopGaugeMetric();
    exports.NOOP_HISTOGRAM_METRIC = new NoopHistogramMetric();
    exports.NOOP_UP_DOWN_COUNTER_METRIC = new NoopUpDownCounterMetric();
    exports.NOOP_OBSERVABLE_COUNTER_METRIC = new NoopObservableCounterMetric();
    exports.NOOP_OBSERVABLE_GAUGE_METRIC = new NoopObservableGaugeMetric();
    exports.NOOP_OBSERVABLE_UP_DOWN_COUNTER_METRIC = new NoopObservableUpDownCounterMetric();
    function createNoopMeter() {
      return exports.NOOP_METER;
    }
    exports.createNoopMeter = createNoopMeter;
  })(NoopMeter);
  return NoopMeter;
}
var Metric = {};
var hasRequiredMetric;
function requireMetric() {
  if (hasRequiredMetric) return Metric;
  hasRequiredMetric = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.ValueType = void 0;
    (function(ValueType) {
      ValueType[ValueType["INT"] = 0] = "INT";
      ValueType[ValueType["DOUBLE"] = 1] = "DOUBLE";
    })(exports.ValueType || (exports.ValueType = {}));
  })(Metric);
  return Metric;
}
var TextMapPropagator = {};
var hasRequiredTextMapPropagator;
function requireTextMapPropagator() {
  if (hasRequiredTextMapPropagator) return TextMapPropagator;
  hasRequiredTextMapPropagator = 1;
  Object.defineProperty(TextMapPropagator, "__esModule", { value: true });
  TextMapPropagator.defaultTextMapSetter = TextMapPropagator.defaultTextMapGetter = void 0;
  TextMapPropagator.defaultTextMapGetter = {
    get(carrier, key) {
      if (carrier == null) {
        return void 0;
      }
      return carrier[key];
    },
    keys(carrier) {
      if (carrier == null) {
        return [];
      }
      return Object.keys(carrier);
    }
  };
  TextMapPropagator.defaultTextMapSetter = {
    set(carrier, key, value) {
      if (carrier == null) {
        return;
      }
      carrier[key] = value;
    }
  };
  return TextMapPropagator;
}
var ProxyTracer = {};
var NoopTracer = {};
var context = {};
var NoopContextManager = {};
var hasRequiredNoopContextManager;
function requireNoopContextManager() {
  if (hasRequiredNoopContextManager) return NoopContextManager;
  hasRequiredNoopContextManager = 1;
  Object.defineProperty(NoopContextManager, "__esModule", { value: true });
  NoopContextManager.NoopContextManager = void 0;
  const context_1 = /* @__PURE__ */ requireContext$1();
  let NoopContextManager$1 = class NoopContextManager {
    active() {
      return context_1.ROOT_CONTEXT;
    }
    with(_context, fn, thisArg, ...args) {
      return fn.call(thisArg, ...args);
    }
    bind(_context, target) {
      return target;
    }
    enable() {
      return this;
    }
    disable() {
      return this;
    }
  };
  NoopContextManager.NoopContextManager = NoopContextManager$1;
  return NoopContextManager;
}
var hasRequiredContext;
function requireContext() {
  if (hasRequiredContext) return context;
  hasRequiredContext = 1;
  Object.defineProperty(context, "__esModule", { value: true });
  context.ContextAPI = void 0;
  const NoopContextManager_1 = /* @__PURE__ */ requireNoopContextManager();
  const global_utils_1 = /* @__PURE__ */ requireGlobalUtils();
  const diag_1 = /* @__PURE__ */ requireDiag();
  const API_NAME = "context";
  const NOOP_CONTEXT_MANAGER = new NoopContextManager_1.NoopContextManager();
  class ContextAPI {
    /** Empty private constructor prevents end users from constructing a new instance of the API */
    constructor() {
    }
    /** Get the singleton instance of the Context API */
    static getInstance() {
      if (!this._instance) {
        this._instance = new ContextAPI();
      }
      return this._instance;
    }
    /**
     * Set the current context manager.
     *
     * @returns true if the context manager was successfully registered, else false
     */
    setGlobalContextManager(contextManager) {
      return (0, global_utils_1.registerGlobal)(API_NAME, contextManager, diag_1.DiagAPI.instance());
    }
    /**
     * Get the currently active context
     */
    active() {
      return this._getContextManager().active();
    }
    /**
     * Execute a function with an active context
     *
     * @param context context to be active during function execution
     * @param fn function to execute in a context
     * @param thisArg optional receiver to be used for calling fn
     * @param args optional arguments forwarded to fn
     */
    with(context2, fn, thisArg, ...args) {
      return this._getContextManager().with(context2, fn, thisArg, ...args);
    }
    /**
     * Bind a context to a target function or event emitter
     *
     * @param context context to bind to the event emitter or function. Defaults to the currently active context
     * @param target function or event emitter to bind
     */
    bind(context2, target) {
      return this._getContextManager().bind(context2, target);
    }
    _getContextManager() {
      return (0, global_utils_1.getGlobal)(API_NAME) || NOOP_CONTEXT_MANAGER;
    }
    /** Disable and remove the global context manager */
    disable() {
      this._getContextManager().disable();
      (0, global_utils_1.unregisterGlobal)(API_NAME, diag_1.DiagAPI.instance());
    }
  }
  context.ContextAPI = ContextAPI;
  return context;
}
var contextUtils = {};
var NonRecordingSpan = {};
var invalidSpanConstants = {};
var trace_flags = {};
var hasRequiredTrace_flags;
function requireTrace_flags() {
  if (hasRequiredTrace_flags) return trace_flags;
  hasRequiredTrace_flags = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.TraceFlags = void 0;
    (function(TraceFlags) {
      TraceFlags[TraceFlags["NONE"] = 0] = "NONE";
      TraceFlags[TraceFlags["SAMPLED"] = 1] = "SAMPLED";
    })(exports.TraceFlags || (exports.TraceFlags = {}));
  })(trace_flags);
  return trace_flags;
}
var hasRequiredInvalidSpanConstants;
function requireInvalidSpanConstants() {
  if (hasRequiredInvalidSpanConstants) return invalidSpanConstants;
  hasRequiredInvalidSpanConstants = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.INVALID_SPAN_CONTEXT = exports.INVALID_TRACEID = exports.INVALID_SPANID = void 0;
    const trace_flags_1 = /* @__PURE__ */ requireTrace_flags();
    exports.INVALID_SPANID = "0000000000000000";
    exports.INVALID_TRACEID = "00000000000000000000000000000000";
    exports.INVALID_SPAN_CONTEXT = {
      traceId: exports.INVALID_TRACEID,
      spanId: exports.INVALID_SPANID,
      traceFlags: trace_flags_1.TraceFlags.NONE
    };
  })(invalidSpanConstants);
  return invalidSpanConstants;
}
var hasRequiredNonRecordingSpan;
function requireNonRecordingSpan() {
  if (hasRequiredNonRecordingSpan) return NonRecordingSpan;
  hasRequiredNonRecordingSpan = 1;
  Object.defineProperty(NonRecordingSpan, "__esModule", { value: true });
  NonRecordingSpan.NonRecordingSpan = void 0;
  const invalid_span_constants_1 = /* @__PURE__ */ requireInvalidSpanConstants();
  let NonRecordingSpan$1 = class NonRecordingSpan {
    constructor(spanContext = invalid_span_constants_1.INVALID_SPAN_CONTEXT) {
      this._spanContext = spanContext;
    }
    // Returns a SpanContext.
    spanContext() {
      return this._spanContext;
    }
    // By default does nothing
    setAttribute(_key, _value) {
      return this;
    }
    // By default does nothing
    setAttributes(_attributes) {
      return this;
    }
    // By default does nothing
    addEvent(_name, _attributes) {
      return this;
    }
    addLink(_link) {
      return this;
    }
    addLinks(_links) {
      return this;
    }
    // By default does nothing
    setStatus(_status) {
      return this;
    }
    // By default does nothing
    updateName(_name) {
      return this;
    }
    // By default does nothing
    end(_endTime) {
    }
    // isRecording always returns false for NonRecordingSpan.
    isRecording() {
      return false;
    }
    // By default does nothing
    recordException(_exception, _time) {
    }
  };
  NonRecordingSpan.NonRecordingSpan = NonRecordingSpan$1;
  return NonRecordingSpan;
}
var hasRequiredContextUtils;
function requireContextUtils() {
  if (hasRequiredContextUtils) return contextUtils;
  hasRequiredContextUtils = 1;
  Object.defineProperty(contextUtils, "__esModule", { value: true });
  contextUtils.getSpanContext = contextUtils.setSpanContext = contextUtils.deleteSpan = contextUtils.setSpan = contextUtils.getActiveSpan = contextUtils.getSpan = void 0;
  const context_1 = /* @__PURE__ */ requireContext$1();
  const NonRecordingSpan_1 = /* @__PURE__ */ requireNonRecordingSpan();
  const context_2 = /* @__PURE__ */ requireContext();
  const SPAN_KEY = (0, context_1.createContextKey)("OpenTelemetry Context Key SPAN");
  function getSpan(context2) {
    return context2.getValue(SPAN_KEY) || void 0;
  }
  contextUtils.getSpan = getSpan;
  function getActiveSpan() {
    return getSpan(context_2.ContextAPI.getInstance().active());
  }
  contextUtils.getActiveSpan = getActiveSpan;
  function setSpan(context2, span) {
    return context2.setValue(SPAN_KEY, span);
  }
  contextUtils.setSpan = setSpan;
  function deleteSpan(context2) {
    return context2.deleteValue(SPAN_KEY);
  }
  contextUtils.deleteSpan = deleteSpan;
  function setSpanContext(context2, spanContext) {
    return setSpan(context2, new NonRecordingSpan_1.NonRecordingSpan(spanContext));
  }
  contextUtils.setSpanContext = setSpanContext;
  function getSpanContext(context2) {
    var _a;
    return (_a = getSpan(context2)) === null || _a === void 0 ? void 0 : _a.spanContext();
  }
  contextUtils.getSpanContext = getSpanContext;
  return contextUtils;
}
var spancontextUtils = {};
var hasRequiredSpancontextUtils;
function requireSpancontextUtils() {
  if (hasRequiredSpancontextUtils) return spancontextUtils;
  hasRequiredSpancontextUtils = 1;
  Object.defineProperty(spancontextUtils, "__esModule", { value: true });
  spancontextUtils.wrapSpanContext = spancontextUtils.isSpanContextValid = spancontextUtils.isValidSpanId = spancontextUtils.isValidTraceId = void 0;
  const invalid_span_constants_1 = /* @__PURE__ */ requireInvalidSpanConstants();
  const NonRecordingSpan_1 = /* @__PURE__ */ requireNonRecordingSpan();
  const isHex = new Uint8Array([
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    1
  ]);
  function isValidHex(id, length) {
    if (typeof id !== "string" || id.length !== length)
      return false;
    let r = 0;
    for (let i = 0; i < id.length; i += 4) {
      r += (isHex[id.charCodeAt(i)] | 0) + (isHex[id.charCodeAt(i + 1)] | 0) + (isHex[id.charCodeAt(i + 2)] | 0) + (isHex[id.charCodeAt(i + 3)] | 0);
    }
    return r === length;
  }
  function isValidTraceId(traceId) {
    return isValidHex(traceId, 32) && traceId !== invalid_span_constants_1.INVALID_TRACEID;
  }
  spancontextUtils.isValidTraceId = isValidTraceId;
  function isValidSpanId(spanId) {
    return isValidHex(spanId, 16) && spanId !== invalid_span_constants_1.INVALID_SPANID;
  }
  spancontextUtils.isValidSpanId = isValidSpanId;
  function isSpanContextValid(spanContext) {
    return isValidTraceId(spanContext.traceId) && isValidSpanId(spanContext.spanId);
  }
  spancontextUtils.isSpanContextValid = isSpanContextValid;
  function wrapSpanContext(spanContext) {
    return new NonRecordingSpan_1.NonRecordingSpan(spanContext);
  }
  spancontextUtils.wrapSpanContext = wrapSpanContext;
  return spancontextUtils;
}
var hasRequiredNoopTracer;
function requireNoopTracer() {
  if (hasRequiredNoopTracer) return NoopTracer;
  hasRequiredNoopTracer = 1;
  Object.defineProperty(NoopTracer, "__esModule", { value: true });
  NoopTracer.NoopTracer = void 0;
  const context_1 = /* @__PURE__ */ requireContext();
  const context_utils_1 = /* @__PURE__ */ requireContextUtils();
  const NonRecordingSpan_1 = /* @__PURE__ */ requireNonRecordingSpan();
  const spancontext_utils_1 = /* @__PURE__ */ requireSpancontextUtils();
  const contextApi2 = context_1.ContextAPI.getInstance();
  let NoopTracer$1 = class NoopTracer {
    // startSpan starts a noop span.
    startSpan(name, options, context2 = contextApi2.active()) {
      const root = Boolean(options === null || options === void 0 ? void 0 : options.root);
      if (root) {
        return new NonRecordingSpan_1.NonRecordingSpan();
      }
      const parentFromContext = context2 && (0, context_utils_1.getSpanContext)(context2);
      if (isSpanContext(parentFromContext) && (0, spancontext_utils_1.isSpanContextValid)(parentFromContext)) {
        return new NonRecordingSpan_1.NonRecordingSpan(parentFromContext);
      } else {
        return new NonRecordingSpan_1.NonRecordingSpan();
      }
    }
    startActiveSpan(name, arg2, arg3, arg4) {
      let opts;
      let ctx;
      let fn;
      if (arguments.length < 2) {
        return;
      } else if (arguments.length === 2) {
        fn = arg2;
      } else if (arguments.length === 3) {
        opts = arg2;
        fn = arg3;
      } else {
        opts = arg2;
        ctx = arg3;
        fn = arg4;
      }
      const parentContext = ctx !== null && ctx !== void 0 ? ctx : contextApi2.active();
      const span = this.startSpan(name, opts, parentContext);
      const contextWithSpanSet = (0, context_utils_1.setSpan)(parentContext, span);
      return contextApi2.with(contextWithSpanSet, fn, void 0, span);
    }
  };
  NoopTracer.NoopTracer = NoopTracer$1;
  function isSpanContext(spanContext) {
    return spanContext !== null && typeof spanContext === "object" && "spanId" in spanContext && typeof spanContext["spanId"] === "string" && "traceId" in spanContext && typeof spanContext["traceId"] === "string" && "traceFlags" in spanContext && typeof spanContext["traceFlags"] === "number";
  }
  return NoopTracer;
}
var hasRequiredProxyTracer;
function requireProxyTracer() {
  if (hasRequiredProxyTracer) return ProxyTracer;
  hasRequiredProxyTracer = 1;
  Object.defineProperty(ProxyTracer, "__esModule", { value: true });
  ProxyTracer.ProxyTracer = void 0;
  const NoopTracer_1 = /* @__PURE__ */ requireNoopTracer();
  const NOOP_TRACER = new NoopTracer_1.NoopTracer();
  let ProxyTracer$1 = class ProxyTracer {
    constructor(provider, name, version2, options) {
      this._provider = provider;
      this.name = name;
      this.version = version2;
      this.options = options;
    }
    startSpan(name, options, context2) {
      return this._getTracer().startSpan(name, options, context2);
    }
    startActiveSpan(_name, _options, _context, _fn) {
      const tracer = this._getTracer();
      return Reflect.apply(tracer.startActiveSpan, tracer, arguments);
    }
    /**
     * Try to get a tracer from the proxy tracer provider.
     * If the proxy tracer provider has no delegate, return a noop tracer.
     */
    _getTracer() {
      if (this._delegate) {
        return this._delegate;
      }
      const tracer = this._provider.getDelegateTracer(this.name, this.version, this.options);
      if (!tracer) {
        return NOOP_TRACER;
      }
      this._delegate = tracer;
      return this._delegate;
    }
  };
  ProxyTracer.ProxyTracer = ProxyTracer$1;
  return ProxyTracer;
}
var ProxyTracerProvider = {};
var NoopTracerProvider = {};
var hasRequiredNoopTracerProvider;
function requireNoopTracerProvider() {
  if (hasRequiredNoopTracerProvider) return NoopTracerProvider;
  hasRequiredNoopTracerProvider = 1;
  Object.defineProperty(NoopTracerProvider, "__esModule", { value: true });
  NoopTracerProvider.NoopTracerProvider = void 0;
  const NoopTracer_1 = /* @__PURE__ */ requireNoopTracer();
  let NoopTracerProvider$1 = class NoopTracerProvider {
    getTracer(_name, _version, _options) {
      return new NoopTracer_1.NoopTracer();
    }
  };
  NoopTracerProvider.NoopTracerProvider = NoopTracerProvider$1;
  return NoopTracerProvider;
}
var hasRequiredProxyTracerProvider;
function requireProxyTracerProvider() {
  if (hasRequiredProxyTracerProvider) return ProxyTracerProvider;
  hasRequiredProxyTracerProvider = 1;
  Object.defineProperty(ProxyTracerProvider, "__esModule", { value: true });
  ProxyTracerProvider.ProxyTracerProvider = void 0;
  const ProxyTracer_1 = /* @__PURE__ */ requireProxyTracer();
  const NoopTracerProvider_1 = /* @__PURE__ */ requireNoopTracerProvider();
  const NOOP_TRACER_PROVIDER = new NoopTracerProvider_1.NoopTracerProvider();
  let ProxyTracerProvider$1 = class ProxyTracerProvider {
    /**
     * Get a {@link ProxyTracer}
     */
    getTracer(name, version2, options) {
      var _a;
      return (_a = this.getDelegateTracer(name, version2, options)) !== null && _a !== void 0 ? _a : new ProxyTracer_1.ProxyTracer(this, name, version2, options);
    }
    getDelegate() {
      var _a;
      return (_a = this._delegate) !== null && _a !== void 0 ? _a : NOOP_TRACER_PROVIDER;
    }
    /**
     * Set the delegate tracer provider
     */
    setDelegate(delegate) {
      this._delegate = delegate;
    }
    getDelegateTracer(name, version2, options) {
      var _a;
      return (_a = this._delegate) === null || _a === void 0 ? void 0 : _a.getTracer(name, version2, options);
    }
  };
  ProxyTracerProvider.ProxyTracerProvider = ProxyTracerProvider$1;
  return ProxyTracerProvider;
}
var SamplingResult = {};
var hasRequiredSamplingResult;
function requireSamplingResult() {
  if (hasRequiredSamplingResult) return SamplingResult;
  hasRequiredSamplingResult = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.SamplingDecision = void 0;
    (function(SamplingDecision) {
      SamplingDecision[SamplingDecision["NOT_RECORD"] = 0] = "NOT_RECORD";
      SamplingDecision[SamplingDecision["RECORD"] = 1] = "RECORD";
      SamplingDecision[SamplingDecision["RECORD_AND_SAMPLED"] = 2] = "RECORD_AND_SAMPLED";
    })(exports.SamplingDecision || (exports.SamplingDecision = {}));
  })(SamplingResult);
  return SamplingResult;
}
var span_kind = {};
var hasRequiredSpan_kind;
function requireSpan_kind() {
  if (hasRequiredSpan_kind) return span_kind;
  hasRequiredSpan_kind = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.SpanKind = void 0;
    (function(SpanKind) {
      SpanKind[SpanKind["INTERNAL"] = 0] = "INTERNAL";
      SpanKind[SpanKind["SERVER"] = 1] = "SERVER";
      SpanKind[SpanKind["CLIENT"] = 2] = "CLIENT";
      SpanKind[SpanKind["PRODUCER"] = 3] = "PRODUCER";
      SpanKind[SpanKind["CONSUMER"] = 4] = "CONSUMER";
    })(exports.SpanKind || (exports.SpanKind = {}));
  })(span_kind);
  return span_kind;
}
var status = {};
var hasRequiredStatus;
function requireStatus() {
  if (hasRequiredStatus) return status;
  hasRequiredStatus = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.SpanStatusCode = void 0;
    (function(SpanStatusCode) {
      SpanStatusCode[SpanStatusCode["UNSET"] = 0] = "UNSET";
      SpanStatusCode[SpanStatusCode["OK"] = 1] = "OK";
      SpanStatusCode[SpanStatusCode["ERROR"] = 2] = "ERROR";
    })(exports.SpanStatusCode || (exports.SpanStatusCode = {}));
  })(status);
  return status;
}
var utils = {};
var tracestateImpl = {};
var tracestateValidators = {};
var hasRequiredTracestateValidators;
function requireTracestateValidators() {
  if (hasRequiredTracestateValidators) return tracestateValidators;
  hasRequiredTracestateValidators = 1;
  Object.defineProperty(tracestateValidators, "__esModule", { value: true });
  tracestateValidators.validateValue = tracestateValidators.validateKey = void 0;
  const VALID_KEY_CHAR_RANGE = "[_0-9a-z-*/]";
  const VALID_KEY = `[a-z]${VALID_KEY_CHAR_RANGE}{0,255}`;
  const VALID_VENDOR_KEY = `[a-z0-9]${VALID_KEY_CHAR_RANGE}{0,240}@[a-z]${VALID_KEY_CHAR_RANGE}{0,13}`;
  const VALID_KEY_REGEX = new RegExp(`^(?:${VALID_KEY}|${VALID_VENDOR_KEY})$`);
  const VALID_VALUE_BASE_REGEX = /^[ -~]{0,255}[!-~]$/;
  const INVALID_VALUE_COMMA_EQUAL_REGEX = /,|=/;
  function validateKey(key) {
    return VALID_KEY_REGEX.test(key);
  }
  tracestateValidators.validateKey = validateKey;
  function validateValue(value) {
    return VALID_VALUE_BASE_REGEX.test(value) && !INVALID_VALUE_COMMA_EQUAL_REGEX.test(value);
  }
  tracestateValidators.validateValue = validateValue;
  return tracestateValidators;
}
var hasRequiredTracestateImpl;
function requireTracestateImpl() {
  if (hasRequiredTracestateImpl) return tracestateImpl;
  hasRequiredTracestateImpl = 1;
  Object.defineProperty(tracestateImpl, "__esModule", { value: true });
  tracestateImpl.TraceStateImpl = void 0;
  const tracestate_validators_1 = /* @__PURE__ */ requireTracestateValidators();
  const MAX_TRACE_STATE_ITEMS = 32;
  const MAX_TRACE_STATE_LEN = 512;
  const LIST_MEMBERS_SEPARATOR = ",";
  const LIST_MEMBER_KEY_VALUE_SPLITTER = "=";
  class TraceStateImpl {
    constructor(rawTraceState) {
      this._internalState = /* @__PURE__ */ new Map();
      if (rawTraceState)
        this._parse(rawTraceState);
    }
    set(key, value) {
      const traceState = this._clone();
      if (traceState._internalState.has(key)) {
        traceState._internalState.delete(key);
      }
      traceState._internalState.set(key, value);
      return traceState;
    }
    unset(key) {
      const traceState = this._clone();
      traceState._internalState.delete(key);
      return traceState;
    }
    get(key) {
      return this._internalState.get(key);
    }
    serialize() {
      return Array.from(this._internalState.keys()).reduceRight((agg, key) => {
        agg.push(key + LIST_MEMBER_KEY_VALUE_SPLITTER + this.get(key));
        return agg;
      }, []).join(LIST_MEMBERS_SEPARATOR);
    }
    _parse(rawTraceState) {
      if (rawTraceState.length > MAX_TRACE_STATE_LEN)
        return;
      this._internalState = rawTraceState.split(LIST_MEMBERS_SEPARATOR).reduceRight((agg, part) => {
        const listMember = part.trim();
        const i = listMember.indexOf(LIST_MEMBER_KEY_VALUE_SPLITTER);
        if (i !== -1) {
          const key = listMember.slice(0, i);
          const value = listMember.slice(i + 1, part.length);
          if ((0, tracestate_validators_1.validateKey)(key) && (0, tracestate_validators_1.validateValue)(value)) {
            agg.set(key, value);
          }
        }
        return agg;
      }, /* @__PURE__ */ new Map());
      if (this._internalState.size > MAX_TRACE_STATE_ITEMS) {
        this._internalState = new Map(Array.from(this._internalState.entries()).reverse().slice(0, MAX_TRACE_STATE_ITEMS));
      }
    }
    // @ts-expect-error TS6133 Accessed in tests only.
    _keys() {
      return Array.from(this._internalState.keys()).reverse();
    }
    _clone() {
      const traceState = new TraceStateImpl();
      traceState._internalState = new Map(this._internalState);
      return traceState;
    }
  }
  tracestateImpl.TraceStateImpl = TraceStateImpl;
  return tracestateImpl;
}
var hasRequiredUtils;
function requireUtils() {
  if (hasRequiredUtils) return utils;
  hasRequiredUtils = 1;
  Object.defineProperty(utils, "__esModule", { value: true });
  utils.createTraceState = void 0;
  const tracestate_impl_1 = /* @__PURE__ */ requireTracestateImpl();
  function createTraceState(rawTraceState) {
    return new tracestate_impl_1.TraceStateImpl(rawTraceState);
  }
  utils.createTraceState = createTraceState;
  return utils;
}
var contextApi = {};
var hasRequiredContextApi;
function requireContextApi() {
  if (hasRequiredContextApi) return contextApi;
  hasRequiredContextApi = 1;
  Object.defineProperty(contextApi, "__esModule", { value: true });
  contextApi.context = void 0;
  const context_1 = /* @__PURE__ */ requireContext();
  contextApi.context = context_1.ContextAPI.getInstance();
  return contextApi;
}
var diagApi = {};
var hasRequiredDiagApi;
function requireDiagApi() {
  if (hasRequiredDiagApi) return diagApi;
  hasRequiredDiagApi = 1;
  Object.defineProperty(diagApi, "__esModule", { value: true });
  diagApi.diag = void 0;
  const diag_1 = /* @__PURE__ */ requireDiag();
  diagApi.diag = diag_1.DiagAPI.instance();
  return diagApi;
}
var metricsApi = {};
var metrics = {};
var NoopMeterProvider = {};
var hasRequiredNoopMeterProvider;
function requireNoopMeterProvider() {
  if (hasRequiredNoopMeterProvider) return NoopMeterProvider;
  hasRequiredNoopMeterProvider = 1;
  Object.defineProperty(NoopMeterProvider, "__esModule", { value: true });
  NoopMeterProvider.NOOP_METER_PROVIDER = NoopMeterProvider.NoopMeterProvider = void 0;
  const NoopMeter_1 = /* @__PURE__ */ requireNoopMeter();
  let NoopMeterProvider$1 = class NoopMeterProvider {
    getMeter(_name, _version, _options) {
      return NoopMeter_1.NOOP_METER;
    }
  };
  NoopMeterProvider.NoopMeterProvider = NoopMeterProvider$1;
  NoopMeterProvider.NOOP_METER_PROVIDER = new NoopMeterProvider$1();
  return NoopMeterProvider;
}
var hasRequiredMetrics;
function requireMetrics() {
  if (hasRequiredMetrics) return metrics;
  hasRequiredMetrics = 1;
  Object.defineProperty(metrics, "__esModule", { value: true });
  metrics.MetricsAPI = void 0;
  const NoopMeterProvider_1 = /* @__PURE__ */ requireNoopMeterProvider();
  const global_utils_1 = /* @__PURE__ */ requireGlobalUtils();
  const diag_1 = /* @__PURE__ */ requireDiag();
  const API_NAME = "metrics";
  class MetricsAPI {
    /** Empty private constructor prevents end users from constructing a new instance of the API */
    constructor() {
    }
    /** Get the singleton instance of the Metrics API */
    static getInstance() {
      if (!this._instance) {
        this._instance = new MetricsAPI();
      }
      return this._instance;
    }
    /**
     * Set the current global meter provider.
     * Returns true if the meter provider was successfully registered, else false.
     */
    setGlobalMeterProvider(provider) {
      return (0, global_utils_1.registerGlobal)(API_NAME, provider, diag_1.DiagAPI.instance());
    }
    /**
     * Returns the global meter provider.
     */
    getMeterProvider() {
      return (0, global_utils_1.getGlobal)(API_NAME) || NoopMeterProvider_1.NOOP_METER_PROVIDER;
    }
    /**
     * Returns a meter from the global meter provider.
     */
    getMeter(name, version2, options) {
      return this.getMeterProvider().getMeter(name, version2, options);
    }
    /** Remove the global meter provider */
    disable() {
      (0, global_utils_1.unregisterGlobal)(API_NAME, diag_1.DiagAPI.instance());
    }
  }
  metrics.MetricsAPI = MetricsAPI;
  return metrics;
}
var hasRequiredMetricsApi;
function requireMetricsApi() {
  if (hasRequiredMetricsApi) return metricsApi;
  hasRequiredMetricsApi = 1;
  Object.defineProperty(metricsApi, "__esModule", { value: true });
  metricsApi.metrics = void 0;
  const metrics_1 = /* @__PURE__ */ requireMetrics();
  metricsApi.metrics = metrics_1.MetricsAPI.getInstance();
  return metricsApi;
}
var propagationApi = {};
var propagation = {};
var NoopTextMapPropagator = {};
var hasRequiredNoopTextMapPropagator;
function requireNoopTextMapPropagator() {
  if (hasRequiredNoopTextMapPropagator) return NoopTextMapPropagator;
  hasRequiredNoopTextMapPropagator = 1;
  Object.defineProperty(NoopTextMapPropagator, "__esModule", { value: true });
  NoopTextMapPropagator.NoopTextMapPropagator = void 0;
  let NoopTextMapPropagator$1 = class NoopTextMapPropagator {
    /** Noop inject function does nothing */
    inject(_context, _carrier) {
    }
    /** Noop extract function does nothing and returns the input context */
    extract(context2, _carrier) {
      return context2;
    }
    fields() {
      return [];
    }
  };
  NoopTextMapPropagator.NoopTextMapPropagator = NoopTextMapPropagator$1;
  return NoopTextMapPropagator;
}
var contextHelpers = {};
var hasRequiredContextHelpers;
function requireContextHelpers() {
  if (hasRequiredContextHelpers) return contextHelpers;
  hasRequiredContextHelpers = 1;
  Object.defineProperty(contextHelpers, "__esModule", { value: true });
  contextHelpers.deleteBaggage = contextHelpers.setBaggage = contextHelpers.getActiveBaggage = contextHelpers.getBaggage = void 0;
  const context_1 = /* @__PURE__ */ requireContext();
  const context_2 = /* @__PURE__ */ requireContext$1();
  const BAGGAGE_KEY = (0, context_2.createContextKey)("OpenTelemetry Baggage Key");
  function getBaggage(context2) {
    return context2.getValue(BAGGAGE_KEY) || void 0;
  }
  contextHelpers.getBaggage = getBaggage;
  function getActiveBaggage() {
    return getBaggage(context_1.ContextAPI.getInstance().active());
  }
  contextHelpers.getActiveBaggage = getActiveBaggage;
  function setBaggage(context2, baggage) {
    return context2.setValue(BAGGAGE_KEY, baggage);
  }
  contextHelpers.setBaggage = setBaggage;
  function deleteBaggage(context2) {
    return context2.deleteValue(BAGGAGE_KEY);
  }
  contextHelpers.deleteBaggage = deleteBaggage;
  return contextHelpers;
}
var hasRequiredPropagation;
function requirePropagation() {
  if (hasRequiredPropagation) return propagation;
  hasRequiredPropagation = 1;
  Object.defineProperty(propagation, "__esModule", { value: true });
  propagation.PropagationAPI = void 0;
  const global_utils_1 = /* @__PURE__ */ requireGlobalUtils();
  const NoopTextMapPropagator_1 = /* @__PURE__ */ requireNoopTextMapPropagator();
  const TextMapPropagator_1 = /* @__PURE__ */ requireTextMapPropagator();
  const context_helpers_1 = /* @__PURE__ */ requireContextHelpers();
  const utils_1 = /* @__PURE__ */ requireUtils$1();
  const diag_1 = /* @__PURE__ */ requireDiag();
  const API_NAME = "propagation";
  const NOOP_TEXT_MAP_PROPAGATOR = new NoopTextMapPropagator_1.NoopTextMapPropagator();
  class PropagationAPI {
    /** Empty private constructor prevents end users from constructing a new instance of the API */
    constructor() {
      this.createBaggage = utils_1.createBaggage;
      this.getBaggage = context_helpers_1.getBaggage;
      this.getActiveBaggage = context_helpers_1.getActiveBaggage;
      this.setBaggage = context_helpers_1.setBaggage;
      this.deleteBaggage = context_helpers_1.deleteBaggage;
    }
    /** Get the singleton instance of the Propagator API */
    static getInstance() {
      if (!this._instance) {
        this._instance = new PropagationAPI();
      }
      return this._instance;
    }
    /**
     * Set the current propagator.
     *
     * @returns true if the propagator was successfully registered, else false
     */
    setGlobalPropagator(propagator) {
      return (0, global_utils_1.registerGlobal)(API_NAME, propagator, diag_1.DiagAPI.instance());
    }
    /**
     * Inject context into a carrier to be propagated inter-process
     *
     * @param context Context carrying tracing data to inject
     * @param carrier carrier to inject context into
     * @param setter Function used to set values on the carrier
     */
    inject(context2, carrier, setter = TextMapPropagator_1.defaultTextMapSetter) {
      return this._getGlobalPropagator().inject(context2, carrier, setter);
    }
    /**
     * Extract context from a carrier
     *
     * @param context Context which the newly created context will inherit from
     * @param carrier Carrier to extract context from
     * @param getter Function used to extract keys from a carrier
     */
    extract(context2, carrier, getter = TextMapPropagator_1.defaultTextMapGetter) {
      return this._getGlobalPropagator().extract(context2, carrier, getter);
    }
    /**
     * Return a list of all fields which may be used by the propagator.
     */
    fields() {
      return this._getGlobalPropagator().fields();
    }
    /** Remove the global propagator */
    disable() {
      (0, global_utils_1.unregisterGlobal)(API_NAME, diag_1.DiagAPI.instance());
    }
    _getGlobalPropagator() {
      return (0, global_utils_1.getGlobal)(API_NAME) || NOOP_TEXT_MAP_PROPAGATOR;
    }
  }
  propagation.PropagationAPI = PropagationAPI;
  return propagation;
}
var hasRequiredPropagationApi;
function requirePropagationApi() {
  if (hasRequiredPropagationApi) return propagationApi;
  hasRequiredPropagationApi = 1;
  Object.defineProperty(propagationApi, "__esModule", { value: true });
  propagationApi.propagation = void 0;
  const propagation_1 = /* @__PURE__ */ requirePropagation();
  propagationApi.propagation = propagation_1.PropagationAPI.getInstance();
  return propagationApi;
}
var traceApi = {};
var trace = {};
var hasRequiredTrace;
function requireTrace() {
  if (hasRequiredTrace) return trace;
  hasRequiredTrace = 1;
  Object.defineProperty(trace, "__esModule", { value: true });
  trace.TraceAPI = void 0;
  const global_utils_1 = /* @__PURE__ */ requireGlobalUtils();
  const ProxyTracerProvider_1 = /* @__PURE__ */ requireProxyTracerProvider();
  const spancontext_utils_1 = /* @__PURE__ */ requireSpancontextUtils();
  const context_utils_1 = /* @__PURE__ */ requireContextUtils();
  const diag_1 = /* @__PURE__ */ requireDiag();
  const API_NAME = "trace";
  class TraceAPI {
    /** Empty private constructor prevents end users from constructing a new instance of the API */
    constructor() {
      this._proxyTracerProvider = new ProxyTracerProvider_1.ProxyTracerProvider();
      this.wrapSpanContext = spancontext_utils_1.wrapSpanContext;
      this.isSpanContextValid = spancontext_utils_1.isSpanContextValid;
      this.deleteSpan = context_utils_1.deleteSpan;
      this.getSpan = context_utils_1.getSpan;
      this.getActiveSpan = context_utils_1.getActiveSpan;
      this.getSpanContext = context_utils_1.getSpanContext;
      this.setSpan = context_utils_1.setSpan;
      this.setSpanContext = context_utils_1.setSpanContext;
    }
    /** Get the singleton instance of the Trace API */
    static getInstance() {
      if (!this._instance) {
        this._instance = new TraceAPI();
      }
      return this._instance;
    }
    /**
     * Set the current global tracer.
     *
     * @returns true if the tracer provider was successfully registered, else false
     */
    setGlobalTracerProvider(provider) {
      const success = (0, global_utils_1.registerGlobal)(API_NAME, this._proxyTracerProvider, diag_1.DiagAPI.instance());
      if (success) {
        this._proxyTracerProvider.setDelegate(provider);
      }
      return success;
    }
    /**
     * Returns the global tracer provider.
     */
    getTracerProvider() {
      return (0, global_utils_1.getGlobal)(API_NAME) || this._proxyTracerProvider;
    }
    /**
     * Returns a tracer from the global tracer provider.
     */
    getTracer(name, version2) {
      return this.getTracerProvider().getTracer(name, version2);
    }
    /** Remove the global tracer provider */
    disable() {
      (0, global_utils_1.unregisterGlobal)(API_NAME, diag_1.DiagAPI.instance());
      this._proxyTracerProvider = new ProxyTracerProvider_1.ProxyTracerProvider();
    }
  }
  trace.TraceAPI = TraceAPI;
  return trace;
}
var hasRequiredTraceApi;
function requireTraceApi() {
  if (hasRequiredTraceApi) return traceApi;
  hasRequiredTraceApi = 1;
  Object.defineProperty(traceApi, "__esModule", { value: true });
  traceApi.trace = void 0;
  const trace_1 = /* @__PURE__ */ requireTrace();
  traceApi.trace = trace_1.TraceAPI.getInstance();
  return traceApi;
}
var hasRequiredSrc;
function requireSrc() {
  if (hasRequiredSrc) return src;
  hasRequiredSrc = 1;
  (function(exports) {
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.trace = exports.propagation = exports.metrics = exports.diag = exports.context = exports.INVALID_SPAN_CONTEXT = exports.INVALID_TRACEID = exports.INVALID_SPANID = exports.isValidSpanId = exports.isValidTraceId = exports.isSpanContextValid = exports.createTraceState = exports.TraceFlags = exports.SpanStatusCode = exports.SpanKind = exports.SamplingDecision = exports.ProxyTracerProvider = exports.ProxyTracer = exports.defaultTextMapSetter = exports.defaultTextMapGetter = exports.ValueType = exports.createNoopMeter = exports.DiagLogLevel = exports.DiagConsoleLogger = exports.ROOT_CONTEXT = exports.createContextKey = exports.baggageEntryMetadataFromString = void 0;
    var utils_1 = /* @__PURE__ */ requireUtils$1();
    Object.defineProperty(exports, "baggageEntryMetadataFromString", { enumerable: true, get: function() {
      return utils_1.baggageEntryMetadataFromString;
    } });
    var context_1 = /* @__PURE__ */ requireContext$1();
    Object.defineProperty(exports, "createContextKey", { enumerable: true, get: function() {
      return context_1.createContextKey;
    } });
    Object.defineProperty(exports, "ROOT_CONTEXT", { enumerable: true, get: function() {
      return context_1.ROOT_CONTEXT;
    } });
    var consoleLogger_1 = /* @__PURE__ */ requireConsoleLogger();
    Object.defineProperty(exports, "DiagConsoleLogger", { enumerable: true, get: function() {
      return consoleLogger_1.DiagConsoleLogger;
    } });
    var types_1 = /* @__PURE__ */ requireTypes();
    Object.defineProperty(exports, "DiagLogLevel", { enumerable: true, get: function() {
      return types_1.DiagLogLevel;
    } });
    var NoopMeter_1 = /* @__PURE__ */ requireNoopMeter();
    Object.defineProperty(exports, "createNoopMeter", { enumerable: true, get: function() {
      return NoopMeter_1.createNoopMeter;
    } });
    var Metric_1 = /* @__PURE__ */ requireMetric();
    Object.defineProperty(exports, "ValueType", { enumerable: true, get: function() {
      return Metric_1.ValueType;
    } });
    var TextMapPropagator_1 = /* @__PURE__ */ requireTextMapPropagator();
    Object.defineProperty(exports, "defaultTextMapGetter", { enumerable: true, get: function() {
      return TextMapPropagator_1.defaultTextMapGetter;
    } });
    Object.defineProperty(exports, "defaultTextMapSetter", { enumerable: true, get: function() {
      return TextMapPropagator_1.defaultTextMapSetter;
    } });
    var ProxyTracer_1 = /* @__PURE__ */ requireProxyTracer();
    Object.defineProperty(exports, "ProxyTracer", { enumerable: true, get: function() {
      return ProxyTracer_1.ProxyTracer;
    } });
    var ProxyTracerProvider_1 = /* @__PURE__ */ requireProxyTracerProvider();
    Object.defineProperty(exports, "ProxyTracerProvider", { enumerable: true, get: function() {
      return ProxyTracerProvider_1.ProxyTracerProvider;
    } });
    var SamplingResult_1 = /* @__PURE__ */ requireSamplingResult();
    Object.defineProperty(exports, "SamplingDecision", { enumerable: true, get: function() {
      return SamplingResult_1.SamplingDecision;
    } });
    var span_kind_1 = /* @__PURE__ */ requireSpan_kind();
    Object.defineProperty(exports, "SpanKind", { enumerable: true, get: function() {
      return span_kind_1.SpanKind;
    } });
    var status_1 = /* @__PURE__ */ requireStatus();
    Object.defineProperty(exports, "SpanStatusCode", { enumerable: true, get: function() {
      return status_1.SpanStatusCode;
    } });
    var trace_flags_1 = /* @__PURE__ */ requireTrace_flags();
    Object.defineProperty(exports, "TraceFlags", { enumerable: true, get: function() {
      return trace_flags_1.TraceFlags;
    } });
    var utils_2 = /* @__PURE__ */ requireUtils();
    Object.defineProperty(exports, "createTraceState", { enumerable: true, get: function() {
      return utils_2.createTraceState;
    } });
    var spancontext_utils_1 = /* @__PURE__ */ requireSpancontextUtils();
    Object.defineProperty(exports, "isSpanContextValid", { enumerable: true, get: function() {
      return spancontext_utils_1.isSpanContextValid;
    } });
    Object.defineProperty(exports, "isValidTraceId", { enumerable: true, get: function() {
      return spancontext_utils_1.isValidTraceId;
    } });
    Object.defineProperty(exports, "isValidSpanId", { enumerable: true, get: function() {
      return spancontext_utils_1.isValidSpanId;
    } });
    var invalid_span_constants_1 = /* @__PURE__ */ requireInvalidSpanConstants();
    Object.defineProperty(exports, "INVALID_SPANID", { enumerable: true, get: function() {
      return invalid_span_constants_1.INVALID_SPANID;
    } });
    Object.defineProperty(exports, "INVALID_TRACEID", { enumerable: true, get: function() {
      return invalid_span_constants_1.INVALID_TRACEID;
    } });
    Object.defineProperty(exports, "INVALID_SPAN_CONTEXT", { enumerable: true, get: function() {
      return invalid_span_constants_1.INVALID_SPAN_CONTEXT;
    } });
    const context_api_1 = /* @__PURE__ */ requireContextApi();
    Object.defineProperty(exports, "context", { enumerable: true, get: function() {
      return context_api_1.context;
    } });
    const diag_api_1 = /* @__PURE__ */ requireDiagApi();
    Object.defineProperty(exports, "diag", { enumerable: true, get: function() {
      return diag_api_1.diag;
    } });
    const metrics_api_1 = /* @__PURE__ */ requireMetricsApi();
    Object.defineProperty(exports, "metrics", { enumerable: true, get: function() {
      return metrics_api_1.metrics;
    } });
    const propagation_api_1 = /* @__PURE__ */ requirePropagationApi();
    Object.defineProperty(exports, "propagation", { enumerable: true, get: function() {
      return propagation_api_1.propagation;
    } });
    const trace_api_1 = /* @__PURE__ */ requireTraceApi();
    Object.defineProperty(exports, "trace", { enumerable: true, get: function() {
      return trace_api_1.trace;
    } });
    exports.default = {
      context: context_api_1.context,
      diag: diag_api_1.diag,
      metrics: metrics_api_1.metrics,
      propagation: propagation_api_1.propagation,
      trace: trace_api_1.trace
    };
  })(src);
  return src;
}
var srcExports = /* @__PURE__ */ requireSrc();
export {
  srcExports as s
};
