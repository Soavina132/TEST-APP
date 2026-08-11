import { p as parseHref } from "./tanstack__history.mjs";
import { s as splitSetCookieString } from "./cookie-es.mjs";
import { c as createPlugin, a as createStream, b as crossSerializeStream, g as getCrossReferenceHeader } from "./seroval.mjs";
import { R as ReadableStreamPlugin } from "./seroval-plugins.mjs";
import { ReadableStream as ReadableStream$1 } from "node:stream/web";
import { Readable } from "node:stream";
function isNotFound(obj) {
  return obj?.isNotFound === true;
}
const rootRouteId = "__root__";
function redirect(opts) {
  opts.statusCode = opts.statusCode || opts.code || 307;
  if (!opts._builtLocation && !opts.reloadDocument && typeof opts.href === "string") try {
    new URL(opts.href);
    opts.reloadDocument = true;
  } catch {
  }
  const headers = new Headers(opts.headers);
  if (opts.href && headers.get("Location") === null) headers.set("Location", opts.href);
  const response = new Response(null, {
    status: opts.statusCode,
    headers
  });
  response.options = opts;
  if (opts.throw) throw response;
  return response;
}
function isRedirect(obj) {
  return obj instanceof Response && !!obj.options;
}
function isResolvedRedirect(obj) {
  return isRedirect(obj) && !!obj.options.href;
}
function dehydrateSsrMatchId(id) {
  return id.replaceAll("~", "~~").replaceAll("\0", "~0").replaceAll("�", "~r").replaceAll("/", "\0");
}
function createLRUCache(max) {
  const cache = /* @__PURE__ */ new Map();
  let oldest;
  let newest;
  const touch = (entry) => {
    if (!entry.next) return;
    if (!entry.prev) {
      entry.next.prev = void 0;
      oldest = entry.next;
      entry.next = void 0;
      if (newest) {
        entry.prev = newest;
        newest.next = entry;
      }
    } else {
      entry.prev.next = entry.next;
      entry.next.prev = entry.prev;
      entry.next = void 0;
      if (newest) {
        newest.next = entry;
        entry.prev = newest;
      }
    }
    newest = entry;
  };
  return {
    get(key) {
      const entry = cache.get(key);
      if (!entry) return void 0;
      touch(entry);
      return entry.value;
    },
    set(key, value) {
      if (cache.size >= max && oldest) {
        const toDelete = oldest;
        cache.delete(toDelete.key);
        if (toDelete.next) {
          oldest = toDelete.next;
          toDelete.next.prev = void 0;
        }
        if (toDelete === newest) newest = void 0;
      }
      const existing = cache.get(key);
      if (existing) {
        existing.value = value;
        touch(existing);
      } else {
        const entry = {
          key,
          value,
          prev: newest
        };
        if (newest) newest.next = entry;
        newest = entry;
        if (!oldest) oldest = entry;
        cache.set(key, entry);
      }
    },
    clear() {
      cache.clear();
      oldest = void 0;
      newest = void 0;
    }
  };
}
function invariant() {
  throw new Error("Invariant failed");
}
const SEGMENT_TYPE_INDEX = 4;
const SEGMENT_TYPE_PATHLESS = 5;
function getOpenAndCloseBraces(part) {
  const openBrace = part.indexOf("{");
  if (openBrace === -1) return null;
  const closeBrace = part.indexOf("}", openBrace);
  if (closeBrace === -1) return null;
  if (openBrace + 1 >= part.length) return null;
  return [openBrace, closeBrace];
}
function parseSegment(path, start, output = new Uint16Array(6)) {
  const next = path.indexOf("/", start);
  const end = next === -1 ? path.length : next;
  const part = path.substring(start, end);
  if (!part || !part.includes("$")) {
    output[0] = 0;
    output[1] = start;
    output[2] = start;
    output[3] = end;
    output[4] = end;
    output[5] = end;
    return output;
  }
  if (part === "$") {
    const total = path.length;
    output[0] = 2;
    output[1] = start;
    output[2] = start;
    output[3] = total;
    output[4] = total;
    output[5] = total;
    return output;
  }
  if (part.charCodeAt(0) === 36) {
    output[0] = 1;
    output[1] = start;
    output[2] = start + 1;
    output[3] = end;
    output[4] = end;
    output[5] = end;
    return output;
  }
  const braces = getOpenAndCloseBraces(part);
  if (braces) {
    const [openBrace, closeBrace] = braces;
    const firstChar = part.charCodeAt(openBrace + 1);
    if (firstChar === 45) {
      if (openBrace + 2 < part.length && part.charCodeAt(openBrace + 2) === 36) {
        const paramStart = openBrace + 3;
        const paramEnd = closeBrace;
        if (paramStart < paramEnd) {
          output[0] = 3;
          output[1] = start + openBrace;
          output[2] = start + paramStart;
          output[3] = start + paramEnd;
          output[4] = start + closeBrace + 1;
          output[5] = end;
          return output;
        }
      }
    } else if (firstChar === 36) {
      const dollarPos = openBrace + 1;
      const afterDollar = openBrace + 2;
      if (afterDollar === closeBrace) {
        output[0] = 2;
        output[1] = start + openBrace;
        output[2] = start + dollarPos;
        output[3] = start + afterDollar;
        output[4] = start + closeBrace + 1;
        output[5] = path.length;
        return output;
      }
      output[0] = 1;
      output[1] = start + openBrace;
      output[2] = start + afterDollar;
      output[3] = start + closeBrace;
      output[4] = start + closeBrace + 1;
      output[5] = end;
      return output;
    }
  }
  output[0] = 0;
  output[1] = start;
  output[2] = start;
  output[3] = end;
  output[4] = end;
  output[5] = end;
  return output;
}
function parseSegments(defaultCaseSensitive, data, route, start, node, depth, onRoute) {
  onRoute?.(route);
  let cursor = start;
  {
    const path = route.fullPath ?? route.from;
    const length = path.length;
    const caseSensitive = route.options?.caseSensitive ?? defaultCaseSensitive;
    const parseParams = route.options?.params?.parse ?? route.options?.parseParams;
    while (cursor < length) {
      const segment = parseSegment(path, cursor, data);
      let nextNode;
      const start2 = cursor;
      const end = segment[5];
      cursor = end + 1;
      depth++;
      switch (segment[0]) {
        case 0: {
          const value = path.substring(segment[2], segment[3]);
          if (caseSensitive) {
            const existingNode = node.static?.get(value);
            if (existingNode) nextNode = existingNode;
            else {
              node.static ??= /* @__PURE__ */ new Map();
              const next = createStaticNode(route.fullPath ?? route.from);
              next.parent = node;
              next.depth = depth;
              nextNode = next;
              node.static.set(value, next);
            }
          } else {
            const name = value.toLowerCase();
            const existingNode = node.staticInsensitive?.get(name);
            if (existingNode) nextNode = existingNode;
            else {
              node.staticInsensitive ??= /* @__PURE__ */ new Map();
              const next = createStaticNode(route.fullPath ?? route.from);
              next.parent = node;
              next.depth = depth;
              nextNode = next;
              node.staticInsensitive.set(name, next);
            }
          }
          break;
        }
        case 1: {
          const prefix_raw = path.substring(start2, segment[1]);
          const suffix_raw = path.substring(segment[4], end);
          const actuallyCaseSensitive = caseSensitive && !!(prefix_raw || suffix_raw);
          const prefix = !prefix_raw ? void 0 : actuallyCaseSensitive ? prefix_raw : prefix_raw.toLowerCase();
          const suffix = !suffix_raw ? void 0 : actuallyCaseSensitive ? suffix_raw : suffix_raw.toLowerCase();
          const existingNode = !parseParams && node.dynamic?.find((s) => !s.parse && s.caseSensitive === actuallyCaseSensitive && s.prefix === prefix && s.suffix === suffix);
          if (existingNode) nextNode = existingNode;
          else {
            const next = createDynamicNode(1, route.fullPath ?? route.from, actuallyCaseSensitive, prefix, suffix);
            nextNode = next;
            next.depth = depth;
            next.parent = node;
            node.dynamic ??= [];
            node.dynamic.push(next);
          }
          break;
        }
        case 3: {
          const prefix_raw = path.substring(start2, segment[1]);
          const suffix_raw = path.substring(segment[4], end);
          const actuallyCaseSensitive = caseSensitive && !!(prefix_raw || suffix_raw);
          const prefix = !prefix_raw ? void 0 : actuallyCaseSensitive ? prefix_raw : prefix_raw.toLowerCase();
          const suffix = !suffix_raw ? void 0 : actuallyCaseSensitive ? suffix_raw : suffix_raw.toLowerCase();
          const existingNode = !parseParams && node.optional?.find((s) => !s.parse && s.caseSensitive === actuallyCaseSensitive && s.prefix === prefix && s.suffix === suffix);
          if (existingNode) nextNode = existingNode;
          else {
            const next = createDynamicNode(3, route.fullPath ?? route.from, actuallyCaseSensitive, prefix, suffix);
            nextNode = next;
            next.parent = node;
            next.depth = depth;
            node.optional ??= [];
            node.optional.push(next);
          }
          break;
        }
        case 2: {
          const prefix_raw = path.substring(start2, segment[1]);
          const suffix_raw = path.substring(segment[4], end);
          const actuallyCaseSensitive = caseSensitive && !!(prefix_raw || suffix_raw);
          const prefix = !prefix_raw ? void 0 : actuallyCaseSensitive ? prefix_raw : prefix_raw.toLowerCase();
          const suffix = !suffix_raw ? void 0 : actuallyCaseSensitive ? suffix_raw : suffix_raw.toLowerCase();
          const next = createDynamicNode(2, route.fullPath ?? route.from, actuallyCaseSensitive, prefix, suffix);
          nextNode = next;
          next.parent = node;
          next.depth = depth;
          node.wildcard ??= [];
          node.wildcard.push(next);
        }
      }
      node = nextNode;
    }
    if (parseParams && route.children && !route.isRoot && route.id && route.id.charCodeAt(route.id.lastIndexOf("/") + 1) === 95) {
      const pathlessNode = createStaticNode(route.fullPath ?? route.from);
      pathlessNode.kind = SEGMENT_TYPE_PATHLESS;
      pathlessNode.parent = node;
      depth++;
      pathlessNode.depth = depth;
      node.pathless ??= [];
      node.pathless.push(pathlessNode);
      node = pathlessNode;
    }
    const isLeaf = (route.path || !route.children) && !route.isRoot;
    if (isLeaf && path.endsWith("/")) {
      const indexNode = createStaticNode(route.fullPath ?? route.from);
      indexNode.kind = SEGMENT_TYPE_INDEX;
      indexNode.parent = node;
      depth++;
      indexNode.depth = depth;
      node.index = indexNode;
      node = indexNode;
    }
    node.parse = parseParams ?? null;
    node.priority = route.options?.params?.priority ?? 0;
    if (isLeaf && !node.route) {
      node.route = route;
      node.fullPath = route.fullPath ?? route.from;
    }
  }
  if (route.children) for (const child of route.children) parseSegments(defaultCaseSensitive, data, child, cursor, node, depth, onRoute);
}
function sortDynamic(a, b) {
  if (a.parse && !b.parse) return -1;
  if (!a.parse && b.parse) return 1;
  if (a.parse && b.parse && (a.priority || b.priority)) return b.priority - a.priority;
  if (a.prefix && b.prefix && a.prefix !== b.prefix) {
    if (a.prefix.startsWith(b.prefix)) return -1;
    if (b.prefix.startsWith(a.prefix)) return 1;
  }
  if (a.suffix && b.suffix && a.suffix !== b.suffix) {
    if (a.suffix.endsWith(b.suffix)) return -1;
    if (b.suffix.endsWith(a.suffix)) return 1;
  }
  if (a.prefix && !b.prefix) return -1;
  if (!a.prefix && b.prefix) return 1;
  if (a.suffix && !b.suffix) return -1;
  if (!a.suffix && b.suffix) return 1;
  if (a.caseSensitive && !b.caseSensitive) return -1;
  if (!a.caseSensitive && b.caseSensitive) return 1;
  return 0;
}
function sortTreeNodes(node) {
  if (node.pathless) for (const child of node.pathless) sortTreeNodes(child);
  if (node.static) for (const child of node.static.values()) sortTreeNodes(child);
  if (node.staticInsensitive) for (const child of node.staticInsensitive.values()) sortTreeNodes(child);
  if (node.dynamic?.length) {
    node.dynamic.sort(sortDynamic);
    for (const child of node.dynamic) sortTreeNodes(child);
  }
  if (node.optional?.length) {
    node.optional.sort(sortDynamic);
    for (const child of node.optional) sortTreeNodes(child);
  }
  if (node.wildcard?.length) {
    node.wildcard.sort(sortDynamic);
    for (const child of node.wildcard) sortTreeNodes(child);
  }
}
function createStaticNode(fullPath) {
  return {
    kind: 0,
    depth: 0,
    pathless: null,
    index: null,
    static: null,
    staticInsensitive: null,
    dynamic: null,
    optional: null,
    wildcard: null,
    route: null,
    fullPath,
    parent: null,
    parse: null,
    priority: 0
  };
}
function createDynamicNode(kind, fullPath, caseSensitive, prefix, suffix) {
  return {
    kind,
    depth: 0,
    pathless: null,
    index: null,
    static: null,
    staticInsensitive: null,
    dynamic: null,
    optional: null,
    wildcard: null,
    route: null,
    fullPath,
    parent: null,
    parse: null,
    priority: 0,
    caseSensitive,
    prefix,
    suffix
  };
}
function processRouteMasks(routeList, processedTree) {
  const segmentTree = createStaticNode("/");
  const data = new Uint16Array(6);
  for (const route of routeList) parseSegments(false, data, route, 1, segmentTree, 0);
  sortTreeNodes(segmentTree);
  processedTree.masksTree = segmentTree;
  processedTree.flatCache = createLRUCache(1e3);
}
function findFlatMatch(path, processedTree) {
  path ||= "/";
  const cached = processedTree.flatCache.get(path);
  if (cached) return cached;
  const result = findMatch(path, processedTree.masksTree);
  processedTree.flatCache.set(path, result);
  return result;
}
function findSingleMatch(from, caseSensitive, fuzzy, path, processedTree) {
  from ||= "/";
  path ||= "/";
  const key = caseSensitive ? `case\0${from}` : from;
  let tree = processedTree.singleCache.get(key);
  if (!tree) {
    tree = createStaticNode("/");
    parseSegments(caseSensitive, new Uint16Array(6), { from }, 1, tree, 0);
    processedTree.singleCache.set(key, tree);
  }
  return findMatch(path, tree, fuzzy);
}
function findRouteMatch(path, processedTree, fuzzy = false) {
  const key = fuzzy ? path : `nofuzz\0${path}`;
  const cached = processedTree.matchCache.get(key);
  if (cached !== void 0) return cached;
  path ||= "/";
  let result;
  try {
    result = findMatch(path, processedTree.segmentTree, fuzzy);
  } catch (err) {
    if (err instanceof URIError) result = null;
    else throw err;
  }
  if (result) result.branch = buildRouteBranch(result.route);
  processedTree.matchCache.set(key, result);
  return result;
}
function trimPathRight$1(path) {
  return path === "/" ? path : path.replace(/\/{1,}$/, "");
}
function processRouteTree(routeTree, caseSensitive = false, initRoute) {
  const segmentTree = createStaticNode(routeTree.fullPath);
  const data = new Uint16Array(6);
  const routesById = {};
  const routesByPath = {};
  let index = 0;
  parseSegments(caseSensitive, data, routeTree, 1, segmentTree, 0, (route) => {
    initRoute?.(route, index);
    if (route.id in routesById) {
      invariant();
    }
    routesById[route.id] = route;
    if (index !== 0 && route.path) {
      const trimmedFullPath = trimPathRight$1(route.fullPath);
      if (!routesByPath[trimmedFullPath] || route.fullPath.endsWith("/")) routesByPath[trimmedFullPath] = route;
    }
    index++;
  });
  sortTreeNodes(segmentTree);
  return {
    processedTree: {
      segmentTree,
      singleCache: createLRUCache(1e3),
      matchCache: createLRUCache(1e3),
      flatCache: null,
      masksTree: null
    },
    routesById,
    routesByPath
  };
}
function findMatch(path, segmentTree, fuzzy = false) {
  const parts = path.split("/");
  const leaf = getNodeMatch(path, parts, segmentTree, fuzzy);
  if (!leaf) return null;
  const [rawParams] = extractParams(path, parts, leaf);
  return {
    route: leaf.node.route,
    rawParams
  };
}
function extractParams(path, parts, leaf) {
  const list = buildBranch(leaf.node);
  let nodeParts = null;
  const rawParams = /* @__PURE__ */ Object.create(null);
  let partIndex = leaf.extract?.part ?? 0;
  let nodeIndex = leaf.extract?.node ?? 0;
  let pathIndex = leaf.extract?.path ?? 0;
  let segmentCount = leaf.extract?.segment ?? 0;
  for (; nodeIndex < list.length; partIndex++, nodeIndex++, pathIndex++, segmentCount++) {
    const node = list[nodeIndex];
    if (node.kind === SEGMENT_TYPE_INDEX) break;
    if (node.kind === SEGMENT_TYPE_PATHLESS) {
      segmentCount--;
      partIndex--;
      pathIndex--;
      continue;
    }
    const part = parts[partIndex];
    const currentPathIndex = pathIndex;
    if (part) pathIndex += part.length;
    if (node.kind === 1) {
      nodeParts ??= leaf.node.fullPath.split("/");
      const nodePart = nodeParts[segmentCount];
      const preLength = node.prefix?.length ?? 0;
      if (nodePart.charCodeAt(preLength) === 123) {
        const sufLength = node.suffix?.length ?? 0;
        const name = nodePart.substring(preLength + 2, nodePart.length - sufLength - 1);
        const value = part.substring(preLength, part.length - sufLength);
        rawParams[name] = decodeURIComponent(value);
      } else {
        const name = nodePart.substring(1);
        rawParams[name] = decodeURIComponent(part);
      }
    } else if (node.kind === 3) {
      if (leaf.skipped & 1 << nodeIndex) {
        partIndex--;
        pathIndex = currentPathIndex - 1;
        continue;
      }
      nodeParts ??= leaf.node.fullPath.split("/");
      const nodePart = nodeParts[segmentCount];
      const preLength = node.prefix?.length ?? 0;
      const sufLength = node.suffix?.length ?? 0;
      const name = nodePart.substring(preLength + 3, nodePart.length - sufLength - 1);
      const value = node.suffix || node.prefix ? part.substring(preLength, part.length - sufLength) : part;
      if (value) rawParams[name] = decodeURIComponent(value);
    } else if (node.kind === 2) {
      const n = node;
      const value = path.substring(currentPathIndex + (n.prefix?.length ?? 0), path.length - (n.suffix?.length ?? 0));
      const splat = decodeURIComponent(value);
      rawParams["*"] = splat;
      rawParams._splat = splat;
      break;
    }
  }
  if (leaf.rawParams) Object.assign(rawParams, leaf.rawParams);
  return [rawParams, {
    part: partIndex,
    node: nodeIndex,
    path: pathIndex,
    segment: segmentCount
  }];
}
function buildRouteBranch(route) {
  const list = [route];
  while (route.parentRoute) {
    route = route.parentRoute;
    list.push(route);
  }
  list.reverse();
  return list;
}
function buildBranch(node) {
  const list = Array(node.depth + 1);
  do {
    list[node.depth] = node;
    node = node.parent;
  } while (node);
  return list;
}
function getNodeMatch(path, parts, segmentTree, fuzzy) {
  if (path === "/" && segmentTree.index) return {
    node: segmentTree.index,
    skipped: 0
  };
  const trailingSlash = !last(parts);
  const pathIsIndex = trailingSlash && path !== "/";
  const partsLength = parts.length - (trailingSlash ? 1 : 0);
  const stack = [{
    node: segmentTree,
    index: 1,
    skipped: 0,
    depth: 1,
    statics: 0,
    dynamics: 0,
    optionals: 0
  }];
  let bestFuzzy = null;
  let bestMatch = null;
  while (stack.length) {
    const frame = stack.pop();
    const { node, index, skipped, depth, statics, dynamics, optionals } = frame;
    let { extract, rawParams } = frame;
    if (node.kind === 2 && node.route && !isFrameMoreSpecific(bestMatch, frame)) continue;
    if (node.parse) {
      if (!validateParseParams(path, parts, frame)) continue;
      rawParams = frame.rawParams;
      extract = frame.extract;
    }
    if (fuzzy && node.route && node.kind !== SEGMENT_TYPE_INDEX && isFrameMoreSpecific(bestFuzzy, frame)) bestFuzzy = frame;
    const isBeyondPath = index === partsLength;
    if (isBeyondPath) {
      if (node.route && (!pathIsIndex || node.kind === SEGMENT_TYPE_INDEX || node.kind === 2) && isFrameMoreSpecific(bestMatch, frame)) bestMatch = frame;
      if (!node.optional && !node.wildcard && !node.index && !node.pathless) continue;
    }
    const part = isBeyondPath ? void 0 : parts[index];
    let lowerPart;
    if (isBeyondPath && node.index) {
      const indexFrame = {
        node: node.index,
        index,
        skipped,
        depth: depth + 1,
        statics,
        dynamics,
        optionals,
        extract,
        rawParams
      };
      let indexValid = true;
      if (node.index.parse) {
        if (!validateParseParams(path, parts, indexFrame)) indexValid = false;
      }
      if (indexValid) {
        if (!dynamics && !optionals && !skipped && isPerfectStaticMatch(statics, partsLength)) return indexFrame;
        if (isFrameMoreSpecific(bestMatch, indexFrame)) bestMatch = indexFrame;
      }
    }
    if (node.wildcard) for (let i = node.wildcard.length - 1; i >= 0; i--) {
      const segment = node.wildcard[i];
      const { prefix, suffix } = segment;
      if (prefix) {
        if (isBeyondPath) continue;
        if (!(segment.caseSensitive ? part : lowerPart ??= part.toLowerCase()).startsWith(prefix)) continue;
      }
      if (suffix) {
        if (isBeyondPath) continue;
        const end = parts.slice(index).join("/").slice(-suffix.length);
        if ((segment.caseSensitive ? end : end.toLowerCase()) !== suffix) continue;
      }
      stack.push({
        node: segment,
        index: partsLength,
        skipped,
        depth: depth + 1,
        statics,
        dynamics,
        optionals,
        extract,
        rawParams
      });
    }
    if (node.optional) {
      const nextSkipped = skipped | 1 << depth;
      const nextDepth = depth + 1;
      for (let i = node.optional.length - 1; i >= 0; i--) {
        const segment = node.optional[i];
        stack.push({
          node: segment,
          index,
          skipped: nextSkipped,
          depth: nextDepth,
          statics,
          dynamics,
          optionals,
          extract,
          rawParams
        });
      }
      if (!isBeyondPath) for (let i = node.optional.length - 1; i >= 0; i--) {
        const segment = node.optional[i];
        const { prefix, suffix } = segment;
        if (prefix || suffix) {
          const casePart = segment.caseSensitive ? part : lowerPart ??= part.toLowerCase();
          if (prefix && !casePart.startsWith(prefix)) continue;
          if (suffix && !casePart.endsWith(suffix)) continue;
        }
        stack.push({
          node: segment,
          index: index + 1,
          skipped,
          depth: nextDepth,
          statics,
          dynamics,
          optionals: optionals + segmentScore(partsLength, index),
          extract,
          rawParams
        });
      }
    }
    if (!isBeyondPath && node.dynamic && part) for (let i = node.dynamic.length - 1; i >= 0; i--) {
      const segment = node.dynamic[i];
      const { prefix, suffix } = segment;
      if (prefix || suffix) {
        const casePart = segment.caseSensitive ? part : lowerPart ??= part.toLowerCase();
        if (prefix && !casePart.startsWith(prefix)) continue;
        if (suffix && !casePart.endsWith(suffix)) continue;
      }
      stack.push({
        node: segment,
        index: index + 1,
        skipped,
        depth: depth + 1,
        statics,
        dynamics: dynamics + segmentScore(partsLength, index),
        optionals,
        extract,
        rawParams
      });
    }
    if (!isBeyondPath && node.staticInsensitive) {
      const match = node.staticInsensitive.get(lowerPart ??= part.toLowerCase());
      if (match) stack.push({
        node: match,
        index: index + 1,
        skipped,
        depth: depth + 1,
        statics: statics + segmentScore(partsLength, index),
        dynamics,
        optionals,
        extract,
        rawParams
      });
    }
    if (!isBeyondPath && node.static) {
      const match = node.static.get(part);
      if (match) stack.push({
        node: match,
        index: index + 1,
        skipped,
        depth: depth + 1,
        statics: statics + segmentScore(partsLength, index),
        dynamics,
        optionals,
        extract,
        rawParams
      });
    }
    if (node.pathless) {
      const nextDepth = depth + 1;
      for (let i = node.pathless.length - 1; i >= 0; i--) {
        const segment = node.pathless[i];
        stack.push({
          node: segment,
          index,
          skipped,
          depth: nextDepth,
          statics,
          dynamics,
          optionals,
          extract,
          rawParams
        });
      }
    }
  }
  if (bestMatch) return bestMatch;
  if (fuzzy && bestFuzzy) {
    let sliceIndex = bestFuzzy.index;
    for (let i = 0; i < bestFuzzy.index; i++) sliceIndex += parts[i].length;
    const splat = sliceIndex === path.length ? "/" : path.slice(sliceIndex);
    bestFuzzy.rawParams ??= /* @__PURE__ */ Object.create(null);
    bestFuzzy.rawParams["**"] = decodeURIComponent(splat);
    return bestFuzzy;
  }
  return null;
}
function segmentScore(partsLength, index) {
  return 2 ** (partsLength - index - 1);
}
function isPerfectStaticMatch(statics, partsLength) {
  return statics === 2 ** (partsLength - 1) - 1;
}
function validateParseParams(path, parts, frame) {
  let rawParams;
  let state;
  try {
    [rawParams, state] = extractParams(path, parts, frame);
  } catch {
    return null;
  }
  frame.rawParams = rawParams;
  frame.extract = state;
  if (!frame.node.parse) return true;
  try {
    if (frame.node.parse(rawParams) === false) return null;
  } catch {
  }
  return true;
}
function isFrameMoreSpecific(prev, next) {
  if (!prev) return true;
  return next.statics > prev.statics || next.statics === prev.statics && (next.dynamics > prev.dynamics || next.dynamics === prev.dynamics && (next.optionals > prev.optionals || next.optionals === prev.optionals && ((next.node.kind === SEGMENT_TYPE_INDEX) > (prev.node.kind === SEGMENT_TYPE_INDEX) || next.node.kind === SEGMENT_TYPE_INDEX === (prev.node.kind === SEGMENT_TYPE_INDEX) && next.depth > prev.depth)));
}
function joinPaths(paths) {
  return cleanPath(paths.filter((val) => {
    return val !== void 0;
  }).join("/"));
}
function cleanPath(path) {
  return path.replace(/\/{2,}/g, "/");
}
function trimPathLeft(path) {
  return path === "/" ? path : path.replace(/^\/{1,}/, "");
}
function trimPathRight(path) {
  const len = path.length;
  return len > 1 && path[len - 1] === "/" ? path.replace(/\/{1,}$/, "") : path;
}
function trimPath(path) {
  return trimPathRight(trimPathLeft(path));
}
function removeTrailingSlash(value, basepath) {
  if (value?.endsWith("/") && value !== "/" && value !== `${basepath}/`) return value.slice(0, -1);
  return value;
}
function exactPathTest(pathName1, pathName2, basepath) {
  return removeTrailingSlash(pathName1, basepath) === removeTrailingSlash(pathName2, basepath);
}
function resolvePath({ base, to, trailingSlash = "never", cache }) {
  const isAbsolute = to.startsWith("/");
  const isBase = !isAbsolute && to === ".";
  let key;
  if (cache) {
    key = isAbsolute ? to : isBase ? base : base + "\0" + to;
    const cached = cache.get(key);
    if (cached) return cached;
  }
  let baseSegments;
  if (isBase) baseSegments = base.split("/");
  else if (isAbsolute) baseSegments = to.split("/");
  else {
    baseSegments = base.split("/");
    while (baseSegments.length > 1 && last(baseSegments) === "") baseSegments.pop();
    const toSegments = to.split("/");
    for (let index = 0, length = toSegments.length; index < length; index++) {
      const value = toSegments[index];
      if (value === "") {
        if (!index) baseSegments = [value];
        else if (index === length - 1) baseSegments.push(value);
      } else if (value === "..") baseSegments.pop();
      else if (value === ".") ;
      else baseSegments.push(value);
    }
  }
  if (baseSegments.length > 1) {
    if (last(baseSegments) === "") {
      if (trailingSlash === "never") baseSegments.pop();
    } else if (trailingSlash === "always") baseSegments.push("");
  }
  const result = cleanPath(baseSegments.join("/")) || "/";
  if (key && cache) cache.set(key, result);
  return result;
}
function compileDecodeCharMap(pathParamsAllowedCharacters) {
  const charMap = new Map(pathParamsAllowedCharacters.map((char) => [encodeURIComponent(char), char]));
  const pattern = Array.from(charMap.keys()).map((key) => key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
  const regex = new RegExp(pattern, "g");
  return (encoded) => encoded.replace(regex, (match) => charMap.get(match) ?? match);
}
function encodeParam(key, params, decoder) {
  const value = params[key];
  if (typeof value !== "string") return value;
  if (key === "_splat") {
    if (/^[a-zA-Z0-9\-._~!/]*$/.test(value)) return value;
    return value.split("/").map((segment) => encodePathParam(segment, decoder)).join("/");
  } else return encodePathParam(value, decoder);
}
function interpolatePath({ path, params, decoder, ...rest }) {
  let isMissingParams = false;
  const usedParams = /* @__PURE__ */ Object.create(null);
  if (!path || path === "/") return {
    interpolatedPath: "/",
    usedParams,
    isMissingParams
  };
  if (!path.includes("$")) return {
    interpolatedPath: path,
    usedParams,
    isMissingParams
  };
  {
    if (path.indexOf("{") === -1) {
      const length2 = path.length;
      let cursor2 = 0;
      let joined2 = "";
      while (cursor2 < length2) {
        while (cursor2 < length2 && path.charCodeAt(cursor2) === 47) cursor2++;
        if (cursor2 >= length2) break;
        const start = cursor2;
        let end = path.indexOf("/", cursor2);
        if (end === -1) end = length2;
        cursor2 = end;
        const part = path.substring(start, end);
        if (!part) continue;
        if (part.charCodeAt(0) === 36) if (part.length === 1) {
          const splat = params._splat;
          usedParams._splat = splat;
          usedParams["*"] = splat;
          if (!splat) {
            isMissingParams = true;
            continue;
          }
          const value = encodeParam("_splat", params, decoder);
          joined2 += "/" + value;
        } else {
          const key = part.substring(1);
          if (!isMissingParams && !(key in params)) isMissingParams = true;
          usedParams[key] = params[key];
          const value = encodeParam(key, params, decoder) ?? "undefined";
          joined2 += "/" + value;
        }
        else joined2 += "/" + part;
      }
      if (path.endsWith("/")) joined2 += "/";
      return {
        usedParams,
        interpolatedPath: joined2 || "/",
        isMissingParams
      };
    }
  }
  const length = path.length;
  let cursor = 0;
  let segment;
  let joined = "";
  while (cursor < length) {
    const start = cursor;
    segment = parseSegment(path, start, segment);
    const end = segment[5];
    cursor = end + 1;
    if (start === end) continue;
    const kind = segment[0];
    if (kind === 0) {
      joined += "/" + path.substring(start, end);
      continue;
    }
    if (kind === 2) {
      const splat = params._splat;
      usedParams._splat = splat;
      usedParams["*"] = splat;
      const prefix = path.substring(start, segment[1]);
      const suffix = path.substring(segment[4], end);
      if (!splat) {
        isMissingParams = true;
        if (prefix || suffix) joined += "/" + prefix + suffix;
        continue;
      }
      const value = encodeParam("_splat", params, decoder);
      joined += "/" + prefix + value + suffix;
      continue;
    }
    if (kind === 1) {
      const key = path.substring(segment[2], segment[3]);
      if (!isMissingParams && !(key in params)) isMissingParams = true;
      usedParams[key] = params[key];
      const prefix = path.substring(start, segment[1]);
      const suffix = path.substring(segment[4], end);
      const value = encodeParam(key, params, decoder) ?? "undefined";
      joined += "/" + prefix + value + suffix;
      continue;
    }
    if (kind === 3) {
      const key = path.substring(segment[2], segment[3]);
      const valueRaw = params[key];
      if (valueRaw == null) continue;
      usedParams[key] = valueRaw;
      const prefix = path.substring(start, segment[1]);
      const suffix = path.substring(segment[4], end);
      const value = encodeParam(key, params, decoder) ?? "";
      joined += "/" + prefix + value + suffix;
      continue;
    }
  }
  if (path.endsWith("/")) joined += "/";
  return {
    usedParams,
    interpolatedPath: joined || "/",
    isMissingParams
  };
}
function encodePathParam(value, decoder) {
  const encoded = encodeURIComponent(value);
  return decoder?.(encoded) ?? encoded;
}
function getSafeSessionStorage() {
  try {
    return sessionStorage;
  } catch {
    return;
  }
}
const storageKey = "tsr-scroll-restoration-v1_3";
getSafeSessionStorage();
const defaultGetScrollRestorationKey = (location) => {
  return location.state.__TSR_key || location.href;
};
function encode(obj, stringify = String) {
  const result = new URLSearchParams();
  for (const key in obj) {
    const val = obj[key];
    if (val !== void 0) result.set(key, stringify(val));
  }
  return result.toString();
}
function toValue(str) {
  if (!str) return "";
  if (str === "false") return false;
  if (str === "true") return true;
  return +str * 0 === 0 && +str + "" === str ? +str : str;
}
function decode(str) {
  const searchParams = new URLSearchParams(str);
  const result = /* @__PURE__ */ Object.create(null);
  for (const [key, value] of searchParams.entries()) {
    const previousValue = result[key];
    if (previousValue == null) result[key] = toValue(value);
    else if (Array.isArray(previousValue)) previousValue.push(toValue(value));
    else result[key] = [previousValue, toValue(value)];
  }
  return result;
}
const defaultParseSearch = parseSearchWith(JSON.parse);
const defaultStringifySearch = stringifySearchWith(JSON.stringify, JSON.parse);
function parseSearchWith(parser) {
  return (searchStr) => {
    if (searchStr[0] === "?") searchStr = searchStr.substring(1);
    const query = decode(searchStr);
    for (const key in query) {
      const value = query[key];
      if (typeof value === "string") try {
        query[key] = parser(value);
      } catch (_err) {
      }
    }
    return query;
  };
}
function stringifySearchWith(stringify, parser) {
  const hasParser = typeof parser === "function";
  function stringifyValue(val) {
    if (typeof val === "object" && val !== null) try {
      return stringify(val);
    } catch (_err) {
    }
    else if (hasParser && typeof val === "string") try {
      parser(val);
      return stringify(val);
    } catch (_err) {
    }
    return val;
  }
  return (search) => {
    const searchStr = encode(search, stringifyValue);
    return searchStr ? `?${searchStr}` : "";
  };
}
function composeRewrites(rewrites) {
  return {
    input: ({ url }) => {
      for (const rewrite of rewrites) url = executeRewriteInput(rewrite, url);
      return url;
    },
    output: ({ url }) => {
      for (let i = rewrites.length - 1; i >= 0; i--) url = executeRewriteOutput(rewrites[i], url);
      return url;
    }
  };
}
function rewriteBasepath(opts) {
  const trimmedBasepath = trimPath(opts.basepath);
  const normalizedBasepath = `/${trimmedBasepath}`;
  const checkBasepath = opts.caseSensitive ? normalizedBasepath : normalizedBasepath.toLowerCase();
  const checkBasepathWithSlash = `${checkBasepath}/`;
  return {
    input: ({ url }) => {
      const pathname = opts.caseSensitive ? url.pathname : url.pathname.toLowerCase();
      if (pathname === checkBasepath) url.pathname = "/";
      else if (pathname.startsWith(checkBasepathWithSlash)) url.pathname = url.pathname.slice(normalizedBasepath.length);
      return url;
    },
    output: ({ url }) => {
      url.pathname = joinPaths([
        "/",
        trimmedBasepath,
        url.pathname
      ]);
      return url;
    }
  };
}
function executeRewriteInput(rewrite, url) {
  const res = rewrite?.input?.({ url });
  if (res) {
    if (typeof res === "string") return new URL(res);
    else if (res instanceof URL) return res;
  }
  return url;
}
function executeRewriteOutput(rewrite, url) {
  const res = rewrite?.output?.({ url });
  if (res) {
    if (typeof res === "string") return new URL(res);
    else if (res instanceof URL) return res;
  }
  return url;
}
function createNonReactiveMutableStore(initialValue) {
  let value = initialValue;
  return {
    get() {
      return value;
    },
    set(nextOrUpdater) {
      value = functionalUpdate(nextOrUpdater, value);
    }
  };
}
function createNonReactiveReadonlyStore(read) {
  return { get() {
    return read();
  } };
}
function createRouterStores(initialLocation, config) {
  const { createMutableStore, createReadonlyStore, batch } = config;
  const byRoute = /* @__PURE__ */ new Map();
  const status = createMutableStore("idle");
  const location = createMutableStore(initialLocation);
  const resolvedLocation = createMutableStore(void 0);
  const ids = createMutableStore([]);
  const matches = createReadonlyStore(() => ids.get().map((id) => byRoute.get(id).get()));
  const __store = createReadonlyStore(() => ({
    status: status.get(),
    isLoading: status.get() === "pending",
    matches: matches.get(),
    location: location.get(),
    resolvedLocation: resolvedLocation.get()
  }));
  function getMatchStore(routeId) {
    let matchStore = byRoute.get(routeId);
    if (!matchStore) {
      matchStore = createMutableStore(void 0);
      byRoute.set(routeId, matchStore);
    }
    return matchStore;
  }
  const store = {
    status,
    location,
    resolvedLocation,
    ids,
    matches,
    byRoute,
    __store,
    getMatchStore,
    setMatches
  };
  function setMatches(nextMatches) {
    const previousIds = ids.get();
    const nextIds = nextMatches.map((match) => match.routeId);
    batch(() => {
      if (!arraysEqual(previousIds, nextIds)) ids.set(nextIds);
      for (const id of previousIds) if (!nextIds.includes(id)) byRoute.get(id).set(() => void 0);
      for (const nextMatch of nextMatches) {
        const matchStore = getMatchStore(nextMatch.routeId);
        if (matchStore.get() !== nextMatch) matchStore.set(nextMatch);
      }
    });
  }
  return store;
}
function routeNeedsLoad(route) {
  return route.options.loader || route.options.beforeLoad || route.lazyFn || route.options.component?.preload || route.options.pendingComponent?.preload;
}
function getLocationChangeInfo(location, resolvedLocation) {
  return {
    fromLocation: resolvedLocation,
    toLocation: location,
    pathChanged: resolvedLocation?.pathname !== location.pathname,
    hrefChanged: resolvedLocation?.href !== location.href,
    hashChanged: resolvedLocation?.hash !== location.hash
  };
}
function _getUserHistoryState({ key: _key, __TSR_key: _tsrKey, __TSR_index: _tsrIndex, __hashScrollIntoViewOptions: _hashScroll, ...state }) {
  return state;
}
function runRouteLifecycle(router, previous, matches, isCurrent) {
  for (const match of previous) {
    if (!matches.some((candidate) => candidate.routeId === match.routeId)) router.routesById[match.routeId].options.onLeave?.(match);
  }
  for (const match of matches) {
    router.routesById[match.routeId].options[previous.some((candidate) => candidate.routeId === match.routeId) ? "onStay" : "onEnter"]?.(match);
  }
}
var RouterCore = class {
  /**
  * @deprecated Use the `createRouter` function instead
  */
  constructor(options, getStoreConfig) {
    this.tempLocationKey = `${Math.round(Math.random() * 1e7)}`;
    this._scroll = { next: true };
    this.subscribers = /* @__PURE__ */ new Set();
    this._cache = /* @__PURE__ */ new Map();
    this._committed = [];
    this.routeBranchCache = /* @__PURE__ */ new WeakMap();
    this.lightweightCache = /* @__PURE__ */ new WeakMap();
    this.startTransition = async (fn) => {
      fn();
      return false;
    };
    this.update = (newOptions) => {
      const prevOptions = this.options;
      const prevBasepath = this.basepath ?? prevOptions?.basepath ?? "/";
      const basepathWasUnset = this.basepath === void 0;
      const prevRewriteOption = prevOptions?.rewrite;
      this.options = {
        ...prevOptions,
        ...newOptions
      };
      this.isServer = this.options.isServer ?? isServer ?? typeof document === "undefined";
      this.protocolAllowlist = new Set(this.options.protocolAllowlist);
      if (this.options.pathParamsAllowedCharacters) this.pathParamsDecoder = compileDecodeCharMap(this.options.pathParamsAllowedCharacters);
      if (!this.history || this.options.history && this.options.history !== this.history) if (!this.options.history) ;
      else this.history = this.options.history;
      this.origin = this.options.origin;
      if (!this.origin) this.origin = "http://localhost";
      if (this.history) this.updateLatestLocation();
      if (this.options.routeTree !== this.routeTree) {
        this.routeTree = this.options.routeTree;
        let processRouteTreeResult;
        if (globalThis.__TSR_CACHE__ && globalThis.__TSR_CACHE__.routeTree === this.routeTree) {
          const cached = globalThis.__TSR_CACHE__;
          this.resolvePathCache = cached.resolvePathCache;
          processRouteTreeResult = cached.processRouteTreeResult;
        } else {
          this.resolvePathCache = createLRUCache(1e3);
          processRouteTreeResult = this.buildRouteTree();
          if (globalThis.__TSR_CACHE__ === void 0) globalThis.__TSR_CACHE__ = {
            routeTree: this.routeTree,
            processRouteTreeResult,
            resolvePathCache: this.resolvePathCache
          };
        }
        this.setRoutes(processRouteTreeResult);
      }
      if (!this.stores && this.latestLocation) {
        const config = this.getStoreConfig(this);
        this.batch = config.batch;
        this.stores = createRouterStores(this.latestLocation, config);
      }
      const nextBasepath = this.options.basepath ?? "/";
      const nextRewriteOption = this.options.rewrite;
      if (basepathWasUnset || prevBasepath !== nextBasepath || prevRewriteOption !== nextRewriteOption) {
        this.basepath = nextBasepath;
        const rewrites = [];
        const trimmed = trimPath(nextBasepath);
        if (trimmed && trimmed !== "/") rewrites.push(rewriteBasepath({ basepath: nextBasepath }));
        if (nextRewriteOption) rewrites.push(nextRewriteOption);
        this.rewrite = rewrites.length === 0 ? void 0 : rewrites.length === 1 ? rewrites[0] : composeRewrites(rewrites);
        if (this.history) this.updateLatestLocation();
        if (this.stores) this.stores.location.set(this.latestLocation);
      }
    };
    this.updateLatestLocation = () => {
      this.latestLocation = this.parseLocation(this.history.location, this.latestLocation);
    };
    this.buildRouteTree = () => {
      const result = processRouteTree(this.routeTree, this.options.caseSensitive, (route, i) => {
        route.init({ originalIndex: i });
      });
      if (this.options.routeMasks) processRouteMasks(this.options.routeMasks, result.processedTree);
      return result;
    };
    this.subscribe = (eventType, fn) => {
      const listener = {
        eventType,
        fn
      };
      this.subscribers.add(listener);
      return () => {
        this.subscribers.delete(listener);
      };
    };
    this.emit = (routerEvent) => {
      for (const listener of this.subscribers) if (listener.eventType === routerEvent.type) try {
        listener.fn(routerEvent);
      } catch (e) {
        console.error(e);
      }
    };
    this.parseLocation = (locationToParse, previousLocation) => {
      const parse = ({ pathname, search, hash, href, state }) => {
        if (!this.rewrite && !/[ \x00-\x1f\x7f\u0080-\uffff]/.test(pathname)) {
          const parsedSearch2 = this.options.parseSearch(search);
          const searchStr2 = this.options.stringifySearch(parsedSearch2);
          return {
            href: pathname + searchStr2 + hash,
            publicHref: pathname + searchStr2 + hash,
            pathname: decodePath(pathname).path,
            external: false,
            searchStr: searchStr2,
            search: nullReplaceEqualDeep(previousLocation?.search, parsedSearch2),
            hash: decodePath(hash.slice(1)).path,
            state: replaceEqualDeep(previousLocation?.state, state)
          };
        }
        const fullUrl = new URL(href, this.origin);
        const url = executeRewriteInput(this.rewrite, fullUrl);
        const parsedSearch = this.options.parseSearch(url.search);
        const searchStr = this.options.stringifySearch(parsedSearch);
        url.search = searchStr;
        return {
          href: url.href.replace(url.origin, ""),
          publicHref: href,
          pathname: decodePath(url.pathname).path,
          external: !!this.rewrite && url.origin !== this.origin,
          searchStr,
          search: nullReplaceEqualDeep(previousLocation?.search, parsedSearch),
          hash: decodePath(url.hash.slice(1)).path,
          state: replaceEqualDeep(previousLocation?.state, state)
        };
      };
      const location = parse(locationToParse);
      const { __tempLocation, __tempKey } = location.state;
      if (__tempLocation && (!__tempKey || __tempKey === this.tempLocationKey)) {
        const parsedTempLocation = parse(__tempLocation);
        parsedTempLocation.state.key = location.state.key;
        parsedTempLocation.state.__TSR_key = location.state.__TSR_key;
        delete parsedTempLocation.state.__tempLocation;
        return {
          ...parsedTempLocation,
          maskedLocation: location
        };
      }
      return location;
    };
    this.resolvePathWithBase = (from, path) => {
      return resolvePath({
        base: from,
        to: path.includes("//") ? cleanPath(path) : path,
        trailingSlash: this.options.trailingSlash,
        cache: this.resolvePathCache
      });
    };
    this.matchRoutes = (pathnameOrNext, locationSearchOrOpts, opts) => {
      if (typeof pathnameOrNext === "string") return this.matchRoutesInternal({
        pathname: pathnameOrNext,
        search: locationSearchOrOpts
      }, opts);
      return this.matchRoutesInternal(pathnameOrNext, locationSearchOrOpts);
    };
    this.getMatchedRoutes = (pathname) => {
      const routeParams = /* @__PURE__ */ Object.create(null);
      const match = findRouteMatch(trimPathRight(pathname), this.processedTree, true);
      if (match) Object.assign(routeParams, match.rawParams);
      return {
        matchedRoutes: match?.branch || [this.routesById["__root__"]],
        routeParams,
        foundRoute: match?.route
      };
    };
    this.buildLocation = (opts) => {
      const build = (dest = {}) => {
        const currentLocation = dest._fromLocation || this._pendingLocation || this.latestLocation;
        const lightweightResult = this.matchRoutesLightweight(currentLocation);
        if (dest.from && false) ;
        const defaultedFromPath = dest.unsafeRelative === "path" ? currentLocation.pathname : dest.from ?? lightweightResult.fullPath;
        const destTo = dest.to ? `${dest.to}` : void 0;
        const fromSearch = lightweightResult.search;
        const fromParams = Object.assign(/* @__PURE__ */ Object.create(null), lightweightResult.params);
        const sourcePath = destTo?.charCodeAt(0) === 47 ? "/" : this.resolvePathWithBase(defaultedFromPath, ".");
        const nextTo = destTo ? this.resolvePathWithBase(sourcePath, destTo) : sourcePath;
        const nextParams = resolveNextParams(dest.params, fromParams);
        const destRoute = this.routesByPath[trimPathRight(nextTo)];
        let destRoutes;
        if (destRoute) destRoutes = this.getRouteBranch(destRoute);
        else if (nextTo.includes("$")) destRoutes = [];
        else {
          const destMatchResult = this.getMatchedRoutes(nextTo);
          destRoutes = destMatchResult.matchedRoutes;
          if (this.options.notFoundRoute && (!destMatchResult.foundRoute || destMatchResult.foundRoute.path !== "/" && destMatchResult.routeParams["**"])) destRoutes = [...destRoutes, this.options.notFoundRoute];
        }
        if (destRoutes.length && hasKeys(nextParams)) for (const route of destRoutes) {
          const fn = route.options.params?.stringify ?? route.options.stringifyParams;
          if (fn) try {
            Object.assign(nextParams, fn(nextParams));
          } catch {
          }
        }
        const nextPathname = opts.leaveParams ? nextTo : decodePath(interpolatePath({
          path: nextTo,
          params: nextParams,
          decoder: this.pathParamsDecoder,
          server: this.isServer
        }).interpolatedPath).path;
        let nextSearch = fromSearch;
        if (opts._includeValidateSearch && this.options.search?.strict) {
          const validatedSearch = {};
          destRoutes.forEach((route) => {
            if (route.options.validateSearch) try {
              Object.assign(validatedSearch, validateSearch(route.options.validateSearch, {
                ...validatedSearch,
                ...nextSearch
              }));
            } catch {
            }
          });
          nextSearch = validatedSearch;
        }
        nextSearch = applySearchMiddleware(nextSearch, dest, destRoutes, opts._includeValidateSearch);
        nextSearch = nullReplaceEqualDeep(fromSearch, nextSearch);
        const searchStr = this.options.stringifySearch(nextSearch);
        const hash = dest.hash === true ? currentLocation.hash : dest.hash ? functionalUpdate(dest.hash, currentLocation.hash) : void 0;
        const hashStr = hash ? `#${hash}` : "";
        let nextState = dest.state === true ? currentLocation.state : dest.state ? functionalUpdate(dest.state, currentLocation.state) : {};
        nextState = replaceEqualDeep(currentLocation.state, nextState);
        const fullPath = `${nextPathname}${searchStr}${hashStr}`;
        let href;
        let publicHref;
        let external = false;
        if (this.rewrite) {
          const url = new URL(fullPath, this.origin);
          const rewrittenUrl = executeRewriteOutput(this.rewrite, url);
          href = url.href.replace(url.origin, "");
          if (rewrittenUrl.origin !== this.origin) {
            publicHref = rewrittenUrl.href;
            external = true;
          } else publicHref = rewrittenUrl.pathname + rewrittenUrl.search + rewrittenUrl.hash;
        } else {
          href = encodePathLikeUrl(fullPath);
          publicHref = href;
        }
        return {
          publicHref,
          href,
          pathname: nextPathname,
          search: nextSearch,
          searchStr,
          state: nextState,
          hash: hash ?? "",
          external,
          unmaskOnReload: dest.unmaskOnReload
        };
      };
      const buildWithMatches = (dest = {}, maskedDest) => {
        const next = build(dest);
        let maskedNext = maskedDest ? build(maskedDest) : void 0;
        if (!maskedNext) {
          const params = /* @__PURE__ */ Object.create(null);
          if (this.options.routeMasks) {
            const match = findFlatMatch(next.pathname, this.processedTree);
            if (match) {
              Object.assign(params, match.rawParams);
              const { from: _from, params: maskParams, ...maskProps } = match.route;
              const nextParams = resolveNextParams(maskParams, params);
              maskedDest = {
                from: opts.from,
                ...maskProps,
                params: nextParams
              };
              maskedNext = build(maskedDest);
            }
          }
        }
        if (maskedNext) next.maskedLocation = maskedNext;
        return next;
      };
      if (opts.mask) return buildWithMatches(opts, {
        from: opts.from,
        ...opts.mask
      });
      return buildWithMatches(opts);
    };
    this.commitLocation = async ({ viewTransition, ignoreBlocker, ...next }) => {
      let historyAction;
      const isSameLocation = trimPathRight(this.latestLocation.href) === trimPathRight(next.href) && deepEqual(_getUserHistoryState(next.state), _getUserHistoryState(this.latestLocation.state));
      const previousCommitPromise = this._commitPromise;
      let resolve;
      const commitPromise = new Promise((done) => {
        resolve = done;
      });
      commitPromise.resolve = () => {
        resolve();
        previousCommitPromise?.resolve();
      };
      this._commitPromise = commitPromise;
      if (isSameLocation) this.load();
      else {
        let { maskedLocation, hashScrollIntoView, ...nextHistory } = next;
        if (maskedLocation) {
          nextHistory = {
            ...maskedLocation,
            state: {
              ...maskedLocation.state,
              __tempKey: void 0,
              __tempLocation: {
                ...nextHistory,
                search: nextHistory.searchStr,
                state: {
                  ...nextHistory.state,
                  __tempKey: void 0,
                  __tempLocation: void 0,
                  __TSR_key: void 0,
                  key: void 0
                }
              }
            }
          };
          if (nextHistory.unmaskOnReload ?? this.options.unmaskOnReload ?? false) nextHistory.state.__tempKey = this.tempLocationKey;
        }
        nextHistory.state.__hashScrollIntoViewOptions = hashScrollIntoView ?? this.options.defaultHashScrollIntoView ?? true;
        this.shouldViewTransition = viewTransition;
        historyAction = next.replace ? "REPLACE" : "PUSH";
        this.history[historyAction === "REPLACE" ? "replace" : "push"](nextHistory.publicHref, nextHistory.state, { ignoreBlocker });
        if (!this.history.subscribers.size) this.load({ action: { type: historyAction } });
      }
      this._scroll.next = next.resetScroll ?? true;
      return this._commitPromise;
    };
    this.buildAndCommitLocation = ({ replace, resetScroll, hashScrollIntoView, viewTransition, ignoreBlocker, _redirects, href, ...rest } = {}) => {
      if (href) {
        const currentIndex = this.history.location.state.__TSR_index;
        const parsed = parseHref(href, { __TSR_index: replace ? currentIndex : currentIndex + 1 });
        const hrefUrl = new URL(parsed.pathname, this.origin);
        rest.to = executeRewriteInput(this.rewrite, hrefUrl).pathname;
        rest.search = this.options.parseSearch(parsed.search);
        rest.hash = parsed.hash.slice(1);
      }
      const location = this.buildLocation({
        ...rest,
        _includeValidateSearch: true
      });
      if (_redirects) location._redirects = _redirects;
      this._pendingLocation = location;
      const commitPromise = this.commitLocation({
        ...location,
        viewTransition,
        replace,
        resetScroll,
        hashScrollIntoView,
        ignoreBlocker
      });
      queueMicrotask(() => {
        if (this._pendingLocation === location) this._pendingLocation = void 0;
      });
      return commitPromise;
    };
    this.navigate = async ({ to, reloadDocument, href, publicHref, ...rest }) => {
      let hrefIsUrl = false;
      if (href) try {
        new URL(`${href}`);
        hrefIsUrl = true;
      } catch {
      }
      if (hrefIsUrl && !reloadDocument) reloadDocument = true;
      if (reloadDocument) {
        if (to !== void 0 || !href) {
          const location = this.buildLocation({
            to,
            ...rest
          });
          href = href ?? location.publicHref;
          publicHref = publicHref ?? location.publicHref;
        }
        const reloadHref = !hrefIsUrl && publicHref ? publicHref : href;
        if (isDangerousProtocol(reloadHref, this.protocolAllowlist)) {
          return;
        }
        if (!rest.ignoreBlocker) {
          const blockers = this.history.getBlockers?.() ?? [];
          for (const blocker of blockers) if (blocker?.blockerFn) {
            if (await blocker.blockerFn({
              currentLocation: this.latestLocation,
              nextLocation: this.latestLocation,
              action: "PUSH"
            })) return;
          }
        }
        if (rest.replace) window.location.replace(reloadHref);
        else window.location.href = reloadHref;
        return;
      }
      return this.buildAndCommitLocation({
        ...rest,
        href,
        to,
        _isNavigate: true
      });
    };
    this.load = async (opts) => {
      return loadServerRoute(this, opts);
    };
    this.startViewTransition = (fn) => {
      this.shouldViewTransition ?? this.options.defaultViewTransition;
      this.shouldViewTransition = void 0;
      return fn();
    };
    this.invalidate = (opts) => {
      const committedMatches = this._committed;
      const filter = opts?.filter;
      const preloads = this._preloads;
      const invalidIds = new Set([
        ...committedMatches,
        ...this._cache.values(),
        ...[...preloads?.values() ?? []].flat(),
        ...this._tx?.[3] ?? []
      ].filter((match) => !filter || filter(match)).map((match) => match.id));
      const discardedPreloads = [];
      for (const [controller, matches] of preloads ?? []) if (matches.some((match) => invalidIds.has(match.id))) {
        preloads.delete(controller);
        discardedPreloads.push(controller);
      }
      const invalidate = (d) => {
        if (invalidIds.has(d.id)) {
          const route = this.routesById[d.routeId];
          const next = {
            ...d,
            invalid: true,
            ...(opts?.forcePending || d.status === "error" || d.status === "notFound") && routeNeedsLoad(route) ? {
              status: "pending",
              error: void 0
            } : void 0
          };
          d._flight = void 0;
          return next;
        }
        return d;
      };
      this._committed = committedMatches.map(invalidate);
      for (const [id, match] of this._cache) if (invalidIds.has(id)) {
        match.invalid = true;
        if (opts?.forcePending) match.status = "pending";
      }
      for (const id of invalidIds) this._flights?.delete(id);
      for (const controller of discardedPreloads) controller.abort();
      this.shouldViewTransition = false;
      return this.load({ sync: opts?.sync });
    };
    this.resolveRedirect = (redirect2) => {
      const locationHeader = redirect2.headers.get("Location");
      if (!redirect2.options.href || redirect2.options._builtLocation) {
        const href = (redirect2.options._builtLocation ?? this.buildLocation(redirect2.options)).publicHref || "/";
        redirect2.options.href = href;
        redirect2.headers.set("Location", href);
      } else if (locationHeader) try {
        const url = new URL(locationHeader);
        if (this.origin && url.origin === this.origin) {
          const href = url.pathname + url.search + url.hash;
          redirect2.options.href = href;
          redirect2.headers.set("Location", href);
        }
      } catch {
      }
      if (redirect2.options.href && !redirect2.options._builtLocation && isDangerousProtocol(redirect2.options.href, this.protocolAllowlist)) throw new Error("Redirect blocked: unsafe protocol");
      if (!redirect2.headers.get("Location")) redirect2.headers.set("Location", redirect2.options.href);
      return redirect2;
    };
    this.clearCache = (opts) => {
      const cached = this._cache;
      const preloads = this._preloads;
      const filter = opts?.filter;
      const discarded = [];
      const discardedIds = [];
      for (const [id, match] of cached) if (!filter || filter(match)) {
        discardedIds.push(id);
        discarded.push(match);
      }
      const abort = [];
      for (const [controller, matches] of preloads ?? []) if (!filter || matches.some(filter)) {
        abort.push(controller);
        discarded.push(...matches);
      }
      for (const id of discardedIds) cached.delete(id);
      for (const controller of abort) preloads.delete(controller);
      for (const match of discarded) {
        const flight = match._flight;
        match._flight = void 0;
        if (flight && !--flight[2]) {
          if (this._flights?.get(match.id) === flight) this._flights.delete(match.id);
          abort.push(flight[1]);
        }
      }
      for (const controller of abort) controller.abort();
    };
    this.loadRouteChunk = loadRouteChunk;
    this.preloadRoute = (opts) => preloadClientRoute(this, opts);
    this.matchRoute = (location, opts) => {
      const matchLocation = {
        ...location,
        to: location.to ? this.resolvePathWithBase(location.from || "", location.to) : void 0,
        params: location.params || {},
        leaveParams: true
      };
      const next = this.buildLocation(matchLocation);
      const isPending = this.stores.status.get() === "pending";
      if (opts?.pending && !isPending) return false;
      const baseLocation = opts?.pending ?? !isPending ? this.latestLocation : this.stores.resolvedLocation.get() || this.stores.location.get();
      const match = findSingleMatch(next.pathname, opts?.caseSensitive ?? false, opts?.fuzzy ?? false, baseLocation.pathname, this.processedTree);
      if (!match) return false;
      if (location.params) {
        if (!deepEqual(match.rawParams, location.params, { partial: true })) return false;
      }
      if (opts?.includeSearch ?? true) return deepEqual(baseLocation.search, next.search, { partial: true }) ? match.rawParams : false;
      return match.rawParams;
    };
    this.getStoreConfig = getStoreConfig;
    this.update({
      defaultPreloadDelay: 50,
      defaultPendingMs: 1e3,
      defaultPendingMinMs: 500,
      context: void 0,
      ...options,
      caseSensitive: options.caseSensitive ?? false,
      notFoundMode: options.notFoundMode ?? "fuzzy",
      stringifySearch: options.stringifySearch ?? defaultStringifySearch,
      parseSearch: options.parseSearch ?? defaultParseSearch,
      protocolAllowlist: options.protocolAllowlist ?? DEFAULT_PROTOCOL_ALLOWLIST
    });
  }
  isShell() {
    return !!this.options.isShell;
  }
  get state() {
    return this.stores.__store.get();
  }
  setRoutes({ routesById, routesByPath, processedTree }) {
    this.routesById = routesById;
    this.routesByPath = routesByPath;
    this.processedTree = processedTree;
    const notFoundRoute = this.options.notFoundRoute;
    if (notFoundRoute) {
      notFoundRoute.init({ originalIndex: 99999999999 });
      this.routesById[notFoundRoute.id] = notFoundRoute;
    }
  }
  getRouteBranch(route) {
    let branch = this.routeBranchCache.get(route);
    if (!branch) {
      branch = buildRouteBranch(route);
      this.routeBranchCache.set(route, branch);
    }
    return branch;
  }
  matchRoutesInternal(next, opts) {
    const matchedRoutesResult = this.getMatchedRoutes(next.pathname);
    const { foundRoute, routeParams } = matchedRoutesResult;
    let { matchedRoutes } = matchedRoutesResult;
    let isGlobalNotFound = false;
    if (foundRoute ? foundRoute.path !== "/" && routeParams["**"] : trimPathRight(next.pathname)) if (this.options.notFoundRoute) matchedRoutes = [...matchedRoutes, this.options.notFoundRoute];
    else isGlobalNotFound = true;
    const _notFoundRouteId = isGlobalNotFound ? findGlobalNotFoundRouteId(this.options.notFoundMode, matchedRoutes) : void 0;
    const matches = new Array(matchedRoutes.length);
    const committed = this._committed;
    const previousAt = (route, index) => {
      const match = committed[index];
      return match?.routeId === route.id ? match : route === this.options.notFoundRoute ? committed.find((candidate) => candidate.routeId === route.id) : void 0;
    };
    for (let index = 0; index < matchedRoutes.length; index++) {
      const route = matchedRoutes[index];
      const parentMatch = matches[index - 1];
      let preMatchSearch;
      let strictMatchSearch;
      let searchError;
      {
        const parentSearch = parentMatch?.search ?? next.search;
        const parentStrictSearch = parentMatch?._strictSearch ?? void 0;
        try {
          const strictSearch = validateSearch(route.options.validateSearch, { ...parentSearch }) ?? void 0;
          preMatchSearch = {
            ...parentSearch,
            ...strictSearch
          };
          strictMatchSearch = {
            ...parentStrictSearch,
            ...strictSearch
          };
        } catch (err) {
          let searchParamError = err;
          if (!(err instanceof SearchParamError)) searchParamError = new SearchParamError(err.message, { cause: err });
          if (opts?.throwOnError) throw searchParamError;
          preMatchSearch = parentSearch;
          strictMatchSearch = {};
          searchError = searchParamError;
        }
      }
      let loaderDeps = "";
      let loaderDepsHash = "";
      try {
        loaderDeps = route.options.loaderDeps?.({ search: preMatchSearch }) ?? "";
        loaderDepsHash = loaderDeps ? JSON.stringify(loaderDeps) || "" : "";
      } catch (cause2) {
        if (opts?.throwOnError) throw cause2;
        searchError ??= cause2;
      }
      const { interpolatedPath, usedParams } = interpolatePath({
        path: route.fullPath,
        params: routeParams,
        decoder: this.pathParamsDecoder,
        server: this.isServer
      });
      const matchId = route.id + interpolatedPath + loaderDepsHash;
      const previousMatch = previousAt(route, index);
      const existingMatch = this._cache.get(matchId) ?? (previousMatch?.id === matchId ? previousMatch : void 0);
      const strictParams = existingMatch?._strictParams ?? usedParams;
      let paramsError;
      if (!existingMatch) try {
        extractStrictParams(route, strictParams);
      } catch (err) {
        if (isNotFound(err) || isRedirect(err)) paramsError = err;
        else paramsError = new PathParamError(err.message, { cause: err });
        if (opts?.throwOnError) throw paramsError;
      }
      Object.assign(routeParams, strictParams);
      const cause = previousMatch ? "stay" : "enter";
      let match;
      if (existingMatch) match = {
        ...existingMatch,
        cause,
        params: previousMatch?.params ?? routeParams,
        _strictParams: strictParams,
        search: previousMatch ? nullReplaceEqualDeep(previousMatch.search, preMatchSearch) : nullReplaceEqualDeep(existingMatch.search, preMatchSearch),
        _strictSearch: strictMatchSearch,
        searchError
      };
      else {
        const status = routeNeedsLoad(route) ? "pending" : "success";
        match = {
          id: matchId,
          ssr: void 0,
          index,
          routeId: route.id,
          params: previousMatch?.params ?? routeParams,
          _strictParams: strictParams,
          pathname: interpolatedPath,
          updatedAt: Date.now(),
          search: previousMatch ? nullReplaceEqualDeep(previousMatch.search, preMatchSearch) : preMatchSearch,
          _strictSearch: strictMatchSearch,
          searchError,
          status,
          isFetching: false,
          error: void 0,
          paramsError,
          context: {},
          abortController: opts?._controller ?? new AbortController(),
          cause,
          loaderDeps: previousMatch ? replaceEqualDeep(previousMatch.loaderDeps, loaderDeps) : loaderDeps,
          invalid: false,
          preload: false,
          staticData: route.options.staticData || {},
          fullPath: route.fullPath
        };
      }
      const _notFound = _notFoundRouteId === route.id;
      if (match._notFound && !_notFound) match.error = void 0;
      match._notFound = _notFound;
      matches[index] = match;
    }
    for (let index = 0; index < matches.length; index++) {
      const match = matches[index];
      match.params = match.cause === "stay" ? nullReplaceEqualDeep(match.params, routeParams) : routeParams;
      if (opts?._controller) match.context = {};
    }
    return matches;
  }
  /**
  * Lightweight route matching for buildLocation.
  * Only computes fullPath, accumulated search, and params - skipping expensive
  * operations like AbortController, loaderDeps, and full match objects.
  */
  matchRoutesLightweight(location) {
    const lastRouteId = last(this.stores.ids.get());
    const lastStateMatch = lastRouteId ? this.stores.byRoute.get(lastRouteId).get() : void 0;
    const lastStateMatchId = lastStateMatch?.id;
    const cached = this.lightweightCache.get(location);
    if (cached && cached[0] === lastStateMatchId) return cached[1];
    const { matchedRoutes, routeParams } = this.getMatchedRoutes(location.pathname);
    const lastRoute = last(matchedRoutes);
    const accumulatedSearch = { ...location.search };
    for (const route of matchedRoutes) try {
      Object.assign(accumulatedSearch, validateSearch(route.options.validateSearch, accumulatedSearch));
    } catch {
    }
    const canReuseParams = lastStateMatch && lastStateMatch.routeId === lastRoute.id && lastStateMatch.pathname === location.pathname;
    let params;
    if (canReuseParams) params = lastStateMatch.params;
    else {
      const strictParams = Object.assign(/* @__PURE__ */ Object.create(null), routeParams);
      for (const route of matchedRoutes) try {
        extractStrictParams(route, strictParams);
      } catch {
      }
      params = strictParams;
    }
    const result = {
      matchedRoutes,
      fullPath: lastRoute.fullPath,
      search: accumulatedSearch,
      params
    };
    this.lightweightCache.set(location, [lastStateMatchId, result]);
    return result;
  }
};
var SearchParamError = class extends Error {
};
var PathParamError = class extends Error {
};
function validateSearch(validateSearch2, input) {
  if (validateSearch2 == null) return {};
  if ("~standard" in validateSearch2) {
    const result = validateSearch2["~standard"].validate(input);
    if (result instanceof Promise) throw new SearchParamError("Async validation not supported");
    if (result.issues) throw new SearchParamError(JSON.stringify(result.issues, void 0, 2), { cause: result });
    return result.value;
  }
  if ("parse" in validateSearch2) return validateSearch2.parse(input);
  if (typeof validateSearch2 === "function") return validateSearch2(input);
  return {};
}
function applySearchMiddleware(search, dest, destRoutes, includeValidateSearch) {
  const middlewares = [];
  for (const route of destRoutes) {
    const routeOptions = route.options;
    if ("search" in routeOptions) {
      if (routeOptions.search?.middlewares) middlewares.push(...routeOptions.search.middlewares);
    } else if (routeOptions.preSearchFilters || routeOptions.postSearchFilters) {
      const legacyMiddleware = ({ search: search2, next }) => {
        const result = next(routeOptions.preSearchFilters ? routeOptions.preSearchFilters.reduce((prev, next2) => next2(prev), search2) : search2);
        return routeOptions.postSearchFilters ? routeOptions.postSearchFilters.reduce((prev, next2) => next2(prev), result) : result;
      };
      middlewares.push(legacyMiddleware);
    }
    const routeValidateSearch = routeOptions.validateSearch;
    if (routeValidateSearch) {
      const validate = ({ search: search2, next, meta }) => {
        const result = next(search2);
        if (includeValidateSearch) try {
          const validated = validateSearch(routeValidateSearch, result);
          if (meta && validated) {
            for (const key in validated) if (!(key in result)) (meta.defaulted ||= /* @__PURE__ */ new Map()).set(key, validated[key]);
          }
          return {
            ...result,
            ...validated
          };
        } catch {
        }
        return result;
      };
      middlewares.push(validate);
    }
  }
  const applyNext = (index, currentSearch, meta) => {
    if (index >= middlewares.length) {
      if (!dest.search) return {};
      if (dest.search === true) return currentSearch;
      const result = functionalUpdate(dest.search, currentSearch);
      if (meta) meta.explicit = result;
      return result;
    }
    const next = (newSearch, collectMeta) => {
      if (collectMeta) {
        const nextMeta = meta || {};
        return {
          search: applyNext(index + 1, newSearch, nextMeta),
          meta: nextMeta
        };
      }
      return applyNext(index + 1, newSearch, meta);
    };
    return middlewares[index]({
      search: currentSearch,
      next,
      meta
    });
  };
  return applyNext(0, search);
}
function findGlobalNotFoundRouteId(notFoundMode, routes) {
  if (notFoundMode !== "root") {
    let fallback;
    for (let i = routes.length - 1; i >= 0; i--) {
      const route = routes[i];
      if (route.options.notFoundComponent) return route.id;
      fallback ||= route.children && route.id;
    }
    if (fallback) return fallback;
  }
  return rootRouteId;
}
function resolveNextParams(spec, base) {
  return spec === false || spec === null ? /* @__PURE__ */ Object.create(null) : (spec ?? true) === true ? base : Object.assign(base, functionalUpdate(spec, base));
}
function extractStrictParams(route, accumulatedParams) {
  const parseParams = route.options.params?.parse ?? route.options.parseParams;
  if (parseParams) Object.assign(accumulatedParams, parseParams(accumulatedParams));
}
function preloadComponent(route, type) {
  return route.options[type]?.preload?.();
}
function loadComponents(route, onPendingReady) {
  const component = preloadComponent(route, "component");
  const pending = preloadComponent(route, "pendingComponent");
  const pendingReady = onPendingReady && pending ? pending.then(onPendingReady) : pending;
  if (onPendingReady && !pending) onPendingReady();
  if (component && pendingReady) return Promise.all([component, pendingReady]).then(() => {
  });
  return component ?? pendingReady;
}
function loadRouteChunk(route, componentType, onPendingReady) {
  const afterLazy = () => componentType === false ? void 0 : componentType ? preloadComponent(route, componentType) : loadComponents(route, onPendingReady);
  const current = route._lazy;
  if (current) return current === true ? afterLazy() : current.then(afterLazy);
  if (!route.lazyFn) return afterLazy();
  const promise = route.lazyFn().then((lazyRoute) => {
    {
      const { id: _id, ...options } = lazyRoute.options;
      Object.assign(route.options, options);
      route._lazy = true;
    }
  }, (error) => {
    route._lazy = void 0;
    throw error;
  });
  route._lazy = promise;
  return promise.then(afterLazy);
}
function _getRenderedMatches(matches) {
  const end = matches.findIndex((match) => match.status !== "success" || match._notFound) + 1;
  return end && end < matches.length ? matches.slice(0, end) : matches;
}
function _getAssetMatches(matches) {
  let end = matches.length;
  for (let index = 0; index < end; index++) {
    const match = matches[index];
    if (match._assetEnd !== void 0) {
      end = Math.min(end, Math.max(index + 1, match._assetEnd));
      continue;
    }
    if (match.status !== "success" || match._notFound) {
      end = index + 1;
      break;
    }
  }
  return end < matches.length ? matches.slice(0, end) : matches;
}
const SUCCESS$1 = 0;
const ERROR$1 = 1;
const NOT_FOUND$1 = 2;
const REDIRECTED$1 = 3;
const CANCELED = 4;
function isControl(result) {
  return typeof result[0] === "number";
}
function waitFor$1(value, signal) {
  if (signal.aborted) return Promise.race([Promise.reject(signal), value]);
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal);
    signal.addEventListener("abort", abort, { once: true });
    Promise.resolve(value).then(resolve, reject).finally(() => signal.removeEventListener("abort", abort));
  });
}
function getRoute$1(router, match) {
  return router.routesById[match.routeId];
}
function normalize$1(value, rejected, routeId) {
  if (isRedirect(value)) return [REDIRECTED$1, value];
  if (isNotFound(value)) {
    value.routeId ||= routeId;
    return [NOT_FOUND$1, value];
  }
  if (rejected && typeof value?.then === "function") value = new Error("A Promise was thrown", { cause: value });
  return rejected ? [ERROR$1, value] : [SUCCESS$1, value];
}
function normalizeError$1(route, cause) {
  let outcome = normalize$1(cause, true, route.id);
  if (outcome[0] !== ERROR$1) return outcome;
  try {
    route.options.onError?.(outcome[1]);
  } catch (onErrorCause) {
    outcome = normalize$1(onErrorCause, true, route.id);
  }
  return outcome;
}
function normalizeLaneError(route, cause, options) {
  if (options[0].signal.aborted || !options[2]()) {
    options[0].abort();
    return [CANCELED];
  }
  return normalizeError$1(route, cause);
}
function navigateFrom$1(router, location) {
  return (opts) => router.navigate({
    ...opts,
    _fromLocation: location
  });
}
async function contextualize$1(router, lane, options, end, planSuccessfulLane) {
  const [location, matches] = lane;
  const signal = options[0].signal;
  const preload = !!options[4];
  for (let index = options[7] ?? 0; index < end; index++) {
    const match = matches[index];
    const route = getRoute$1(router, match);
    match.abortController = options[0];
    const parentContext = matches[index - 1]?.context ?? router.options.context ?? {};
    const common = {
      params: match.params,
      location,
      navigate: navigateFrom$1(router, location),
      buildLocation: router.buildLocation,
      cause: preload ? "preload" : match.cause,
      abortController: options[0],
      preload,
      matches,
      routeId: route.id
    };
    let context = parentContext;
    try {
      let routeContext = match._ctx;
      if (!routeContext && route.options.context) routeContext = match._ctx = route.options.context({
        ...common,
        deps: match.loaderDeps,
        context: parentContext
      }) || {};
      context = {
        ...parentContext,
        ...routeContext
      };
      match.context = context;
    } catch (cause) {
      releaseFlight(router, match);
      return [index, normalizeLaneError(route, cause, options)];
    }
    if (signal.aborted || !options[2]()) {
      options[0].abort();
      return [index, [CANCELED]];
    }
    const validationError = match.paramsError ?? match.searchError;
    if (validationError !== void 0) {
      releaseFlight(router, match);
      return [index, normalizeLaneError(route, validationError, options)];
    }
    const beforeLoad = route.options.beforeLoad;
    if (!beforeLoad) continue;
    const beforeLoadContext = {
      ...common,
      search: match.search,
      context,
      ...router.options.additionalContext
    };
    const previousStatus = match.status;
    if (previousStatus === "success") match.status = "pending";
    options[8]?.();
    try {
      setFetching(router, match, "beforeLoad", options[0]);
      const result = await waitFor$1(beforeLoad(beforeLoadContext), signal);
      if (!options[2]()) {
        options[0].abort();
        return [index, [CANCELED]];
      }
      const outcome = normalize$1(result, false, route.id);
      if (outcome[0] !== SUCCESS$1) {
        releaseFlight(router, match);
        return [index, outcome];
      }
      match.context = {
        ...context,
        ...result
      };
    } catch (cause) {
      releaseFlight(router, match);
      return [index, normalizeLaneError(route, cause, options)];
    } finally {
      if (previousStatus === "success" && match.status === "pending") match.status = "success";
      setFetching(router, match, false, options[0]);
    }
  }
  planSuccessfulLane();
}
function releaseOwnedFlight(router, match, flight) {
  if (!flight || --flight[2]) return;
  if (router._flights?.get(match.id) === flight) {
    const current = router._tx;
    if (current && !current[0].signal.aborted && true && !current[3].includes(match) && current[3].some((candidate) => candidate.id === match.id) && current[3].some((candidate) => candidate.isFetching === "beforeLoad")) return;
    router._flights.delete(match.id);
  }
  return flight[1];
}
function releaseFlight(router, match) {
  const flight = match._flight;
  match._flight = void 0;
  releaseOwnedFlight(router, match, flight)?.abort();
}
function transferMatchResources(router, previous, next) {
  const abort = [];
  for (const match of previous) {
    const flight = match._flight;
    match._flight = void 0;
    const controller = releaseOwnedFlight(router, match, flight);
    if (controller) abort.push(controller);
  }
  for (const controller of abort) controller.abort();
}
function releaseUnownedFlights(router) {
  const abort = [];
  for (const [id, flight] of router._flights ?? []) if (!flight[2]) {
    router._flights.delete(id);
    abort.push(flight[1]);
  }
  for (const controller of abort) controller.abort();
}
function acquireMatchResources(matches) {
  for (const match of matches) {
    const flight = match._flight;
    if (flight) flight[2]++;
  }
}
function setFetching(router, match, value, owner) {
  match.isFetching = value;
  if (owner && router._tx?.[0] !== owner) return;
  const store = router.stores.byRoute.get(match.routeId);
  const presented = store?.get();
  if (presented?.id === match.id) store.set({
    ...presented,
    isFetching: value
  });
}
function getLoaderContext$1(router, lane, match, route, controller, parentMatchPromise, preload) {
  const location = lane[0];
  return {
    params: match.params,
    location,
    navigate: navigateFrom$1(router, location),
    cause: preload ? "preload" : match.cause,
    abortController: controller,
    preload,
    deps: match.loaderDeps,
    parentMatchPromise,
    context: match.context,
    route,
    ...router.options.additionalContext
  };
}
async function loadResource(router, lane, match, route, loader, parentMatchPromise, preload, owner) {
  const signal = owner.signal;
  if (signal.aborted) return [CANCELED];
  if (!loader) return [SUCCESS$1, void 0];
  let flight = match._flight;
  setFetching(router, match, "loader", owner);
  try {
    if (!flight) {
      const controller = new AbortController();
      flight = [
        Promise.resolve().then(() => loader(getLoaderContext$1(router, lane, match, route, controller, parentMatchPromise, preload))).then((value) => normalize$1(value, false, route.id), (cause) => normalize$1(cause, true, route.id)).then((result) => {
          if (result[0] !== SUCCESS$1 && router._flights?.get(match.id) === flight) {
            router._flights.delete(match.id);
            if (!flight[2]) controller.abort();
          }
          return result[0] === ERROR$1 && flight[2] ? normalizeError$1(route, result[1]) : result;
        }),
        controller,
        1
      ];
      (router._flights ??= /* @__PURE__ */ new Map()).set(match.id, flight);
    }
    match._flight = flight;
    match.abortController = flight[1];
    return await waitFor$1(flight[0], signal);
  } catch (cause) {
    if (cause !== signal) throw cause;
    releaseFlight(router, match);
    return [CANCELED];
  } finally {
    setFetching(router, match, false, owner);
  }
}
function settleInto(match, result, preload) {
  if (result[0] === SUCCESS$1) {
    match.loaderData = result[1];
    match.error = void 0;
    match.status = "success";
    match.invalid = false;
    match.updatedAt = Date.now();
    match.preload = preload;
  } else if (result[0] !== REDIRECTED$1) {
    match.status = "success";
    match.error = void 0;
    match.invalid = true;
  }
}
function cacheLoaderMatch(router, match, planned) {
  const current = router._cache.get(match.id);
  if (current !== planned || router._committed.some((candidate) => candidate.id === match.id && candidate._flight === match._flight)) return;
  const cached = {
    ...match,
    _notFound: void 0,
    context: {}
  };
  if (cached._flight) cached._flight[2]++;
  router._cache.set(match.id, cached);
  if (current) releaseFlight(router, current);
}
function getParentSnapshot(match, outcome) {
  if (outcome[0] === ERROR$1 || outcome[0] === NOT_FOUND$1) return {
    ...match,
    status: outcome[0] === ERROR$1 ? "error" : "notFound",
    error: outcome[1],
    _flight: void 0
  };
  return match;
}
function createLoaderTask$1(router, lane, index, tasks, semanticParent, options) {
  const match = lane[1][index];
  const route = getRoute$1(router, match);
  const preload = !!options[4];
  const plannedCacheMatch = preload ? router._cache.get(match.id) : void 0;
  let configured;
  let reload = false;
  let reloadFailure;
  try {
    if (match.status === "success") {
      configured = route.options.shouldReload;
      if (typeof configured === "function") configured = configured(getLoaderContext$1(router, lane, match, route, options[0], semanticParent, preload));
      if (!options[2]()) {
        options[0].abort();
        reloadFailure = [CANCELED];
      }
    }
    if (!reloadFailure) if (match.status !== "success") reload = true;
    else {
      const staleAge = options[4] || match.preload ? route.options.preloadStaleTime ?? router.options.defaultPreloadStaleTime ?? 3e4 : route.options.staleTime ?? router.options.defaultStaleTime ?? 0;
      reload = !!(match.invalid || configured || configured === void 0 && Date.now() - match.updatedAt >= staleAge && (options[6] || match.cause === "enter" || options[3].some((candidate2) => candidate2.routeId === match.routeId && candidate2.id !== match.id)));
    }
  } catch (cause) {
    match.invalid = true;
    releaseFlight(router, match);
    reloadFailure = normalizeLaneError(route, cause, options);
  }
  const routeLoader = route.options.loader;
  const loader = typeof routeLoader === "function" ? routeLoader : routeLoader?.handler;
  let donor = (!preload || route.options.preload !== false) && routeLoader && true ? router._flights?.get(match.id) : void 0;
  if (donor === match._flight || reloadFailure) donor = void 0;
  else if (donor && !reload && !preload && configured === void 0) reload = true;
  else if (!reload) donor = void 0;
  const background = !!(routeLoader && reload && match.status === "success" && !preload && !options[5] && ((typeof routeLoader === "function" ? void 0 : routeLoader?.staleReloadMode) ?? router.options.defaultStaleReloadMode) !== "blocking");
  const loaded = reload && (!preload || route.options.preload !== false);
  const blocking = loaded && !background && (match.status !== "success" || !!routeLoader);
  const onLazyReady = route.lazyFn && route._lazy !== true ? options[8] : void 0;
  if (loaded && !routeLoader) {
    match.invalid = false;
    match.updatedAt = Date.now();
  }
  if (donor) donor[2]++;
  if (blocking) {
    const acceptedFlight = match._flight;
    match._flight = donor;
    releaseOwnedFlight(router, match, acceptedFlight)?.abort();
    if (match.status === "success") match.status = "pending";
    options[8]?.();
  }
  if (!loaded) match.isFetching = false;
  const outcome = (reloadFailure ? Promise.resolve(reloadFailure) : !blocking ? Promise.resolve([SUCCESS$1, match.loaderData]) : loadResource(router, lane, match, route, loader, semanticParent, preload, options[0])).then((result) => {
    if (blocking) {
      settleInto(match, result, preload);
      if (result[0] === SUCCESS$1) {
        if (preload && routeLoader && !options[0].signal.aborted) cacheLoaderMatch(router, match, plannedCacheMatch);
        match.status = "pending";
      }
    }
    return result;
  });
  const chunkFailure = waitFor$1(Promise.resolve().then(() => loadRouteChunk(route, void 0, onLazyReady)), options[0].signal).then(() => void 0, (cause) => [index, normalizeLaneError(route, cause, options)]).then((failure) => outcome.then((result) => {
    if (blocking && !failure && result[0] === SUCCESS$1 && match.status === "pending" && options[2]()) {
      match.status = "success";
      options[8]?.();
    }
    return failure;
  }));
  tasks.push([
    index,
    outcome,
    chunkFailure
  ]);
  if (!background) return outcome.then((result) => getParentSnapshot(match, result));
  const candidate = {
    ...match,
    status: "pending",
    preload: false,
    _flight: donor
  };
  match.invalid = false;
  match.isFetching = "loader";
  const backgroundOutcome = loadResource(router, lane, candidate, route, loader, semanticParent, false, options[0]).then((result) => {
    match.isFetching = false;
    settleInto(candidate, result, false);
    return result;
  });
  (lane[2] ??= []).push([
    index,
    backgroundOutcome,
    chunkFailure,
    candidate
  ]);
  return backgroundOutcome.then((result) => getParentSnapshot(candidate, result));
}
async function getNotFoundBoundary$1(router, matches, indexed, signal, fallback = 0) {
  const cause = indexed?.[1][1];
  let index = cause?.routeId ? matches.findIndex((match) => match.routeId === cause.routeId) : indexed?.[0] ?? matches.length - 1;
  if (index < 0) index = 0;
  for (let i = index; i >= 0; i--) {
    const route = getRoute$1(router, matches[i]);
    const loading = loadRouteChunk(route, false);
    if (loading) try {
      await waitFor$1(loading, signal);
    } catch (cause2) {
      if (cause2 === signal) throw cause2;
    }
    if (route.options.notFoundComponent) return i;
  }
  return cause?.routeId ? index : fallback;
}
function discardBackground(router, lane) {
  if (lane[2]) {
    transferMatchResources(router, lane[2].map((task) => task[3]));
    lane[2] = void 0;
  }
}
async function settleTasks(tasks, serialFailure, redirectTasks, gate) {
  let loaderFailure;
  try {
    await Promise.all(tasks.map((task) => task[1].then(async (outcome) => {
      const taskIndex = task[0];
      if (gate && taskIndex >= await gate) return;
      if (outcome[0] >= REDIRECTED$1) throw [taskIndex, outcome];
      if (!loaderFailure && outcome[0] !== SUCCESS$1) {
        loaderFailure = [taskIndex, outcome];
        await Promise.all((redirectTasks ?? []).map((nextTask) => {
          if (nextTask[0] <= taskIndex) return;
          return nextTask[1].then((nextOutcome) => {
            if (nextOutcome[0] === REDIRECTED$1) throw [nextTask[0], nextOutcome];
          });
        }));
      }
    })));
  } catch (cause) {
    return cause;
  }
  return serialFailure ?? loaderFailure;
}
async function reduceLane(router, lane, tasks, controller, redirects, settlement, onReady) {
  const matches = lane[1];
  let failure = await settlement;
  let redirectLimitExceeded = false;
  const plannedBoundary = matches.findIndex((match) => match._notFound);
  const boundaryOf = (found) => found[1][0] === NOT_FOUND$1 ? getNotFoundBoundary$1(router, matches, found, controller.signal) : found[0];
  let readinessEnd = plannedBoundary < 0 ? matches.length : plannedBoundary;
  if ((failure?.[1][0] ?? 0) >= REDIRECTED$1) readinessEnd = 0;
  else if (failure) {
    readinessEnd = failure[2] ??= await boundaryOf(failure);
    for (const task of tasks) {
      if (task[0] >= readinessEnd) break;
      const outcome = await task[1];
      if (outcome[0] !== SUCCESS$1 && outcome[0] < REDIRECTED$1 && !("loaderData" in matches[task[0]])) {
        failure = [task[0], outcome];
        readinessEnd = failure[2] = await boundaryOf(failure);
        break;
      }
    }
  }
  for (const task of tasks) {
    if (task[0] >= readinessEnd) break;
    const chunkFailure = await task[2];
    if (!chunkFailure) continue;
    failure = chunkFailure;
    break;
  }
  if ((failure?.[1][0] ?? 0) >= REDIRECTED$1) {
    const outcome = failure[1];
    if (outcome[0] !== REDIRECTED$1 || outcome[1].options.reloadDocument || redirects < 20) {
      discardBackground(router, lane);
      return outcome;
    }
    redirectLimitExceeded = true;
    failure = [0, [ERROR$1, /* @__PURE__ */ new Error("Too many redirects")]];
  }
  const boundary = failure ? failure[2] ?? await boundaryOf(failure) : plannedBoundary;
  if (boundary >= 0) {
    const outcome = failure?.[1];
    const kind = outcome?.[0];
    const match = matches[boundary];
    const cause = outcome?.[1];
    const install = () => {
      if (outcome) {
        match._notFound = void 0;
        if (kind === ERROR$1) match.status = "error";
        else {
          cause.routeId = match.routeId;
          if (match.routeId === router.routeTree.id) {
            match.status = "success";
            match._notFound = true;
          } else match.status = "notFound";
        }
        match.error = cause;
        match.isFetching = false;
      }
    };
    install();
    try {
      await waitFor$1(outcome ? Promise.resolve().then(() => loadRouteChunk(getRoute$1(router, match), kind === ERROR$1 ? "errorComponent" : "notFoundComponent")) : Promise.all([loadRouteChunk(getRoute$1(router, match)), loadRouteChunk(getRoute$1(router, match), "notFoundComponent")]), controller.signal);
    } catch (cause2) {
      if (cause2 === controller.signal) {
        discardBackground(router, lane);
        return [CANCELED];
      }
    }
    if (!outcome) {
      match.status = "success";
      onReady?.();
    } else if (redirectLimitExceeded) {
      controller.abort();
      await Promise.all([
        ...tasks.map((task) => task[1]),
        ...tasks.map((task) => task[2]),
        ...(lane[2] ?? []).map((task) => task[1])
      ]);
      discardBackground(router, lane);
      transferMatchResources(router, matches);
      install();
    }
  }
  return lane;
}
async function projectLane$1(router, lane, signal, start = 0, end = lane[1].length) {
  const matches = lane[1];
  for (let index = start; index < end; index++) {
    const match = matches[index];
    const routeOptions = getRoute$1(router, match).options;
    if (routeOptions.head || routeOptions.scripts) try {
      const context = {
        ssr: router.options.ssr,
        matches,
        match,
        params: match.params,
        loaderData: match.loaderData
      };
      const [head, scripts] = await waitFor$1(Promise.all([routeOptions.head?.(context), routeOptions.scripts?.(context)]), signal);
      match.meta = head?.meta;
      match.links = head?.links;
      match.headScripts = head?.scripts;
      match.styles = head?.styles;
      match.scripts = scripts;
    } catch (cause) {
      if (cause === signal) break;
      console.error(cause);
    }
    if (match.status !== "success" || match._notFound) break;
  }
  return lane;
}
async function executeClientLane(router, location, matches, options) {
  const matched = [location, matches];
  let plannedBoundary = matches.findIndex((match) => match._notFound);
  if (router.options.notFoundMode !== "root" && plannedBoundary >= 0) {
    const boundary = await getNotFoundBoundary$1(router, matched[1], void 0, options[0].signal, plannedBoundary);
    if (boundary !== plannedBoundary) {
      matches[plannedBoundary]._notFound = void 0;
      matches[boundary]._notFound = true;
    }
    plannedBoundary = boundary;
  }
  let end = plannedBoundary < 0 ? matches.length : plannedBoundary + 1;
  const tasks = [];
  const start = options[7] ?? 0;
  let semanticParent = start ? Promise.resolve(matched[1][start - 1]) : void 0;
  const planSuccessfulLane = () => {
    for (let index = start; index < end; index++) {
      if (options[0].signal.aborted) break;
      semanticParent = createLoaderTask$1(router, matched, index, tasks, semanticParent, options);
    }
  };
  const failure = await contextualize$1(router, matched, options, end, planSuccessfulLane);
  if (failure) {
    options[5] = true;
    end = failure[0];
    if (failure[1][0] === NOT_FOUND$1) {
      failure[2] = await getNotFoundBoundary$1(router, matched[1], failure, options[0].signal);
      end = Math.min(end, failure[2] + 1);
    } else if (failure[1][0] >= REDIRECTED$1) end = 0;
    planSuccessfulLane();
  }
  if (options[2]() && !options[4]) releaseUnownedFlights(router);
  let reduced;
  try {
    const reduction = reduceLane(router, matched, tasks, options[0], options[1], settleTasks(tasks, failure, matched[2]), options[8]);
    if (matched[2]?.length) matched[3] = settleTasks(matched[2], void 0, void 0, reduction.then((foreground) => isControl(foreground) ? 0 : _getRenderedMatches(foreground[1]).length, () => 0));
    reduced = await reduction;
  } catch (cause) {
    discardBackground(router, matched);
    throw cause;
  }
  if (isControl(reduced)) return reduced;
  return projectLane$1(router, reduced, options[0].signal, options[7] === reduced[1].length ? options[7] : 0);
}
async function preloadClientRoute(router, opts, redirects = 0) {
  if (redirects > 20) return;
  const location = opts._builtLocation ?? router.buildLocation(opts);
  const base = router._committed;
  const controller = new AbortController();
  let matches;
  try {
    matches = router.matchRoutes(location, { _controller: controller });
    acquireMatchResources(matches);
  } catch (cause) {
    controller.abort();
    if (!isNotFound(cause)) console.error(cause);
    return;
  }
  (router._preloads ??= /* @__PURE__ */ new Map()).set(controller, matches);
  let active;
  try {
    let result;
    try {
      result = await executeClientLane(router, location, matches, [
        controller,
        redirects,
        () => true,
        base,
        true
      ]);
    } finally {
      active = router._preloads.delete(controller);
      transferMatchResources(router, matches);
      controller.abort();
    }
    if (!isControl(result)) return result[1];
    if (active && result[0] === REDIRECTED$1 && !result[1].options.reloadDocument) return preloadClientRoute(router, {
      ...result[1].options,
      _fromLocation: location
    }, redirects + 1);
  } catch (cause) {
    if (!isNotFound(cause)) console.error(cause);
  }
}
function waitForReason(value, signal, onLate) {
  const promise = Promise.resolve(value);
  if (signal.aborted) {
    return Promise.race([Promise.reject(signal.reason), promise]);
  }
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, { once: true });
    promise.then((result) => {
      if (signal.aborted) ;
      else resolve(result);
    }, reject).finally(() => signal.removeEventListener("abort", abort));
  });
}
const SUCCESS = 0;
const ERROR = 1;
const NOT_FOUND = 2;
const REDIRECTED = 3;
const SKIPPED = 4;
function getRoute(router, match) {
  return router.routesById[match.routeId];
}
function normalize(value, rejected) {
  if (isRedirect(value)) return [REDIRECTED, value];
  if (isNotFound(value)) return [NOT_FOUND, value];
  if (rejected && typeof value?.then === "function") value = new Error("A Promise was thrown", { cause: value });
  return rejected ? [ERROR, value] : [SUCCESS, value];
}
function normalizeError(route, cause) {
  let outcome = normalize(cause, true);
  if (outcome[0] !== ERROR) return outcome;
  try {
    route.options.onError?.(outcome[1]);
  } catch (onErrorCause) {
    outcome = normalize(onErrorCause, true);
  }
  return outcome;
}
function maybe(value, cause) {
  if (cause !== void 0) return {
    status: "error",
    error: cause
  };
  return {
    status: "success",
    value
  };
}
function navigateFrom(router, location) {
  return (options) => router.navigate({
    ...options,
    _fromLocation: location
  });
}
function waitFor(value, signal) {
  return signal ? waitForReason(value, signal) : value;
}
async function resolveSsr(router, lane, index) {
  const match = lane.matches[index];
  const route = getRoute(router, match);
  const parentSsr = lane.matches[index - 1]?.ssr;
  if (router.isShell()) return route.id === rootRouteId;
  if (parentSsr === false) return false;
  const inherit = (value) => {
    return value === true && parentSsr === "data-only" ? "data-only" : value;
  };
  const defaultSsr = router.options.defaultSsr ?? true;
  const inheritedDefault = inherit(defaultSsr);
  match.ssr = inheritedDefault;
  const option = route.options.ssr;
  if (option === void 0) return inheritedDefault;
  if (typeof option !== "function") return inherit(option);
  return inherit(await option({
    search: maybe(match.search, match.searchError),
    params: maybe(match.params, match.paramsError),
    location: lane.location,
    matches: lane.matches.map((candidate) => ({
      index: candidate.index,
      pathname: candidate.pathname,
      fullPath: candidate.fullPath,
      staticData: candidate.staticData,
      id: candidate.id,
      routeId: candidate.routeId,
      search: maybe(candidate.search, candidate.searchError),
      params: maybe(candidate.params, candidate.paramsError),
      ssr: candidate.ssr
    }))
  }) ?? defaultSsr);
}
function stampNotFound(match, outcome) {
  if (outcome[0] === NOT_FOUND && !outcome[1].routeId) outcome[1].routeId = match.routeId;
  return outcome;
}
async function contextualize(router, lane, signal) {
  const globalBoundary = lane.matches.findIndex((match) => match._notFound);
  let end = globalBoundary < 0 ? lane.matches.length : globalBoundary + 1;
  let failure;
  let parentContext = { ...router.options.context ?? {} };
  for (let index = 0; index < end; index++) {
    const match = lane.matches[index];
    const route = getRoute(router, match);
    try {
      match.ssr = await resolveSsr(router, lane, index);
    } catch (cause) {
      signal?.throwIfAborted();
      failure = [index, stampNotFound(match, normalizeError(route, cause))];
      end = index;
    }
    signal?.throwIfAborted();
    if (failure?.[1][0] === REDIRECTED) break;
    match.__beforeLoadContext = void 0;
    let context = parentContext;
    try {
      let routeContext;
      if (route.options.context) {
        const routeContextOptions = {
          deps: match.loaderDeps,
          params: match.params,
          context: parentContext,
          location: lane.location,
          navigate: navigateFrom(router, lane.location),
          buildLocation: router.buildLocation,
          cause: match.cause,
          abortController: match.abortController,
          preload: false,
          matches: lane.matches,
          routeId: route.id
        };
        routeContext = route.options.context(routeContextOptions) ?? void 0;
      }
      context = {
        ...parentContext,
        ...routeContext
      };
      match.context = context;
    } catch (cause) {
      signal?.throwIfAborted();
      if (!failure) failure = [index, stampNotFound(match, normalizeError(route, cause))];
      end = index;
      break;
    }
    signal?.throwIfAborted();
    if (failure) break;
    const validationError = match.paramsError ?? match.searchError;
    if (validationError !== void 0) {
      failure = [index, stampNotFound(match, normalizeError(route, validationError))];
      end = index;
      break;
    }
    signal?.throwIfAborted();
    if (match.ssr === false || !route.options.beforeLoad) {
      parentContext = context;
      continue;
    }
    const abortController = match.abortController;
    const options = {
      search: match.search,
      abortController,
      params: match.params,
      preload: false,
      context,
      location: lane.location,
      navigate: navigateFrom(router, lane.location),
      buildLocation: router.buildLocation,
      cause: match.cause,
      matches: lane.matches,
      routeId: route.id,
      ...router.options.additionalContext
    };
    try {
      const beforeLoadContext = await route.options.beforeLoad(options);
      signal?.throwIfAborted();
      const outcome = stampNotFound(match, normalize(beforeLoadContext, false));
      if (outcome[0] !== SUCCESS) {
        failure = [index, outcome];
        end = index;
        break;
      }
      match.__beforeLoadContext = beforeLoadContext;
      match.context = {
        ...context,
        ...beforeLoadContext
      };
      parentContext = match.context;
    } catch (cause) {
      signal?.throwIfAborted();
      failure = [index, stampNotFound(match, normalizeError(route, cause))];
      end = index;
      break;
    }
  }
  return {
    location: lane.location,
    matches: lane.matches,
    end,
    failure
  };
}
function getLoaderContext(router, lane, match, route, index, tasks) {
  return {
    params: match.params,
    deps: match.loaderDeps,
    preload: false,
    parentMatchPromise: tasks[index - 1]?.match,
    abortController: match.abortController,
    context: match.context,
    location: lane.location,
    navigate: navigateFrom(router, lane.location),
    cause: match.cause,
    route,
    ...router.options.additionalContext
  };
}
function createLoaderTask(router, lane, index, tasks, signal) {
  const match = lane.matches[index];
  const route = getRoute(router, match);
  let outcome;
  if (match.ssr === false) outcome = Promise.resolve([SKIPPED]);
  else {
    const routeLoader = route.options.loader;
    const loader = typeof routeLoader === "function" ? routeLoader : routeLoader?.handler;
    if (!loader) outcome = Promise.resolve([SUCCESS, void 0]);
    else outcome = Promise.resolve().then(() => loader(getLoaderContext(router, lane, match, route, index, tasks))).then((result) => normalize(result, false), (cause) => normalize(cause, true)).then((result) => {
      if (result[0] !== REDIRECTED && (signal?.aborted || match.abortController.signal.reason === lane)) return [SKIPPED];
      if (result[0] === ERROR) result = normalizeError(route, result[1]);
      return stampNotFound(match, result);
    });
  }
  const parentMatch = outcome.then((result) => {
    const snapshot = { ...match };
    if (result[0] === SUCCESS) {
      snapshot.loaderData = result[1];
      snapshot.status = "success";
      snapshot.error = void 0;
      snapshot.invalid = false;
      snapshot.isFetching = false;
    } else if (result[0] === ERROR) {
      snapshot.status = "error";
      snapshot.error = result[1];
    } else if (result[0] === NOT_FOUND) {
      snapshot.status = "notFound";
      snapshot.error = result[1];
    }
    return snapshot;
  });
  return {
    index,
    outcome,
    match: parentMatch
  };
}
async function getNotFoundBoundary(router, matches, indexed, signal, fallback = 0) {
  const cause = indexed?.[1][1];
  let index = cause?.routeId ? matches.findIndex((match) => match.routeId === cause.routeId) : indexed?.[0] ?? matches.length - 1;
  if (index < 0) index = 0;
  for (let candidate = index; candidate >= 0; candidate--) {
    const route = getRoute(router, matches[candidate]);
    const loading = loadRouteChunk(route, false);
    if (loading) try {
      await loading;
    } catch {
      signal?.throwIfAborted();
    }
    signal?.throwIfAborted();
    if (route.options.notFoundComponent) return candidate;
  }
  return cause?.routeId ? index : fallback;
}
function abortMatches(matches, start = 0, reason) {
  for (let index = start; index < matches.length; index++) matches[index].abortController.abort(reason);
}
function resolveServerRedirect(router, location, value) {
  value.options._fromLocation = location;
  return {
    type: "redirect",
    redirect: router.resolveRedirect(value)
  };
}
async function applyFailure(router, lane, indexed, signal) {
  if (!indexed) {
    const boundary2 = lane.matches.findIndex((match2) => match2._notFound);
    if (boundary2 >= 0) {
      abortMatches(lane.matches, boundary2 + 1);
      return {
        status: 404,
        boundary: boundary2,
        kind: NOT_FOUND
      };
    }
    return { status: 200 };
  }
  const [index, outcome] = indexed;
  if (outcome[0] === ERROR) {
    const match2 = lane.matches[index];
    match2._notFound = void 0;
    match2.status = "error";
    match2.error = outcome[1];
    match2.isFetching = false;
    abortMatches(lane.matches, index + 1);
    return {
      status: 500,
      boundary: index,
      kind: ERROR
    };
  }
  const boundary = indexed[2] ?? await getNotFoundBoundary(router, lane.matches, indexed, signal);
  const match = lane.matches[boundary];
  const cause = outcome[1];
  cause.routeId = match.routeId;
  match._notFound = void 0;
  if (match.routeId === router.routeTree.id) {
    match.status = "success";
    match._notFound = true;
    match.error = cause;
  } else {
    match.status = "notFound";
    match.error = cause;
  }
  match.isFetching = false;
  abortMatches(lane.matches, boundary + 1);
  return {
    status: 404,
    boundary,
    kind: NOT_FOUND
  };
}
async function loadNormalChunks(router, lane, end, signal) {
  const chunks = [];
  for (let index = 0; index < lane.matches.length; index++) {
    const match = lane.matches[index];
    if (index >= end || match.ssr !== true || match.status !== "success") continue;
    const route = getRoute(router, match);
    try {
      const loading = loadRouteChunk(route);
      if (loading) {
        const chunk = loading.then(() => {
          signal?.throwIfAborted();
        }, (cause) => {
          signal?.throwIfAborted();
          return [index, stampNotFound(match, normalizeError(route, cause))];
        });
        chunk.catch(() => {
        });
        chunks.push(chunk);
      }
    } catch (cause) {
      signal?.throwIfAborted();
      chunks.push([index, stampNotFound(match, normalizeError(route, cause))]);
    }
  }
  for (const chunk of chunks) {
    const indexed = Array.isArray(chunk) ? chunk : await chunk;
    if (indexed) return indexed;
  }
}
async function projectLane(router, lane, signal) {
  for (const match of lane.matches) {
    const routeOptions = getRoute(router, match).options;
    if (routeOptions.head || routeOptions.scripts || routeOptions.headers) {
      const context = {
        ssr: router.options.ssr,
        matches: lane.matches,
        match,
        params: match.params,
        loaderData: match.loaderData
      };
      try {
        const [head, scripts, headers] = await Promise.all([
          routeOptions.head?.(context),
          routeOptions.scripts?.(context),
          routeOptions.headers?.(context)
        ]);
        signal?.throwIfAborted();
        match.meta = head?.meta;
        match.links = head?.links;
        match.headScripts = head?.scripts;
        match.styles = head?.styles;
        match.scripts = scripts;
        match.headers = headers;
      } catch (cause) {
        signal?.throwIfAborted();
        console.error(cause);
      }
    }
    if (match.ssr === false || match.status !== "success" || match._notFound) break;
  }
}
async function executeServerLane(router, location, matchedMatches, signal) {
  const matched = {
    location,
    matches: matchedMatches.map((match) => ({
      ...match,
      __beforeLoadContext: void 0,
      context: {},
      isFetching: false,
      abortController: new AbortController()
    }))
  };
  const abortLane = () => abortMatches(matched.matches, 0, signal?.reason);
  if (signal?.aborted) {
    abortLane();
    signal.throwIfAborted();
  }
  signal?.addEventListener("abort", abortLane, { once: true });
  try {
    const plannedGlobalBoundary = matched.matches.findIndex((match) => match._notFound);
    if (router.options.notFoundMode !== "root" && plannedGlobalBoundary >= 0) {
      const boundary = await getNotFoundBoundary(router, matched.matches, void 0, signal, plannedGlobalBoundary);
      if (boundary !== plannedGlobalBoundary) {
        matched.matches[plannedGlobalBoundary]._notFound = void 0;
        matched.matches[boundary]._notFound = true;
      }
    }
    const lane = await contextualize(router, matched, signal);
    signal?.throwIfAborted();
    let loaderEnd = lane.end;
    if (lane.failure?.[1][0] === REDIRECTED) loaderEnd = 0;
    else if (lane.failure?.[1][0] === NOT_FOUND) {
      lane.failure[2] = await getNotFoundBoundary(router, lane.matches, lane.failure, signal);
      loaderEnd = Math.min(loaderEnd, lane.failure[2] + 1);
    }
    const tasks = [];
    for (let index = 0; index < loaderEnd; index++) {
      const task = createLoaderTask(router, lane, index, tasks, signal);
      tasks.push(task);
    }
    let loaderFailure;
    let control = lane.failure?.[1][0] === REDIRECTED ? lane.failure : void 0;
    try {
      await Promise.all(tasks.map((task) => task.outcome.then((loadedOutcome) => {
        const match = lane.matches[task.index];
        const outcome = loadedOutcome;
        if (outcome[0] === SUCCESS) {
          match.loaderData = outcome[1];
          match.status = "success";
          match.error = void 0;
          match.invalid = false;
          match.isFetching = false;
          match.updatedAt = Date.now();
        } else if (outcome[0] === REDIRECTED) {
          control = [task.index, outcome];
          throw control;
        } else {
          if (match.ssr !== false) {
            match.status = "success";
            match.error = void 0;
            match.invalid = true;
            match.isFetching = false;
          }
          if (!loaderFailure && outcome[0] !== SKIPPED) loaderFailure = [task.index, outcome];
        }
      })));
    } catch (cause) {
      if (!Array.isArray(cause)) throw cause;
      control = cause;
    }
    signal?.throwIfAborted();
    if (control?.[1][0] === REDIRECTED) {
      abortMatches(lane.matches, 0, lane);
      return resolveServerRedirect(router, location, control[1][1]);
    }
    let failure = lane.failure ?? loaderFailure;
    const plannedBoundary = lane.matches.findIndex((match) => match._notFound);
    let readinessEnd;
    if (failure) {
      const outcomeEnd = failure[2] ??= failure[1][0] === NOT_FOUND ? await getNotFoundBoundary(router, lane.matches, failure, signal) : failure[0];
      for (const task of tasks) {
        if (task.index >= outcomeEnd) break;
        const outcome = await task.outcome;
        if (outcome[0] !== SUCCESS && outcome[0] < REDIRECTED && !("loaderData" in lane.matches[task.index])) {
          failure = [task.index, outcome];
          failure[2] = outcome[0] === NOT_FOUND ? await getNotFoundBoundary(router, lane.matches, failure, signal) : task.index;
          break;
        }
      }
      readinessEnd = failure[2];
    } else readinessEnd = plannedBoundary < 0 ? lane.matches.length : plannedBoundary;
    const requiredFailure = await loadNormalChunks(router, lane, readinessEnd, signal);
    signal?.throwIfAborted();
    if (requiredFailure) {
      if (requiredFailure[1][0] === REDIRECTED) {
        abortMatches(lane.matches);
        return resolveServerRedirect(router, location, requiredFailure[1][1]);
      }
      failure = requiredFailure;
    }
    const terminal = await applyFailure(router, lane, failure, signal);
    if (terminal.boundary !== void 0) {
      const match = lane.matches[terminal.boundary];
      if (match.ssr === true) {
        const route = getRoute(router, match);
        try {
          if (terminal.kind === ERROR) await loadRouteChunk(route, "errorComponent");
          else if (match._notFound) await Promise.all([loadRouteChunk(route), loadRouteChunk(route, "notFoundComponent")]);
          else await loadRouteChunk(route, "notFoundComponent");
        } catch {
        }
        signal?.throwIfAborted();
      }
    }
    signal?.throwIfAborted();
    await projectLane(router, {
      location: lane.location,
      matches: lane.matches
    }, signal);
    signal?.throwIfAborted();
    router.serverSsr?.onCleanup(abortLane);
    return {
      type: "render",
      status: terminal.status,
      matches: lane.matches
    };
  } finally {
    signal?.removeEventListener("abort", abortLane);
  }
}
async function loadServerRoute(router, opts) {
  router.updateLatestLocation();
  const next = router.latestLocation;
  const previous = router._committed;
  let result;
  try {
    const canonical = router.buildLocation({
      to: next.pathname,
      search: true,
      params: true,
      hash: true,
      state: true,
      _includeValidateSearch: true
    });
    if (next.publicHref !== canonical.publicHref) {
      const href = canonical.publicHref || "/";
      throw canonical.external ? redirect({ href }) : redirect({
        href,
        _builtLocation: canonical
      });
    }
    const changeInfo = getLocationChangeInfo(next, router.stores.resolvedLocation.get());
    router.emit({
      type: "onBeforeNavigate",
      ...changeInfo
    });
    router.emit({
      type: "onBeforeLoad",
      ...changeInfo
    });
    opts?._signal?.throwIfAborted();
    result = await waitFor(executeServerLane(router, next, router.matchRoutes(next), opts?._signal), opts?._signal);
    opts?._signal?.throwIfAborted();
  } catch (cause) {
    opts?._signal?.throwIfAborted();
    if (!isRedirect(cause)) throw cause;
    result = resolveServerRedirect(router, next, cause);
  }
  router._serverResult = result;
  router.batch(() => {
    router.stores.location.set(next);
    router.stores.status.set("idle");
    if (result.type === "render") {
      router.stores.setMatches(result.matches);
      router.stores.resolvedLocation.set(next);
    }
  });
  if (result.type === "render") {
    router._committed = result.matches;
    runRouteLifecycle(router, previous, result.matches);
  }
  router._commitPromise?.resolve();
  router._commitPromise = void 0;
}
const isServer = true;
function last(arr) {
  return arr[arr.length - 1];
}
function isFunction(d) {
  return typeof d === "function";
}
function functionalUpdate(updater, previous) {
  if (isFunction(updater)) return updater(previous);
  return updater;
}
const hasOwn = Object.prototype.hasOwnProperty;
function hasKeys(obj) {
  for (const key in obj) if (hasOwn.call(obj, key)) return true;
  return false;
}
const createNull = () => /* @__PURE__ */ Object.create(null);
const nullReplaceEqualDeep = (prev, next) => replaceEqualDeep(prev, next, createNull);
function replaceEqualDeep(prev, _next, _makeObj = () => ({}), _depth = 0) {
  return _next;
}
function isPlainObject(o) {
  if (!hasObjectPrototype(o)) return false;
  const ctor = o.constructor;
  if (typeof ctor === "undefined") return true;
  const prot = ctor.prototype;
  if (!hasObjectPrototype(prot)) return false;
  if (!prot.hasOwnProperty("isPrototypeOf")) return false;
  return true;
}
function hasObjectPrototype(o) {
  return Object.prototype.toString.call(o) === "[object Object]";
}
function deepEqual(a, b, opts) {
  if (a === b) return true;
  if (typeof a !== typeof b) return false;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    for (let i = 0, l = a.length; i < l; i++) if (!deepEqual(a[i], b[i], opts)) return false;
    return true;
  }
  if (isPlainObject(a) && isPlainObject(b)) {
    const ignoreUndefined = opts?.ignoreUndefined ?? true;
    if (opts?.partial) {
      for (const k in b) if (!ignoreUndefined || b[k] !== void 0) {
        if (!deepEqual(a[k], b[k], opts)) return false;
      }
      return true;
    }
    let aCount = 0;
    if (!ignoreUndefined) aCount = Object.keys(a).length;
    else for (const k in a) if (a[k] !== void 0) aCount++;
    let bCount = 0;
    for (const k in b) if (!ignoreUndefined || b[k] !== void 0) {
      bCount++;
      if (bCount > aCount || !deepEqual(a[k], b[k], opts)) return false;
    }
    return aCount === bCount;
  }
  return false;
}
function isModuleNotFoundError(error) {
  if (typeof error?.message !== "string") return false;
  return error.message.startsWith("Failed to fetch dynamically imported module") || error.message.startsWith("error loading dynamically imported module") || error.message.startsWith("Importing a module script failed");
}
const PATH_UNSAFE_RE = /[\x00-\x1f\x7f"<>`{}]/g;
function sanitizePathSegment(segment) {
  return segment.replace(PATH_UNSAFE_RE, (ch) => "%" + ch.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0"));
}
function decodeSegment(segment) {
  let decoded;
  try {
    decoded = decodeURI(segment);
  } catch {
    decoded = segment.replaceAll(/%[0-9A-F]{2}/gi, (match) => {
      try {
        return decodeURI(match);
      } catch {
        return match;
      }
    });
  }
  return sanitizePathSegment(decoded);
}
const DEFAULT_PROTOCOL_ALLOWLIST = [
  "http:",
  "https:",
  "mailto:",
  "tel:"
];
function isDangerousProtocol(url, allowlist) {
  if (!url) return false;
  try {
    const parsed = new URL(url);
    return !allowlist.has(parsed.protocol);
  } catch {
    return false;
  }
}
const HTML_ESCAPE_LOOKUP = {
  "&": "\\u0026",
  ">": "\\u003e",
  "<": "\\u003c",
  "\u2028": "\\u2028",
  "\u2029": "\\u2029"
};
const HTML_ESCAPE_REGEX = /[&><\u2028\u2029]/g;
function escapeHtml(str) {
  return str.replace(HTML_ESCAPE_REGEX, (match) => HTML_ESCAPE_LOOKUP[match]);
}
function decodePath(path) {
  if (!path) return {
    path,
    handledProtocolRelativeURL: false
  };
  if (!/[%\\\x00-\x1f\x7f]/.test(path) && !path.startsWith("//")) return {
    path,
    handledProtocolRelativeURL: false
  };
  const re = /%25|%5C/gi;
  let cursor = 0;
  let result = "";
  let match;
  while (null !== (match = re.exec(path))) {
    result += decodeSegment(path.slice(cursor, match.index)) + match[0];
    cursor = re.lastIndex;
  }
  result = result + decodeSegment(cursor ? path.slice(cursor) : path);
  let handledProtocolRelativeURL = false;
  if (result.startsWith("//")) {
    handledProtocolRelativeURL = true;
    result = "/" + result.replace(/^\/+/, "");
  }
  return {
    path: result,
    handledProtocolRelativeURL
  };
}
function encodePathLikeUrl(path) {
  if (!/\s|[^\u0000-\u007F]/.test(path)) return path;
  return path.replace(/\s|[^\u0000-\u007F]/gu, encodeURIComponent);
}
function arraysEqual(a, b) {
  if (a === b) return true;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
function getAssetCrossOrigin(assetCrossOrigin, kind) {
  if (!assetCrossOrigin) return;
  if (typeof assetCrossOrigin === "string") return assetCrossOrigin;
  return assetCrossOrigin[kind];
}
function getManifestScriptFormat(manifest) {
  return manifest?.scriptFormat ?? "module";
}
function getScriptPreloadAttrs(manifest, link, assetCrossOrigin) {
  const preloadLink = resolveManifestAssetLink(link);
  const crossOrigin = getAssetCrossOrigin(assetCrossOrigin, "script") ?? preloadLink.crossOrigin;
  return {
    ...getManifestScriptFormat(manifest) === "iife" ? {
      rel: "preload",
      as: "script"
    } : { rel: "modulepreload" },
    href: preloadLink.href,
    ...crossOrigin ? { crossOrigin } : {}
  };
}
function resolveManifestAssetLink(link) {
  if (typeof link === "string") return {
    href: link,
    crossOrigin: void 0
  };
  return link;
}
function appendUniqueUserTags(target, tags) {
  if (tags.length === 0) return;
  if (tags.length === 1) {
    target.push(tags[0]);
    return;
  }
  const seen = /* @__PURE__ */ new Set();
  for (const tag of tags) {
    const key = JSON.stringify(tag);
    if (seen.has(key)) continue;
    seen.add(key);
    target.push(tag);
  }
}
function getStylesheetHref(asset) {
  return resolveManifestCssLink(asset).href;
}
function resolveManifestCssLink(link) {
  if (typeof link === "string") return {
    href: link,
    crossOrigin: void 0
  };
  return link;
}
function createInlineCssStyleAsset(css) {
  return {
    attrs: { suppressHydrationWarning: true },
    children: css
  };
}
function createInlineCssPlaceholderAsset() {
  return { attrs: { suppressHydrationWarning: true } };
}
var BaseRoute = class {
  get to() {
    return this._to;
  }
  get id() {
    return this._id;
  }
  get path() {
    return this._path;
  }
  get fullPath() {
    return this._fullPath;
  }
  constructor(options) {
    this.init = (opts) => {
      this.originalIndex = opts.originalIndex;
      const options2 = this.options;
      const isRoot = !options2?.path && !options2?.id;
      this.parentRoute = this.options.getParentRoute?.();
      if (isRoot) this._path = rootRouteId;
      else if (!this.parentRoute) {
        invariant();
      }
      let path = isRoot ? rootRouteId : options2?.path;
      if (path && path !== "/") path = trimPathLeft(path);
      const customId = options2?.id || path;
      let id = isRoot ? rootRouteId : joinPaths([this.parentRoute.id === "__root__" ? "" : this.parentRoute.id, customId]);
      if (path === "__root__") path = "/";
      if (id !== "__root__") id = joinPaths(["/", id]);
      const fullPath = id === "__root__" ? "/" : joinPaths([this.parentRoute.fullPath, path]);
      this._path = path;
      this._id = id;
      this._fullPath = fullPath;
      this._to = trimPathRight(fullPath);
    };
    this.addChildren = (children) => {
      return this._addFileChildren(children);
    };
    this._addFileChildren = (children) => {
      if (Array.isArray(children)) this.children = children;
      if (typeof children === "object" && children !== null) this.children = Object.values(children);
      return this;
    };
    this._addFileTypes = () => {
      return this;
    };
    this.updateLoader = (options2) => {
      Object.assign(this.options, options2);
      return this;
    };
    this.update = (options2) => {
      Object.assign(this.options, options2);
      return this;
    };
    this.lazy = (lazyFn) => {
      this.lazyFn = lazyFn;
      return this;
    };
    this.redirect = (opts) => redirect({
      from: this.fullPath,
      ...opts
    });
    this.options = options || {};
    this.isRoot = !options?.getParentRoute;
    if (options?.id && options?.path) throw new Error(`Route cannot have both an 'id' and a 'path' option.`);
  }
};
var BaseRootRoute = class extends BaseRoute {
  constructor(options) {
    super(options);
  }
};
const GLOBAL_TSR = "$_TSR";
const TSR_SCRIPT_BARRIER_ID = "$tsr-stream-barrier";
function createSerializationAdapter(opts) {
  return opts;
}
// @__NO_SIDE_EFFECTS__
function makeSsrSerovalPlugin(serializationAdapter, options) {
  return /* @__PURE__ */ createPlugin({
    tag: "$TSR/t/" + serializationAdapter.key,
    test: serializationAdapter.test,
    parse: { stream(value, ctx, _data) {
      return { v: ctx.parse(serializationAdapter.toSerializable(value)) };
    } },
    serialize(node, ctx, _data) {
      options.didRun = true;
      return GLOBAL_TSR + '.t.get("' + serializationAdapter.key + '")(' + ctx.serialize(node.v) + ")";
    },
    deserialize: void 0
  });
}
// @__NO_SIDE_EFFECTS__
function makeSerovalPlugin(serializationAdapter) {
  return /* @__PURE__ */ createPlugin({
    tag: "$TSR/t/" + serializationAdapter.key,
    test: serializationAdapter.test,
    parse: {
      sync(value, ctx, _data) {
        return { v: ctx.parse(serializationAdapter.toSerializable(value)) };
      },
      async async(value, ctx, _data) {
        return { v: await ctx.parse(serializationAdapter.toSerializable(value)) };
      },
      stream(value, ctx, _data) {
        return { v: ctx.parse(serializationAdapter.toSerializable(value)) };
      }
    },
    serialize: void 0,
    deserialize(node, ctx, _data) {
      return serializationAdapter.fromSerializable(ctx.deserialize(node.v));
    }
  });
}
var RawStream = class {
  constructor(stream, options) {
    this.stream = stream;
    this.hint = options?.hint ?? "binary";
  }
};
const BufferCtor = globalThis.Buffer;
const hasNodeBuffer = !!BufferCtor && typeof BufferCtor.from === "function";
function uint8ArrayToBase64(bytes) {
  if (bytes.length === 0) return "";
  if (hasNodeBuffer) return BufferCtor.from(bytes).toString("base64");
  const CHUNK_SIZE = 32768;
  const chunks = [];
  for (let i = 0; i < bytes.length; i += CHUNK_SIZE) {
    const chunk = bytes.subarray(i, i + CHUNK_SIZE);
    chunks.push(String.fromCharCode.apply(null, chunk));
  }
  return btoa(chunks.join(""));
}
function base64ToUint8Array(base64) {
  if (base64.length === 0) return new Uint8Array(0);
  if (hasNodeBuffer) {
    const buf = BufferCtor.from(base64, "base64");
    return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
const RAW_STREAM_FACTORY_BINARY = /* @__PURE__ */ Object.create(null);
const RAW_STREAM_FACTORY_TEXT = /* @__PURE__ */ Object.create(null);
const RAW_STREAM_FACTORY_CONSTRUCTOR_BINARY = (stream) => new ReadableStream({ start(controller) {
  stream.on({
    next(base64) {
      try {
        controller.enqueue(base64ToUint8Array(base64));
      } catch {
      }
    },
    throw(error) {
      controller.error(error);
    },
    return() {
      try {
        controller.close();
      } catch {
      }
    }
  });
} });
const textEncoderForFactory = new TextEncoder();
const RAW_STREAM_FACTORY_CONSTRUCTOR_TEXT = (stream) => {
  return new ReadableStream({ start(controller) {
    stream.on({
      next(value) {
        try {
          if (typeof value === "string") controller.enqueue(textEncoderForFactory.encode(value));
          else controller.enqueue(base64ToUint8Array(value.$b64));
        } catch {
        }
      },
      throw(error) {
        controller.error(error);
      },
      return() {
        try {
          controller.close();
        } catch {
        }
      }
    });
  } });
};
const FACTORY_BINARY = `(s=>new ReadableStream({start(c){s.on({next(b){try{const d=atob(b),a=new Uint8Array(d.length);for(let i=0;i<d.length;i++)a[i]=d.charCodeAt(i);c.enqueue(a)}catch(_){}},throw(e){c.error(e)},return(){try{c.close()}catch(_){}}})}}))`;
const FACTORY_TEXT = `(s=>{const e=new TextEncoder();return new ReadableStream({start(c){s.on({next(v){try{if(typeof v==='string'){c.enqueue(e.encode(v))}else{const d=atob(v.$b64),a=new Uint8Array(d.length);for(let i=0;i<d.length;i++)a[i]=d.charCodeAt(i);c.enqueue(a)}}catch(_){}},throw(x){c.error(x)},return(){try{c.close()}catch(_){}}})}})})`;
function toBinaryStream(readable) {
  const stream = createStream();
  const reader = readable.getReader();
  (async () => {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          stream.return(void 0);
          break;
        }
        stream.next(uint8ArrayToBase64(value));
      }
    } catch (error) {
      stream.throw(error);
    } finally {
      reader.releaseLock();
    }
  })();
  return stream;
}
function toTextStream(readable) {
  const stream = createStream();
  const reader = readable.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  (async () => {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          try {
            const remaining = decoder.decode();
            if (remaining.length > 0) stream.next(remaining);
          } catch {
          }
          stream.return(void 0);
          break;
        }
        try {
          const text = decoder.decode(value, { stream: true });
          if (text.length > 0) stream.next(text);
        } catch {
          stream.next({ $b64: uint8ArrayToBase64(value) });
        }
      }
    } catch (error) {
      stream.throw(error);
    } finally {
      reader.releaseLock();
    }
  })();
  return stream;
}
const RawStreamSSRPlugin = /* @__PURE__ */ createPlugin({
  tag: "tss/RawStream",
  extends: [/* @__PURE__ */ createPlugin({
    tag: "tss/RawStreamFactory",
    test(value) {
      return value === RAW_STREAM_FACTORY_BINARY;
    },
    parse: {
      sync(_value, _ctx, _data) {
        return {};
      },
      async async(_value, _ctx, _data) {
        return {};
      },
      stream(_value, _ctx, _data) {
        return {};
      }
    },
    serialize(_node, _ctx, _data) {
      return FACTORY_BINARY;
    },
    deserialize(_node, _ctx, _data) {
      return RAW_STREAM_FACTORY_BINARY;
    }
  }), /* @__PURE__ */ createPlugin({
    tag: "tss/RawStreamFactoryText",
    test(value) {
      return value === RAW_STREAM_FACTORY_TEXT;
    },
    parse: {
      sync(_value, _ctx, _data) {
        return {};
      },
      async async(_value, _ctx, _data) {
        return {};
      },
      stream(_value, _ctx, _data) {
        return {};
      }
    },
    serialize(_node, _ctx, _data) {
      return FACTORY_TEXT;
    },
    deserialize(_node, _ctx, _data) {
      return RAW_STREAM_FACTORY_TEXT;
    }
  })],
  test(value) {
    return value instanceof RawStream;
  },
  parse: {
    sync(value, ctx, _data) {
      const factory = value.hint === "text" ? RAW_STREAM_FACTORY_TEXT : RAW_STREAM_FACTORY_BINARY;
      return {
        hint: ctx.parse(value.hint),
        factory: ctx.parse(factory),
        stream: ctx.parse(createStream())
      };
    },
    async async(value, ctx, _data) {
      const factory = value.hint === "text" ? RAW_STREAM_FACTORY_TEXT : RAW_STREAM_FACTORY_BINARY;
      const encodedStream = value.hint === "text" ? toTextStream(value.stream) : toBinaryStream(value.stream);
      return {
        hint: await ctx.parse(value.hint),
        factory: await ctx.parse(factory),
        stream: await ctx.parse(encodedStream)
      };
    },
    stream(value, ctx, _data) {
      const factory = value.hint === "text" ? RAW_STREAM_FACTORY_TEXT : RAW_STREAM_FACTORY_BINARY;
      const encodedStream = value.hint === "text" ? toTextStream(value.stream) : toBinaryStream(value.stream);
      return {
        hint: ctx.parse(value.hint),
        factory: ctx.parse(factory),
        stream: ctx.parse(encodedStream)
      };
    }
  },
  serialize(node, ctx, _data) {
    return "(" + ctx.serialize(node.factory) + ")(" + ctx.serialize(node.stream) + ")";
  },
  deserialize(node, ctx, _data) {
    const stream = ctx.deserialize(node.stream);
    return ctx.deserialize(node.hint) === "text" ? RAW_STREAM_FACTORY_CONSTRUCTOR_TEXT(stream) : RAW_STREAM_FACTORY_CONSTRUCTOR_BINARY(stream);
  }
});
// @__NO_SIDE_EFFECTS__
function createRawStreamRPCPlugin(onRawStream) {
  let nextStreamId = 1;
  return /* @__PURE__ */ createPlugin({
    tag: "tss/RawStream",
    test(value) {
      return value instanceof RawStream;
    },
    parse: {
      async async(value, ctx, _data) {
        const streamId = nextStreamId++;
        onRawStream(streamId, value.stream);
        return { streamId: await ctx.parse(streamId) };
      },
      stream(value, ctx, _data) {
        const streamId = nextStreamId++;
        onRawStream(streamId, value.stream);
        return { streamId: ctx.parse(streamId) };
      }
    },
    serialize() {
      throw new Error("RawStreamRPCPlugin.serialize should not be called. RPC uses JSON serialization, not JS code generation.");
    },
    deserialize() {
      throw new Error("RawStreamRPCPlugin.deserialize should not be called. Use createRawStreamDeserializePlugin on client.");
    }
  });
}
const ShallowErrorPlugin = /* @__PURE__ */ createPlugin({
  tag: "$TSR/Error",
  test(value) {
    return value instanceof Error;
  },
  parse: {
    sync(value, ctx) {
      return { message: ctx.parse(value.message) };
    },
    async async(value, ctx) {
      return { message: await ctx.parse(value.message) };
    },
    stream(value, ctx) {
      return { message: ctx.parse(value.message) };
    }
  },
  serialize(node, ctx) {
    return "new Error(" + ctx.serialize(node.message) + ")";
  },
  deserialize(node, ctx) {
    return new Error(ctx.deserialize(node.message));
  }
});
const defaultSerovalPlugins = [
  ShallowErrorPlugin,
  RawStreamSSRPlugin,
  ReadableStreamPlugin
];
function toHeadersInstance(init) {
  if (init instanceof Headers) return init;
  else if (Array.isArray(init)) return new Headers(init);
  else if (typeof init === "object") return new Headers(init);
  else return null;
}
function mergeHeaders(...headers) {
  return headers.reduce((acc, header) => {
    const headersInstance = toHeadersInstance(header);
    if (!headersInstance) return acc;
    for (const [key, value] of headersInstance.entries()) if (key === "set-cookie") splitSetCookieString(value).forEach((cookie) => acc.append("set-cookie", cookie));
    else acc.set(key, value);
    return acc;
  }, new Headers());
}
var tsrScript_default = "self.$_TSR={h(){this.hydrated=!0,this.c()},e(){this.streamEnded=!0,this.c()},c(){this.hydrated&&this.streamEnded&&(delete self.$_TSR,delete self.$R.tsr)},p(e){this.initialized?e():this.buffer.push(e)},buffer:[]}";
const SCOPE_ID = "tsr";
const TSR_PREFIX = GLOBAL_TSR + ".router=";
const P_PREFIX = GLOBAL_TSR + ".p(()=>";
const P_SUFFIX = ")";
function dehydrateMatch(match) {
  const dehydratedMatch = {
    i: dehydrateSsrMatchId(match.id),
    u: match.updatedAt,
    s: match.status
  };
  for (const [key, shorthand] of [
    ["__beforeLoadContext", "b"],
    ["loaderData", "l"],
    ["error", "e"],
    ["ssr", "ssr"]
  ]) if (match[key] !== void 0) dehydratedMatch[shorthand] = match[key];
  if (match._notFound) dehydratedMatch.g = true;
  return dehydratedMatch;
}
const INITIAL_SCRIPTS = [getCrossReferenceHeader(SCOPE_ID), tsrScript_default];
var ScriptBuffer = class {
  constructor(injectScript) {
    this._scriptBarrierLifted = false;
    this._cleanedUp = false;
    this._microtaskVersion = 0;
    this._pendingMicrotaskVersion = 0;
    this.injectScript = injectScript;
    this._queue = INITIAL_SCRIPTS.slice();
  }
  enqueue(script) {
    if (this._cleanedUp) return;
    this._queue.push(script);
    if (this._scriptBarrierLifted) this.scheduleInjectBufferedScripts();
  }
  liftBarrier() {
    if (this._scriptBarrierLifted || this._cleanedUp) return;
    this._scriptBarrierLifted = true;
    if (this._queue.length > 0) this.scheduleInjectBufferedScripts();
  }
  scheduleInjectBufferedScripts() {
    if (this._pendingMicrotaskVersion !== 0) return;
    const pendingVersion = ++this._microtaskVersion;
    this._pendingMicrotaskVersion = pendingVersion;
    queueMicrotask(() => {
      if (this._pendingMicrotaskVersion !== pendingVersion) return;
      this._pendingMicrotaskVersion = 0;
      this.injectBufferedScripts();
    });
  }
  clearPendingMicrotask() {
    if (this._pendingMicrotaskVersion === 0) return;
    this._pendingMicrotaskVersion = 0;
    this._microtaskVersion++;
  }
  /**
  * Flushes any pending scripts synchronously.
  * Call this before signaling serialization finished to ensure all scripts are injected.
  *
  * IMPORTANT: Only injects if the barrier has been lifted. Before the barrier is lifted,
  * scripts should remain in the queue so takeBufferedScripts() can retrieve them
  */
  flush() {
    if (!this._scriptBarrierLifted) return;
    if (this._cleanedUp) return;
    this.clearPendingMicrotask();
    this.injectBufferedScripts();
  }
  takeAll() {
    return this.takeScripts(this._queue.length);
  }
  takeScripts(count) {
    if (count <= 0) return void 0;
    const bufferedScripts = this._queue.splice(0, count);
    if (bufferedScripts.length === 0) return;
    if (bufferedScripts.length === 1) return bufferedScripts[0] + ";document.currentScript.remove()";
    return bufferedScripts.join(";") + ";document.currentScript.remove()";
  }
  hasPending() {
    return this._queue.length > 0;
  }
  injectBufferedScripts() {
    if (this._cleanedUp) return;
    if (this._queue.length === 0) return;
    const scriptsToInject = this.takeAll();
    if (scriptsToInject) this.injectScript?.(scriptsToInject);
  }
  cleanup() {
    this._cleanedUp = true;
    this.clearPendingMicrotask();
    this._queue = [];
    this.injectScript = void 0;
  }
};
const MANIFEST_CACHE_SIZE = 100;
const manifestCaches = /* @__PURE__ */ new WeakMap();
function getManifestCache(manifest) {
  const cache = manifestCaches.get(manifest);
  if (cache) return cache;
  const newCache = createLRUCache(MANIFEST_CACHE_SIZE);
  manifestCaches.set(manifest, newCache);
  return newCache;
}
function getInlineCssForPreparedRoutes(manifest, preparedRoutes) {
  if (preparedRoutes.inlineCss !== void 0) return preparedRoutes.inlineCss;
  const styles = manifest.inlineCss?.styles;
  const hrefs = preparedRoutes.inlineCssHrefs;
  if (!styles || !hrefs?.length) return void 0;
  let css = "";
  for (const href of hrefs) css += styles[href];
  preparedRoutes.inlineCss = css;
  return css;
}
function getInlineCssAssetForPreparedRoutes(manifest, preparedRoutes) {
  const css = getInlineCssForPreparedRoutes(manifest, preparedRoutes);
  return css === void 0 ? void 0 : createInlineCssStyleAsset(css);
}
function getMatchedRoutesCacheKey(matches) {
  let cacheKey = "";
  for (let i = 0; i < matches.length; i++) cacheKey += (i === 0 ? "" : "\0") + matches[i].routeId;
  return cacheKey;
}
function getPreparedMatchedManifestRoutes(manifest, matches, cacheKey) {
  {
    const cached = getManifestCache(manifest).get(cacheKey);
    if (cached) return cached;
  }
  const preparedRoutes = prepareMatchedManifestRoutes(manifest, matches);
  getManifestCache(manifest).set(cacheKey, preparedRoutes);
  return preparedRoutes;
}
function prepareMatchedManifestRoutes(manifest, matches) {
  const inlineStyles = manifest.inlineCss?.styles;
  const routes = {};
  if (!inlineStyles) {
    for (const match of matches) {
      const route = manifest.routes[match.routeId];
      if (route) routes[match.routeId] = route;
    }
    return {
      routes,
      hasStrippedRoutes: false
    };
  }
  const inlineCssHrefs = [];
  const seenInlineCssHrefs = /* @__PURE__ */ new Set();
  let hasStrippedRoutes = false;
  for (const match of matches) {
    const routeId = match.routeId;
    const route = manifest.routes[routeId];
    if (!route) continue;
    const nextRoute = stripInlinedStylesheetAssetsFromRoute(inlineStyles, route, inlineCssHrefs, seenInlineCssHrefs);
    if (nextRoute !== route) hasStrippedRoutes = true;
    routes[routeId] = nextRoute;
  }
  return {
    routes,
    hasStrippedRoutes,
    ...inlineCssHrefs.length ? { inlineCssHrefs } : {}
  };
}
function stripInlinedStylesheetAssetsFromRoute(inlineStyles, route, inlineCssHrefs, seenInlineCssHrefs) {
  const css = route.css;
  if (!css) return route;
  if (css.length === 0) {
    const nextRoute2 = { ...route };
    delete nextRoute2.css;
    return nextRoute2;
  }
  let cssLinks;
  for (let i = 0; i < css.length; i++) {
    const link = css[i];
    const href = getStylesheetHref(link);
    if (inlineStyles[href] === void 0) {
      if (cssLinks) cssLinks.push(link);
      continue;
    }
    if (!seenInlineCssHrefs.has(href)) {
      seenInlineCssHrefs.add(href);
      inlineCssHrefs.push(href);
    }
    if (!cssLinks) cssLinks = css.slice(0, i);
  }
  if (!cssLinks) return route;
  if (cssLinks.length > 0) return {
    ...route,
    css: cssLinks
  };
  const nextRoute = { ...route };
  delete nextRoute.css;
  return nextRoute;
}
function hasRouteAssets(route) {
  return !!route.scripts?.length || !!route.css?.length;
}
function hasRequestAssets(assets) {
  return !!assets && (!!assets.preloads?.length || hasRouteAssets(assets));
}
function mergeRequestAssetsIntoRootRoute(rootRoute, requestAssets) {
  const preloads = requestAssets?.preloads?.length ? [...requestAssets.preloads, ...rootRoute?.preloads ?? []] : rootRoute?.preloads;
  const scripts = requestAssets?.scripts?.length ? [...requestAssets.scripts, ...rootRoute?.scripts ?? []] : rootRoute?.scripts;
  const cssLinks = requestAssets?.css?.length ? [...requestAssets.css, ...rootRoute?.css ?? []] : rootRoute?.css;
  return {
    ...rootRoute ?? {},
    ...preloads?.length ? { preloads } : {},
    ...scripts?.length ? { scripts } : {},
    ...cssLinks?.length ? { css: cssLinks } : {}
  };
}
function attachRouterServerSsrUtils({ router, manifest, getRequestAssets }) {
  router.ssr = { get manifest() {
    if (!manifest) return manifest;
    const requestAssets = getRequestAssets?.();
    const matches = _getRenderedMatches(router.stores.matches.get());
    const hasAssets = hasRequestAssets(requestAssets);
    if (!hasAssets && !manifest.inlineCss) return manifest;
    let inlineCssAsset;
    let routes = manifest.routes;
    if (manifest.inlineCss) {
      const preparedManifest = getPreparedMatchedManifestRoutes(manifest, matches, getMatchedRoutesCacheKey(matches));
      inlineCssAsset = getInlineCssAssetForPreparedRoutes(manifest, preparedManifest);
      if (preparedManifest.hasStrippedRoutes) routes = {
        ...manifest.routes,
        ...preparedManifest.routes
      };
    }
    if (!hasAssets) return {
      ...manifest.scriptFormat ? { scriptFormat: manifest.scriptFormat } : {},
      ...inlineCssAsset ? { inlineStyle: inlineCssAsset } : {},
      routes
    };
    const rootRoute = routes[rootRouteId];
    return {
      ...manifest.scriptFormat ? { scriptFormat: manifest.scriptFormat } : {},
      ...inlineCssAsset ? { inlineStyle: inlineCssAsset } : {},
      routes: {
        ...routes,
        [rootRouteId]: mergeRequestAssetsIntoRootRoute(rootRoute, requestAssets)
      }
    };
  } };
  let _dehydrated = false;
  let _serializationFinished = false;
  let streamFastPathReserved = false;
  const renderFinishedListeners = [];
  const injectedHtmlListeners = [];
  const serializationFinishedListeners = [];
  const cleanupListeners = [];
  let cleanupStarted = false;
  let injectedHtmlBuffer = "";
  const callListeners = (listeners, errorPrefix) => {
    const snapshot = listeners.slice();
    for (const l of snapshot) try {
      l();
    } catch (err) {
      console.error(`${errorPrefix}:`, err);
    }
  };
  const removeListener = (listeners, listener) => {
    const index = listeners.indexOf(listener);
    if (index >= 0) listeners.splice(index, 1);
  };
  const scriptBuffer = new ScriptBuffer((script) => {
    serverSsr.injectScript(script);
  });
  const serverSsr = {
    injectHtml: (html) => {
      if (!html || cleanupStarted) return;
      injectedHtmlBuffer += html;
      callListeners(injectedHtmlListeners, "SSR injected HTML listener error");
    },
    injectScript: (script) => {
      if (!script || cleanupStarted) return;
      const html = `<script${router.options.ssr?.nonce ? ` nonce='${router.options.ssr.nonce}'` : ""}>${script}<\/script>`;
      serverSsr.injectHtml(html);
    },
    dehydrate: async (opts) => {
      if (_dehydrated) {
        invariant();
      }
      let matchesToDehydrate = _getRenderedMatches(router.stores.matches.get());
      if (router.isShell()) matchesToDehydrate = matchesToDehydrate.slice(0, 1);
      const matches = matchesToDehydrate.map(dehydrateMatch);
      let manifestToDehydrate = void 0;
      if (manifest) {
        const cacheKey = getMatchedRoutesCacheKey(matchesToDehydrate);
        const preparedManifest = getPreparedMatchedManifestRoutes(manifest, matchesToDehydrate, cacheKey);
        manifestToDehydrate = {
          ...manifest.scriptFormat ? { scriptFormat: manifest.scriptFormat } : {},
          ...preparedManifest.inlineCssHrefs ? { inlineStyle: createInlineCssPlaceholderAsset() } : {},
          routes: preparedManifest.routes
        };
        const requestAssets = opts?.requestAssets;
        if (hasRequestAssets(requestAssets)) {
          const existingRoot = manifestToDehydrate.routes[rootRouteId];
          manifestToDehydrate.routes = {
            ...manifestToDehydrate.routes,
            [rootRouteId]: mergeRequestAssetsIntoRootRoute(existingRoot, requestAssets)
          };
        }
      }
      const dehydratedRouter = {
        manifest: manifestToDehydrate,
        matches
      };
      const dehydratedData = await router.options.dehydrate?.();
      if (cleanupStarted) return;
      if (dehydratedData) dehydratedRouter.dehydratedData = dehydratedData;
      _dehydrated = true;
      const trackPlugins = { didRun: false };
      const serializationAdapters = router.options.serializationAdapters;
      const plugins = serializationAdapters ? serializationAdapters.map((t) => /* @__PURE__ */ makeSsrSerovalPlugin(t, trackPlugins)).concat(defaultSerovalPlugins) : defaultSerovalPlugins;
      let serializationCompleteSignaled = false;
      const signalSerializationComplete = () => {
        if (serializationCompleteSignaled || cleanupStarted) return;
        serializationCompleteSignaled = true;
        _serializationFinished = true;
        const listeners = serializationFinishedListeners.slice();
        serializationFinishedListeners.length = 0;
        for (const l of listeners) try {
          l();
        } catch (err) {
          console.error("Serialization listener error:", err);
        }
      };
      const finishScriptSerialization = () => {
        if (serializationCompleteSignaled || cleanupStarted) return;
        scriptBuffer.enqueue(GLOBAL_TSR + ".e()");
        scriptBuffer.flush();
        signalSerializationComplete();
      };
      crossSerializeStream(dehydratedRouter, {
        refs: /* @__PURE__ */ new Map(),
        plugins,
        onSerialize: (data, initial) => {
          let serialized = initial ? TSR_PREFIX + data : data;
          if (trackPlugins.didRun) serialized = P_PREFIX + serialized + P_SUFFIX;
          scriptBuffer.enqueue(serialized);
        },
        onError: (err) => {
          console.error("Serialization error:", err);
          if (err && err.stack) console.error(err.stack);
          finishScriptSerialization();
        },
        scopeId: SCOPE_ID,
        onDone: () => {
          finishScriptSerialization();
        }
      });
    },
    isDehydrated() {
      return _dehydrated;
    },
    isSerializationFinished() {
      return _serializationFinished;
    },
    reserveStreamFastPath() {
      if (!cleanupStarted && _serializationFinished && !streamFastPathReserved && renderFinishedListeners.length === 0 && !injectedHtmlBuffer && !scriptBuffer.hasPending()) {
        streamFastPathReserved = true;
        return true;
      }
      return false;
    },
    onInjectedHtml: (listener) => {
      if (cleanupStarted) return () => {
      };
      injectedHtmlListeners.push(listener);
      return () => removeListener(injectedHtmlListeners, listener);
    },
    onRenderFinished: (listener) => {
      if (cleanupStarted || streamFastPathReserved) return;
      renderFinishedListeners.push(listener);
    },
    onSerializationFinished: (listener) => {
      if (cleanupStarted) return () => {
      };
      if (_serializationFinished && !cleanupStarted) {
        try {
          listener();
        } catch (err) {
          console.error("Serialization listener error:", err);
        }
        return () => {
        };
      }
      serializationFinishedListeners.push(listener);
      return () => removeListener(serializationFinishedListeners, listener);
    },
    onCleanup: (listener) => {
      if (cleanupStarted) return;
      cleanupListeners.push(listener);
    },
    setRenderFinished: () => {
      if (cleanupStarted) return;
      scriptBuffer.liftBarrier();
      const listeners = renderFinishedListeners.slice();
      renderFinishedListeners.length = 0;
      for (const l of listeners) try {
        l();
      } catch (err) {
        console.error("Error in render finished listener:", err);
      }
      if (_serializationFinished) scriptBuffer.flush();
    },
    takeBufferedScripts() {
      const scripts = scriptBuffer.takeAll();
      if (!scripts) return void 0;
      return {
        tag: "script",
        attrs: {
          nonce: router.options.ssr?.nonce,
          className: "$tsr",
          id: TSR_SCRIPT_BARRIER_ID
        },
        children: scripts
      };
    },
    liftScriptBarrier() {
      scriptBuffer.liftBarrier();
    },
    takeBufferedHtml() {
      if (!injectedHtmlBuffer) return;
      const buffered = injectedHtmlBuffer;
      injectedHtmlBuffer = "";
      return buffered;
    },
    cleanup() {
      if (cleanupStarted) return;
      cleanupStarted = true;
      const listeners = cleanupListeners.slice();
      cleanupListeners.length = 0;
      for (const l of listeners) try {
        l();
      } catch (err) {
        console.error("Error in SSR cleanup listener:", err);
      }
      renderFinishedListeners.length = 0;
      injectedHtmlListeners.length = 0;
      serializationFinishedListeners.length = 0;
      injectedHtmlBuffer = "";
      scriptBuffer.cleanup();
      router.serverSsr = void 0;
    }
  };
  router.serverSsr = serverSsr;
  for (const listener of router.serverSsrLifecycle?.onServerSsrAttach ?? []) try {
    listener(serverSsr);
  } catch (err) {
    console.error("SSR attach listener error:", err);
  }
}
function getOrigin(request) {
  try {
    return new URL(request.url).origin;
  } catch {
  }
  return "http://localhost";
}
function getNormalizedURL(url, base) {
  if (typeof url === "string") url = url.replace("\\", "%5C");
  const rawUrl = new URL(url, base);
  const { path: decodedPathname, handledProtocolRelativeURL } = decodePath(rawUrl.pathname);
  const searchParams = new URLSearchParams(rawUrl.search);
  const normalizedHref = decodedPathname + (searchParams.size > 0 ? "?" : "") + searchParams.toString() + rawUrl.hash;
  return {
    url: new URL(normalizedHref, rawUrl.origin),
    handledProtocolRelativeURL
  };
}
function isSsrResponse(value) {
  return typeof value === "object" && value !== null && "response" in value && "serverSsrCleanup" in value;
}
function normalizeSsrResponse(result) {
  return isSsrResponse(result) ? result : {
    response: result,
    serverSsrCleanup: "none"
  };
}
function disposeSsrResponse(response, reason) {
  if (response.serverSsrCleanup !== "stream") return Promise.resolve();
  try {
    return Promise.resolve(response.dispose(reason));
  } catch (error) {
    return Promise.reject(error);
  }
}
function disposeSsrResponseDetached(result, reason, onError = console.error) {
  const ssrResponse = normalizeSsrResponse(result);
  if (ssrResponse.serverSsrCleanup === "stream") {
    disposeSsrResponse(ssrResponse, reason).catch(onError);
    return;
  }
  if (ssrResponse.response.body) try {
    ssrResponse.response.body.cancel(reason).catch(onError);
  } catch (error) {
    onError(error);
  }
}
function createSsrStreamResponse(router, response) {
  if (!response.body) throw new Error("Invariant failed: SSR stream response requires a body");
  let disposed = false;
  return {
    response,
    serverSsrCleanup: "stream",
    async dispose(reason) {
      if (disposed) return;
      disposed = true;
      router.serverSsr?.cleanup();
      try {
        await response.body.cancel(reason);
      } catch {
      }
    }
  };
}
function bindSsrResponseToRequest(router, result, signal) {
  const ssrResponse = normalizeSsrResponse(result);
  if (ssrResponse.serverSsrCleanup !== "stream") {
    if (signal.aborted) disposeSsrResponseDetached(result, signal.reason);
    return ssrResponse;
  }
  const failed = (error) => {
    router?.serverSsr?.cleanup();
    console.error(error);
  };
  const abort = () => {
    disposeSsrResponseDetached(ssrResponse, signal.reason, failed);
  };
  if (signal.aborted) {
    abort();
    return ssrResponse;
  }
  signal.addEventListener("abort", abort, { once: true });
  router?.serverSsr?.onCleanup(() => {
    signal.removeEventListener("abort", abort);
  });
  return ssrResponse;
}
async function replaceSsrResponse(result, response, reason) {
  await disposeSsrResponse(normalizeSsrResponse(result), reason);
  return {
    response,
    serverSsrCleanup: "none"
  };
}
async function stripSsrResponseBody(result, reason) {
  const ssrResponse = normalizeSsrResponse(result);
  await disposeSsrResponse(ssrResponse, reason);
  return {
    response: new Response(null, ssrResponse.response),
    serverSsrCleanup: "none"
  };
}
function defineHandlerCallback(handler) {
  return handler;
}
const requestWaiters = /* @__PURE__ */ new WeakMap();
function removeRequestWaiter(waiters, index, reject) {
  if (waiters[index] !== reject) return;
  if (index !== waiters.length - 1) {
    waiters[index] = void 0;
    return;
  }
  waiters.pop();
  while (waiters.length && waiters[waiters.length - 1] === void 0) waiters.pop();
}
function waitForRequest(value, signal, onLate) {
  const promise = Promise.resolve(value);
  if (signal.aborted) {
    promise.then(onLate, () => {
    });
    return Promise.reject(signal.reason);
  }
  return new Promise((resolve, reject) => {
    let waiters = requestWaiters.get(signal);
    let index;
    if (waiters) index = waiters.push(reject) - 1;
    else {
      const newWaiters = [reject];
      waiters = newWaiters;
      index = 0;
      requestWaiters.set(signal, newWaiters);
      signal.addEventListener("abort", () => {
        requestWaiters.delete(signal);
        for (const rejectWaiter of newWaiters) rejectWaiter?.(signal.reason);
        newWaiters.length = 0;
      }, { once: true });
    }
    promise.then((result) => {
      removeRequestWaiter(waiters, index, reject);
      if (signal.aborted) onLate?.(result);
      else resolve(result);
    }, (error) => {
      removeRequestWaiter(waiters, index, reject);
      reject(error);
    });
  });
}
function transformReadableStreamWithRouter(router, routerStream, opts) {
  return transformStreamWithRouter(router, routerStream, opts);
}
function transformPipeableStreamWithRouter(router, routerStream, opts) {
  return Readable.fromWeb(transformStreamWithRouter(router, Readable.toWeb(routerStream), opts));
}
const MIN_CLOSING_TAG_LENGTH = 4;
const DEFAULT_SERIALIZATION_TIMEOUT_MS = 6e4;
const DEFAULT_LIFETIME_TIMEOUT_MS = DEFAULT_SERIALIZATION_TIMEOUT_MS * 2;
const MAX_LEFTOVER_CHARS = 2048;
const MAX_TAIL_CHARS = 64 * 1024;
const MAX_ROUTER_HTML_CHARS = 16 * 1024 * 1024;
const MAX_PENDING_WRITE_CHARS = 16 * 1024 * 1024;
const MergeState = {
  ReadingBody: 0,
  HoldingTail: 1,
  AppDone: 2,
  Draining: 3,
  Done: 4
};
const textEncoder = new TextEncoder();
const noop = () => {
};
const resolvedPromise = Promise.resolve();
function findHtmlBoundary(str) {
  let lastClosingTagEnd = -1;
  let searchFrom = str.length - MIN_CLOSING_TAG_LENGTH;
  while (searchFrom >= 0) {
    const openSlash = str.lastIndexOf("</", searchFrom);
    if (openSlash === -1) break;
    if ((str.charCodeAt(openSlash + 2) | 32) === 98 && (str.charCodeAt(openSlash + 3) | 32) === 111 && (str.charCodeAt(openSlash + 4) | 32) === 100 && (str.charCodeAt(openSlash + 5) | 32) === 121 && str.charCodeAt(openSlash + 6) === 62) return -openSlash - 2;
    if (lastClosingTagEnd === -1) {
      let i = openSlash + 2;
      const startCode = str.charCodeAt(i);
      if (startCode >= 97 && startCode <= 122 || startCode >= 65 && startCode <= 90) {
        i++;
        while (i < str.length) {
          const code = str.charCodeAt(i);
          if (code >= 97 && code <= 122 || code >= 65 && code <= 90 || code >= 48 && code <= 57 || code === 95 || code === 58 || code === 46 || code === 45) i++;
          else break;
        }
        if (str.charCodeAt(i) === 62) lastClosingTagEnd = i + 1;
      }
    }
    searchFrom = openSlash - 1;
  }
  return lastClosingTagEnd;
}
function safeReleaseReader(reader) {
  try {
    reader.releaseLock();
    return true;
  } catch {
    return false;
  }
}
function safeCancelReader(reader, reason) {
  let cancelPromise;
  try {
    cancelPromise = reader.cancel(reason);
  } catch {
  }
  if (!safeReleaseReader(reader) && cancelPromise) return cancelPromise.then(noop, noop).then(() => {
    safeReleaseReader(reader);
  });
  return cancelPromise ? cancelPromise.then(noop, noop) : resolvedPromise;
}
function createReaderState(appStream) {
  const reader = appStream.getReader();
  let released = false;
  return {
    reader,
    cancel: (reason) => {
      if (released) return resolvedPromise;
      released = true;
      return safeCancelReader(reader, reason);
    },
    release: () => {
      if (released) return;
      released = true;
      safeReleaseReader(reader);
    }
  };
}
function createAbortNotifier(opts) {
  let abortNotified = false;
  return (reason) => {
    if (abortNotified) return;
    abortNotified = true;
    try {
      opts?.onAbort?.(reason);
    } catch {
    }
  };
}
function listenToAbort(signal, onAbort) {
  if (!signal) return;
  if (signal.aborted) {
    onAbort(signal.reason);
    return;
  }
  const listener = () => onAbort(signal.reason);
  signal.addEventListener("abort", listener, { once: true });
  return () => signal.removeEventListener("abort", listener);
}
function transformStreamWithRouter(router, appStream, opts) {
  const serverSsr = router.serverSsr;
  if (!serverSsr) throw new Error("Invariant failed: router.serverSsr is required");
  if (serverSsr.reserveStreamFastPath()) return makeFastPathStream(appStream, opts, serverSsr);
  return makeMainStream(serverSsr, appStream, opts);
}
function makeFastPathStream(appStream, opts, serverSsr) {
  let cleanedUp = false;
  let controller;
  let state = MergeState.ReadingBody;
  let lifetimeTimeoutHandle;
  let stopListeningToAbort;
  let stopListeningToInjectedHtml;
  const readerState = createReaderState(appStream);
  const notifyAbort = createAbortNotifier(opts);
  const isDone = () => state === MergeState.Done;
  let renderFinished = false;
  const finishSsrRendering = () => {
    if (!serverSsr || renderFinished) return true;
    renderFinished = true;
    try {
      serverSsr.setRenderFinished();
      return true;
    } catch (error) {
      safeError(error);
      cleanup(error);
      return false;
    }
  };
  const cleanup = (reason, cancelReader = true) => {
    if (cleanedUp) return resolvedPromise;
    cleanedUp = true;
    if (lifetimeTimeoutHandle !== void 0) {
      clearTimeout(lifetimeTimeoutHandle);
      lifetimeTimeoutHandle = void 0;
    }
    stopListeningToAbort?.();
    stopListeningToAbort = void 0;
    try {
      stopListeningToInjectedHtml?.();
    } catch {
    }
    stopListeningToInjectedHtml = void 0;
    if (cancelReader) notifyAbort(reason);
    const readerDone = cancelReader ? readerState.cancel(reason) : (readerState.release(), resolvedPromise);
    if (serverSsr) try {
      serverSsr.cleanup();
    } catch (error) {
      console.error("Error in SSR cleanup:", error);
    }
    return readerDone;
  };
  const safeClose = () => {
    if (isDone()) return;
    state = MergeState.Done;
    try {
      controller?.close();
    } catch {
    }
  };
  const safeError = (error) => {
    if (isDone()) return;
    state = MergeState.Done;
    try {
      controller?.error(error);
    } catch {
    }
  };
  if (serverSsr) stopListeningToInjectedHtml = serverSsr.onInjectedHtml(() => {
    const err = /* @__PURE__ */ new Error("SSR router HTML injected during fast path");
    safeError(err);
    cleanup(err);
  });
  const lifetimeMs = opts?.lifetimeMs ?? DEFAULT_LIFETIME_TIMEOUT_MS;
  lifetimeTimeoutHandle = setTimeout(() => {
    if (!cleanedUp && !isDone()) {
      const err = /* @__PURE__ */ new Error("Stream lifetime exceeded");
      console.warn(`SSR stream transform exceeded maximum lifetime (${lifetimeMs}ms), forcing cleanup`);
      safeError(err);
      cleanup(err);
    }
  }, lifetimeMs);
  const stream = new ReadableStream$1({
    start(c) {
      controller = c;
    },
    async pull(c) {
      if (cleanedUp || isDone()) return;
      try {
        const { done, value } = await readerState.reader.read();
        if (!done) {
          if (!cleanedUp && !isDone()) c.enqueue(value);
          return;
        }
        if (cleanedUp || isDone()) return;
        if (!finishSsrRendering()) return;
        safeClose();
        return cleanup(void 0, false);
      } catch (error) {
        if (cleanedUp) return;
        console.error("Error reading appStream:", error);
        if (state < MergeState.AppDone) try {
          serverSsr?.setRenderFinished();
        } catch {
        }
        safeError(error);
        return cleanup(error);
      } finally {
        if (cleanedUp || isDone()) readerState.release();
      }
    },
    cancel(reason) {
      state = MergeState.Done;
      return cleanup(reason);
    }
  });
  stopListeningToAbort = listenToAbort(opts?.signal, (reason) => {
    safeError(reason);
    cleanup(reason);
  });
  return stream;
}
function makeMainStream(serverSsr, appStream, opts) {
  let stopListeningToInjectedHtml;
  let stopListeningToSerializationFinished;
  let serializationTimeoutHandle;
  let lifetimeTimeoutHandle;
  let stopListeningToAbort;
  let cleanedUp = false;
  let controller;
  let closeWhenDrained = false;
  let state = MergeState.ReadingBody;
  const readerState = createReaderState(appStream);
  const notifyAbort = createAbortNotifier(opts);
  const pendingWrites = [];
  let pendingWriteHead = 0;
  let pendingWriteChars = 0;
  function clearPending() {
    pendingWrites.length = 0;
    pendingWriteHead = 0;
    pendingWriteChars = 0;
  }
  let drainResolve = null;
  const waitForDrain = () => new Promise((r) => {
    drainResolve = r;
  });
  const signalDrain = () => {
    if (drainResolve) {
      const r = drainResolve;
      drainResolve = null;
      r();
    }
  };
  const isDone = () => state === MergeState.Done;
  function drainPending() {
    if (!controller || isDone()) return;
    while (pendingWriteHead < pendingWrites.length) {
      const ds = controller.desiredSize;
      if (ds !== null && ds <= 0) return;
      const next = pendingWrites[pendingWriteHead];
      pendingWrites[pendingWriteHead] = "";
      pendingWriteHead++;
      pendingWriteChars -= next.length;
      try {
        controller.enqueue(textEncoder.encode(next));
      } catch (error) {
        safeError(error);
        cleanup(error);
        return;
      }
    }
    if (pendingWriteHead >= pendingWrites.length) {
      pendingWrites.length = 0;
      pendingWriteHead = 0;
    }
    if (closeWhenDrained && pendingWriteHead >= pendingWrites.length) {
      closeWhenDrained = false;
      safeClose();
      cleanup(void 0, false);
    }
  }
  function writeChunk(chunk) {
    if (cleanedUp || isDone()) return;
    if (!chunk.length) return;
    if (pendingWriteChars + chunk.length > MAX_PENDING_WRITE_CHARS) {
      const err = /* @__PURE__ */ new Error("SSR stream pending output exceeded maximum buffer");
      safeError(err);
      cleanup(err);
      return;
    }
    pendingWrites.push(chunk);
    pendingWriteChars += chunk.length;
    drainPending();
  }
  function safeClose() {
    if (isDone()) return;
    state = MergeState.Done;
    try {
      controller?.close();
    } catch {
    }
  }
  function safeError(error) {
    if (isDone()) return;
    state = MergeState.Done;
    try {
      controller?.error(error);
    } catch {
    }
  }
  function cleanup(reason, cancelReader = true) {
    if (cleanedUp) return resolvedPromise;
    cleanedUp = true;
    try {
      stopListeningToInjectedHtml?.();
      stopListeningToSerializationFinished?.();
    } catch {
    }
    stopListeningToInjectedHtml = void 0;
    stopListeningToSerializationFinished = void 0;
    stopListeningToAbort?.();
    stopListeningToAbort = void 0;
    if (serializationTimeoutHandle !== void 0) {
      clearTimeout(serializationTimeoutHandle);
      serializationTimeoutHandle = void 0;
    }
    if (lifetimeTimeoutHandle !== void 0) {
      clearTimeout(lifetimeTimeoutHandle);
      lifetimeTimeoutHandle = void 0;
    }
    clearPendingRouterHtml();
    leftover = "";
    pendingTail = "";
    clearPending();
    if (cancelReader) notifyAbort(reason);
    const readerDone = cancelReader ? readerState.cancel(reason) : (readerState.release(), resolvedPromise);
    signalDrain();
    try {
      serverSsr.cleanup();
    } catch (error) {
      console.error("Error in SSR cleanup:", error);
    }
    return readerDone;
  }
  const textDecoder = new TextDecoder();
  const pendingRouterHtml = [];
  let pendingRouterHtmlChars = 0;
  let leftover = "";
  let pendingTail = "";
  let streamBarrierLifted = false;
  let streamBarrierMarkerSeen = false;
  let serializationFinished = false;
  function noteBarrierMarker(chunk) {
    if (streamBarrierMarkerSeen) return;
    if (chunk.includes("$tsr-stream-barrier")) streamBarrierMarkerSeen = true;
  }
  function liftBarrierAfterBoundary() {
    if (streamBarrierLifted) return;
    if (!streamBarrierMarkerSeen) return;
    streamBarrierLifted = true;
    serverSsr.liftScriptBarrier();
  }
  const stream = new ReadableStream$1({
    start(c) {
      controller = c;
      drainPending();
    },
    pull() {
      drainPending();
      signalDrain();
    },
    cancel(reason) {
      state = MergeState.Done;
      return cleanup(reason);
    }
  });
  function drainRouterHtml() {
    if (cleanedUp || isDone()) return;
    let html;
    try {
      html = serverSsr.takeBufferedHtml();
    } catch (error) {
      safeError(error);
      cleanup(error);
      return;
    }
    if (!html) return;
    if (state >= MergeState.Draining) {
      const err = /* @__PURE__ */ new Error("SSR router HTML injected after stream finalization");
      safeError(err);
      cleanup(err);
      return;
    }
    if (state === MergeState.HoldingTail) {
      flushPendingRouterHtml();
      writeChunk(html);
    } else {
      if (pendingRouterHtmlChars + html.length > MAX_ROUTER_HTML_CHARS) {
        const err = /* @__PURE__ */ new Error("SSR router HTML exceeded maximum buffer");
        safeError(err);
        cleanup(err);
        return;
      }
      pendingRouterHtml.push(html);
      pendingRouterHtmlChars += html.length;
    }
  }
  function flushPendingRouterHtml() {
    if (!pendingRouterHtml.length) return;
    for (const html of pendingRouterHtml) writeChunk(html);
    clearPendingRouterHtml();
  }
  function clearPendingRouterHtml() {
    pendingRouterHtml.length = 0;
    pendingRouterHtmlChars = 0;
  }
  function appendTail(chunk) {
    pendingTail += chunk;
    if (pendingTail.length > MAX_TAIL_CHARS) throw new Error("SSR stream tail exceeded maximum buffer");
  }
  function waitForBackpressure() {
    return !!(controller && controller.desiredSize !== null && controller.desiredSize <= 0);
  }
  function startSerializationTimeout() {
    if (cleanedUp || isDone()) return;
    if (serializationTimeoutHandle !== void 0) return;
    const timeoutMs2 = opts?.timeoutMs ?? DEFAULT_SERIALIZATION_TIMEOUT_MS;
    serializationTimeoutHandle = setTimeout(() => {
      if (!cleanedUp && !isDone()) {
        const err = /* @__PURE__ */ new Error("Serialization timeout after app render finished");
        console.error("Serialization timeout after app render finished");
        safeError(err);
        cleanup(err);
      }
    }, timeoutMs2);
  }
  function tryFinish() {
    if (state !== MergeState.AppDone || !serializationFinished) return;
    if (cleanedUp || isDone()) return;
    if (serializationTimeoutHandle !== void 0) {
      clearTimeout(serializationTimeoutHandle);
      serializationTimeoutHandle = void 0;
    }
    drainRouterHtml();
    if (cleanedUp || isDone()) return;
    const decoderRemainder = textDecoder.decode();
    if (leftover) writeChunk(leftover);
    if (cleanedUp || isDone()) return;
    if (decoderRemainder) writeChunk(decoderRemainder);
    if (cleanedUp || isDone()) return;
    flushPendingRouterHtml();
    if (cleanedUp || isDone()) return;
    if (pendingTail) writeChunk(pendingTail);
    if (cleanedUp || isDone()) return;
    leftover = "";
    pendingTail = "";
    state = MergeState.Draining;
    closeWhenDrained = true;
    drainPending();
  }
  function finishAppRendering() {
    if (state >= MergeState.AppDone) return;
    state = MergeState.AppDone;
    try {
      serverSsr.setRenderFinished();
    } catch (error) {
      safeError(error);
      cleanup(error);
      return;
    }
    drainRouterHtml();
    if (cleanedUp || isDone()) return;
    serializationFinished = serializationFinished || serverSsr.isSerializationFinished();
    if (serializationFinished) tryFinish();
    else startSerializationTimeout();
  }
  const timeoutMs = opts?.timeoutMs ?? DEFAULT_SERIALIZATION_TIMEOUT_MS;
  const lifetimeMs = opts?.lifetimeMs ?? timeoutMs * 2;
  lifetimeTimeoutHandle = setTimeout(() => {
    if (!cleanedUp && !isDone()) {
      const err = /* @__PURE__ */ new Error("Stream lifetime exceeded");
      console.warn(`SSR stream transform exceeded maximum lifetime (${lifetimeMs}ms), forcing cleanup`);
      safeError(err);
      cleanup(err);
    }
  }, lifetimeMs);
  stopListeningToInjectedHtml = serverSsr.onInjectedHtml(() => {
    drainRouterHtml();
  });
  stopListeningToSerializationFinished = serverSsr.onSerializationFinished(() => {
    serializationFinished = true;
    drainRouterHtml();
    tryFinish();
  });
  drainRouterHtml();
  if (cleanedUp || isDone()) return stream;
  serializationFinished = serializationFinished || serverSsr.isSerializationFinished();
  if (serializationFinished) {
    drainRouterHtml();
    if (cleanedUp || isDone()) return stream;
  }
  stopListeningToAbort = listenToAbort(opts?.signal, (reason) => {
    safeError(reason);
    cleanup(reason);
  });
  if (cleanedUp || isDone()) return stream;
  (async () => {
    try {
      while (true) {
        if (waitForBackpressure()) {
          await waitForDrain();
          if (cleanedUp || isDone()) return;
        }
        const { done, value } = await readerState.reader.read();
        if (done) break;
        if (cleanedUp || isDone()) return;
        const text = typeof value === "string" ? value : textDecoder.decode(value, { stream: true });
        const chunkString = leftover ? leftover + text : text;
        if (state >= MergeState.HoldingTail) {
          appendTail(chunkString);
          leftover = "";
          continue;
        }
        const boundary = findHtmlBoundary(chunkString);
        if (boundary < -1) {
          const bodyEndIndex = -boundary - 2;
          state = MergeState.HoldingTail;
          appendTail(chunkString.slice(bodyEndIndex));
          const bodyChunk = chunkString.slice(0, bodyEndIndex);
          writeChunk(bodyChunk);
          if (cleanedUp || isDone()) return;
          noteBarrierMarker(bodyChunk);
          liftBarrierAfterBoundary();
          if (cleanedUp || isDone()) return;
          flushPendingRouterHtml();
          leftover = "";
          continue;
        }
        const lastClosingTagEnd = boundary;
        if (lastClosingTagEnd > 0) {
          const safeChunk = chunkString.slice(0, lastClosingTagEnd);
          writeChunk(safeChunk);
          if (cleanedUp || isDone()) return;
          noteBarrierMarker(safeChunk);
          liftBarrierAfterBoundary();
          if (cleanedUp || isDone()) return;
          flushPendingRouterHtml();
          leftover = chunkString.slice(lastClosingTagEnd);
          if (leftover.length > MAX_LEFTOVER_CHARS) {
            noteBarrierMarker(leftover);
            writeChunk(leftover.slice(0, leftover.length - MAX_LEFTOVER_CHARS));
            leftover = leftover.slice(-2048);
          }
        } else {
          const combined = chunkString;
          if (combined.length > MAX_LEFTOVER_CHARS) {
            noteBarrierMarker(combined);
            const flushUpto = combined.length - MAX_LEFTOVER_CHARS;
            writeChunk(combined.slice(0, flushUpto));
            leftover = combined.slice(flushUpto);
          } else leftover = combined;
        }
      }
      if (cleanedUp || isDone()) return;
      finishAppRendering();
    } catch (error) {
      if (cleanedUp) return;
      console.error("Error reading appStream:", error);
      if (state < MergeState.AppDone) try {
        serverSsr.setRenderFinished();
      } catch {
      }
      safeError(error);
      cleanup(error);
    } finally {
      readerState.release();
    }
  })().catch((error) => {
    if (cleanedUp) return;
    console.error("Error in stream transform:", error);
    safeError(error);
    cleanup(error);
  });
  return stream;
}
var scroll_restoration_inline_default = 'function(a,f){let l;try{l=JSON.parse(sessionStorage.getItem(a)||"{}")}catch{return}const n=l?.[f||history.state?.__TSR_key];let c=!1;for(const t in n){const e=n[t],o=e?.scrollX,s=e?.scrollY;if(Number.isFinite(o)&&Number.isFinite(s)){if(t==="window")scrollTo(o,s),c=!0;else if(t)try{const r=document.querySelector(t);r&&(r.scrollLeft=o,r.scrollTop=s)}catch{}}}if(c)return;const i=location.hash.slice(1);if(i){const t=history.state?.__hashScrollIntoViewOptions??!0;if(t){const e=document.getElementById(i);e&&e.scrollIntoView(t)}return}scrollTo(0,0)}';
const defaultInlineScrollRestorationScript = `(${scroll_restoration_inline_default})(${escapeHtml(JSON.stringify(storageKey))})`;
function getScrollRestorationScript(key) {
  if (key === void 0) return defaultInlineScrollRestorationScript;
  return `(${scroll_restoration_inline_default})(${escapeHtml(JSON.stringify(storageKey))},${escapeHtml(JSON.stringify(key))})`;
}
function getScrollRestorationScriptForRouter(router) {
  if (typeof router.options.scrollRestoration === "function" && !router.options.scrollRestoration({ location: router.latestLocation })) return null;
  const getKey = router.options.getScrollRestorationKey;
  if (!getKey) return defaultInlineScrollRestorationScript;
  const location = router.latestLocation;
  const userKey = getKey(location);
  if (userKey === defaultGetScrollRestorationKey(location)) return defaultInlineScrollRestorationScript;
  return getScrollRestorationScript(userKey);
}
export {
  waitForRequest as A,
  BaseRootRoute as B,
  bindSsrResponseToRequest as C,
  normalizeSsrResponse as D,
  attachRouterServerSsrUtils as E,
  _getRenderedMatches as F,
  createSerializationAdapter as G,
  createRawStreamRPCPlugin as H,
  isRedirect as I,
  isResolvedRedirect as J,
  replaceSsrResponse as K,
  mergeHeaders as L,
  isSsrResponse as M,
  disposeSsrResponseDetached as N,
  executeRewriteInput as O,
  stripSsrResponseBody as P,
  defaultSerovalPlugins as Q,
  RouterCore as R,
  makeSerovalPlugin as S,
  getStylesheetHref as T,
  redirect as U,
  _getAssetMatches as _,
  isDangerousProtocol as a,
  BaseRoute as b,
  isModuleNotFoundError as c,
  deepEqual as d,
  exactPathTest as e,
  functionalUpdate as f,
  isNotFound as g,
  hasKeys as h,
  invariant as i,
  getScrollRestorationScriptForRouter as j,
  rootRouteId as k,
  createNonReactiveReadonlyStore as l,
  createNonReactiveMutableStore as m,
  escapeHtml as n,
  getAssetCrossOrigin as o,
  getScriptPreloadAttrs as p,
  appendUniqueUserTags as q,
  removeTrailingSlash as r,
  resolveManifestCssLink as s,
  transformReadableStreamWithRouter as t,
  createSsrStreamResponse as u,
  transformPipeableStreamWithRouter as v,
  defineHandlerCallback as w,
  resolveManifestAssetLink as x,
  getNormalizedURL as y,
  getOrigin as z
};
