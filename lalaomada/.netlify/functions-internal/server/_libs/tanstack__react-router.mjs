import { r as reactExports, j as jsxRuntimeExports, R as React__default } from "./react.mjs";
import { i as invariant, a as isDangerousProtocol, e as exactPathTest, r as removeTrailingSlash, h as hasKeys, d as deepEqual, f as functionalUpdate, B as BaseRootRoute, b as BaseRoute, c as isModuleNotFoundError, g as isNotFound, j as getScrollRestorationScriptForRouter, k as rootRouteId, l as createNonReactiveReadonlyStore, m as createNonReactiveMutableStore, R as RouterCore, _ as _getAssetMatches, n as escapeHtml, o as getAssetCrossOrigin, p as getScriptPreloadAttrs, q as appendUniqueUserTags, s as resolveManifestCssLink, t as transformReadableStreamWithRouter, u as createSsrStreamResponse, v as transformPipeableStreamWithRouter } from "./tanstack__router-core.mjs";
import { R as ReactDOMServer } from "./react-dom.mjs";
import { PassThrough } from "node:stream";
import { i as isbot } from "./isbot.mjs";
var reactUse = reactExports.use;
var useLayoutEffect = reactExports.useEffect;
function useForwardedRef(ref) {
  const innerRef = reactExports.useRef(null);
  reactExports.useImperativeHandle(ref, () => innerRef.current, []);
  return innerRef;
}
function CatchBoundary(props) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(CatchBoundaryImpl, { ...props });
}
var CatchBoundaryImpl = class extends reactExports.Component {
  constructor(..._args) {
    super(..._args);
    this.state = { error: null };
    this.reset = () => {
      this.setState({ error: null });
    };
  }
  static getDerivedStateFromProps(props, state) {
    const resetKey = props.getResetKey();
    if (state.error && state.resetKey !== resetKey) return {
      resetKey,
      error: null
    };
    return { resetKey };
  }
  static getDerivedStateFromError(error) {
    return { error };
  }
  componentDidCatch(error, errorInfo) {
    this.props.onCatch?.(error, errorInfo);
  }
  render() {
    const error = this.state.error;
    return error ? reactExports.createElement(this.props.errorComponent ?? ErrorComponent, {
      error,
      reset: this.reset
    }) : this.props.children;
  }
};
function ErrorComponent({ error }) {
  const [show, setShow] = reactExports.useState(false);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", {
    style: {
      padding: ".5rem",
      maxWidth: "100%"
    },
    children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", {
        style: {
          display: "flex",
          alignItems: "center",
          gap: ".5rem"
        },
        children: [/* @__PURE__ */ jsxRuntimeExports.jsx("strong", {
          style: { fontSize: "1rem" },
          children: "Something went wrong!"
        }), /* @__PURE__ */ jsxRuntimeExports.jsx("button", {
          style: {
            appearance: "none",
            fontSize: ".6em",
            border: "1px solid currentColor",
            padding: ".1rem .2rem",
            fontWeight: "bold",
            borderRadius: ".25rem"
          },
          onClick: () => setShow((d) => !d),
          children: show ? "Hide Error" : "Show Error"
        })]
      }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { style: { height: ".25rem" } }),
      show ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: /* @__PURE__ */ jsxRuntimeExports.jsx("pre", {
        style: {
          fontSize: ".7em",
          border: "1px solid red",
          borderRadius: ".25rem",
          padding: ".3rem",
          color: "red",
          overflow: "auto"
        },
        children: error.message ? /* @__PURE__ */ jsxRuntimeExports.jsx("code", { children: error.message }) : null
      }) }) : null
    ]
  });
}
function ClientOnly({ children, fallback = null }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(React__default.Fragment, { children: useHydrated() ? children : fallback });
}
function useHydrated() {
  return React__default.useSyncExternalStore(subscribe, () => true, () => false);
}
function subscribe() {
  return () => {
  };
}
var routerContext = reactExports.createContext(null);
function useRouter(opts) {
  const value = reactExports.useContext(routerContext);
  return value;
}
var matchContext = reactExports.createContext(void 0);
var dummyMatchContext = reactExports.createContext(void 0);
function useMatch(opts) {
  const router = useRouter();
  const nearestRouteId = reactExports.useContext(opts.from ? dummyMatchContext : matchContext);
  const routeId = opts.from ?? nearestRouteId;
  const matchStore = router.stores.getMatchStore(routeId);
  {
    const match = matchStore.get();
    if (!match) {
      if (opts.shouldThrow ?? true) {
        invariant();
      }
      return;
    }
    return opts.select ? opts.select(match) : match;
  }
}
function useLoaderData(opts) {
  return useMatch({
    from: opts.from,
    strict: opts.strict,
    structuralSharing: opts.structuralSharing,
    select: (match) => {
      return opts.select ? opts.select(match.loaderData) : match.loaderData;
    }
  });
}
function useLoaderDeps(opts) {
  const { select, ...rest } = opts;
  return useMatch({
    ...rest,
    select: (match) => {
      return select ? select(match.loaderDeps) : match.loaderDeps;
    }
  });
}
function useParams(opts) {
  return useMatch({
    from: opts.from,
    shouldThrow: opts.shouldThrow,
    structuralSharing: opts.structuralSharing,
    strict: opts.strict,
    select: (match) => {
      const params = opts.strict === false ? match.params : match._strictParams;
      return opts.select ? opts.select(params) : params;
    }
  });
}
function useSearch(opts) {
  return useMatch({
    from: opts.from,
    strict: opts.strict,
    shouldThrow: opts.shouldThrow,
    structuralSharing: opts.structuralSharing,
    select: (match) => {
      return opts.select ? opts.select(match.search) : match.search;
    }
  });
}
function useNavigate(_defaultOpts) {
  const router = useRouter();
  return reactExports.useCallback((options) => {
    return router.navigate({
      ...options,
      from: options.from ?? _defaultOpts?.from
    });
  }, [_defaultOpts?.from, router]);
}
function Navigate(props) {
  const router = useRouter();
  const navigate = useNavigate();
  const previousPropsRef = reactExports.useRef(null);
  useLayoutEffect(() => {
    if (previousPropsRef.current !== props) {
      navigate(props);
      previousPropsRef.current = props;
    }
  }, [
    router,
    props,
    navigate
  ]);
  return null;
}
function useRouteContext(opts) {
  return useMatch({
    ...opts,
    select: (match) => opts.select ? opts.select(match.context) : match.context
  });
}
function useLinkProps(options, forwardedRef) {
  const router = useRouter();
  const innerRef = useForwardedRef(forwardedRef);
  const { activeProps, inactiveProps, activeOptions, to, preload: userPreload, preloadDelay: userPreloadDelay, preloadIntentProximity: _preloadIntentProximity, hashScrollIntoView, replace, startTransition, resetScroll, viewTransition, children, target, disabled, style, className, onClick, onBlur, onFocus, onMouseEnter, onMouseLeave, onTouchStart, ignoreBlocker, params: _params, search: _search, hash: _hash, state: _state, mask: _mask, reloadDocument: _reloadDocument, unsafeRelative: _unsafeRelative, from: _from, _fromLocation, ...propsSafeToSpread } = options;
  {
    const safeInternal = isSafeInternal(to);
    if (typeof to === "string" && !safeInternal && to.indexOf(":") > -1) try {
      new URL(to);
      if (isDangerousProtocol(to, router.protocolAllowlist)) {
        if (false) ;
        return {
          ...propsSafeToSpread,
          ref: innerRef,
          href: void 0,
          ...children && { children },
          ...target && { target },
          ...disabled && { disabled },
          ...style && { style },
          ...className && { className }
        };
      }
      return {
        ...propsSafeToSpread,
        ref: innerRef,
        href: to,
        ...children && { children },
        ...target && { target },
        ...disabled && { disabled },
        ...style && { style },
        ...className && { className }
      };
    } catch {
    }
    const next2 = router.buildLocation({
      ...options,
      from: options.from
    });
    const hrefOption2 = getHrefOption(next2.maskedLocation ? next2.maskedLocation.publicHref : next2.publicHref, next2.maskedLocation ? next2.maskedLocation.external : next2.external, router.history, disabled);
    const externalLink2 = (() => {
      if (hrefOption2?.external) {
        if (isDangerousProtocol(hrefOption2.href, router.protocolAllowlist)) {
          return;
        }
        return hrefOption2.href;
      }
      if (safeInternal) return void 0;
      if (typeof to === "string" && to.indexOf(":") > -1) try {
        new URL(to);
        if (isDangerousProtocol(to, router.protocolAllowlist)) {
          if (false) ;
          return;
        }
        return to;
      } catch {
      }
    })();
    const isActive2 = (() => {
      if (externalLink2) return false;
      const currentLocation2 = router.stores.location.get();
      const exact = activeOptions?.exact ?? false;
      if (exact) {
        if (!exactPathTest(currentLocation2.pathname, next2.pathname, router.basepath)) return false;
      } else {
        const currentPathSplit = removeTrailingSlash(currentLocation2.pathname, router.basepath);
        const nextPathSplit = removeTrailingSlash(next2.pathname, router.basepath);
        if (!(currentPathSplit.startsWith(nextPathSplit) && (currentPathSplit.length === nextPathSplit.length || currentPathSplit[nextPathSplit.length] === "/"))) return false;
      }
      if (activeOptions?.includeSearch ?? true) {
        if (currentLocation2.search !== next2.search) {
          const currentSearchEmpty = !currentLocation2.search || typeof currentLocation2.search === "object" && !hasKeys(currentLocation2.search);
          const nextSearchEmpty = !next2.search || typeof next2.search === "object" && !hasKeys(next2.search);
          if (!(currentSearchEmpty && nextSearchEmpty)) {
            if (!deepEqual(currentLocation2.search, next2.search, {
              partial: !exact,
              ignoreUndefined: !activeOptions?.explicitUndefined
            })) return false;
          }
        }
      }
      if (activeOptions?.includeHash) return false;
      return true;
    })();
    if (externalLink2) return {
      ...propsSafeToSpread,
      ref: innerRef,
      href: externalLink2,
      ...children && { children },
      ...target && { target },
      ...disabled && { disabled },
      ...style && { style },
      ...className && { className }
    };
    const resolvedActiveProps2 = isActive2 ? functionalUpdate(activeProps, {}) ?? STATIC_ACTIVE_OBJECT : STATIC_EMPTY_OBJECT;
    const resolvedInactiveProps2 = isActive2 ? STATIC_EMPTY_OBJECT : functionalUpdate(inactiveProps, {}) ?? STATIC_EMPTY_OBJECT;
    const resolvedStyle2 = (() => {
      const baseStyle = style;
      const activeStyle = resolvedActiveProps2.style;
      const inactiveStyle = resolvedInactiveProps2.style;
      if (!baseStyle && !activeStyle && !inactiveStyle) return;
      if (baseStyle && !activeStyle && !inactiveStyle) return baseStyle;
      if (!baseStyle && activeStyle && !inactiveStyle) return activeStyle;
      if (!baseStyle && !activeStyle && inactiveStyle) return inactiveStyle;
      return {
        ...baseStyle,
        ...activeStyle,
        ...inactiveStyle
      };
    })();
    const resolvedClassName2 = (() => {
      const baseClassName = className;
      const activeClassName = resolvedActiveProps2.className;
      const inactiveClassName = resolvedInactiveProps2.className;
      if (!baseClassName && !activeClassName && !inactiveClassName) return "";
      let out = "";
      if (baseClassName) out = baseClassName;
      if (activeClassName) out = out ? `${out} ${activeClassName}` : activeClassName;
      if (inactiveClassName) out = out ? `${out} ${inactiveClassName}` : inactiveClassName;
      return out;
    })();
    return {
      ...propsSafeToSpread,
      ...resolvedActiveProps2,
      ...resolvedInactiveProps2,
      href: hrefOption2?.href,
      ref: innerRef,
      disabled: !!disabled,
      target,
      ...resolvedStyle2 && { style: resolvedStyle2 },
      ...resolvedClassName2 && { className: resolvedClassName2 },
      ...disabled && STATIC_DISABLED_PROPS,
      ...isActive2 && STATIC_ACTIVE_PROPS
    };
  }
}
var STATIC_EMPTY_OBJECT = {};
var STATIC_ACTIVE_OBJECT = { className: "active" };
var STATIC_DISABLED_PROPS = {
  role: "link",
  "aria-disabled": true
};
var STATIC_ACTIVE_PROPS = {
  "data-status": "active",
  "aria-current": "page"
};
function getHrefOption(publicHref, external, history, disabled) {
  if (disabled) return void 0;
  if (external) return {
    href: publicHref,
    external: true
  };
  return {
    href: history.createHref(publicHref) || "/",
    external: false
  };
}
function isSafeInternal(to) {
  if (typeof to !== "string") return false;
  const zero = to.charCodeAt(0);
  if (zero === 47) return to.charCodeAt(1) !== 47;
  return zero === 46;
}
var Link = reactExports.forwardRef((props, ref) => {
  const { _asChild, ...rest } = props;
  const { type: _type, ...linkProps } = useLinkProps(rest, ref);
  const children = typeof rest.children === "function" ? rest.children({ isActive: linkProps["data-status"] === "active" }) : rest.children;
  if (!_asChild) {
    const { disabled: _, ...rest2 } = linkProps;
    return reactExports.createElement("a", rest2, children);
  }
  return reactExports.createElement(_asChild, linkProps, children);
});
var Route = class extends BaseRoute {
  /**
  * @deprecated Use the `createRoute` function instead.
  */
  constructor(options) {
    super(options);
    this.useMatch = (opts) => {
      return useMatch({
        select: opts?.select,
        from: this.id,
        structuralSharing: opts?.structuralSharing
      });
    };
    this.useRouteContext = (opts) => {
      return useRouteContext({
        ...opts,
        from: this.id
      });
    };
    this.useSearch = (opts) => {
      return useSearch({
        select: opts?.select,
        structuralSharing: opts?.structuralSharing,
        from: this.id
      });
    };
    this.useParams = (opts) => {
      return useParams({
        select: opts?.select,
        structuralSharing: opts?.structuralSharing,
        from: this.id
      });
    };
    this.useLoaderDeps = (opts) => {
      return useLoaderDeps({
        ...opts,
        from: this.id
      });
    };
    this.useLoaderData = (opts) => {
      return useLoaderData({
        ...opts,
        from: this.id
      });
    };
    this.useNavigate = () => {
      return useNavigate({ from: this.fullPath });
    };
    this.Link = React__default.forwardRef((props, ref) => {
      return /* @__PURE__ */ jsxRuntimeExports.jsx(Link, {
        ref,
        from: this.fullPath,
        ...props
      });
    });
  }
};
function createRoute(options) {
  return new Route(options);
}
function createRootRouteWithContext() {
  return (options) => {
    return createRootRoute(options);
  };
}
var RootRoute = class extends BaseRootRoute {
  /**
  * @deprecated `RootRoute` is now an internal implementation detail. Use `createRootRoute()` instead.
  */
  constructor(options) {
    super(options);
    this.useMatch = (opts) => {
      return useMatch({
        select: opts?.select,
        from: this.id,
        structuralSharing: opts?.structuralSharing
      });
    };
    this.useRouteContext = (opts) => {
      return useRouteContext({
        ...opts,
        from: this.id
      });
    };
    this.useSearch = (opts) => {
      return useSearch({
        select: opts?.select,
        structuralSharing: opts?.structuralSharing,
        from: this.id
      });
    };
    this.useParams = (opts) => {
      return useParams({
        select: opts?.select,
        structuralSharing: opts?.structuralSharing,
        from: this.id
      });
    };
    this.useLoaderDeps = (opts) => {
      return useLoaderDeps({
        ...opts,
        from: this.id
      });
    };
    this.useLoaderData = (opts) => {
      return useLoaderData({
        ...opts,
        from: this.id
      });
    };
    this.useNavigate = () => {
      return useNavigate({ from: this.fullPath });
    };
    this.Link = React__default.forwardRef((props, ref) => {
      return /* @__PURE__ */ jsxRuntimeExports.jsx(Link, {
        ref,
        from: this.fullPath,
        ...props
      });
    });
  }
};
function createRootRoute(options) {
  return new RootRoute(options);
}
function createFileRoute(path) {
  return new FileRoute(path, { silent: true }).createRoute;
}
var FileRoute = class {
  constructor(path, _opts) {
    this.path = path;
    this.createRoute = (options) => {
      const route = createRoute(options);
      route.isRoot = false;
      return route;
    };
    this.silent = _opts?.silent;
  }
};
function lazyRouteComponent(importer, exportName) {
  let loadPromise;
  let comp;
  let error;
  const load = () => {
    if (!loadPromise) {
      error = void 0;
      loadPromise = importer().then((res) => {
        comp = res[exportName];
      }).catch((err) => {
        loadPromise = void 0;
        error = err;
      });
    }
    return loadPromise;
  };
  const lazyComp = function Lazy(props) {
    if (error) {
      if (isModuleNotFoundError(error) && false) ;
      throw error;
    }
    if (!comp) if (reactUse) reactUse(load());
    else throw load();
    return reactExports.createElement(comp, props);
  };
  lazyComp.preload = load;
  return lazyComp;
}
function CatchNotFound(props) {
  const router = useRouter();
  {
    const resetKey = `not-found-${router.stores.location.get().pathname}-${router.stores.status.get()}`;
    return /* @__PURE__ */ jsxRuntimeExports.jsx(CatchBoundary, {
      getResetKey: () => resetKey,
      onCatch: (error, errorInfo) => {
        if (isNotFound(error)) props.onCatch?.(error, errorInfo);
        else throw error;
      },
      errorComponent: ({ error }) => {
        if (isNotFound(error)) return props.fallback?.(error);
        else throw error;
      },
      children: props.children
    });
  }
}
function DefaultGlobalNotFound() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("p", { children: "Not Found" });
}
function ScriptOnce({ children }) {
  const router = useRouter();
  return /* @__PURE__ */ jsxRuntimeExports.jsx("script", {
    nonce: router.options.ssr?.nonce,
    dangerouslySetInnerHTML: { __html: children + ";document.currentScript.remove()" }
  });
}
function SafeFragment(props) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: props.children });
}
function renderRouteNotFound(router, route, data) {
  if (!route.options.notFoundComponent) {
    if (router.options.defaultNotFoundComponent) return /* @__PURE__ */ jsxRuntimeExports.jsx(router.options.defaultNotFoundComponent, { ...data });
    return /* @__PURE__ */ jsxRuntimeExports.jsx(DefaultGlobalNotFound, {});
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx(route.options.notFoundComponent, { ...data });
}
function ScrollRestoration() {
  const script = getScrollRestorationScriptForRouter(useRouter());
  if (!script) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx(ScriptOnce, { children: script });
}
function renderPending(router, route) {
  const PendingComponent = route?.options.pendingComponent ?? router.options.defaultPendingComponent;
  return PendingComponent ? /* @__PURE__ */ jsxRuntimeExports.jsx(PendingComponent, {}) : null;
}
var Match = reactExports.memo(function MatchImpl({ routeId }) {
  const router = useRouter();
  return /* @__PURE__ */ jsxRuntimeExports.jsx(MatchView, {
    router,
    match: router.stores.byRoute.get(routeId).get()
  });
});
function MatchView({ router, match }) {
  const route = router.routesById[match.routeId];
  const pendingElement = renderPending(router, route);
  const routeErrorComponent = route.options.errorComponent ?? router.options.defaultErrorComponent;
  const routeOnCatch = route.options.onCatch ?? router.options.defaultOnCatch;
  const routeNotFoundComponent = route.isRoot ? route.options.notFoundComponent ?? router.options.notFoundRoute?.options.component : route.options.notFoundComponent;
  const resolvedNoSsr = match.ssr === false || match.ssr === "data-only";
  const ResolvedSuspenseBoundary = route.options.wrapInSuspense ?? pendingElement ?? (route.options.errorComponent?.preload || resolvedNoSsr) ? reactExports.Suspense : SafeFragment;
  const ResolvedCatchBoundary = routeErrorComponent ? CatchBoundary : SafeFragment;
  const ResolvedNotFoundBoundary = routeNotFoundComponent ? CatchNotFound : SafeFragment;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(route.isRoot ? route.options.shellComponent ?? SafeFragment : SafeFragment, { children: [/* @__PURE__ */ jsxRuntimeExports.jsx(matchContext.Provider, {
    value: match.routeId,
    children: /* @__PURE__ */ jsxRuntimeExports.jsx(ResolvedSuspenseBoundary, {
      fallback: pendingElement,
      children: /* @__PURE__ */ jsxRuntimeExports.jsx(ResolvedCatchBoundary, {
        getResetKey: () => match,
        errorComponent: routeErrorComponent,
        onCatch: (error, errorInfo) => {
          if (isNotFound(error)) {
            error.routeId ??= match.routeId;
            throw error;
          }
          routeOnCatch?.(error, errorInfo);
        },
        children: /* @__PURE__ */ jsxRuntimeExports.jsx(ResolvedNotFoundBoundary, {
          fallback: (error) => {
            error.routeId ??= match.routeId;
            if (error.routeId !== match.routeId) throw error;
            return reactExports.createElement(routeNotFoundComponent, error);
          },
          children: resolvedNoSsr ? /* @__PURE__ */ jsxRuntimeExports.jsx(ClientOnly, {
            fallback: pendingElement,
            children: /* @__PURE__ */ jsxRuntimeExports.jsx(MatchInner, { match })
          }) : /* @__PURE__ */ jsxRuntimeExports.jsx(MatchInner, { match })
        })
      })
    })
  }), route.parentRoute?.id === rootRouteId && router.options.scrollRestoration ? /* @__PURE__ */ jsxRuntimeExports.jsx(ScrollRestoration, {}) : null] });
}
var MatchInner = reactExports.memo(function MatchInnerImpl({ match }) {
  const router = useRouter();
  const routeId = match.routeId;
  const route = router.routesById[routeId];
  const key = reactExports.useMemo(() => {
    const remountDeps = (route.options.remountDeps ?? router.options.defaultRemountDeps)?.({
      routeId,
      loaderDeps: match.loaderDeps,
      params: match._strictParams,
      search: match._strictSearch
    });
    return remountDeps ? JSON.stringify(remountDeps) : void 0;
  }, [
    routeId,
    match.loaderDeps,
    match._strictParams,
    match._strictSearch,
    route.options.remountDeps,
    router.options.defaultRemountDeps
  ]);
  const out = reactExports.useMemo(() => {
    const Comp = route.options.component ?? router.options.defaultComponent;
    return Comp ? /* @__PURE__ */ jsxRuntimeExports.jsx(Comp, {}, key) : /* @__PURE__ */ jsxRuntimeExports.jsx(Outlet, {});
  }, [
    key,
    route.options.component,
    router.options.defaultComponent
  ]);
  if (match.status === "pending") {
    if (router._tx) throw router._tx[5];
    return renderPending(router, route);
  }
  if (match.status === "notFound") return renderRouteNotFound(router, route, match.error);
  if (match.status === "error") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx((route.options.errorComponent ?? router.options.defaultErrorComponent) || ErrorComponent, {
      error: match.error,
      reset: void 0,
      info: { componentStack: "" }
    });
  }
  return out;
});
var Outlet = reactExports.memo(function OutletImpl() {
  const router = useRouter();
  const routeId = reactExports.useContext(matchContext);
  let parentGlobalNotFound;
  let parentNotFoundError;
  let childRouteId;
  {
    const matches = router.stores.matches.get();
    const parentIndex = matches.findIndex((match) => match.routeId === routeId);
    const parentMatch = matches[parentIndex];
    parentGlobalNotFound = !!parentMatch._notFound;
    parentNotFoundError = parentMatch.error;
    childRouteId = matches[parentIndex + 1]?.routeId;
  }
  if (parentGlobalNotFound) return renderRouteNotFound(router, router.routesById[routeId], parentNotFoundError);
  if (!childRouteId) return null;
  const nextMatch = /* @__PURE__ */ jsxRuntimeExports.jsx(Match, { routeId: childRouteId });
  if (routeId === rootRouteId) return /* @__PURE__ */ jsxRuntimeExports.jsx(reactExports.Suspense, {
    fallback: renderPending(router),
    children: nextMatch
  });
  return nextMatch;
});
function settleOwner(owner, rendered) {
  const settle = owner[1];
  owner.length = 0;
  settle?.(rendered);
}
function Matches() {
  const router = useRouter();
  const rootRoute = router.routesById[rootRouteId];
  const pendingElement = renderPending(router, rootRoute);
  const ResolvedSuspense = SafeFragment;
  const inner = /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [false, /* @__PURE__ */ jsxRuntimeExports.jsx(ResolvedSuspense, {
    fallback: pendingElement,
    children: /* @__PURE__ */ jsxRuntimeExports.jsx(MatchesInner, {})
  })] });
  return router.options.InnerWrap ? /* @__PURE__ */ jsxRuntimeExports.jsx(router.options.InnerWrap, { children: inner }) : inner;
}
function MatchesInner() {
  const router = useRouter();
  const acknowledgement = router._rendered;
  const matches = router.stores.matches.get();
  const match = matches[0];
  const routeId = match?.routeId;
  useLayoutEffect(() => {
    if (acknowledgement[0] === matches) settleOwner(acknowledgement, true);
  }, [acknowledgement, matches]);
  const matchComponent = routeId ? /* @__PURE__ */ jsxRuntimeExports.jsx(Match, { routeId }) : null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx(matchContext.Provider, {
    value: routeId,
    children: router.options.disableGlobalCatchBoundary ? matchComponent : /* @__PURE__ */ jsxRuntimeExports.jsx(CatchBoundary, {
      getResetKey: () => match,
      onCatch: void 0,
      children: matchComponent
    })
  });
}
var getStoreFactory = (opts) => {
  return {
    createMutableStore: createNonReactiveMutableStore,
    createReadonlyStore: createNonReactiveReadonlyStore,
    batch: (fn) => fn()
  };
};
var createRouter = (options) => {
  return new Router(options);
};
var Router = class extends RouterCore {
  constructor(options) {
    super(options, getStoreFactory);
  }
};
function RouterContextProvider({ router, children, ...rest }) {
  if (hasKeys(rest)) router.update({
    ...router.options,
    ...rest,
    context: {
      ...router.options.context,
      ...rest.context
    }
  });
  const provider = /* @__PURE__ */ jsxRuntimeExports.jsx(routerContext.Provider, {
    value: router,
    children
  });
  if (router.options.Wrap) return /* @__PURE__ */ jsxRuntimeExports.jsx(router.options.Wrap, { children: provider });
  return provider;
}
function RouterProvider({ router, ...rest }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(RouterContextProvider, {
    router,
    ...rest,
    children: /* @__PURE__ */ jsxRuntimeExports.jsx(Matches, {})
  });
}
function useRouterState(opts) {
  const contextRouter = useRouter({ warn: opts?.router === void 0 });
  const router = opts?.router || contextRouter;
  {
    const state = router.stores.__store.get();
    return opts?.select ? opts.select(state) : state;
  }
}
function useLocation(opts) {
  const router = useRouter();
  {
    const location = router.stores.location.get();
    return location;
  }
}
var noopScriptHandler = () => {
};
function setScriptAttrs(script, attrs) {
  if (!attrs) return;
  for (const [key, value] of Object.entries(attrs)) if (key !== "suppressHydrationWarning" && value !== void 0 && value !== false) script.setAttribute(key, typeof value === "boolean" ? "" : String(value));
}
function Asset(asset) {
  const { attrs, children, nonce, preventScriptHoist } = asset;
  switch (asset.tag) {
    case "title":
      return /* @__PURE__ */ jsxRuntimeExports.jsx("title", {
        ...attrs,
        suppressHydrationWarning: true,
        children
      });
    case "meta":
      return /* @__PURE__ */ jsxRuntimeExports.jsx("meta", {
        ...attrs,
        suppressHydrationWarning: true
      });
    case "link":
      return /* @__PURE__ */ jsxRuntimeExports.jsx("link", {
        ...attrs,
        precedence: attrs?.precedence ?? (attrs?.rel === "stylesheet" ? "default" : void 0),
        nonce,
        suppressHydrationWarning: true
      });
    case "style":
      if (asset.inlineCss && false) ;
      return /* @__PURE__ */ jsxRuntimeExports.jsx("style", {
        ...attrs,
        dangerouslySetInnerHTML: { __html: children },
        nonce
      });
    case "script":
      return /* @__PURE__ */ jsxRuntimeExports.jsx(Script, {
        attrs,
        preventScriptHoist,
        children
      });
    default:
      return null;
  }
}
function Script({ attrs, children, preventScriptHoist }) {
  useRouter();
  useHydrated();
  const dataScript = typeof attrs?.type === "string" && attrs.type !== "" && attrs.type !== "text/javascript" && attrs.type !== "module";
  reactExports.useEffect(() => {
    if (dataScript) return;
    if (attrs?.src) {
      const normSrc = (() => {
        try {
          const base = document.baseURI || window.location.href;
          return new URL(attrs.src, base).href;
        } catch {
          return attrs.src;
        }
      })();
      for (const el of document.querySelectorAll("script[src]")) if (el.src === normSrc) return;
      const script = document.createElement("script");
      setScriptAttrs(script, attrs);
      document.head.appendChild(script);
      return () => script.remove();
    }
    if (typeof children === "string") {
      const typeAttr = typeof attrs?.type === "string" ? attrs.type : "text/javascript";
      const nonceAttr = typeof attrs?.nonce === "string" ? attrs.nonce : void 0;
      for (const el of document.querySelectorAll("script:not([src])")) {
        if (!(el instanceof HTMLScriptElement)) continue;
        const sType = el.getAttribute("type") ?? "text/javascript";
        const sNonce = el.getAttribute("nonce") ?? void 0;
        if (el.textContent === children && sType === typeAttr && sNonce === nonceAttr) return;
      }
      const script = document.createElement("script");
      script.textContent = children;
      setScriptAttrs(script, attrs);
      document.head.appendChild(script);
      return () => script.remove();
    }
  }, [
    attrs,
    children,
    dataScript
  ]);
  {
    if (attrs?.src) {
      if (!preventScriptHoist) return /* @__PURE__ */ jsxRuntimeExports.jsx("script", {
        ...attrs,
        suppressHydrationWarning: true
      });
      return /* @__PURE__ */ jsxRuntimeExports.jsx("script", {
        ...attrs,
        onLoad: noopScriptHandler,
        suppressHydrationWarning: true
      });
    }
    if (typeof children === "string") return /* @__PURE__ */ jsxRuntimeExports.jsx("script", {
      ...attrs,
      dangerouslySetInnerHTML: { __html: children },
      suppressHydrationWarning: true
    });
    return null;
  }
}
function buildTagsFromMatches(router, nonce, matches, assetCrossOrigin) {
  matches = _getAssetMatches(matches);
  const routeMeta = matches.map((match) => match.meta).filter((meta) => meta !== void 0);
  const resultMeta = [];
  const metaByAttribute = {};
  let title;
  for (let i = routeMeta.length - 1; i >= 0; i--) {
    const metas = routeMeta[i];
    for (let j = metas.length - 1; j >= 0; j--) {
      const m = metas[j];
      if (!m) continue;
      if (m.title) {
        if (!title) title = {
          tag: "title",
          children: m.title
        };
      } else if ("script:ld+json" in m) try {
        const json = JSON.stringify(m["script:ld+json"]);
        resultMeta.push({
          tag: "script",
          attrs: { type: "application/ld+json" },
          children: escapeHtml(json)
        });
      } catch {
      }
      else {
        const attribute = m.name ?? m.property;
        if (attribute) if (metaByAttribute[attribute]) continue;
        else metaByAttribute[attribute] = true;
        resultMeta.push({
          tag: "meta",
          attrs: {
            ...m,
            nonce
          }
        });
      }
    }
  }
  if (title) resultMeta.push(title);
  if (nonce) resultMeta.push({
    tag: "meta",
    attrs: {
      property: "csp-nonce",
      content: nonce
    }
  });
  resultMeta.reverse();
  const constructedLinks = matches.flatMap((match) => match.links ?? []).filter((link) => link !== void 0).map((link) => ({
    tag: "link",
    attrs: {
      ...link,
      nonce
    }
  }));
  const manifest = router.ssr?.manifest;
  const manifestCssTags = [];
  if (manifest) {
    matches.forEach((match) => {
      manifest.routes[match.routeId]?.css?.forEach((link) => {
        const resolvedLink = resolveManifestCssLink(link);
        manifestCssTags.push({
          tag: "link",
          attrs: {
            rel: "stylesheet",
            ...resolvedLink,
            crossOrigin: getAssetCrossOrigin(assetCrossOrigin, "stylesheet") ?? resolvedLink.crossOrigin,
            suppressHydrationWarning: true,
            nonce
          }
        });
      });
    });
    if (manifest.inlineStyle) manifestCssTags.push({
      tag: "style",
      attrs: {
        ...manifest.inlineStyle.attrs,
        nonce
      },
      children: manifest.inlineStyle.children,
      inlineCss: true
    });
  }
  const preloadLinks = [];
  if (manifest) matches.forEach((match) => {
    manifest.routes[match.routeId]?.preloads?.forEach((preload) => {
      preloadLinks.push({
        tag: "link",
        attrs: {
          ...getScriptPreloadAttrs(manifest, preload, assetCrossOrigin),
          nonce
        }
      });
    });
  });
  const styles = matches.flatMap((match) => match.styles ?? []).filter((style) => style !== void 0).map(({ children, ...attrs }) => ({
    tag: "style",
    attrs: {
      ...attrs,
      nonce
    },
    children
  }));
  const headScripts = matches.flatMap((match) => match.headScripts ?? []).filter((script) => script !== void 0).map(({ children, ...script }) => ({
    tag: "script",
    attrs: {
      ...script,
      nonce
    },
    children
  }));
  const tags = [];
  appendUniqueUserTags(tags, resultMeta);
  tags.push(...preloadLinks);
  appendUniqueUserTags(tags, constructedLinks);
  tags.push(...manifestCssTags);
  appendUniqueUserTags(tags, styles);
  appendUniqueUserTags(tags, headScripts);
  return tags;
}
var useTags = (assetCrossOrigin) => {
  const router = useRouter();
  const nonce = router.options.ssr?.nonce;
  return buildTagsFromMatches(router, nonce, router.stores.matches.get(), assetCrossOrigin);
};
function HeadContent(props) {
  const tags = useTags(props.assetCrossOrigin);
  const nonce = useRouter().options.ssr?.nonce;
  return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: tags.map((tag) => /* @__PURE__ */ reactExports.createElement(Asset, {
    ...tag,
    key: `tsr-meta-${JSON.stringify(tag)}`,
    nonce
  })) });
}
var Scripts = () => {
  const router = useRouter();
  const nonce = router.options.ssr?.nonce;
  const getScripts = (matches) => {
    matches = _getAssetMatches(matches);
    const scripts = matches.flatMap((match) => match.scripts ?? []).filter(Boolean).map(({ children, ...script }) => ({
      tag: "script",
      attrs: {
        ...script,
        suppressHydrationWarning: true,
        nonce
      },
      children
    }));
    const manifest = router.ssr?.manifest;
    if (!manifest) return scripts;
    for (const match of matches) {
      const manifestScripts = manifest.routes[match.routeId]?.scripts;
      if (!manifestScripts) continue;
      for (const asset of manifestScripts) scripts.push({
        tag: "script",
        attrs: {
          ...asset.attrs,
          nonce
        },
        children: asset.children,
        ...typeof asset.attrs?.src === "string" ? { preventScriptHoist: true } : {}
      });
    }
    return scripts;
  };
  return renderScripts(router, getScripts(router.stores.matches.get()));
};
function renderScripts(router, scripts) {
  if (router.serverSsr) {
    const serverBufferedScript = router.serverSsr.takeBufferedScripts();
    if (serverBufferedScript) scripts.unshift(serverBufferedScript);
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: scripts.map((asset, i) => /* @__PURE__ */ reactExports.createElement(Asset, {
    ...asset,
    key: `tsr-scripts-${asset.tag}-${i}`
  })) });
}
var noop = () => {
};
async function waitForReadyOrAbort(ready, signal) {
  let cleanup = noop;
  try {
    await Promise.race([ready, new Promise((resolve) => {
      const onAbort = () => resolve();
      cleanup = () => signal.removeEventListener("abort", onAbort);
      signal.addEventListener("abort", onAbort, { once: true });
      if (signal.aborted) resolve();
    })]);
  } finally {
    cleanup();
  }
}
var isAbortError = (request, error) => request.signal.aborted && error === request.signal.reason || error instanceof Error && error.name === "AbortError";
var renderRouterToStream = async ({ request, router, responseHeaders, children }) => {
  if (typeof ReactDOMServer.renderToReadableStream === "function") {
    const stream = await ReactDOMServer.renderToReadableStream(children, {
      signal: request.signal,
      nonce: router.options.ssr?.nonce,
      progressiveChunkSize: Number.POSITIVE_INFINITY,
      onError: (error, info) => {
        if (!isAbortError(request, error)) console.error("Error in renderToReadableStream:", error, info);
      }
    });
    if (isbot(request.headers.get("User-Agent"))) await waitForReadyOrAbort(stream.allReady, request.signal);
    const responseStream = transformReadableStreamWithRouter(router, stream, {
      signal: request.signal,
      onAbort: () => stream.cancel().catch(() => {
      })
    });
    return createSsrStreamResponse(router, new Response(responseStream, {
      status: router._serverResult?.type === "render" ? router._serverResult.status : 200,
      headers: responseHeaders
    }));
  }
  if (typeof ReactDOMServer.renderToPipeableStream === "function") {
    const reactAppPassthrough = new PassThrough();
    let pipeable;
    let responseAttached = false;
    let aborted = false;
    let endedBeforeAttach = false;
    let pendingAbortReason;
    const toError = (reason) => reason instanceof Error ? reason : new Error(String(reason ?? "SSR aborted"));
    const destroyError = (reason) => reason === void 0 ? void 0 : toError(reason);
    const pendingDestroyError = () => pendingAbortReason === void 0 ? toError(pendingAbortReason) : destroyError(pendingAbortReason);
    const finishPassThrough = (reason, opts) => {
      if (reactAppPassthrough.destroyed) return;
      if (responseAttached) reactAppPassthrough.destroy(opts?.defaultError ? toError(reason) : destroyError(reason));
      else endedBeforeAttach = true;
    };
    const abortPipeable = (reason, opts) => {
      if (aborted) return;
      aborted = true;
      pendingAbortReason = reason;
      const err = toError(reason);
      try {
        pipeable?.abort(err);
      } catch {
      }
      finishPassThrough(reason, opts);
    };
    if (request.signal.aborted) abortPipeable(request.signal.reason);
    else {
      const onRequestAbort = () => abortPipeable(request.signal.reason);
      request.signal.addEventListener("abort", onRequestAbort, { once: true });
      router.serverSsr?.onCleanup(() => {
        request.signal.removeEventListener("abort", onRequestAbort);
      });
    }
    try {
      pipeable = ReactDOMServer.renderToPipeableStream(children, {
        nonce: router.options.ssr?.nonce,
        progressiveChunkSize: Number.POSITIVE_INFINITY,
        ...isbot(request.headers.get("User-Agent")) ? { onAllReady() {
          pipeable.pipe(reactAppPassthrough);
        } } : { onShellReady() {
          pipeable.pipe(reactAppPassthrough);
        } },
        onError: (error, info) => {
          if (!isAbortError(request, error)) console.error("Error in renderToPipeableStream:", error, info);
          abortPipeable(error, { defaultError: true });
        }
      });
    } catch (e) {
      console.error("Error in renderToPipeableStream:", e);
      router.serverSsr?.cleanup();
      throw e;
    }
    const responseStream = transformPipeableStreamWithRouter(router, reactAppPassthrough, {
      signal: request.signal,
      onAbort: abortPipeable
    });
    responseAttached = true;
    if (endedBeforeAttach) reactAppPassthrough.destroy(pendingDestroyError());
    if (aborted && pipeable) try {
      pipeable.abort(toError(pendingAbortReason));
    } catch {
    }
    return createSsrStreamResponse(router, new Response(responseStream, {
      status: router._serverResult?.type === "render" ? router._serverResult.status : 200,
      headers: responseHeaders
    }));
  }
  throw new Error("No renderToReadableStream or renderToPipeableStream found in react-dom/server. Ensure you are using a version of react-dom that supports streaming.");
};
export {
  HeadContent as H,
  Link as L,
  Navigate as N,
  Outlet as O,
  RouterProvider as R,
  Scripts as S,
  createRootRouteWithContext as a,
  createFileRoute as b,
  createRouter as c,
  useRouterState as d,
  useNavigate as e,
  useLocation as f,
  useParams as g,
  lazyRouteComponent as l,
  renderRouterToStream as r,
  useRouter as u
};
