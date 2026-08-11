import { G as GatewayAuthenticationError, g as gateway, a as GatewayError } from "./ai-sdk__gateway.mjs";
import { i as withUserAgentSuffix, x as getErrorMessage, s as safeValidateTypes, y as asSchema, A as createIdGenerator, B as safeParseJSON, C as retryWithExponentialBackoff, D as executeTool, E as isUrlSupported, q as convertUint8ArrayToBase64, f as convertBase64ToUint8Array, F as getRuntimeEnvironmentUserAgent, G as fetchWithValidatedRedirects, H as cancelResponseBody, I as DownloadError, J as readResponseWithSizeLimit, K as DEFAULT_MAX_DOWNLOAD_SIZE, r as resolve } from "./ai-sdk__provider-utils.mjs";
import { d as InvalidPromptError, g as getErrorMessage$1, A as AISDKError, a as APICallError, T as TypeValidationError } from "./ai-sdk__provider.mjs";
import { s as srcExports } from "./opentelemetry__api.mjs";
import { d as array$1, u as union, a as string, x as _instanceof, y as custom, z as lazy, r as record, o as object$1, e as literal, c as boolean, g as unknown, f as discriminatedUnion, A as _null, n as number } from "./zod.mjs";
var __defProp = Object.defineProperty;
var __export = (target, all) => {
  for (var name22 in all)
    __defProp(target, name22, { get: all[name22], enumerable: true });
};
var name = "AI_InvalidArgumentError";
var marker = `vercel.ai.error.${name}`;
var symbol = Symbol.for(marker);
var _a;
var InvalidArgumentError = class extends AISDKError {
  constructor({
    parameter,
    value,
    message
  }) {
    super({
      name,
      message: `Invalid argument for parameter ${parameter}: ${message}`
    });
    this[_a] = true;
    this.parameter = parameter;
    this.value = value;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker);
  }
};
_a = symbol;
var name3 = "AI_InvalidToolApprovalError";
var marker3 = `vercel.ai.error.${name3}`;
var symbol3 = Symbol.for(marker3);
var _a3;
var InvalidToolApprovalError = class extends AISDKError {
  constructor({ approvalId }) {
    super({
      name: name3,
      message: `Tool approval response references unknown approvalId: "${approvalId}". No matching tool-approval-request found in message history.`
    });
    this[_a3] = true;
    this.approvalId = approvalId;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker3);
  }
};
_a3 = symbol3;
var name4 = "AI_InvalidToolApprovalSignatureError";
var marker4 = `vercel.ai.error.${name4}`;
var symbol4 = Symbol.for(marker4);
var _a4;
var InvalidToolApprovalSignatureError = class extends AISDKError {
  constructor({
    approvalId,
    toolCallId,
    reason
  }) {
    super({
      name: name4,
      message: `Tool approval signature verification failed for approval "${approvalId}" (tool call "${toolCallId}"): ${reason}`
    });
    this[_a4] = true;
    this.approvalId = approvalId;
    this.toolCallId = toolCallId;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker4);
  }
};
_a4 = symbol4;
var name5 = "AI_InvalidToolInputError";
var marker5 = `vercel.ai.error.${name5}`;
var symbol5 = Symbol.for(marker5);
var _a5;
var InvalidToolInputError = class extends AISDKError {
  constructor({
    toolInput,
    toolName,
    cause,
    message = `Invalid input for tool ${toolName}: ${getErrorMessage$1(cause)}`
  }) {
    super({ name: name5, message, cause });
    this[_a5] = true;
    this.toolInput = toolInput;
    this.toolName = toolName;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker5);
  }
};
_a5 = symbol5;
var name6 = "AI_ToolCallNotFoundForApprovalError";
var marker6 = `vercel.ai.error.${name6}`;
var symbol6 = Symbol.for(marker6);
var _a6;
var ToolCallNotFoundForApprovalError = class extends AISDKError {
  constructor({
    toolCallId,
    approvalId
  }) {
    super({
      name: name6,
      message: `Tool call "${toolCallId}" not found for approval request "${approvalId}".`
    });
    this[_a6] = true;
    this.toolCallId = toolCallId;
    this.approvalId = approvalId;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker6);
  }
};
_a6 = symbol6;
var name7 = "AI_MissingToolResultsError";
var marker7 = `vercel.ai.error.${name7}`;
var symbol7 = Symbol.for(marker7);
var _a7;
var MissingToolResultsError = class extends AISDKError {
  constructor({ toolCallIds }) {
    super({
      name: name7,
      message: `Tool result${toolCallIds.length > 1 ? "s are" : " is"} missing for tool call${toolCallIds.length > 1 ? "s" : ""} ${toolCallIds.join(
        ", "
      )}.`
    });
    this[_a7] = true;
    this.toolCallIds = toolCallIds;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker7);
  }
};
_a7 = symbol7;
var name9 = "AI_NoObjectGeneratedError";
var marker9 = `vercel.ai.error.${name9}`;
var symbol9 = Symbol.for(marker9);
var _a9;
var NoObjectGeneratedError = class extends AISDKError {
  constructor({
    message = "No object generated.",
    cause,
    text: text2,
    response,
    usage,
    finishReason
  }) {
    super({ name: name9, message, cause });
    this[_a9] = true;
    this.text = text2;
    this.response = response;
    this.usage = usage;
    this.finishReason = finishReason;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker9);
  }
};
_a9 = symbol9;
var name10 = "AI_NoOutputGeneratedError";
var marker10 = `vercel.ai.error.${name10}`;
var symbol10 = Symbol.for(marker10);
var _a10;
var NoOutputGeneratedError = class extends AISDKError {
  // used in isInstance
  constructor({
    message = "No output generated.",
    cause
  } = {}) {
    super({ name: name10, message, cause });
    this[_a10] = true;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker10);
  }
};
_a10 = symbol10;
var name14 = "AI_NoSuchToolError";
var marker14 = `vercel.ai.error.${name14}`;
var symbol14 = Symbol.for(marker14);
var _a14;
var NoSuchToolError = class extends AISDKError {
  constructor({
    toolName,
    availableTools = void 0,
    message = `Model tried to call unavailable tool '${toolName}'. ${availableTools === void 0 ? "No tools are available." : `Available tools: ${availableTools.join(", ")}.`}`
  }) {
    super({ name: name14, message });
    this[_a14] = true;
    this.toolName = toolName;
    this.availableTools = availableTools;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker14);
  }
};
_a14 = symbol14;
var name15 = "AI_ToolCallRepairError";
var marker15 = `vercel.ai.error.${name15}`;
var symbol15 = Symbol.for(marker15);
var _a15;
var ToolCallRepairError = class extends AISDKError {
  constructor({
    cause,
    originalError,
    message = `Error repairing tool call: ${getErrorMessage$1(cause)}`
  }) {
    super({ name: name15, message, cause });
    this[_a15] = true;
    this.originalError = originalError;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker15);
  }
};
_a15 = symbol15;
var UnsupportedModelVersionError = class extends AISDKError {
  constructor(options) {
    super({
      name: "AI_UnsupportedModelVersionError",
      message: `Unsupported model version ${options.version} for provider "${options.provider}" and model "${options.modelId}". AI SDK 5 only supports models that implement specification version "v2".`
    });
    this.version = options.version;
    this.provider = options.provider;
    this.modelId = options.modelId;
  }
};
var name18 = "AI_InvalidMessageRoleError";
var marker18 = `vercel.ai.error.${name18}`;
var symbol18 = Symbol.for(marker18);
var _a18;
var InvalidMessageRoleError = class extends AISDKError {
  constructor({
    role,
    message = `Invalid message role: '${role}'. Must be one of: "system", "user", "assistant", "tool".`
  }) {
    super({ name: name18, message });
    this[_a18] = true;
    this.role = role;
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker18);
  }
};
_a18 = symbol18;
var name20 = "AI_RetryError";
var marker20 = `vercel.ai.error.${name20}`;
var symbol20 = Symbol.for(marker20);
var _a20;
var RetryError = class extends AISDKError {
  constructor({
    message,
    reason,
    errors
  }) {
    super({ name: name20, message });
    this[_a20] = true;
    this.reason = reason;
    this.errors = errors;
    this.lastError = errors[errors.length - 1];
  }
  static isInstance(error) {
    return AISDKError.hasMarker(error, marker20);
  }
};
_a20 = symbol20;
function asArray(value) {
  return value === void 0 ? [] : Array.isArray(value) ? value : [value];
}
async function notify(options) {
  for (const callback of asArray(options.callbacks)) {
    if (callback == null)
      continue;
    try {
      await callback(options.event);
    } catch (_ignored) {
    }
  }
}
function formatWarning({
  warning,
  provider,
  model
}) {
  const prefix = `AI SDK Warning (${provider} / ${model}):`;
  switch (warning.type) {
    case "unsupported": {
      let message = `${prefix} The feature "${warning.feature}" is not supported.`;
      if (warning.details) {
        message += ` ${warning.details}`;
      }
      return message;
    }
    case "compatibility": {
      let message = `${prefix} The feature "${warning.feature}" is used in a compatibility mode.`;
      if (warning.details) {
        message += ` ${warning.details}`;
      }
      return message;
    }
    case "other": {
      return `${prefix} ${warning.message}`;
    }
    default: {
      return `${prefix} ${JSON.stringify(warning, null, 2)}`;
    }
  }
}
var FIRST_WARNING_INFO_MESSAGE = "AI SDK Warning System: To turn off warning logging, set the AI_SDK_LOG_WARNINGS global to false.";
var hasLoggedBefore = false;
var logWarnings = (options) => {
  if (options.warnings.length === 0) {
    return;
  }
  const logger = globalThis.AI_SDK_LOG_WARNINGS;
  if (logger === false) {
    return;
  }
  if (typeof logger === "function") {
    logger(options);
    return;
  }
  if (!hasLoggedBefore) {
    hasLoggedBefore = true;
    console.info(FIRST_WARNING_INFO_MESSAGE);
  }
  for (const warning of options.warnings) {
    console.warn(
      formatWarning({
        warning,
        provider: options.provider,
        model: options.model
      })
    );
  }
};
function logV2CompatibilityWarning({
  provider,
  modelId
}) {
  logWarnings({
    warnings: [
      {
        type: "compatibility",
        feature: "specificationVersion",
        details: `Using v2 specification compatibility mode. Some features may not be available.`
      }
    ],
    provider,
    model: modelId
  });
}
function asLanguageModelV3(model) {
  if (model.specificationVersion === "v3") {
    return model;
  }
  logV2CompatibilityWarning({
    provider: model.provider,
    modelId: model.modelId
  });
  return new Proxy(model, {
    get(target, prop) {
      switch (prop) {
        case "specificationVersion":
          return "v3";
        case "doGenerate":
          return async (...args) => {
            const result = await target.doGenerate(...args);
            return {
              ...result,
              finishReason: convertV2FinishReasonToV3(result.finishReason),
              usage: convertV2UsageToV3(result.usage)
            };
          };
        case "doStream":
          return async (...args) => {
            const result = await target.doStream(...args);
            return {
              ...result,
              stream: convertV2StreamToV3(result.stream)
            };
          };
        default:
          return target[prop];
      }
    }
  });
}
function convertV2StreamToV3(stream) {
  return stream.pipeThrough(
    new TransformStream({
      transform(chunk, controller) {
        switch (chunk.type) {
          case "finish":
            controller.enqueue({
              ...chunk,
              finishReason: convertV2FinishReasonToV3(chunk.finishReason),
              usage: convertV2UsageToV3(chunk.usage)
            });
            break;
          default:
            controller.enqueue(chunk);
            break;
        }
      }
    })
  );
}
function convertV2FinishReasonToV3(finishReason) {
  return {
    unified: finishReason === "unknown" ? "other" : finishReason,
    raw: void 0
  };
}
function convertV2UsageToV3(usage) {
  return {
    inputTokens: {
      total: usage.inputTokens,
      noCache: void 0,
      cacheRead: usage.cachedInputTokens,
      cacheWrite: void 0
    },
    outputTokens: {
      total: usage.outputTokens,
      text: void 0,
      reasoning: usage.reasoningTokens
    }
  };
}
function resolveLanguageModel(model) {
  if (typeof model !== "string") {
    if (model.specificationVersion !== "v3" && model.specificationVersion !== "v2") {
      const unsupportedModel = model;
      throw new UnsupportedModelVersionError({
        version: unsupportedModel.specificationVersion,
        provider: unsupportedModel.provider,
        modelId: unsupportedModel.modelId
      });
    }
    return asLanguageModelV3(model);
  }
  return getGlobalProvider().languageModel(model);
}
function getGlobalProvider() {
  var _a22;
  return (_a22 = globalThis.AI_SDK_DEFAULT_PROVIDER) != null ? _a22 : gateway;
}
function getTotalTimeoutMs(timeout) {
  if (timeout == null) {
    return void 0;
  }
  if (typeof timeout === "number") {
    return timeout;
  }
  return timeout.totalMs;
}
function getStepTimeoutMs(timeout) {
  if (timeout == null || typeof timeout === "number") {
    return void 0;
  }
  return timeout.stepMs;
}
var imageMediaTypeSignatures = [
  {
    mediaType: "image/gif",
    bytesPrefix: [71, 73, 70]
    // GIF
  },
  {
    mediaType: "image/png",
    bytesPrefix: [137, 80, 78, 71]
    // PNG
  },
  {
    mediaType: "image/jpeg",
    bytesPrefix: [255, 216]
    // JPEG
  },
  {
    mediaType: "image/webp",
    bytesPrefix: [
      82,
      73,
      70,
      70,
      // "RIFF"
      null,
      null,
      null,
      null,
      // file size (variable)
      87,
      69,
      66,
      80
      // "WEBP"
    ]
  },
  {
    mediaType: "image/bmp",
    bytesPrefix: [66, 77]
  },
  {
    mediaType: "image/tiff",
    bytesPrefix: [73, 73, 42, 0]
  },
  {
    mediaType: "image/tiff",
    bytesPrefix: [77, 77, 0, 42]
  },
  {
    mediaType: "image/avif",
    bytesPrefix: [
      0,
      0,
      0,
      32,
      102,
      116,
      121,
      112,
      97,
      118,
      105,
      102
    ]
  },
  {
    mediaType: "image/heic",
    bytesPrefix: [
      0,
      0,
      0,
      32,
      102,
      116,
      121,
      112,
      104,
      101,
      105,
      99
    ]
  }
];
var DEFAULT_SNIFF_BYTES = 18;
var MAX_SIGNATURE_BYTES = 12;
var MAX_ID3_TAG_BYTES = 128 * 1024;
var ID3_SCAN_BYTES = MAX_ID3_TAG_BYTES + MAX_SIGNATURE_BYTES;
function decodePrefix(data, maxBytes) {
  if (typeof data !== "string") {
    return data.length > maxBytes ? data.subarray(0, maxBytes) : data;
  }
  const maxChars = Math.ceil(maxBytes / 3) * 4;
  const bytes = convertBase64ToUint8Array(
    data.substring(0, Math.min(data.length, maxChars))
  );
  return bytes.length > maxBytes ? bytes.subarray(0, maxBytes) : bytes;
}
function hasID3(bytes) {
  return bytes.length > 10 && bytes[0] === 73 && // 'I'
  bytes[1] === 68 && // 'D'
  bytes[2] === 51;
}
var stripID3 = (bytes) => {
  const id3Size = (bytes[6] & 127) << 21 | (bytes[7] & 127) << 14 | (bytes[8] & 127) << 7 | bytes[9] & 127;
  return bytes.subarray(id3Size + 10);
};
function detectMediaType({
  data,
  signatures
}) {
  let bytes = decodePrefix(data, DEFAULT_SNIFF_BYTES);
  if (hasID3(bytes)) {
    bytes = stripID3(decodePrefix(data, ID3_SCAN_BYTES));
  }
  for (const signature of signatures) {
    if (bytes.length >= signature.bytesPrefix.length && signature.bytesPrefix.every(
      (byte, index) => byte === null || bytes[index] === byte
    )) {
      return signature.mediaType;
    }
  }
  return void 0;
}
var VERSION = "6.0.242";
var download = async ({
  url,
  maxBytes,
  abortSignal
}) => {
  var _a22;
  const urlText = url.toString();
  try {
    const headers = withUserAgentSuffix(
      {},
      `ai-sdk/${VERSION}`,
      getRuntimeEnvironmentUserAgent()
    );
    const response = await fetchWithValidatedRedirects({
      url: urlText,
      headers,
      abortSignal
    });
    if (!response.ok) {
      await cancelResponseBody(response);
      throw new DownloadError({
        url: urlText,
        statusCode: response.status,
        statusText: response.statusText
      });
    }
    const data = await readResponseWithSizeLimit({
      response,
      url: urlText,
      maxBytes: maxBytes != null ? maxBytes : DEFAULT_MAX_DOWNLOAD_SIZE
    });
    return {
      data,
      mediaType: (_a22 = response.headers.get("content-type")) != null ? _a22 : void 0
    };
  } catch (error) {
    if (DownloadError.isInstance(error)) {
      throw error;
    }
    throw new DownloadError({ url: urlText, cause: error });
  }
};
var createDefaultDownloadFunction = (download2 = download) => (requestedDownloads) => Promise.all(
  requestedDownloads.map(
    async (requestedDownload) => requestedDownload.isUrlSupportedByModel ? null : download2(requestedDownload)
  )
);
function mergeObjects(base, overrides) {
  if (base === void 0 && overrides === void 0) {
    return void 0;
  }
  if (base === void 0) {
    return overrides;
  }
  if (overrides === void 0) {
    return base;
  }
  const result = { ...base };
  for (const key in overrides) {
    if (key === "__proto__" || key === "constructor" || key === "prototype") {
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(overrides, key)) {
      const overridesValue = overrides[key];
      if (overridesValue === void 0)
        continue;
      const baseValue = key in base ? base[key] : void 0;
      const isSourceObject = overridesValue !== null && typeof overridesValue === "object" && !Array.isArray(overridesValue) && !(overridesValue instanceof Date) && !(overridesValue instanceof RegExp);
      const isTargetObject = baseValue !== null && baseValue !== void 0 && typeof baseValue === "object" && !Array.isArray(baseValue) && !(baseValue instanceof Date) && !(baseValue instanceof RegExp);
      if (isSourceObject && isTargetObject) {
        result[key] = mergeObjects(
          baseValue,
          overridesValue
        );
      } else {
        result[key] = overridesValue;
      }
    }
  }
  return result;
}
function splitDataUrl(dataUrl) {
  try {
    const [header, base64Content] = dataUrl.split(",");
    return {
      mediaType: header.split(";")[0].split(":")[1],
      base64Content
    };
  } catch (error) {
    return {
      mediaType: void 0,
      base64Content: void 0
    };
  }
}
var dataContentSchema = union([
  string(),
  _instanceof(Uint8Array),
  _instanceof(ArrayBuffer),
  custom(
    // Buffer might not be available in some environments such as CloudFlare:
    (value) => {
      var _a22, _b;
      return (_b = (_a22 = globalThis.Buffer) == null ? void 0 : _a22.isBuffer(value)) != null ? _b : false;
    },
    { message: "Must be a Buffer" }
  )
]);
function convertToLanguageModelV3DataContent(content) {
  if (content instanceof Uint8Array) {
    return { data: content, mediaType: void 0 };
  }
  if (content instanceof ArrayBuffer) {
    return { data: new Uint8Array(content), mediaType: void 0 };
  }
  if (typeof content === "string") {
    try {
      content = new URL(content);
    } catch (error) {
    }
  }
  if (content instanceof URL && content.protocol === "data:") {
    const { mediaType: dataUrlMediaType, base64Content } = splitDataUrl(
      content.toString()
    );
    if (dataUrlMediaType == null || base64Content == null) {
      throw new AISDKError({
        name: "InvalidDataContentError",
        message: `Invalid data URL format in content ${content.toString()}`
      });
    }
    return { data: base64Content, mediaType: dataUrlMediaType };
  }
  return { data: content, mediaType: void 0 };
}
function convertDataContentToBase64String(content) {
  if (typeof content === "string") {
    return content;
  }
  if (content instanceof ArrayBuffer) {
    return convertUint8ArrayToBase64(new Uint8Array(content));
  }
  return convertUint8ArrayToBase64(content);
}
async function convertToLanguageModelPrompt({
  prompt,
  supportedUrls,
  download: download2 = createDefaultDownloadFunction()
}) {
  const downloadedAssets = await downloadAssets(
    prompt.messages,
    download2,
    supportedUrls
  );
  const approvalIdToToolCallId = /* @__PURE__ */ new Map();
  for (const message of prompt.messages) {
    if (message.role === "assistant" && Array.isArray(message.content)) {
      for (const part of message.content) {
        if (part.type === "tool-approval-request" && "approvalId" in part && "toolCallId" in part) {
          approvalIdToToolCallId.set(
            part.approvalId,
            part.toolCallId
          );
        }
      }
    }
  }
  const approvedToolCallIds = /* @__PURE__ */ new Set();
  for (const message of prompt.messages) {
    if (message.role === "tool") {
      for (const part of message.content) {
        if (part.type === "tool-approval-response") {
          const toolCallId = approvalIdToToolCallId.get(part.approvalId);
          if (toolCallId) {
            approvedToolCallIds.add(toolCallId);
          }
        }
      }
    }
  }
  const messages = [
    ...prompt.system != null ? typeof prompt.system === "string" ? [{ role: "system", content: prompt.system }] : asArray(prompt.system).map((message) => ({
      role: "system",
      content: message.content,
      providerOptions: message.providerOptions
    })) : [],
    ...prompt.messages.map(
      (message) => convertToLanguageModelMessage({ message, downloadedAssets })
    )
  ];
  const combinedMessages = [];
  for (const message of messages) {
    if (message.role !== "tool") {
      combinedMessages.push(message);
      continue;
    }
    const lastCombinedMessage = combinedMessages.at(-1);
    if ((lastCombinedMessage == null ? void 0 : lastCombinedMessage.role) === "tool") {
      const lastContentPart = lastCombinedMessage.content.at(-1);
      if (lastContentPart != null && lastCombinedMessage.providerOptions != null) {
        lastContentPart.providerOptions = mergeObjects(
          lastCombinedMessage.providerOptions,
          lastContentPart.providerOptions
        );
      }
      lastCombinedMessage.content.push(...message.content);
      lastCombinedMessage.providerOptions = message.providerOptions;
    } else {
      combinedMessages.push(message);
    }
  }
  const toolCallIds = /* @__PURE__ */ new Set();
  for (const message of combinedMessages) {
    switch (message.role) {
      case "assistant": {
        for (const content of message.content) {
          if (content.type === "tool-call" && !content.providerExecuted) {
            toolCallIds.add(content.toolCallId);
          }
        }
        break;
      }
      case "tool": {
        for (const content of message.content) {
          if (content.type === "tool-result") {
            toolCallIds.delete(content.toolCallId);
          }
        }
        break;
      }
      case "user":
      case "system":
        for (const id of approvedToolCallIds) {
          toolCallIds.delete(id);
        }
        if (toolCallIds.size > 0) {
          throw new MissingToolResultsError({
            toolCallIds: Array.from(toolCallIds)
          });
        }
        break;
    }
  }
  for (const id of approvedToolCallIds) {
    toolCallIds.delete(id);
  }
  if (toolCallIds.size > 0) {
    throw new MissingToolResultsError({ toolCallIds: Array.from(toolCallIds) });
  }
  return combinedMessages.filter(
    // Filter out empty tool messages (e.g. if they only contained
    // tool-approval-response parts that were removed).
    // This prevents sending invalid empty messages to the provider.
    // Note: provider-executed tool-approval-response parts are preserved.
    (message) => message.role !== "tool" || message.content.length > 0
  );
}
function convertToLanguageModelMessage({
  message,
  downloadedAssets
}) {
  const role = message.role;
  switch (role) {
    case "system": {
      return {
        role: "system",
        content: message.content,
        providerOptions: message.providerOptions
      };
    }
    case "user": {
      if (typeof message.content === "string") {
        return {
          role: "user",
          content: [{ type: "text", text: message.content }],
          providerOptions: message.providerOptions
        };
      }
      return {
        role: "user",
        content: message.content.map((part) => convertPartToLanguageModelPart(part, downloadedAssets)).filter((part) => part.type !== "text" || part.text !== ""),
        providerOptions: message.providerOptions
      };
    }
    case "assistant": {
      if (typeof message.content === "string") {
        return {
          role: "assistant",
          content: [{ type: "text", text: message.content }],
          providerOptions: message.providerOptions
        };
      }
      return {
        role: "assistant",
        content: message.content.filter(
          // remove empty text parts (no text, and no provider options):
          (part) => part.type !== "text" || part.text !== "" || part.providerOptions != null
        ).filter(
          (part) => part.type !== "tool-approval-request"
        ).map((part) => {
          const providerOptions = part.providerOptions;
          switch (part.type) {
            case "file": {
              const { data, mediaType } = convertToLanguageModelV3DataContent(
                part.data
              );
              return {
                type: "file",
                data,
                filename: part.filename,
                mediaType: mediaType != null ? mediaType : part.mediaType,
                providerOptions
              };
            }
            case "reasoning": {
              return {
                type: "reasoning",
                text: part.text,
                providerOptions
              };
            }
            case "text": {
              return {
                type: "text",
                text: part.text,
                providerOptions
              };
            }
            case "tool-call": {
              return {
                type: "tool-call",
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                input: part.input,
                providerExecuted: part.providerExecuted,
                providerOptions
              };
            }
            case "tool-result": {
              return {
                type: "tool-result",
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                output: mapToolResultOutput({
                  output: part.output,
                  downloadedAssets
                }),
                providerOptions
              };
            }
          }
        }),
        providerOptions: message.providerOptions
      };
    }
    case "tool": {
      return {
        role: "tool",
        content: message.content.filter(
          // Only include tool-approval-response for provider-executed tools
          (part) => part.type !== "tool-approval-response" || part.providerExecuted
        ).map((part) => {
          switch (part.type) {
            case "tool-result": {
              return {
                type: "tool-result",
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                output: mapToolResultOutput({
                  output: part.output,
                  downloadedAssets
                }),
                providerOptions: part.providerOptions
              };
            }
            case "tool-approval-response": {
              return {
                type: "tool-approval-response",
                approvalId: part.approvalId,
                approved: part.approved,
                reason: part.reason
              };
            }
          }
        }),
        providerOptions: message.providerOptions
      };
    }
    default: {
      const _exhaustiveCheck = role;
      throw new InvalidMessageRoleError({ role: _exhaustiveCheck });
    }
  }
}
async function downloadAssets(messages, download2, supportedUrls) {
  var _a22;
  const downloadableFiles = [];
  for (const message of messages) {
    if (message.role === "user" && Array.isArray(message.content)) {
      for (const part of message.content) {
        if (part.type === "image" || part.type === "file") {
          downloadableFiles.push({
            data: part.type === "image" ? part.image : part.data,
            mediaType: (_a22 = part.mediaType) != null ? _a22 : part.type === "image" ? "image/*" : void 0
          });
        }
      }
    }
    if (message.role === "tool" || message.role === "assistant") {
      if (!Array.isArray(message.content)) {
        continue;
      }
      for (const part of message.content) {
        if (part.type !== "tool-result") {
          continue;
        }
        if (part.output.type !== "content") {
          continue;
        }
        for (const contentPart of part.output.value) {
          if (contentPart.type === "image-url" || contentPart.type === "file-url") {
            downloadableFiles.push({
              data: new URL(contentPart.url),
              mediaType: contentPart.type === "image-url" ? "image/*" : void 0
            });
          }
        }
      }
    }
  }
  const plannedDownloads = downloadableFiles.map((part) => {
    const mediaType = part.mediaType;
    const { data } = convertToLanguageModelV3DataContent(part.data);
    return { mediaType, data };
  }).filter(
    (part) => part.data instanceof URL
  ).map((part) => ({
    url: part.data,
    isUrlSupportedByModel: part.mediaType != null && isUrlSupported({
      url: part.data.toString(),
      mediaType: part.mediaType,
      supportedUrls
    })
  }));
  const downloadedFiles = await download2(plannedDownloads);
  return Object.fromEntries(
    downloadedFiles.map(
      (file, index) => file == null ? null : [
        plannedDownloads[index].url.toString(),
        { data: file.data, mediaType: file.mediaType }
      ]
    ).filter((file) => file != null)
  );
}
function convertPartToLanguageModelPart(part, downloadedAssets) {
  var _a22;
  if (part.type === "text") {
    return {
      type: "text",
      text: part.text,
      providerOptions: part.providerOptions
    };
  }
  let originalData;
  const type = part.type;
  switch (type) {
    case "image":
      originalData = part.image;
      break;
    case "file":
      originalData = part.data;
      break;
    default:
      throw new Error(`Unsupported part type: ${type}`);
  }
  const { data: convertedData, mediaType: convertedMediaType } = convertToLanguageModelV3DataContent(originalData);
  let mediaType = convertedMediaType != null ? convertedMediaType : part.mediaType;
  let data = convertedData;
  if (data instanceof URL) {
    const downloadedFile = downloadedAssets[data.toString()];
    if (downloadedFile) {
      data = downloadedFile.data;
      mediaType != null ? mediaType : mediaType = downloadedFile.mediaType;
    }
  }
  switch (type) {
    case "image": {
      if (data instanceof Uint8Array || typeof data === "string") {
        mediaType = (_a22 = detectMediaType({ data, signatures: imageMediaTypeSignatures })) != null ? _a22 : mediaType;
      }
      return {
        type: "file",
        mediaType: mediaType != null ? mediaType : "image/*",
        // any image
        filename: void 0,
        data,
        providerOptions: part.providerOptions
      };
    }
    case "file": {
      if (mediaType == null) {
        throw new Error(`Media type is missing for file part`);
      }
      return {
        type: "file",
        mediaType,
        filename: part.filename,
        data,
        providerOptions: part.providerOptions
      };
    }
  }
}
function mapToolResultOutput({
  output,
  downloadedAssets
}) {
  if (output.type !== "content") {
    return output;
  }
  return {
    type: "content",
    value: output.value.map((item) => {
      var _a22, _b;
      if (item.type === "image-url") {
        const downloadedFile = downloadedAssets[new URL(item.url).toString()];
        if (downloadedFile) {
          return {
            type: "image-data",
            data: convertDataContentToBase64String(downloadedFile.data),
            mediaType: (_a22 = downloadedFile.mediaType) != null ? _a22 : "image/*",
            providerOptions: item.providerOptions
          };
        }
        return item;
      }
      if (item.type === "file-url") {
        const downloadedFile = downloadedAssets[new URL(item.url).toString()];
        if (downloadedFile) {
          return {
            type: "file-data",
            data: convertDataContentToBase64String(downloadedFile.data),
            mediaType: (_b = downloadedFile.mediaType) != null ? _b : "application/octet-stream",
            providerOptions: item.providerOptions
          };
        }
        return item;
      }
      if (item.type !== "media") {
        return item;
      }
      if (item.mediaType.startsWith("image/")) {
        return {
          type: "image-data",
          data: item.data,
          mediaType: item.mediaType
        };
      }
      return {
        type: "file-data",
        data: item.data,
        mediaType: item.mediaType
      };
    })
  };
}
async function createToolModelOutput({
  toolCallId,
  input,
  output,
  tool: tool2,
  errorMode
}) {
  if (errorMode === "text") {
    return { type: "error-text", value: getErrorMessage$1(output) };
  } else if (errorMode === "json") {
    return { type: "error-json", value: toJSONValue(output) };
  }
  if (tool2 == null ? void 0 : tool2.toModelOutput) {
    return await tool2.toModelOutput({ toolCallId, input, output });
  }
  return typeof output === "string" ? { type: "text", value: output } : { type: "json", value: toJSONValue(output) };
}
function toJSONValue(value) {
  return value === void 0 ? null : value;
}
function prepareCallSettings({
  maxOutputTokens,
  temperature,
  topP,
  topK,
  presencePenalty,
  frequencyPenalty,
  seed,
  stopSequences
}) {
  if (maxOutputTokens != null) {
    if (!Number.isInteger(maxOutputTokens)) {
      throw new InvalidArgumentError({
        parameter: "maxOutputTokens",
        value: maxOutputTokens,
        message: "maxOutputTokens must be an integer"
      });
    }
    if (maxOutputTokens < 1) {
      throw new InvalidArgumentError({
        parameter: "maxOutputTokens",
        value: maxOutputTokens,
        message: "maxOutputTokens must be >= 1"
      });
    }
  }
  if (temperature != null) {
    if (typeof temperature !== "number") {
      throw new InvalidArgumentError({
        parameter: "temperature",
        value: temperature,
        message: "temperature must be a number"
      });
    }
  }
  if (topP != null) {
    if (typeof topP !== "number") {
      throw new InvalidArgumentError({
        parameter: "topP",
        value: topP,
        message: "topP must be a number"
      });
    }
  }
  if (topK != null) {
    if (typeof topK !== "number") {
      throw new InvalidArgumentError({
        parameter: "topK",
        value: topK,
        message: "topK must be a number"
      });
    }
  }
  if (presencePenalty != null) {
    if (typeof presencePenalty !== "number") {
      throw new InvalidArgumentError({
        parameter: "presencePenalty",
        value: presencePenalty,
        message: "presencePenalty must be a number"
      });
    }
  }
  if (frequencyPenalty != null) {
    if (typeof frequencyPenalty !== "number") {
      throw new InvalidArgumentError({
        parameter: "frequencyPenalty",
        value: frequencyPenalty,
        message: "frequencyPenalty must be a number"
      });
    }
  }
  if (seed != null) {
    if (!Number.isInteger(seed)) {
      throw new InvalidArgumentError({
        parameter: "seed",
        value: seed,
        message: "seed must be an integer"
      });
    }
  }
  return {
    maxOutputTokens,
    temperature,
    topP,
    topK,
    presencePenalty,
    frequencyPenalty,
    stopSequences,
    seed
  };
}
function isNonEmptyObject(object2) {
  return object2 != null && Object.keys(object2).length > 0;
}
async function prepareToolsAndToolChoice({
  tools,
  toolChoice,
  activeTools
}) {
  if (!isNonEmptyObject(tools)) {
    return {
      tools: void 0,
      toolChoice: void 0
    };
  }
  const filteredTools = activeTools != null ? Object.entries(tools).filter(
    ([name22]) => activeTools.includes(name22)
  ) : Object.entries(tools);
  const languageModelTools = [];
  for (const [name22, tool2] of filteredTools) {
    const toolType = tool2.type;
    switch (toolType) {
      case void 0:
      case "dynamic":
      case "function":
        languageModelTools.push({
          type: "function",
          name: name22,
          description: tool2.description,
          inputSchema: await asSchema(tool2.inputSchema).jsonSchema,
          ...tool2.inputExamples != null ? { inputExamples: tool2.inputExamples } : {},
          providerOptions: tool2.providerOptions,
          ...tool2.strict != null ? { strict: tool2.strict } : {}
        });
        break;
      case "provider":
        languageModelTools.push({
          type: "provider",
          name: name22,
          id: tool2.id,
          args: tool2.args
        });
        break;
      default: {
        const exhaustiveCheck = toolType;
        throw new Error(`Unsupported tool type: ${exhaustiveCheck}`);
      }
    }
  }
  return {
    tools: languageModelTools,
    toolChoice: toolChoice == null ? { type: "auto" } : typeof toolChoice === "string" ? { type: toolChoice } : { type: "tool", toolName: toolChoice.toolName }
  };
}
var jsonValueSchema = lazy(
  () => union([
    _null(),
    string(),
    number(),
    boolean(),
    record(string(), jsonValueSchema.optional()),
    array$1(jsonValueSchema)
  ])
);
var providerMetadataSchema = record(
  string(),
  record(string(), jsonValueSchema.optional())
);
var textPartSchema = object$1({
  type: literal("text"),
  text: string(),
  providerOptions: providerMetadataSchema.optional()
});
var imagePartSchema = object$1({
  type: literal("image"),
  image: union([dataContentSchema, _instanceof(URL)]),
  mediaType: string().optional(),
  providerOptions: providerMetadataSchema.optional()
});
var filePartSchema = object$1({
  type: literal("file"),
  data: union([dataContentSchema, _instanceof(URL)]),
  filename: string().optional(),
  mediaType: string(),
  providerOptions: providerMetadataSchema.optional()
});
var reasoningPartSchema = object$1({
  type: literal("reasoning"),
  text: string(),
  providerOptions: providerMetadataSchema.optional()
});
var toolCallPartSchema = object$1({
  type: literal("tool-call"),
  toolCallId: string(),
  toolName: string(),
  input: unknown(),
  providerOptions: providerMetadataSchema.optional(),
  providerExecuted: boolean().optional()
});
var outputSchema = discriminatedUnion(
  "type",
  [
    object$1({
      type: literal("text"),
      value: string(),
      providerOptions: providerMetadataSchema.optional()
    }),
    object$1({
      type: literal("json"),
      value: jsonValueSchema,
      providerOptions: providerMetadataSchema.optional()
    }),
    object$1({
      type: literal("execution-denied"),
      reason: string().optional(),
      providerOptions: providerMetadataSchema.optional()
    }),
    object$1({
      type: literal("error-text"),
      value: string(),
      providerOptions: providerMetadataSchema.optional()
    }),
    object$1({
      type: literal("error-json"),
      value: jsonValueSchema,
      providerOptions: providerMetadataSchema.optional()
    }),
    object$1({
      type: literal("content"),
      value: array$1(
        union([
          object$1({
            type: literal("text"),
            text: string(),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("media"),
            data: string(),
            mediaType: string()
          }),
          object$1({
            type: literal("file-data"),
            data: string(),
            mediaType: string(),
            filename: string().optional(),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("file-url"),
            url: string(),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("file-id"),
            fileId: union([string(), record(string(), string())]),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("image-data"),
            data: string(),
            mediaType: string(),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("image-url"),
            url: string(),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("image-file-id"),
            fileId: union([string(), record(string(), string())]),
            providerOptions: providerMetadataSchema.optional()
          }),
          object$1({
            type: literal("custom"),
            providerOptions: providerMetadataSchema.optional()
          })
        ])
      )
    })
  ]
);
var toolResultPartSchema = object$1({
  type: literal("tool-result"),
  toolCallId: string(),
  toolName: string(),
  output: outputSchema,
  providerOptions: providerMetadataSchema.optional()
});
var toolApprovalRequestSchema = object$1({
  type: literal("tool-approval-request"),
  approvalId: string(),
  toolCallId: string()
});
var toolApprovalResponseSchema = object$1({
  type: literal("tool-approval-response"),
  approvalId: string(),
  approved: boolean(),
  reason: string().optional()
});
var systemModelMessageSchema = object$1(
  {
    role: literal("system"),
    content: string(),
    providerOptions: providerMetadataSchema.optional()
  }
);
var userModelMessageSchema = object$1({
  role: literal("user"),
  content: union([
    string(),
    array$1(union([textPartSchema, imagePartSchema, filePartSchema]))
  ]),
  providerOptions: providerMetadataSchema.optional()
});
var assistantModelMessageSchema = object$1({
  role: literal("assistant"),
  content: union([
    string(),
    array$1(
      union([
        textPartSchema,
        filePartSchema,
        reasoningPartSchema,
        toolCallPartSchema,
        toolResultPartSchema,
        toolApprovalRequestSchema
      ])
    )
  ]),
  providerOptions: providerMetadataSchema.optional()
});
var toolModelMessageSchema = object$1({
  role: literal("tool"),
  content: array$1(union([toolResultPartSchema, toolApprovalResponseSchema])),
  providerOptions: providerMetadataSchema.optional()
});
var modelMessageSchema = union([
  systemModelMessageSchema,
  userModelMessageSchema,
  assistantModelMessageSchema,
  toolModelMessageSchema
]);
async function standardizePrompt({
  allowSystemInMessages,
  system,
  prompt,
  messages
}) {
  if (prompt == null && messages == null) {
    throw new InvalidPromptError({
      prompt,
      message: "prompt or messages must be defined"
    });
  }
  if (prompt != null && messages != null) {
    throw new InvalidPromptError({
      prompt,
      message: "prompt and messages cannot be defined at the same time"
    });
  }
  if (typeof system !== "string" && !asArray(system).every((message) => message.role === "system")) {
    throw new InvalidPromptError({
      prompt,
      message: "system must be a string, SystemModelMessage, or array of SystemModelMessage"
    });
  }
  if (prompt != null && typeof prompt === "string") {
    messages = [{ role: "user", content: prompt }];
  } else if (prompt != null && Array.isArray(prompt)) {
    messages = prompt;
  } else if (messages == null) {
    throw new InvalidPromptError({
      prompt,
      message: "prompt or messages must be defined"
    });
  }
  if (messages.length === 0) {
    throw new InvalidPromptError({
      prompt,
      message: "messages must not be empty"
    });
  }
  if (messages.some((message) => message.role === "system")) {
    if (allowSystemInMessages === false) {
      throw new InvalidPromptError({
        prompt,
        message: "System messages are not allowed in the prompt or messages fields. Use the system option instead."
      });
    }
    if (allowSystemInMessages === void 0) {
      console.warn(
        "AI SDK Warning: System messages in the prompt or messages fields can be a security risk because they may enable prompt injection attacks. Use the system option instead when possible. Set allowSystemInMessages to true to suppress this warning, or false to throw an error."
      );
    }
  }
  const validationResult = await safeValidateTypes({
    value: messages,
    schema: array$1(modelMessageSchema)
  });
  if (!validationResult.success) {
    throw new InvalidPromptError({
      prompt,
      message: "The messages do not match the ModelMessage[] schema.",
      cause: validationResult.error
    });
  }
  return { messages, system };
}
function wrapGatewayError(error) {
  if (!GatewayAuthenticationError.isInstance(error))
    return error;
  const isProductionEnv = (process == null ? void 0 : "production") === "production";
  const moreInfoURL = "https://ai-sdk.dev/unauthenticated-ai-gateway";
  if (isProductionEnv) {
    return new AISDKError({
      name: "GatewayError",
      message: `Unauthenticated. Configure AI_GATEWAY_API_KEY or use a provider module. Learn more: ${moreInfoURL}`
    });
  }
  return Object.assign(
    new Error(`\x1B[1m\x1B[31mUnauthenticated request to AI Gateway.\x1B[0m

To authenticate, set the \x1B[33mAI_GATEWAY_API_KEY\x1B[0m environment variable with your API key.

Alternatively, you can use a provider module instead of the AI Gateway.

Learn more: \x1B[34m${moreInfoURL}\x1B[0m

`),
    { name: "GatewayAuthenticationError" }
  );
}
function assembleOperationName({
  operationId,
  telemetry
}) {
  return {
    // standardized operation and resource name:
    "operation.name": `${operationId}${(telemetry == null ? void 0 : telemetry.functionId) != null ? ` ${telemetry.functionId}` : ""}`,
    "resource.name": telemetry == null ? void 0 : telemetry.functionId,
    // detailed, AI SDK specific data:
    "ai.operationId": operationId,
    "ai.telemetry.functionId": telemetry == null ? void 0 : telemetry.functionId
  };
}
function getBaseTelemetryAttributes({
  model,
  settings,
  telemetry,
  headers
}) {
  var _a22;
  return {
    "ai.model.provider": model.provider,
    "ai.model.id": model.modelId,
    // settings:
    ...Object.entries(settings).reduce((attributes, [key, value]) => {
      if (key === "timeout") {
        const totalTimeoutMs = getTotalTimeoutMs(
          value
        );
        if (totalTimeoutMs != null) {
          attributes[`ai.settings.${key}`] = totalTimeoutMs;
        }
      } else {
        attributes[`ai.settings.${key}`] = value;
      }
      return attributes;
    }, {}),
    // add metadata as attributes:
    ...Object.entries((_a22 = telemetry == null ? void 0 : telemetry.metadata) != null ? _a22 : {}).reduce(
      (attributes, [key, value]) => {
        attributes[`ai.telemetry.metadata.${key}`] = value;
        return attributes;
      },
      {}
    ),
    // request headers
    ...Object.entries(headers != null ? headers : {}).reduce((attributes, [key, value]) => {
      if (value !== void 0) {
        attributes[`ai.request.headers.${key}`] = value;
      }
      return attributes;
    }, {})
  };
}
var noopTracer = {
  startSpan() {
    return noopSpan;
  },
  startActiveSpan(name22, arg1, arg2, arg3) {
    if (typeof arg1 === "function") {
      return arg1(noopSpan);
    }
    if (typeof arg2 === "function") {
      return arg2(noopSpan);
    }
    if (typeof arg3 === "function") {
      return arg3(noopSpan);
    }
  }
};
var noopSpan = {
  spanContext() {
    return noopSpanContext;
  },
  setAttribute() {
    return this;
  },
  setAttributes() {
    return this;
  },
  addEvent() {
    return this;
  },
  addLink() {
    return this;
  },
  addLinks() {
    return this;
  },
  setStatus() {
    return this;
  },
  updateName() {
    return this;
  },
  end() {
    return this;
  },
  isRecording() {
    return false;
  },
  recordException() {
    return this;
  }
};
var noopSpanContext = {
  traceId: "",
  spanId: "",
  traceFlags: 0
};
function getTracer({
  isEnabled = false,
  tracer
} = {}) {
  if (!isEnabled) {
    return noopTracer;
  }
  if (tracer) {
    return tracer;
  }
  return srcExports.trace.getTracer("ai");
}
async function recordSpan({
  name: name22,
  tracer,
  attributes,
  fn,
  endWhenDone = true
}) {
  return tracer.startActiveSpan(
    name22,
    { attributes: await attributes },
    async (span) => {
      const ctx = srcExports.context.active();
      try {
        const result = await srcExports.context.with(ctx, () => fn(span));
        if (endWhenDone) {
          span.end();
        }
        return result;
      } catch (error) {
        try {
          recordErrorOnSpan(span, error);
        } finally {
          span.end();
        }
        throw error;
      }
    }
  );
}
function recordErrorOnSpan(span, error) {
  if (error instanceof Error) {
    span.recordException({
      name: error.name,
      message: error.message,
      stack: error.stack
    });
    span.setStatus({
      code: srcExports.SpanStatusCode.ERROR,
      message: error.message
    });
  } else {
    span.setStatus({ code: srcExports.SpanStatusCode.ERROR });
  }
}
function isPrimitiveAttributeValue(value) {
  return typeof value === "string" || typeof value === "number" || typeof value === "boolean";
}
function sanitizeAttributeValue(value) {
  if (!Array.isArray(value)) {
    return value;
  }
  const primitiveTypes = new Set(
    value.filter(isPrimitiveAttributeValue).map((item) => typeof item)
  );
  if (primitiveTypes.size !== 1) {
    return void 0;
  }
  const [primitiveType] = primitiveTypes;
  if (primitiveType === "string") {
    return value.filter((item) => typeof item === "string");
  }
  if (primitiveType === "number") {
    return value.filter((item) => typeof item === "number");
  }
  return value.filter((item) => typeof item === "boolean");
}
async function selectTelemetryAttributes({
  telemetry,
  attributes
}) {
  if ((telemetry == null ? void 0 : telemetry.isEnabled) !== true) {
    return {};
  }
  const resultAttributes = {};
  for (const [key, value] of Object.entries(attributes)) {
    if (value == null) {
      continue;
    }
    if (typeof value === "object" && "input" in value && typeof value.input === "function") {
      if ((telemetry == null ? void 0 : telemetry.recordInputs) === false) {
        continue;
      }
      const result = await value.input();
      if (result != null) {
        const sanitized2 = sanitizeAttributeValue(result);
        if (sanitized2 != null)
          resultAttributes[key] = sanitized2;
      }
      continue;
    }
    if (typeof value === "object" && "output" in value && typeof value.output === "function") {
      if ((telemetry == null ? void 0 : telemetry.recordOutputs) === false) {
        continue;
      }
      const result = await value.output();
      if (result != null) {
        const sanitized2 = sanitizeAttributeValue(result);
        if (sanitized2 != null)
          resultAttributes[key] = sanitized2;
      }
      continue;
    }
    const sanitized = sanitizeAttributeValue(value);
    if (sanitized != null)
      resultAttributes[key] = sanitized;
  }
  return resultAttributes;
}
function stringifyForTelemetry(prompt) {
  return JSON.stringify(
    prompt.map((message) => ({
      ...message,
      content: typeof message.content === "string" ? message.content : message.content.map(
        (part) => part.type === "file" ? {
          ...part,
          data: part.data instanceof Uint8Array ? convertDataContentToBase64String(part.data) : part.data
        } : part
      )
    }))
  );
}
function getGlobalTelemetryIntegrations() {
  var _a22;
  return (_a22 = globalThis.AI_SDK_TELEMETRY_INTEGRATIONS) != null ? _a22 : [];
}
function getGlobalTelemetryIntegration() {
  const globalIntegrations = getGlobalTelemetryIntegrations();
  return (integrations) => {
    const localIntegrations = asArray(integrations);
    const allIntegrations = [...globalIntegrations, ...localIntegrations];
    function createTelemetryComposite(getListenerFromIntegration) {
      const listeners = allIntegrations.map(getListenerFromIntegration).filter(Boolean);
      return async (event) => {
        for (const listener of listeners) {
          try {
            await listener(event);
          } catch (_ignored) {
          }
        }
      };
    }
    return {
      onStart: createTelemetryComposite((integration) => integration.onStart),
      onStepStart: createTelemetryComposite(
        (integration) => integration.onStepStart
      ),
      onToolCallStart: createTelemetryComposite(
        (integration) => integration.onToolCallStart
      ),
      onToolCallFinish: createTelemetryComposite(
        (integration) => integration.onToolCallFinish
      ),
      onStepFinish: createTelemetryComposite(
        (integration) => integration.onStepFinish
      ),
      onFinish: createTelemetryComposite((integration) => integration.onFinish)
    };
  };
}
function asLanguageModelUsage(usage) {
  return {
    inputTokens: usage.inputTokens.total,
    inputTokenDetails: {
      noCacheTokens: usage.inputTokens.noCache,
      cacheReadTokens: usage.inputTokens.cacheRead,
      cacheWriteTokens: usage.inputTokens.cacheWrite
    },
    outputTokens: usage.outputTokens.total,
    outputTokenDetails: {
      textTokens: usage.outputTokens.text,
      reasoningTokens: usage.outputTokens.reasoning
    },
    totalTokens: addTokenCounts(
      usage.inputTokens.total,
      usage.outputTokens.total
    ),
    raw: usage.raw,
    reasoningTokens: usage.outputTokens.reasoning,
    cachedInputTokens: usage.inputTokens.cacheRead
  };
}
function addLanguageModelUsage(usage1, usage2) {
  var _a22, _b, _c, _d, _e, _f, _g, _h, _i, _j;
  return {
    inputTokens: addTokenCounts(usage1.inputTokens, usage2.inputTokens),
    inputTokenDetails: {
      noCacheTokens: addTokenCounts(
        (_a22 = usage1.inputTokenDetails) == null ? void 0 : _a22.noCacheTokens,
        (_b = usage2.inputTokenDetails) == null ? void 0 : _b.noCacheTokens
      ),
      cacheReadTokens: addTokenCounts(
        (_c = usage1.inputTokenDetails) == null ? void 0 : _c.cacheReadTokens,
        (_d = usage2.inputTokenDetails) == null ? void 0 : _d.cacheReadTokens
      ),
      cacheWriteTokens: addTokenCounts(
        (_e = usage1.inputTokenDetails) == null ? void 0 : _e.cacheWriteTokens,
        (_f = usage2.inputTokenDetails) == null ? void 0 : _f.cacheWriteTokens
      )
    },
    outputTokens: addTokenCounts(usage1.outputTokens, usage2.outputTokens),
    outputTokenDetails: {
      textTokens: addTokenCounts(
        (_g = usage1.outputTokenDetails) == null ? void 0 : _g.textTokens,
        (_h = usage2.outputTokenDetails) == null ? void 0 : _h.textTokens
      ),
      reasoningTokens: addTokenCounts(
        (_i = usage1.outputTokenDetails) == null ? void 0 : _i.reasoningTokens,
        (_j = usage2.outputTokenDetails) == null ? void 0 : _j.reasoningTokens
      )
    },
    totalTokens: addTokenCounts(usage1.totalTokens, usage2.totalTokens),
    reasoningTokens: addTokenCounts(
      usage1.reasoningTokens,
      usage2.reasoningTokens
    ),
    cachedInputTokens: addTokenCounts(
      usage1.cachedInputTokens,
      usage2.cachedInputTokens
    )
  };
}
function addTokenCounts(tokenCount1, tokenCount2) {
  return tokenCount1 == null && tokenCount2 == null ? void 0 : (tokenCount1 != null ? tokenCount1 : 0) + (tokenCount2 != null ? tokenCount2 : 0);
}
function getRetryDelayInMs({
  error,
  exponentialBackoffDelay
}) {
  const headers = APICallError.isInstance(error) ? error.responseHeaders : APICallError.isInstance(error.cause) ? error.cause.responseHeaders : void 0;
  if (!headers)
    return exponentialBackoffDelay;
  let ms;
  const retryAfterMs = headers["retry-after-ms"];
  if (retryAfterMs) {
    const timeoutMs = parseFloat(retryAfterMs);
    if (!Number.isNaN(timeoutMs)) {
      ms = timeoutMs;
    }
  }
  const retryAfter = headers["retry-after"];
  if (retryAfter && ms === void 0) {
    const timeoutSeconds = parseFloat(retryAfter);
    if (!Number.isNaN(timeoutSeconds)) {
      ms = timeoutSeconds * 1e3;
    } else {
      ms = Date.parse(retryAfter) - Date.now();
    }
  }
  if (ms != null && !Number.isNaN(ms) && 0 <= ms && (ms < 60 * 1e3 || ms < exponentialBackoffDelay)) {
    return ms;
  }
  return exponentialBackoffDelay;
}
var retryWithExponentialBackoffRespectingRetryHeaders = ({
  maxRetries = 2,
  initialDelayInMs = 2e3,
  backoffFactor = 2,
  abortSignal
} = {}) => retryWithExponentialBackoff({
  maxRetries,
  initialDelayInMs,
  backoffFactor,
  abortSignal,
  shouldRetry: (error) => error instanceof Error && (APICallError.isInstance(error) && error.isRetryable === true || GatewayError.isInstance(error) && error.isRetryable === true),
  getDelayInMs: ({ error, exponentialBackoffDelay }) => getRetryDelayInMs({
    error,
    exponentialBackoffDelay
  }),
  createRetryError: ({ message, reason, errors }) => new RetryError({ message, reason, errors })
});
function prepareRetries({
  maxRetries,
  abortSignal
}) {
  if (maxRetries != null) {
    if (!Number.isInteger(maxRetries)) {
      throw new InvalidArgumentError({
        parameter: "maxRetries",
        value: maxRetries,
        message: "maxRetries must be an integer"
      });
    }
    if (maxRetries < 0) {
      throw new InvalidArgumentError({
        parameter: "maxRetries",
        value: maxRetries,
        message: "maxRetries must be >= 0"
      });
    }
  }
  const maxRetriesResult = maxRetries != null ? maxRetries : 2;
  return {
    maxRetries: maxRetriesResult,
    retry: retryWithExponentialBackoffRespectingRetryHeaders({
      maxRetries: maxRetriesResult,
      abortSignal
    })
  };
}
function setAbortTimeout({
  abortController,
  label,
  timeoutMs
}) {
  if (abortController == null || timeoutMs == null) {
    return void 0;
  }
  return setTimeout(
    () => abortController.abort(
      new DOMException(
        `${label} timeout of ${timeoutMs}ms exceeded`,
        "TimeoutError"
      )
    ),
    timeoutMs
  );
}
function collectToolApprovals({
  messages
}) {
  const lastMessage = messages.at(-1);
  if ((lastMessage == null ? void 0 : lastMessage.role) != "tool") {
    return {
      approvedToolApprovals: [],
      deniedToolApprovals: []
    };
  }
  const toolCallsByToolCallId = {};
  for (const message of messages) {
    if (message.role === "assistant" && typeof message.content !== "string") {
      const content = message.content;
      for (const part of content) {
        if (part.type === "tool-call") {
          toolCallsByToolCallId[part.toolCallId] = part;
        }
      }
    }
  }
  const toolApprovalRequestsByApprovalId = {};
  for (const message of messages) {
    if (message.role === "assistant" && typeof message.content !== "string") {
      const content = message.content;
      for (const part of content) {
        if (part.type === "tool-approval-request") {
          toolApprovalRequestsByApprovalId[part.approvalId] = part;
        }
      }
    }
  }
  const toolResults = {};
  for (const part of lastMessage.content) {
    if (part.type === "tool-result") {
      toolResults[part.toolCallId] = part;
    }
  }
  const approvedToolApprovals = [];
  const deniedToolApprovals = [];
  const approvalResponses = lastMessage.content.filter(
    (part) => part.type === "tool-approval-response"
  );
  for (const approvalResponse of approvalResponses) {
    const approvalRequest = toolApprovalRequestsByApprovalId[approvalResponse.approvalId];
    if (approvalRequest == null) {
      throw new InvalidToolApprovalError({
        approvalId: approvalResponse.approvalId
      });
    }
    if (toolResults[approvalRequest.toolCallId] != null) {
      continue;
    }
    const toolCall = toolCallsByToolCallId[approvalRequest.toolCallId];
    if (toolCall == null) {
      throw new ToolCallNotFoundForApprovalError({
        toolCallId: approvalRequest.toolCallId,
        approvalId: approvalRequest.approvalId
      });
    }
    const approval = {
      approvalRequest,
      approvalResponse,
      toolCall
    };
    if (approvalResponse.approved) {
      approvedToolApprovals.push(approval);
    } else {
      deniedToolApprovals.push(approval);
    }
  }
  return { approvedToolApprovals, deniedToolApprovals };
}
function now() {
  var _a22, _b;
  return (_b = (_a22 = globalThis == null ? void 0 : globalThis.performance) == null ? void 0 : _a22.now()) != null ? _b : Date.now();
}
async function executeToolCall({
  toolCall,
  tools,
  tracer,
  telemetry,
  messages,
  abortSignal,
  experimental_context,
  stepNumber,
  model,
  onPreliminaryToolResult,
  onToolCallStart,
  onToolCallFinish
}) {
  const { toolName, toolCallId, input } = toolCall;
  const tool2 = tools == null ? void 0 : tools[toolName];
  if ((tool2 == null ? void 0 : tool2.execute) == null) {
    return void 0;
  }
  const baseCallbackEvent = {
    stepNumber,
    model,
    toolCall,
    messages,
    abortSignal,
    functionId: telemetry == null ? void 0 : telemetry.functionId,
    metadata: telemetry == null ? void 0 : telemetry.metadata,
    experimental_context
  };
  return recordSpan({
    name: "ai.toolCall",
    attributes: selectTelemetryAttributes({
      telemetry,
      attributes: {
        ...assembleOperationName({
          operationId: "ai.toolCall",
          telemetry
        }),
        "ai.toolCall.name": toolName,
        "ai.toolCall.id": toolCallId,
        "ai.toolCall.args": {
          output: () => JSON.stringify(input)
        }
      }
    }),
    tracer,
    fn: async (span) => {
      let output;
      await notify({ event: baseCallbackEvent, callbacks: onToolCallStart });
      const startTime = now();
      try {
        const stream = executeTool({
          execute: tool2.execute.bind(tool2),
          input,
          options: {
            toolCallId,
            messages,
            abortSignal,
            experimental_context
          }
        });
        for await (const part of stream) {
          if (part.type === "preliminary") {
            onPreliminaryToolResult == null ? void 0 : onPreliminaryToolResult({
              ...toolCall,
              type: "tool-result",
              output: part.output,
              preliminary: true
            });
          } else {
            output = part.output;
          }
        }
      } catch (error) {
        const durationMs2 = now() - startTime;
        await notify({
          event: {
            ...baseCallbackEvent,
            success: false,
            error,
            durationMs: durationMs2
          },
          callbacks: onToolCallFinish
        });
        recordErrorOnSpan(span, error);
        return {
          type: "tool-error",
          toolCallId,
          toolName,
          input,
          error,
          dynamic: tool2.type === "dynamic",
          ...toolCall.providerMetadata != null ? { providerMetadata: toolCall.providerMetadata } : {},
          ...toolCall.toolMetadata != null ? { toolMetadata: toolCall.toolMetadata } : {}
        };
      }
      const durationMs = now() - startTime;
      await notify({
        event: {
          ...baseCallbackEvent,
          success: true,
          output,
          durationMs
        },
        callbacks: onToolCallFinish
      });
      try {
        span.setAttributes(
          await selectTelemetryAttributes({
            telemetry,
            attributes: {
              "ai.toolCall.result": {
                output: () => JSON.stringify(output)
              }
            }
          })
        );
      } catch (ignored) {
      }
      return {
        type: "tool-result",
        toolCallId,
        toolName,
        input,
        output,
        dynamic: tool2.type === "dynamic",
        ...toolCall.providerMetadata != null ? { providerMetadata: toolCall.providerMetadata } : {},
        ...toolCall.toolMetadata != null ? { toolMetadata: toolCall.toolMetadata } : {}
      };
    }
  });
}
function extractReasoningContent(content) {
  const parts = content.filter(
    (content2) => content2.type === "reasoning"
  );
  return parts.length === 0 ? void 0 : parts.map((content2) => content2.text).join("\n");
}
function extractTextContent(content) {
  const parts = content.filter(
    (content2) => content2.type === "text"
  );
  if (parts.length === 0) {
    return void 0;
  }
  return parts.map((content2) => content2.text).join("");
}
function filterActiveTools({
  tools,
  activeTools
}) {
  if (tools == null || activeTools == null) {
    return tools;
  }
  return Object.fromEntries(
    Object.entries(tools).filter(
      ([name22]) => activeTools.includes(name22)
    )
  );
}
var DefaultGeneratedFile = class {
  constructor({
    data,
    mediaType
  }) {
    const isUint8Array = data instanceof Uint8Array;
    this.base64Data = isUint8Array ? void 0 : data;
    this.uint8ArrayData = isUint8Array ? data : void 0;
    this.mediaType = mediaType;
  }
  // lazy conversion with caching to avoid unnecessary conversion overhead:
  get base64() {
    if (this.base64Data == null) {
      this.base64Data = convertUint8ArrayToBase64(this.uint8ArrayData);
    }
    return this.base64Data;
  }
  // lazy conversion with caching to avoid unnecessary conversion overhead:
  get uint8Array() {
    if (this.uint8ArrayData == null) {
      this.uint8ArrayData = convertBase64ToUint8Array(this.base64Data);
    }
    return this.uint8ArrayData;
  }
};
async function isApprovalNeeded({
  tool: tool2,
  toolCall,
  messages,
  experimental_context
}) {
  if (tool2.needsApproval == null) {
    return false;
  }
  if (typeof tool2.needsApproval === "boolean") {
    return tool2.needsApproval;
  }
  return await tool2.needsApproval(toolCall.input, {
    toolCallId: toolCall.toolCallId,
    messages,
    experimental_context
  });
}
var encoder = new TextEncoder();
function canonicalJSON(value) {
  if (value === null || value === void 0) {
    return JSON.stringify(value);
  }
  if (typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSON).join(",")}]`;
  }
  const keys = Object.keys(value).sort();
  const entries = keys.map(
    (k) => `${JSON.stringify(k)}:${canonicalJSON(value[k])}`
  );
  return `{${entries.join(",")}}`;
}
function toBase64url(bytes) {
  return convertUint8ArrayToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function fromBase64url(str) {
  return convertBase64ToUint8Array(str);
}
async function importKey(secret) {
  const keyData = typeof secret === "string" ? encoder.encode(secret) : secret;
  return crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}
async function hashInput(input) {
  const canonical = canonicalJSON(input);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(canonical)
  );
  return toBase64url(new Uint8Array(digest));
}
function buildPayload(approvalId, toolCallId, toolName, inputDigest) {
  return encoder.encode(
    `${approvalId}
${toolCallId}
${toolName}
${inputDigest}`
  );
}
async function signToolApproval({
  secret,
  approvalId,
  toolCallId,
  toolName,
  input
}) {
  const key = await importKey(secret);
  const inputDigest = await hashInput(input);
  const payload = buildPayload(approvalId, toolCallId, toolName, inputDigest);
  const sig = await crypto.subtle.sign("HMAC", key, payload);
  return toBase64url(new Uint8Array(sig));
}
async function verifyToolApprovalSignature({
  secret,
  signature,
  approvalId,
  toolCallId,
  toolName,
  input
}) {
  const key = await importKey(secret);
  const inputDigest = await hashInput(input);
  const payload = buildPayload(approvalId, toolCallId, toolName, inputDigest);
  const sigBytes = fromBase64url(signature);
  return crypto.subtle.verify("HMAC", key, sigBytes, payload);
}
async function maybeSignApproval({
  secret,
  approvalId,
  toolCallId,
  toolName,
  input
}) {
  if (secret == null)
    return void 0;
  return signToolApproval({ secret, approvalId, toolCallId, toolName, input });
}
async function validateApprovedToolApprovals({
  approvedToolApprovals,
  tools,
  messages,
  experimental_context,
  toolApprovalSecret
}) {
  var _a22;
  const approved = [];
  const denied = [];
  for (const approval of approvedToolApprovals) {
    const { toolCall, approvalRequest } = approval;
    const tool2 = tools == null ? void 0 : tools[toolCall.toolName];
    if (toolApprovalSecret != null) {
      if (approvalRequest.signature == null) {
        throw new InvalidToolApprovalSignatureError({
          approvalId: approvalRequest.approvalId,
          toolCallId: toolCall.toolCallId,
          reason: "missing signature"
        });
      }
      const valid = await verifyToolApprovalSignature({
        secret: toolApprovalSecret,
        signature: approvalRequest.signature,
        approvalId: approvalRequest.approvalId,
        toolCallId: toolCall.toolCallId,
        toolName: toolCall.toolName,
        input: toolCall.input
      });
      if (!valid) {
        throw new InvalidToolApprovalSignatureError({
          approvalId: approvalRequest.approvalId,
          toolCallId: toolCall.toolCallId,
          reason: "invalid signature"
        });
      }
    }
    if (tool2 != null && typeof tool2.execute === "function" && tool2.inputSchema != null) {
      const validation = await safeValidateTypes({
        value: toolCall.input,
        schema: asSchema(tool2.inputSchema)
      });
      if (!validation.success) {
        throw new InvalidToolInputError({
          toolName: toolCall.toolName,
          toolInput: JSON.stringify(toolCall.input),
          cause: validation.error
        });
      }
    }
    const approvalNeeded = tool2 != null && await isApprovalNeeded({
      tool: tool2,
      toolCall,
      messages,
      experimental_context
    });
    if (approvalNeeded) {
      approved.push(approval);
    } else {
      denied.push({
        ...approval,
        approvalResponse: {
          ...approval.approvalResponse,
          approved: false,
          reason: (_a22 = approval.approvalResponse.reason) != null ? _a22 : `Tool "${toolCall.toolName}" does not require approval`
        }
      });
    }
  }
  return { approvedToolApprovals: approved, deniedToolApprovals: denied };
}
var output_exports = {};
__export(output_exports, {
  array: () => array,
  choice: () => choice,
  json: () => json,
  object: () => object,
  text: () => text
});
function fixJson(input) {
  const stack = ["ROOT"];
  let lastValidIndex = -1;
  let literalStart = null;
  let unicodeEscapeDigits = 0;
  function isHexDigit(char) {
    return char >= "0" && char <= "9" || char >= "A" && char <= "F" || char >= "a" && char <= "f";
  }
  function processValueStart(char, i, swapState) {
    {
      switch (char) {
        case '"': {
          lastValidIndex = i;
          stack.pop();
          stack.push(swapState);
          stack.push("INSIDE_STRING");
          break;
        }
        case "f":
        case "t":
        case "n": {
          lastValidIndex = i;
          literalStart = i;
          stack.pop();
          stack.push(swapState);
          stack.push("INSIDE_LITERAL");
          break;
        }
        case "-": {
          stack.pop();
          stack.push(swapState);
          stack.push("INSIDE_NUMBER");
          break;
        }
        case "0":
        case "1":
        case "2":
        case "3":
        case "4":
        case "5":
        case "6":
        case "7":
        case "8":
        case "9": {
          lastValidIndex = i;
          stack.pop();
          stack.push(swapState);
          stack.push("INSIDE_NUMBER");
          break;
        }
        case "{": {
          lastValidIndex = i;
          stack.pop();
          stack.push(swapState);
          stack.push("INSIDE_OBJECT_START");
          break;
        }
        case "[": {
          lastValidIndex = i;
          stack.pop();
          stack.push(swapState);
          stack.push("INSIDE_ARRAY_START");
          break;
        }
      }
    }
  }
  function processAfterObjectValue(char, i) {
    switch (char) {
      case ",": {
        stack.pop();
        stack.push("INSIDE_OBJECT_AFTER_COMMA");
        break;
      }
      case "}": {
        lastValidIndex = i;
        stack.pop();
        break;
      }
    }
  }
  function processAfterArrayValue(char, i) {
    switch (char) {
      case ",": {
        stack.pop();
        stack.push("INSIDE_ARRAY_AFTER_COMMA");
        break;
      }
      case "]": {
        lastValidIndex = i;
        stack.pop();
        break;
      }
    }
  }
  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    const currentState = stack[stack.length - 1];
    switch (currentState) {
      case "ROOT":
        processValueStart(char, i, "FINISH");
        break;
      case "INSIDE_OBJECT_START": {
        switch (char) {
          case '"': {
            stack.pop();
            stack.push("INSIDE_OBJECT_KEY");
            break;
          }
          case "}": {
            lastValidIndex = i;
            stack.pop();
            break;
          }
        }
        break;
      }
      case "INSIDE_OBJECT_AFTER_COMMA": {
        switch (char) {
          case '"': {
            stack.pop();
            stack.push("INSIDE_OBJECT_KEY");
            break;
          }
        }
        break;
      }
      case "INSIDE_OBJECT_KEY": {
        switch (char) {
          case '"': {
            stack.pop();
            stack.push("INSIDE_OBJECT_AFTER_KEY");
            break;
          }
        }
        break;
      }
      case "INSIDE_OBJECT_AFTER_KEY": {
        switch (char) {
          case ":": {
            stack.pop();
            stack.push("INSIDE_OBJECT_BEFORE_VALUE");
            break;
          }
        }
        break;
      }
      case "INSIDE_OBJECT_BEFORE_VALUE": {
        processValueStart(char, i, "INSIDE_OBJECT_AFTER_VALUE");
        break;
      }
      case "INSIDE_OBJECT_AFTER_VALUE": {
        processAfterObjectValue(char, i);
        break;
      }
      case "INSIDE_STRING": {
        switch (char) {
          case '"': {
            stack.pop();
            lastValidIndex = i;
            break;
          }
          case "\\": {
            stack.push("INSIDE_STRING_ESCAPE");
            break;
          }
          default: {
            lastValidIndex = i;
          }
        }
        break;
      }
      case "INSIDE_ARRAY_START": {
        switch (char) {
          case "]": {
            lastValidIndex = i;
            stack.pop();
            break;
          }
          default: {
            lastValidIndex = i;
            processValueStart(char, i, "INSIDE_ARRAY_AFTER_VALUE");
            break;
          }
        }
        break;
      }
      case "INSIDE_ARRAY_AFTER_VALUE": {
        switch (char) {
          case ",": {
            stack.pop();
            stack.push("INSIDE_ARRAY_AFTER_COMMA");
            break;
          }
          case "]": {
            lastValidIndex = i;
            stack.pop();
            break;
          }
          default: {
            lastValidIndex = i;
            break;
          }
        }
        break;
      }
      case "INSIDE_ARRAY_AFTER_COMMA": {
        processValueStart(char, i, "INSIDE_ARRAY_AFTER_VALUE");
        break;
      }
      case "INSIDE_STRING_ESCAPE": {
        stack.pop();
        if (char === "u") {
          unicodeEscapeDigits = 0;
          stack.push("INSIDE_STRING_UNICODE_ESCAPE");
        } else {
          lastValidIndex = i;
        }
        break;
      }
      case "INSIDE_STRING_UNICODE_ESCAPE": {
        if (isHexDigit(char)) {
          unicodeEscapeDigits++;
          if (unicodeEscapeDigits === 4) {
            stack.pop();
            lastValidIndex = i;
          }
        }
        break;
      }
      case "INSIDE_NUMBER": {
        switch (char) {
          case "0":
          case "1":
          case "2":
          case "3":
          case "4":
          case "5":
          case "6":
          case "7":
          case "8":
          case "9": {
            lastValidIndex = i;
            break;
          }
          case "e":
          case "E":
          case "-":
          case ".": {
            break;
          }
          case ",": {
            stack.pop();
            if (stack[stack.length - 1] === "INSIDE_ARRAY_AFTER_VALUE") {
              processAfterArrayValue(char, i);
            }
            if (stack[stack.length - 1] === "INSIDE_OBJECT_AFTER_VALUE") {
              processAfterObjectValue(char, i);
            }
            break;
          }
          case "}": {
            stack.pop();
            if (stack[stack.length - 1] === "INSIDE_OBJECT_AFTER_VALUE") {
              processAfterObjectValue(char, i);
            }
            break;
          }
          case "]": {
            stack.pop();
            if (stack[stack.length - 1] === "INSIDE_ARRAY_AFTER_VALUE") {
              processAfterArrayValue(char, i);
            }
            break;
          }
          default: {
            stack.pop();
            break;
          }
        }
        break;
      }
      case "INSIDE_LITERAL": {
        const partialLiteral = input.substring(literalStart, i + 1);
        if (!"false".startsWith(partialLiteral) && !"true".startsWith(partialLiteral) && !"null".startsWith(partialLiteral)) {
          stack.pop();
          if (stack[stack.length - 1] === "INSIDE_OBJECT_AFTER_VALUE") {
            processAfterObjectValue(char, i);
          } else if (stack[stack.length - 1] === "INSIDE_ARRAY_AFTER_VALUE") {
            processAfterArrayValue(char, i);
          }
        } else {
          lastValidIndex = i;
        }
        break;
      }
    }
  }
  let result = input.slice(0, lastValidIndex + 1);
  for (let i = stack.length - 1; i >= 0; i--) {
    const state = stack[i];
    switch (state) {
      case "INSIDE_STRING": {
        result += '"';
        break;
      }
      case "INSIDE_OBJECT_KEY":
      case "INSIDE_OBJECT_AFTER_KEY":
      case "INSIDE_OBJECT_AFTER_COMMA":
      case "INSIDE_OBJECT_START":
      case "INSIDE_OBJECT_BEFORE_VALUE":
      case "INSIDE_OBJECT_AFTER_VALUE": {
        result += "}";
        break;
      }
      case "INSIDE_ARRAY_START":
      case "INSIDE_ARRAY_AFTER_COMMA":
      case "INSIDE_ARRAY_AFTER_VALUE": {
        result += "]";
        break;
      }
      case "INSIDE_LITERAL": {
        const partialLiteral = input.substring(literalStart, input.length);
        if ("true".startsWith(partialLiteral)) {
          result += "true".slice(partialLiteral.length);
        } else if ("false".startsWith(partialLiteral)) {
          result += "false".slice(partialLiteral.length);
        } else if ("null".startsWith(partialLiteral)) {
          result += "null".slice(partialLiteral.length);
        }
      }
    }
  }
  return result;
}
async function parsePartialJson(jsonText) {
  if (jsonText === void 0) {
    return { value: void 0, state: "undefined-input" };
  }
  let result = await safeParseJSON({ text: jsonText });
  if (result.success) {
    return { value: result.value, state: "successful-parse" };
  }
  result = await safeParseJSON({ text: fixJson(jsonText) });
  if (result.success) {
    return { value: result.value, state: "repaired-parse" };
  }
  return { value: void 0, state: "failed-parse" };
}
var text = () => ({
  name: "text",
  responseFormat: Promise.resolve({ type: "text" }),
  async parseCompleteOutput({ text: text2 }) {
    return text2;
  },
  async parsePartialOutput({ text: text2 }) {
    return { partial: text2 };
  },
  createElementStreamTransform() {
    return void 0;
  }
});
var object = ({
  schema: inputSchema,
  name: name22,
  description
}) => {
  const schema = asSchema(inputSchema);
  return {
    name: "object",
    responseFormat: resolve(schema.jsonSchema).then((jsonSchema2) => ({
      type: "json",
      schema: jsonSchema2,
      ...name22 != null && { name: name22 },
      ...description != null && { description }
    })),
    async parseCompleteOutput({ text: text2 }, context2) {
      const parseResult = await safeParseJSON({ text: text2 });
      if (!parseResult.success) {
        throw new NoObjectGeneratedError({
          message: "No object generated: could not parse the response.",
          cause: parseResult.error,
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      const validationResult = await safeValidateTypes({
        value: parseResult.value,
        schema
      });
      if (!validationResult.success) {
        throw new NoObjectGeneratedError({
          message: "No object generated: response did not match schema.",
          cause: validationResult.error,
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      return validationResult.value;
    },
    async parsePartialOutput({ text: text2 }) {
      const result = await parsePartialJson(text2);
      switch (result.state) {
        case "failed-parse":
        case "undefined-input": {
          return void 0;
        }
        case "repaired-parse":
        case "successful-parse": {
          return {
            // Note: currently no validation of partial results:
            partial: result.value
          };
        }
      }
    },
    createElementStreamTransform() {
      return void 0;
    }
  };
};
var array = ({
  element: inputElementSchema,
  name: name22,
  description
}) => {
  const elementSchema = asSchema(inputElementSchema);
  return {
    name: "array",
    // JSON schema that describes an array of elements:
    responseFormat: resolve(elementSchema.jsonSchema).then((jsonSchema2) => {
      const { $schema, ...itemSchema } = jsonSchema2;
      return {
        type: "json",
        schema: {
          $schema: "http://json-schema.org/draft-07/schema#",
          type: "object",
          properties: {
            elements: { type: "array", items: itemSchema }
          },
          required: ["elements"],
          additionalProperties: false
        },
        ...name22 != null && { name: name22 },
        ...description != null && { description }
      };
    }),
    async parseCompleteOutput({ text: text2 }, context2) {
      const parseResult = await safeParseJSON({ text: text2 });
      if (!parseResult.success) {
        throw new NoObjectGeneratedError({
          message: "No object generated: could not parse the response.",
          cause: parseResult.error,
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      const outerValue = parseResult.value;
      if (outerValue == null || typeof outerValue !== "object" || !("elements" in outerValue) || !Array.isArray(outerValue.elements)) {
        throw new NoObjectGeneratedError({
          message: "No object generated: response did not match schema.",
          cause: new TypeValidationError({
            value: outerValue,
            cause: "response must be an object with an elements array"
          }),
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      const validatedElements = [];
      for (const element of outerValue.elements) {
        const validationResult = await safeValidateTypes({
          value: element,
          schema: elementSchema
        });
        if (!validationResult.success) {
          throw new NoObjectGeneratedError({
            message: "No object generated: response did not match schema.",
            cause: validationResult.error,
            text: text2,
            response: context2.response,
            usage: context2.usage,
            finishReason: context2.finishReason
          });
        }
        validatedElements.push(validationResult.value);
      }
      return validatedElements;
    },
    async parsePartialOutput({ text: text2 }) {
      const result = await parsePartialJson(text2);
      switch (result.state) {
        case "failed-parse":
        case "undefined-input": {
          return void 0;
        }
        case "repaired-parse":
        case "successful-parse": {
          const outerValue = result.value;
          if (outerValue == null || typeof outerValue !== "object" || !("elements" in outerValue) || !Array.isArray(outerValue.elements)) {
            return void 0;
          }
          const rawElements = result.state === "repaired-parse" && outerValue.elements.length > 0 ? outerValue.elements.slice(0, -1) : outerValue.elements;
          const parsedElements = [];
          for (const rawElement of rawElements) {
            const validationResult = await safeValidateTypes({
              value: rawElement,
              schema: elementSchema
            });
            if (validationResult.success) {
              parsedElements.push(validationResult.value);
            }
          }
          return { partial: parsedElements };
        }
      }
    },
    createElementStreamTransform() {
      let publishedElements = 0;
      return new TransformStream({
        transform({ partialOutput }, controller) {
          if (partialOutput != null) {
            for (; publishedElements < partialOutput.length; publishedElements++) {
              controller.enqueue(partialOutput[publishedElements]);
            }
          }
        }
      });
    }
  };
};
var choice = ({
  options: choiceOptions,
  name: name22,
  description
}) => {
  return {
    name: "choice",
    // JSON schema that describes an enumeration:
    responseFormat: Promise.resolve({
      type: "json",
      schema: {
        $schema: "http://json-schema.org/draft-07/schema#",
        type: "object",
        properties: {
          result: { type: "string", enum: choiceOptions }
        },
        required: ["result"],
        additionalProperties: false
      },
      ...name22 != null && { name: name22 },
      ...description != null && { description }
    }),
    async parseCompleteOutput({ text: text2 }, context2) {
      const parseResult = await safeParseJSON({ text: text2 });
      if (!parseResult.success) {
        throw new NoObjectGeneratedError({
          message: "No object generated: could not parse the response.",
          cause: parseResult.error,
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      const outerValue = parseResult.value;
      if (outerValue == null || typeof outerValue !== "object" || !("result" in outerValue) || typeof outerValue.result !== "string" || !choiceOptions.includes(outerValue.result)) {
        throw new NoObjectGeneratedError({
          message: "No object generated: response did not match schema.",
          cause: new TypeValidationError({
            value: outerValue,
            cause: "response must be an object that contains a choice value."
          }),
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      return outerValue.result;
    },
    async parsePartialOutput({ text: text2 }) {
      const result = await parsePartialJson(text2);
      switch (result.state) {
        case "failed-parse":
        case "undefined-input": {
          return void 0;
        }
        case "repaired-parse":
        case "successful-parse": {
          const outerValue = result.value;
          if (outerValue == null || typeof outerValue !== "object" || !("result" in outerValue) || typeof outerValue.result !== "string") {
            return void 0;
          }
          const potentialMatches = choiceOptions.filter(
            (choiceOption) => choiceOption.startsWith(outerValue.result)
          );
          if (result.state === "successful-parse") {
            return potentialMatches.includes(outerValue.result) ? { partial: outerValue.result } : void 0;
          } else {
            return potentialMatches.length === 1 ? { partial: potentialMatches[0] } : void 0;
          }
        }
      }
    },
    createElementStreamTransform() {
      return void 0;
    }
  };
};
var json = ({
  name: name22,
  description
} = {}) => {
  return {
    name: "json",
    responseFormat: Promise.resolve({
      type: "json",
      ...name22 != null && { name: name22 },
      ...description != null && { description }
    }),
    async parseCompleteOutput({ text: text2 }, context2) {
      const parseResult = await safeParseJSON({ text: text2 });
      if (!parseResult.success) {
        throw new NoObjectGeneratedError({
          message: "No object generated: could not parse the response.",
          cause: parseResult.error,
          text: text2,
          response: context2.response,
          usage: context2.usage,
          finishReason: context2.finishReason
        });
      }
      return parseResult.value;
    },
    async parsePartialOutput({ text: text2 }) {
      const result = await parsePartialJson(text2);
      switch (result.state) {
        case "failed-parse":
        case "undefined-input": {
          return void 0;
        }
        case "repaired-parse":
        case "successful-parse": {
          return result.value === void 0 ? void 0 : { partial: result.value };
        }
      }
    },
    createElementStreamTransform() {
      return void 0;
    }
  };
};
async function parseToolCall({
  toolCall,
  tools,
  repairToolCall,
  system,
  messages
}) {
  try {
    if (tools == null) {
      if (toolCall.providerExecuted && toolCall.dynamic) {
        return await parseProviderExecutedDynamicToolCall(toolCall);
      }
      throw new NoSuchToolError({ toolName: toolCall.toolName });
    }
    try {
      return await doParseToolCall({ toolCall, tools });
    } catch (error) {
      if (repairToolCall == null || !(NoSuchToolError.isInstance(error) || InvalidToolInputError.isInstance(error))) {
        throw error;
      }
      let repairedToolCall = null;
      try {
        repairedToolCall = await repairToolCall({
          toolCall,
          tools,
          inputSchema: async ({ toolName }) => {
            const { inputSchema } = tools[toolName];
            return await asSchema(inputSchema).jsonSchema;
          },
          system,
          messages,
          error
        });
      } catch (repairError) {
        throw new ToolCallRepairError({
          cause: repairError,
          originalError: error
        });
      }
      if (repairedToolCall == null) {
        throw error;
      }
      return await doParseToolCall({ toolCall: repairedToolCall, tools });
    }
  } catch (error) {
    const parsedInput = await safeParseJSON({ text: toolCall.input });
    const input = parsedInput.success ? parsedInput.value : toolCall.input;
    const tool2 = tools == null ? void 0 : tools[toolCall.toolName];
    return {
      type: "tool-call",
      toolCallId: toolCall.toolCallId,
      toolName: toolCall.toolName,
      input,
      dynamic: true,
      invalid: true,
      error,
      title: tool2 == null ? void 0 : tool2.title,
      providerExecuted: toolCall.providerExecuted,
      providerMetadata: toolCall.providerMetadata,
      ...(tool2 == null ? void 0 : tool2.metadata) != null ? { toolMetadata: tool2.metadata } : {}
    };
  }
}
async function parseProviderExecutedDynamicToolCall(toolCall) {
  const parseResult = toolCall.input.trim() === "" ? { success: true, value: {} } : await safeParseJSON({ text: toolCall.input });
  if (parseResult.success === false) {
    throw new InvalidToolInputError({
      toolName: toolCall.toolName,
      toolInput: toolCall.input,
      cause: parseResult.error
    });
  }
  return {
    type: "tool-call",
    toolCallId: toolCall.toolCallId,
    toolName: toolCall.toolName,
    input: parseResult.value,
    providerExecuted: true,
    dynamic: true,
    providerMetadata: toolCall.providerMetadata
  };
}
async function doParseToolCall({
  toolCall,
  tools
}) {
  const toolName = toolCall.toolName;
  const tool2 = tools[toolName];
  if (tool2 == null) {
    if (toolCall.providerExecuted && toolCall.dynamic) {
      return await parseProviderExecutedDynamicToolCall(toolCall);
    }
    throw new NoSuchToolError({
      toolName: toolCall.toolName,
      availableTools: Object.keys(tools)
    });
  }
  const schema = asSchema(tool2.inputSchema);
  const parseResult = toolCall.input.trim() === "" ? await safeValidateTypes({ value: {}, schema }) : await safeParseJSON({ text: toolCall.input, schema });
  if (parseResult.success === false) {
    throw new InvalidToolInputError({
      toolName,
      toolInput: toolCall.input,
      cause: parseResult.error
    });
  }
  return tool2.type === "dynamic" ? {
    type: "tool-call",
    toolCallId: toolCall.toolCallId,
    toolName: toolCall.toolName,
    input: parseResult.value,
    providerExecuted: toolCall.providerExecuted,
    providerMetadata: toolCall.providerMetadata,
    ...tool2.metadata != null ? { toolMetadata: tool2.metadata } : {},
    dynamic: true,
    title: tool2.title
  } : {
    type: "tool-call",
    toolCallId: toolCall.toolCallId,
    toolName,
    input: parseResult.value,
    providerExecuted: toolCall.providerExecuted,
    providerMetadata: toolCall.providerMetadata,
    ...tool2.metadata != null ? { toolMetadata: tool2.metadata } : {},
    title: tool2.title
  };
}
function prepareStepCallSettings({
  callSettings,
  stepSettings
}) {
  var _a22, _b, _c, _d, _e, _f, _g, _h;
  return prepareCallSettings({
    maxOutputTokens: (_a22 = stepSettings == null ? void 0 : stepSettings.maxOutputTokens) != null ? _a22 : callSettings.maxOutputTokens,
    temperature: (_b = stepSettings == null ? void 0 : stepSettings.temperature) != null ? _b : callSettings.temperature,
    topP: (_c = stepSettings == null ? void 0 : stepSettings.topP) != null ? _c : callSettings.topP,
    topK: (_d = stepSettings == null ? void 0 : stepSettings.topK) != null ? _d : callSettings.topK,
    presencePenalty: (_e = stepSettings == null ? void 0 : stepSettings.presencePenalty) != null ? _e : callSettings.presencePenalty,
    frequencyPenalty: (_f = stepSettings == null ? void 0 : stepSettings.frequencyPenalty) != null ? _f : callSettings.frequencyPenalty,
    stopSequences: (_g = stepSettings == null ? void 0 : stepSettings.stopSequences) != null ? _g : callSettings.stopSequences,
    seed: (_h = stepSettings == null ? void 0 : stepSettings.seed) != null ? _h : callSettings.seed
  });
}
var DefaultStepResult = class {
  constructor({
    stepNumber,
    model,
    functionId,
    metadata,
    experimental_context,
    content,
    finishReason,
    rawFinishReason,
    usage,
    warnings,
    request,
    response,
    providerMetadata
  }) {
    this.stepNumber = stepNumber;
    this.model = model;
    this.functionId = functionId;
    this.metadata = metadata;
    this.experimental_context = experimental_context;
    this.content = content;
    this.finishReason = finishReason;
    this.rawFinishReason = rawFinishReason;
    this.usage = usage;
    this.warnings = warnings;
    this.request = request;
    this.response = response;
    this.providerMetadata = providerMetadata;
  }
  get text() {
    return this.content.filter((part) => part.type === "text").map((part) => part.text).join("");
  }
  get reasoning() {
    return this.content.filter((part) => part.type === "reasoning");
  }
  get reasoningText() {
    return this.reasoning.length === 0 ? void 0 : this.reasoning.map((part) => part.text).join("");
  }
  get files() {
    return this.content.filter((part) => part.type === "file").map((part) => part.file);
  }
  get sources() {
    return this.content.filter((part) => part.type === "source");
  }
  get toolCalls() {
    return this.content.filter((part) => part.type === "tool-call");
  }
  get staticToolCalls() {
    return this.toolCalls.filter(
      (toolCall) => toolCall.dynamic !== true
    );
  }
  get dynamicToolCalls() {
    return this.toolCalls.filter(
      (toolCall) => toolCall.dynamic === true
    );
  }
  get toolResults() {
    return this.content.filter((part) => part.type === "tool-result");
  }
  get staticToolResults() {
    return this.toolResults.filter(
      (toolResult) => toolResult.dynamic !== true
    );
  }
  get dynamicToolResults() {
    return this.toolResults.filter(
      (toolResult) => toolResult.dynamic === true
    );
  }
};
function stepCountIs(stepCount) {
  return ({ steps }) => steps.length === stepCount;
}
async function isStopConditionMet({
  stopConditions,
  steps
}) {
  return (await Promise.all(stopConditions.map((condition) => condition({ steps })))).some((result) => result);
}
async function toResponseMessages({
  content: inputContent,
  tools
}) {
  const responseMessages = [];
  const toolCallOrder = /* @__PURE__ */ new Map();
  const content = [];
  for (const part of inputContent) {
    if (part.type === "source") {
      continue;
    }
    if ((part.type === "tool-result" || part.type === "tool-error") && !part.providerExecuted) {
      continue;
    }
    if (part.type === "text" && part.text.length === 0) {
      continue;
    }
    switch (part.type) {
      case "text":
        content.push({
          type: "text",
          text: part.text,
          providerOptions: part.providerMetadata
        });
        break;
      case "reasoning":
        content.push({
          type: "reasoning",
          text: part.text,
          providerOptions: part.providerMetadata
        });
        break;
      case "file":
        content.push({
          type: "file",
          data: part.file.base64,
          mediaType: part.file.mediaType,
          providerOptions: part.providerMetadata
        });
        break;
      case "tool-call":
        if (!toolCallOrder.has(part.toolCallId)) {
          toolCallOrder.set(part.toolCallId, toolCallOrder.size);
        }
        content.push({
          type: "tool-call",
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          input: part.invalid && typeof part.input !== "object" ? {} : part.input,
          providerExecuted: part.providerExecuted,
          providerOptions: part.providerMetadata
        });
        break;
      case "tool-result": {
        const output = await createToolModelOutput({
          toolCallId: part.toolCallId,
          input: part.input,
          tool: tools == null ? void 0 : tools[part.toolName],
          output: part.output,
          errorMode: "none"
        });
        content.push({
          type: "tool-result",
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          output,
          providerOptions: part.providerMetadata
        });
        break;
      }
      case "tool-error": {
        const output = await createToolModelOutput({
          toolCallId: part.toolCallId,
          input: part.input,
          tool: tools == null ? void 0 : tools[part.toolName],
          output: part.error,
          errorMode: "json"
        });
        content.push({
          type: "tool-result",
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          output,
          providerOptions: part.providerMetadata
        });
        break;
      }
      case "tool-approval-request":
        content.push({
          type: "tool-approval-request",
          approvalId: part.approvalId,
          toolCallId: part.toolCall.toolCallId,
          ...part.signature != null ? { signature: part.signature } : {}
        });
        break;
    }
  }
  if (content.length > 0) {
    responseMessages.push({
      role: "assistant",
      content
    });
  }
  const toolResultContent = [];
  for (const part of inputContent) {
    if (!(part.type === "tool-result" || part.type === "tool-error") || part.providerExecuted) {
      continue;
    }
    const output = await createToolModelOutput({
      toolCallId: part.toolCallId,
      input: part.input,
      tool: tools == null ? void 0 : tools[part.toolName],
      output: part.type === "tool-result" ? part.output : part.error,
      errorMode: part.type === "tool-error" ? "text" : "none"
    });
    toolResultContent.push({
      type: "tool-result",
      toolCallId: part.toolCallId,
      toolName: part.toolName,
      output,
      ...part.providerMetadata != null ? { providerOptions: part.providerMetadata } : {}
    });
  }
  if (toolResultContent.length > 0) {
    responseMessages.push({
      role: "tool",
      content: sortToolResultContentByToolCallOrder({
        toolResultContent,
        toolCallOrder
      })
    });
  }
  return responseMessages;
}
function sortToolResultContentByToolCallOrder({
  toolResultContent,
  toolCallOrder
}) {
  const sortedToolResults = toolResultContent.filter((part) => part.type === "tool-result").map((part, index) => ({ part, index })).sort((a, b) => {
    const aOrder = toolCallOrder.get(a.part.toolCallId);
    const bOrder = toolCallOrder.get(b.part.toolCallId);
    if (aOrder == null && bOrder == null) {
      return a.index - b.index;
    }
    if (aOrder == null) {
      return 1;
    }
    if (bOrder == null) {
      return -1;
    }
    return aOrder - bOrder || a.index - b.index;
  }).map(({ part }) => part);
  let toolResultIndex = 0;
  return toolResultContent.map(
    (part) => part.type === "tool-result" ? sortedToolResults[toolResultIndex++] : part
  );
}
function mergeAbortSignals(...signals) {
  const validSignals = signals.filter(
    (signal) => signal != null
  );
  if (validSignals.length === 0) {
    return void 0;
  }
  if (validSignals.length === 1) {
    return validSignals[0];
  }
  const controller = new AbortController();
  for (const signal of validSignals) {
    if (signal.aborted) {
      controller.abort(signal.reason);
      return controller.signal;
    }
    signal.addEventListener(
      "abort",
      () => {
        controller.abort(signal.reason);
      },
      { once: true }
    );
  }
  return controller.signal;
}
var originalGenerateId = createIdGenerator({
  prefix: "aitxt",
  size: 24
});
async function generateText({
  model: modelArg,
  tools,
  toolChoice,
  system,
  prompt,
  messages,
  allowSystemInMessages,
  maxRetries: maxRetriesArg,
  abortSignal,
  timeout,
  headers,
  stopWhen = stepCountIs(1),
  experimental_output,
  output = experimental_output,
  experimental_telemetry: telemetry,
  providerOptions,
  experimental_activeTools,
  activeTools = experimental_activeTools,
  experimental_prepareStep,
  prepareStep = experimental_prepareStep,
  experimental_repairToolCall: repairToolCall,
  experimental_download: download2,
  experimental_context,
  experimental_toolApprovalSecret,
  experimental_include: include,
  _internal: { generateId: generateId2 = originalGenerateId } = {},
  experimental_onStart: onStart,
  experimental_onStepStart: onStepStart,
  experimental_onToolCallStart: onToolCallStart,
  experimental_onToolCallFinish: onToolCallFinish,
  onStepFinish,
  onFinish,
  ...settings
}) {
  const model = resolveLanguageModel(modelArg);
  const createGlobalTelemetry = getGlobalTelemetryIntegration();
  const stopConditions = asArray(stopWhen);
  const totalTimeoutMs = getTotalTimeoutMs(timeout);
  const stepTimeoutMs = getStepTimeoutMs(timeout);
  const stepAbortController = stepTimeoutMs != null ? new AbortController() : void 0;
  const mergedAbortSignal = mergeAbortSignals(
    abortSignal,
    totalTimeoutMs != null ? AbortSignal.timeout(totalTimeoutMs) : void 0,
    stepAbortController == null ? void 0 : stepAbortController.signal
  );
  const { maxRetries, retry } = prepareRetries({
    maxRetries: maxRetriesArg,
    abortSignal: mergedAbortSignal
  });
  const callSettings = prepareCallSettings(settings);
  const headersWithUserAgent = withUserAgentSuffix(
    headers != null ? headers : {},
    `ai/${VERSION}`
  );
  const baseTelemetryAttributes = getBaseTelemetryAttributes({
    model,
    telemetry,
    headers: headersWithUserAgent,
    settings: { ...callSettings, maxRetries }
  });
  const modelInfo = { provider: model.provider, modelId: model.modelId };
  const initialPrompt = await standardizePrompt({
    system,
    prompt,
    messages,
    allowSystemInMessages
  });
  const globalTelemetry = createGlobalTelemetry(telemetry == null ? void 0 : telemetry.integrations);
  await notify({
    event: {
      model: modelInfo,
      system,
      prompt,
      messages,
      tools,
      toolChoice,
      activeTools,
      maxOutputTokens: callSettings.maxOutputTokens,
      temperature: callSettings.temperature,
      topP: callSettings.topP,
      topK: callSettings.topK,
      presencePenalty: callSettings.presencePenalty,
      frequencyPenalty: callSettings.frequencyPenalty,
      stopSequences: callSettings.stopSequences,
      seed: callSettings.seed,
      maxRetries,
      timeout,
      headers,
      providerOptions,
      stopWhen,
      output,
      abortSignal,
      include,
      functionId: telemetry == null ? void 0 : telemetry.functionId,
      metadata: telemetry == null ? void 0 : telemetry.metadata,
      experimental_context
    },
    callbacks: [
      onStart,
      globalTelemetry.onStart
    ]
  });
  const tracer = getTracer(telemetry);
  try {
    return await recordSpan({
      name: "ai.generateText",
      attributes: selectTelemetryAttributes({
        telemetry,
        attributes: {
          ...assembleOperationName({
            operationId: "ai.generateText",
            telemetry
          }),
          ...baseTelemetryAttributes,
          // model:
          "ai.model.provider": model.provider,
          "ai.model.id": model.modelId,
          // specific settings that only make sense on the outer level:
          "ai.prompt": {
            input: () => JSON.stringify({ system, prompt, messages })
          }
        }
      }),
      tracer,
      fn: async (span) => {
        var _a22, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t;
        const initialMessages = initialPrompt.messages;
        const responseMessages = [];
        const {
          approvedToolApprovals,
          deniedToolApprovals: collectedDeniedToolApprovals
        } = collectToolApprovals({ messages: initialMessages });
        const {
          approvedToolApprovals: localApprovedToolApprovals,
          deniedToolApprovals: revalidationDeniedToolApprovals
        } = await validateApprovedToolApprovals({
          approvedToolApprovals: approvedToolApprovals.filter(
            (toolApproval) => !toolApproval.toolCall.providerExecuted
          ),
          tools,
          messages: initialMessages,
          experimental_context,
          toolApprovalSecret: experimental_toolApprovalSecret
        });
        const deniedToolApprovals = [
          ...collectedDeniedToolApprovals,
          ...revalidationDeniedToolApprovals
        ];
        if (deniedToolApprovals.length > 0 || localApprovedToolApprovals.length > 0) {
          const toolOutputs = await executeTools({
            toolCalls: localApprovedToolApprovals.map(
              (toolApproval) => toolApproval.toolCall
            ),
            tools,
            tracer,
            telemetry,
            messages: initialMessages,
            abortSignal: mergedAbortSignal,
            experimental_context,
            stepNumber: 0,
            model: modelInfo,
            onToolCallStart: [
              onToolCallStart,
              globalTelemetry.onToolCallStart
            ],
            onToolCallFinish: [
              onToolCallFinish,
              globalTelemetry.onToolCallFinish
            ]
          });
          const toolContent = [];
          for (const output2 of toolOutputs) {
            const modelOutput = await createToolModelOutput({
              toolCallId: output2.toolCallId,
              input: output2.input,
              tool: tools == null ? void 0 : tools[output2.toolName],
              output: output2.type === "tool-result" ? output2.output : output2.error,
              errorMode: output2.type === "tool-error" ? "text" : "none"
            });
            toolContent.push({
              type: "tool-result",
              toolCallId: output2.toolCallId,
              toolName: output2.toolName,
              output: modelOutput
            });
          }
          for (const toolApproval of deniedToolApprovals) {
            toolContent.push({
              type: "tool-result",
              toolCallId: toolApproval.toolCall.toolCallId,
              toolName: toolApproval.toolCall.toolName,
              output: {
                type: "execution-denied",
                reason: toolApproval.approvalResponse.reason,
                // For provider-executed tools, include approvalId so provider can correlate
                ...toolApproval.toolCall.providerExecuted && {
                  providerOptions: {
                    openai: {
                      approvalId: toolApproval.approvalResponse.approvalId
                    }
                  }
                }
              }
            });
          }
          responseMessages.push({
            role: "tool",
            content: toolContent
          });
        }
        const callSettings2 = prepareCallSettings(settings);
        let currentModelResponse;
        let clientToolCalls = [];
        let clientToolOutputs = [];
        const steps = [];
        const pendingDeferredToolCalls = /* @__PURE__ */ new Map();
        do {
          if (steps.length > 0) {
            mergedAbortSignal == null ? void 0 : mergedAbortSignal.throwIfAborted();
          }
          const stepTimeoutId = setAbortTimeout({
            abortController: stepAbortController,
            label: "Step",
            timeoutMs: stepTimeoutMs
          });
          try {
            const stepInputMessages = [...initialMessages, ...responseMessages];
            const prepareStepResult = await (prepareStep == null ? void 0 : prepareStep({
              model,
              steps,
              stepNumber: steps.length,
              messages: stepInputMessages,
              experimental_context
            }));
            const stepModel = resolveLanguageModel(
              (_a22 = prepareStepResult == null ? void 0 : prepareStepResult.model) != null ? _a22 : model
            );
            const stepModelInfo = {
              provider: stepModel.provider,
              modelId: stepModel.modelId
            };
            const promptMessages = await convertToLanguageModelPrompt({
              prompt: {
                system: (_b = prepareStepResult == null ? void 0 : prepareStepResult.system) != null ? _b : initialPrompt.system,
                messages: (_c = prepareStepResult == null ? void 0 : prepareStepResult.messages) != null ? _c : stepInputMessages
              },
              supportedUrls: await stepModel.supportedUrls,
              download: download2
            });
            experimental_context = (_d = prepareStepResult == null ? void 0 : prepareStepResult.experimental_context) != null ? _d : experimental_context;
            const stepActiveTools = (_e = prepareStepResult == null ? void 0 : prepareStepResult.activeTools) != null ? _e : activeTools;
            const stepToolSet = filterActiveTools({
              tools,
              activeTools: stepActiveTools
            });
            const { toolChoice: stepToolChoice, tools: stepTools } = await prepareToolsAndToolChoice({
              tools,
              toolChoice: (_f = prepareStepResult == null ? void 0 : prepareStepResult.toolChoice) != null ? _f : toolChoice,
              activeTools: stepActiveTools
            });
            const stepMessages = (_g = prepareStepResult == null ? void 0 : prepareStepResult.messages) != null ? _g : stepInputMessages;
            const stepSystem = (_h = prepareStepResult == null ? void 0 : prepareStepResult.system) != null ? _h : initialPrompt.system;
            const stepProviderOptions = mergeObjects(
              providerOptions,
              prepareStepResult == null ? void 0 : prepareStepResult.providerOptions
            );
            const stepCallSettings = prepareStepCallSettings({
              callSettings: callSettings2,
              stepSettings: prepareStepResult
            });
            await notify({
              event: {
                stepNumber: steps.length,
                model: stepModelInfo,
                system: stepSystem,
                messages: stepMessages,
                tools,
                toolChoice: stepToolChoice,
                activeTools: stepActiveTools,
                steps: [...steps],
                providerOptions: stepProviderOptions,
                timeout,
                headers,
                stopWhen,
                output,
                abortSignal,
                include,
                functionId: telemetry == null ? void 0 : telemetry.functionId,
                metadata: telemetry == null ? void 0 : telemetry.metadata,
                experimental_context
              },
              callbacks: [
                onStepStart,
                globalTelemetry.onStepStart
              ]
            });
            currentModelResponse = await retry(
              () => recordSpan({
                name: "ai.generateText.doGenerate",
                attributes: selectTelemetryAttributes({
                  telemetry,
                  attributes: {
                    ...assembleOperationName({
                      operationId: "ai.generateText.doGenerate",
                      telemetry
                    }),
                    ...baseTelemetryAttributes,
                    // model:
                    "ai.model.provider": stepModel.provider,
                    "ai.model.id": stepModel.modelId,
                    // prompt:
                    "ai.prompt.messages": {
                      input: () => stringifyForTelemetry(promptMessages)
                    },
                    "ai.prompt.tools": {
                      // convert the language model level tools:
                      input: () => stepTools == null ? void 0 : stepTools.map((tool2) => JSON.stringify(tool2))
                    },
                    "ai.prompt.toolChoice": {
                      input: () => stepToolChoice != null ? JSON.stringify(stepToolChoice) : void 0
                    },
                    // standardized gen-ai llm span attributes:
                    "gen_ai.system": stepModel.provider,
                    "gen_ai.request.model": stepModel.modelId,
                    "gen_ai.request.frequency_penalty": stepCallSettings.frequencyPenalty,
                    "gen_ai.request.max_tokens": stepCallSettings.maxOutputTokens,
                    "gen_ai.request.presence_penalty": stepCallSettings.presencePenalty,
                    "gen_ai.request.stop_sequences": stepCallSettings.stopSequences,
                    "gen_ai.request.temperature": stepCallSettings.temperature,
                    "gen_ai.request.top_k": stepCallSettings.topK,
                    "gen_ai.request.top_p": stepCallSettings.topP
                  }
                }),
                tracer,
                fn: async (span2) => {
                  var _a23, _b2, _c2, _d2, _e2, _f2, _g2, _h2;
                  const result = await stepModel.doGenerate({
                    ...stepCallSettings,
                    tools: stepTools,
                    toolChoice: stepToolChoice,
                    responseFormat: await (output == null ? void 0 : output.responseFormat),
                    prompt: promptMessages,
                    providerOptions: stepProviderOptions,
                    abortSignal: mergedAbortSignal,
                    headers: headersWithUserAgent
                  });
                  const responseData = {
                    id: (_b2 = (_a23 = result.response) == null ? void 0 : _a23.id) != null ? _b2 : generateId2(),
                    timestamp: (_d2 = (_c2 = result.response) == null ? void 0 : _c2.timestamp) != null ? _d2 : /* @__PURE__ */ new Date(),
                    modelId: (_f2 = (_e2 = result.response) == null ? void 0 : _e2.modelId) != null ? _f2 : stepModel.modelId,
                    headers: (_g2 = result.response) == null ? void 0 : _g2.headers,
                    body: (_h2 = result.response) == null ? void 0 : _h2.body
                  };
                  const usage = asLanguageModelUsage(result.usage);
                  span2.setAttributes(
                    await selectTelemetryAttributes({
                      telemetry,
                      attributes: {
                        "ai.response.finishReason": result.finishReason.unified,
                        "ai.response.text": {
                          output: () => extractTextContent(result.content)
                        },
                        "ai.response.reasoning": {
                          output: () => extractReasoningContent(result.content)
                        },
                        "ai.response.toolCalls": {
                          output: () => {
                            const toolCalls = asToolCalls(result.content);
                            return toolCalls == null ? void 0 : JSON.stringify(toolCalls);
                          }
                        },
                        "ai.response.id": responseData.id,
                        "ai.response.model": responseData.modelId,
                        "ai.response.timestamp": responseData.timestamp.toISOString(),
                        "ai.response.providerMetadata": JSON.stringify(
                          result.providerMetadata
                        ),
                        "ai.usage.inputTokens": result.usage.inputTokens.total,
                        "ai.usage.inputTokenDetails.noCacheTokens": result.usage.inputTokens.noCache,
                        "ai.usage.inputTokenDetails.cacheReadTokens": result.usage.inputTokens.cacheRead,
                        "ai.usage.inputTokenDetails.cacheWriteTokens": result.usage.inputTokens.cacheWrite,
                        "ai.usage.outputTokens": result.usage.outputTokens.total,
                        "ai.usage.outputTokenDetails.textTokens": result.usage.outputTokens.text,
                        "ai.usage.outputTokenDetails.reasoningTokens": result.usage.outputTokens.reasoning,
                        "ai.usage.totalTokens": usage.totalTokens,
                        "ai.usage.reasoningTokens": result.usage.outputTokens.reasoning,
                        "ai.usage.cachedInputTokens": result.usage.inputTokens.cacheRead,
                        // standardized gen-ai llm span attributes:
                        "gen_ai.response.finish_reasons": [
                          result.finishReason.unified
                        ],
                        "gen_ai.response.id": responseData.id,
                        "gen_ai.response.model": responseData.modelId,
                        "gen_ai.usage.input_tokens": result.usage.inputTokens.total,
                        "gen_ai.usage.output_tokens": result.usage.outputTokens.total
                      }
                    })
                  );
                  return { ...result, response: responseData };
                }
              })
            );
            const stepToolCalls = await Promise.all(
              currentModelResponse.content.filter(
                (part) => part.type === "tool-call"
              ).map(
                (toolCall) => parseToolCall({
                  toolCall,
                  tools: stepToolSet,
                  repairToolCall,
                  system,
                  messages: stepInputMessages
                })
              )
            );
            const toolApprovalRequests = {};
            for (const toolCall of stepToolCalls) {
              if (toolCall.invalid) {
                continue;
              }
              const tool2 = stepToolSet == null ? void 0 : stepToolSet[toolCall.toolName];
              if (tool2 == null) {
                continue;
              }
              if (tool2.onInputStart != null) {
                await tool2.onInputStart({
                  toolCallId: toolCall.toolCallId,
                  messages: stepInputMessages,
                  abortSignal: mergedAbortSignal,
                  experimental_context
                });
              }
              if (tool2.onInputAvailable != null) {
                await tool2.onInputAvailable({
                  input: toolCall.input,
                  toolCallId: toolCall.toolCallId,
                  messages: stepInputMessages,
                  abortSignal: mergedAbortSignal,
                  experimental_context
                });
              }
              if (await isApprovalNeeded({
                tool: tool2,
                toolCall,
                messages: stepInputMessages,
                experimental_context
              })) {
                const approvalId = generateId2();
                const signature = await maybeSignApproval({
                  secret: experimental_toolApprovalSecret,
                  approvalId,
                  toolCallId: toolCall.toolCallId,
                  toolName: toolCall.toolName,
                  input: toolCall.input
                });
                toolApprovalRequests[toolCall.toolCallId] = {
                  type: "tool-approval-request",
                  approvalId,
                  toolCall,
                  ...signature != null ? { signature } : {}
                };
              }
            }
            const invalidToolCalls = stepToolCalls.filter(
              (toolCall) => toolCall.invalid && toolCall.dynamic && !toolCall.providerExecuted
            );
            clientToolOutputs = [];
            for (const toolCall of invalidToolCalls) {
              clientToolOutputs.push({
                type: "tool-error",
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                input: toolCall.input,
                error: getErrorMessage(toolCall.error),
                dynamic: true
              });
            }
            clientToolCalls = stepToolCalls.filter(
              (toolCall) => !toolCall.providerExecuted
            );
            if (stepToolSet != null) {
              clientToolOutputs.push(
                ...await executeTools({
                  toolCalls: clientToolCalls.filter(
                    (toolCall) => !toolCall.invalid && toolApprovalRequests[toolCall.toolCallId] == null
                  ),
                  tools: stepToolSet,
                  tracer,
                  telemetry,
                  messages: stepInputMessages,
                  abortSignal: mergedAbortSignal,
                  experimental_context,
                  stepNumber: steps.length,
                  model: stepModelInfo,
                  onToolCallStart: [
                    onToolCallStart,
                    globalTelemetry.onToolCallStart
                  ],
                  onToolCallFinish: [
                    onToolCallFinish,
                    globalTelemetry.onToolCallFinish
                  ]
                })
              );
            }
            for (const toolCall of stepToolCalls) {
              if (!toolCall.providerExecuted)
                continue;
              const tool2 = stepToolSet == null ? void 0 : stepToolSet[toolCall.toolName];
              if ((tool2 == null ? void 0 : tool2.type) === "provider" && tool2.supportsDeferredResults) {
                const hasResultInResponse = currentModelResponse.content.some(
                  (part) => part.type === "tool-result" && part.toolCallId === toolCall.toolCallId
                );
                if (!hasResultInResponse) {
                  pendingDeferredToolCalls.set(toolCall.toolCallId, {
                    toolName: toolCall.toolName
                  });
                }
              }
            }
            for (const part of currentModelResponse.content) {
              if (part.type === "tool-result") {
                pendingDeferredToolCalls.delete(part.toolCallId);
              }
            }
            const stepContent = asContent({
              content: currentModelResponse.content,
              toolCalls: stepToolCalls,
              toolOutputs: clientToolOutputs,
              toolApprovalRequests: Object.values(toolApprovalRequests),
              tools: stepToolSet
            });
            responseMessages.push(
              ...await toResponseMessages({
                content: stepContent,
                tools: stepToolSet
              })
            );
            const stepRequest = ((_i = include == null ? void 0 : include.requestBody) != null ? _i : true) ? (_j = currentModelResponse.request) != null ? _j : {} : { ...currentModelResponse.request, body: void 0 };
            const stepResponse = {
              ...currentModelResponse.response,
              // deep clone msgs to avoid mutating past messages in multi-step:
              messages: structuredClone(responseMessages),
              // Conditionally include response body:
              body: ((_k = include == null ? void 0 : include.responseBody) != null ? _k : true) ? (_l = currentModelResponse.response) == null ? void 0 : _l.body : void 0
            };
            const stepNumber = steps.length;
            const currentStepResult = new DefaultStepResult({
              stepNumber,
              model: stepModelInfo,
              functionId: telemetry == null ? void 0 : telemetry.functionId,
              metadata: telemetry == null ? void 0 : telemetry.metadata,
              experimental_context,
              content: stepContent,
              finishReason: currentModelResponse.finishReason.unified,
              rawFinishReason: currentModelResponse.finishReason.raw,
              usage: asLanguageModelUsage(currentModelResponse.usage),
              warnings: currentModelResponse.warnings,
              providerMetadata: currentModelResponse.providerMetadata,
              request: stepRequest,
              response: stepResponse
            });
            logWarnings({
              warnings: (_m = currentModelResponse.warnings) != null ? _m : [],
              provider: stepModelInfo.provider,
              model: stepModelInfo.modelId
            });
            steps.push(currentStepResult);
            await notify({
              event: currentStepResult,
              callbacks: [onStepFinish, globalTelemetry.onStepFinish]
            });
          } finally {
            if (stepTimeoutId != null) {
              clearTimeout(stepTimeoutId);
            }
          }
        } while (
          // Continue if:
          // 1. There are client tool calls that have all been executed, OR
          // 2. There are pending deferred results from provider-executed tools
          (clientToolCalls.length > 0 && clientToolOutputs.length === clientToolCalls.length || pendingDeferredToolCalls.size > 0) && // continue until a stop condition is met:
          !await isStopConditionMet({ stopConditions, steps })
        );
        span.setAttributes(
          await selectTelemetryAttributes({
            telemetry,
            attributes: {
              "ai.response.finishReason": currentModelResponse.finishReason.unified,
              "ai.response.text": {
                output: () => extractTextContent(currentModelResponse.content)
              },
              "ai.response.reasoning": {
                output: () => extractReasoningContent(currentModelResponse.content)
              },
              "ai.response.toolCalls": {
                output: () => {
                  const toolCalls = asToolCalls(currentModelResponse.content);
                  return toolCalls == null ? void 0 : JSON.stringify(toolCalls);
                }
              },
              "ai.response.providerMetadata": JSON.stringify(
                currentModelResponse.providerMetadata
              )
            }
          })
        );
        const lastStep = steps[steps.length - 1];
        const totalUsage = steps.reduce(
          (totalUsage2, step) => {
            return addLanguageModelUsage(totalUsage2, step.usage);
          },
          {
            inputTokens: void 0,
            outputTokens: void 0,
            totalTokens: void 0,
            reasoningTokens: void 0,
            cachedInputTokens: void 0
          }
        );
        span.setAttributes(
          await selectTelemetryAttributes({
            telemetry,
            attributes: {
              "ai.usage.inputTokens": totalUsage.inputTokens,
              "ai.usage.inputTokenDetails.noCacheTokens": (_n = totalUsage.inputTokenDetails) == null ? void 0 : _n.noCacheTokens,
              "ai.usage.inputTokenDetails.cacheReadTokens": (_o = totalUsage.inputTokenDetails) == null ? void 0 : _o.cacheReadTokens,
              "ai.usage.inputTokenDetails.cacheWriteTokens": (_p = totalUsage.inputTokenDetails) == null ? void 0 : _p.cacheWriteTokens,
              "ai.usage.outputTokens": totalUsage.outputTokens,
              "ai.usage.outputTokenDetails.textTokens": (_q = totalUsage.outputTokenDetails) == null ? void 0 : _q.textTokens,
              "ai.usage.outputTokenDetails.reasoningTokens": (_r = totalUsage.outputTokenDetails) == null ? void 0 : _r.reasoningTokens,
              "ai.usage.totalTokens": totalUsage.totalTokens,
              "ai.usage.reasoningTokens": (_s = totalUsage.outputTokenDetails) == null ? void 0 : _s.reasoningTokens,
              "ai.usage.cachedInputTokens": (_t = totalUsage.inputTokenDetails) == null ? void 0 : _t.cacheReadTokens
            }
          })
        );
        await notify({
          event: {
            stepNumber: lastStep.stepNumber,
            model: lastStep.model,
            functionId: lastStep.functionId,
            metadata: lastStep.metadata,
            experimental_context: lastStep.experimental_context,
            finishReason: lastStep.finishReason,
            rawFinishReason: lastStep.rawFinishReason,
            usage: lastStep.usage,
            content: lastStep.content,
            text: lastStep.text,
            reasoningText: lastStep.reasoningText,
            reasoning: lastStep.reasoning,
            files: lastStep.files,
            sources: lastStep.sources,
            toolCalls: lastStep.toolCalls,
            staticToolCalls: lastStep.staticToolCalls,
            dynamicToolCalls: lastStep.dynamicToolCalls,
            toolResults: lastStep.toolResults,
            staticToolResults: lastStep.staticToolResults,
            dynamicToolResults: lastStep.dynamicToolResults,
            request: lastStep.request,
            response: lastStep.response,
            warnings: lastStep.warnings,
            providerMetadata: lastStep.providerMetadata,
            steps,
            totalUsage
          },
          callbacks: [
            onFinish,
            globalTelemetry.onFinish
          ]
        });
        let resolvedOutput;
        if (lastStep.finishReason === "stop") {
          const outputSpecification = output != null ? output : text();
          resolvedOutput = await outputSpecification.parseCompleteOutput(
            { text: lastStep.text },
            {
              response: lastStep.response,
              usage: lastStep.usage,
              finishReason: lastStep.finishReason
            }
          );
        }
        return new DefaultGenerateTextResult({
          steps,
          totalUsage,
          output: resolvedOutput
        });
      }
    });
  } catch (error) {
    throw wrapGatewayError(error);
  }
}
async function executeTools({
  toolCalls,
  tools,
  tracer,
  telemetry,
  messages,
  abortSignal,
  experimental_context,
  stepNumber,
  model,
  onToolCallStart,
  onToolCallFinish
}) {
  const toolOutputs = await Promise.all(
    toolCalls.map(
      async (toolCall) => executeToolCall({
        toolCall,
        tools,
        tracer,
        telemetry,
        messages,
        abortSignal,
        experimental_context,
        stepNumber,
        model,
        onToolCallStart,
        onToolCallFinish
      })
    )
  );
  return toolOutputs.filter(
    (output) => output != null
  );
}
var DefaultGenerateTextResult = class {
  constructor(options) {
    this.steps = options.steps;
    this._output = options.output;
    this.totalUsage = options.totalUsage;
  }
  get finalStep() {
    return this.steps[this.steps.length - 1];
  }
  get content() {
    return this.finalStep.content;
  }
  get text() {
    return this.finalStep.text;
  }
  get files() {
    return this.finalStep.files;
  }
  get reasoningText() {
    return this.finalStep.reasoningText;
  }
  get reasoning() {
    return this.finalStep.reasoning;
  }
  get toolCalls() {
    return this.finalStep.toolCalls;
  }
  get staticToolCalls() {
    return this.finalStep.staticToolCalls;
  }
  get dynamicToolCalls() {
    return this.finalStep.dynamicToolCalls;
  }
  get toolResults() {
    return this.finalStep.toolResults;
  }
  get staticToolResults() {
    return this.finalStep.staticToolResults;
  }
  get dynamicToolResults() {
    return this.finalStep.dynamicToolResults;
  }
  get sources() {
    return this.finalStep.sources;
  }
  get finishReason() {
    return this.finalStep.finishReason;
  }
  get rawFinishReason() {
    return this.finalStep.rawFinishReason;
  }
  get warnings() {
    return this.finalStep.warnings;
  }
  get providerMetadata() {
    return this.finalStep.providerMetadata;
  }
  get response() {
    return this.finalStep.response;
  }
  get request() {
    return this.finalStep.request;
  }
  get usage() {
    return this.finalStep.usage;
  }
  get experimental_output() {
    return this.output;
  }
  get output() {
    if (this._output == null) {
      throw new NoOutputGeneratedError();
    }
    return this._output;
  }
};
function asToolCalls(content) {
  const parts = content.filter(
    (part) => part.type === "tool-call"
  );
  if (parts.length === 0) {
    return void 0;
  }
  return parts.map((toolCall) => ({
    toolCallId: toolCall.toolCallId,
    toolName: toolCall.toolName,
    input: toolCall.input
  }));
}
function asContent({
  content,
  toolCalls,
  toolOutputs,
  toolApprovalRequests,
  tools
}) {
  const contentParts = [];
  for (const part of content) {
    switch (part.type) {
      case "text":
      case "reasoning":
      case "source":
        contentParts.push(part);
        break;
      case "file": {
        contentParts.push({
          type: "file",
          file: new DefaultGeneratedFile(part),
          ...part.providerMetadata != null ? { providerMetadata: part.providerMetadata } : {}
        });
        break;
      }
      case "tool-call": {
        contentParts.push(
          toolCalls.find((toolCall) => toolCall.toolCallId === part.toolCallId)
        );
        break;
      }
      case "tool-result": {
        const toolCall = toolCalls.find(
          (toolCall2) => toolCall2.toolCallId === part.toolCallId
        );
        if (toolCall == null) {
          const tool2 = tools == null ? void 0 : tools[part.toolName];
          const supportsDeferredResults = (tool2 == null ? void 0 : tool2.type) === "provider" && tool2.supportsDeferredResults;
          if (!supportsDeferredResults) {
            throw new Error(`Tool call ${part.toolCallId} not found.`);
          }
          if (part.isError) {
            contentParts.push({
              type: "tool-error",
              toolCallId: part.toolCallId,
              toolName: part.toolName,
              input: void 0,
              error: part.result,
              providerExecuted: true,
              dynamic: part.dynamic,
              ...part.providerMetadata != null ? { providerMetadata: part.providerMetadata } : {},
              ...(tool2 == null ? void 0 : tool2.metadata) != null ? { toolMetadata: tool2.metadata } : {}
            });
          } else {
            contentParts.push({
              type: "tool-result",
              toolCallId: part.toolCallId,
              toolName: part.toolName,
              input: void 0,
              output: part.result,
              providerExecuted: true,
              dynamic: part.dynamic,
              ...part.providerMetadata != null ? { providerMetadata: part.providerMetadata } : {},
              ...(tool2 == null ? void 0 : tool2.metadata) != null ? { toolMetadata: tool2.metadata } : {}
            });
          }
          break;
        }
        if (part.isError) {
          contentParts.push({
            type: "tool-error",
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            input: toolCall.input,
            error: part.result,
            providerExecuted: true,
            dynamic: toolCall.dynamic,
            ...part.providerMetadata != null ? { providerMetadata: part.providerMetadata } : {},
            ...toolCall.toolMetadata != null ? { toolMetadata: toolCall.toolMetadata } : {}
          });
        } else {
          contentParts.push({
            type: "tool-result",
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            input: toolCall.input,
            output: part.result,
            providerExecuted: true,
            dynamic: toolCall.dynamic,
            ...part.providerMetadata != null ? { providerMetadata: part.providerMetadata } : {},
            ...toolCall.toolMetadata != null ? { toolMetadata: toolCall.toolMetadata } : {}
          });
        }
        break;
      }
      case "tool-approval-request": {
        const toolCall = toolCalls.find(
          (toolCall2) => toolCall2.toolCallId === part.toolCallId
        );
        if (toolCall == null) {
          throw new ToolCallNotFoundForApprovalError({
            toolCallId: part.toolCallId,
            approvalId: part.approvalId
          });
        }
        contentParts.push({
          type: "tool-approval-request",
          approvalId: part.approvalId,
          toolCall
        });
        break;
      }
    }
  }
  return [...contentParts, ...toolOutputs, ...toolApprovalRequests];
}
(class extends TransformStream {
  constructor() {
    super({
      transform(part, controller) {
        controller.enqueue(`data: ${JSON.stringify(part)}

`);
      },
      flush(controller) {
        controller.enqueue("data: [DONE]\n\n");
      }
    });
  }
});
record(
  string(),
  jsonValueSchema.optional()
);
createIdGenerator({
  prefix: "aitxt",
  size: 24
});
record(
  string(),
  jsonValueSchema.optional()
);
createIdGenerator({ prefix: "aiobj", size: 24 });
createIdGenerator({ prefix: "aiobj", size: 24 });
export {
  generateText as g
};
