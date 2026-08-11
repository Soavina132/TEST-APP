import { w as withoutTrailingSlash, r as resolve, a as postJsonToApi, c as createJsonErrorResponseHandler, h as createJsonResponseHandler, b as combineHeaders, i as withUserAgentSuffix, m as loadOptionalSetting, n as parseJsonEventStream, o as getFromApi, s as safeValidateTypes, q as convertUint8ArrayToBase64, d as createEventSourceResponseHandler, t as createProviderToolFactoryWithOutputSchema, u as lazySchema, v as secureJsonParse, z as zodSchema } from "./ai-sdk__provider-utils.mjs";
import { a as APICallError } from "./ai-sdk__provider.mjs";
import { d as distExports } from "./@vercel/oidc.mjs";
import { b as any, o as object, r as record, a as string, d as array, f as discriminatedUnion, e as literal, g as unknown, n as number, u as union, _ as _enum, c as boolean, h as objectType, i as numberType, j as unionType, k as stringType, m as arrayType, p as booleanType, q as enumType, v as recordType, w as anyType } from "./zod.mjs";
var marker = "vercel.ai.gateway.error";
var symbol = Symbol.for(marker);
var _a, _b;
var GatewayError = class _GatewayError extends (_b = Error, _a = symbol, _b) {
  constructor({
    message,
    statusCode = 500,
    cause,
    generationId,
    isRetryable = statusCode != null && (statusCode === 408 || // request timeout
    statusCode === 409 || // conflict
    statusCode === 429 || // too many requests
    statusCode >= 500)
    // server error
  }) {
    super(generationId ? `${message} [${generationId}]` : message);
    this[_a] = true;
    this.statusCode = statusCode;
    this.cause = cause;
    this.generationId = generationId;
    this.isRetryable = isRetryable;
  }
  /**
   * Checks if the given error is a Gateway Error.
   * @param {unknown} error - The error to check.
   * @returns {boolean} True if the error is a Gateway Error, false otherwise.
   */
  static isInstance(error) {
    return _GatewayError.hasMarker(error);
  }
  static hasMarker(error) {
    return typeof error === "object" && error !== null && symbol in error && error[symbol] === true;
  }
};
var name = "GatewayAuthenticationError";
var marker2 = `vercel.ai.gateway.error.${name}`;
var symbol2 = Symbol.for(marker2);
var _a2, _b2;
var GatewayAuthenticationError = class _GatewayAuthenticationError extends (_b2 = GatewayError, _a2 = symbol2, _b2) {
  constructor({
    message = "Authentication failed",
    statusCode = 401,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a2] = true;
    this.name = name;
    this.type = "authentication_error";
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol2 in error;
  }
  /**
   * Creates a contextual error message when authentication fails
   */
  static createContextualError({
    apiKeyProvided,
    oidcTokenProvided,
    message = "Authentication failed",
    statusCode = 401,
    cause,
    generationId
  }) {
    let contextualMessage;
    if (apiKeyProvided) {
      contextualMessage = `AI Gateway authentication failed: Invalid API key.

Create a new API key: https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai%2Fapi-keys

Provide via 'apiKey' option or 'AI_GATEWAY_API_KEY' environment variable.`;
    } else if (oidcTokenProvided) {
      contextualMessage = `AI Gateway authentication failed: Invalid OIDC token.

Run 'npx vercel link' to link your project, then 'vc env pull' to fetch the token.

Alternatively, use an API key: https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai%2Fapi-keys`;
    } else {
      contextualMessage = `AI Gateway authentication failed: No authentication provided.

Option 1 - API key:
Create an API key: https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai%2Fapi-keys
Provide via 'apiKey' option or 'AI_GATEWAY_API_KEY' environment variable.

Option 2 - OIDC token:
Run 'npx vercel link' to link your project, then 'vc env pull' to fetch the token.`;
    }
    return new _GatewayAuthenticationError({
      message: contextualMessage,
      statusCode,
      cause,
      generationId
    });
  }
};
var name2 = "GatewayInvalidRequestError";
var marker3 = `vercel.ai.gateway.error.${name2}`;
var symbol3 = Symbol.for(marker3);
var _a3, _b3;
var GatewayInvalidRequestError = class extends (_b3 = GatewayError, _a3 = symbol3, _b3) {
  constructor({
    message = "Invalid request",
    statusCode = 400,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a3] = true;
    this.name = name2;
    this.type = "invalid_request_error";
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol3 in error;
  }
};
var name3 = "GatewayRateLimitError";
var marker4 = `vercel.ai.gateway.error.${name3}`;
var symbol4 = Symbol.for(marker4);
var _a4, _b4;
var GatewayRateLimitError = class extends (_b4 = GatewayError, _a4 = symbol4, _b4) {
  constructor({
    message = "Rate limit exceeded",
    statusCode = 429,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a4] = true;
    this.name = name3;
    this.type = "rate_limit_exceeded";
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol4 in error;
  }
};
var name4 = "GatewayModelNotFoundError";
var marker5 = `vercel.ai.gateway.error.${name4}`;
var symbol5 = Symbol.for(marker5);
var modelNotFoundParamSchema = lazySchema(
  () => zodSchema(
    object({
      modelId: string()
    })
  )
);
var _a5, _b5;
var GatewayModelNotFoundError = class extends (_b5 = GatewayError, _a5 = symbol5, _b5) {
  constructor({
    message = "Model not found",
    statusCode = 404,
    modelId,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a5] = true;
    this.name = name4;
    this.type = "model_not_found";
    this.modelId = modelId;
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol5 in error;
  }
};
var name5 = "GatewayInternalServerError";
var marker6 = `vercel.ai.gateway.error.${name5}`;
var symbol6 = Symbol.for(marker6);
var _a6, _b6;
var GatewayInternalServerError = class extends (_b6 = GatewayError, _a6 = symbol6, _b6) {
  constructor({
    message = "Internal server error",
    statusCode = 500,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a6] = true;
    this.name = name5;
    this.type = "internal_server_error";
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol6 in error;
  }
};
var name6 = "GatewayFailedDependencyError";
var marker7 = `vercel.ai.gateway.error.${name6}`;
var symbol7 = Symbol.for(marker7);
var _a7, _b7;
var GatewayFailedDependencyError = class extends (_b7 = GatewayError, _a7 = symbol7, _b7) {
  constructor({
    message = "Failed dependency",
    statusCode = 424,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a7] = true;
    this.name = name6;
    this.type = "failed_dependency";
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol7 in error;
  }
};
var name7 = "GatewayForbiddenError";
var marker8 = `vercel.ai.gateway.error.${name7}`;
var symbol8 = Symbol.for(marker8);
var forbiddenParamSchema = lazySchema(
  () => zodSchema(
    object({
      ruleId: string()
    })
  )
);
var _a8, _b8;
var GatewayForbiddenError = class extends (_b8 = GatewayError, _a8 = symbol8, _b8) {
  constructor({
    message = "Forbidden",
    statusCode = 403,
    cause,
    generationId,
    ruleId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a8] = true;
    this.name = name7;
    this.type = "forbidden";
    this.ruleId = ruleId;
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol8 in error;
  }
};
var name8 = "GatewayResponseError";
var marker9 = `vercel.ai.gateway.error.${name8}`;
var symbol9 = Symbol.for(marker9);
var _a9, _b9;
var GatewayResponseError = class extends (_b9 = GatewayError, _a9 = symbol9, _b9) {
  constructor({
    message = "Invalid response from Gateway",
    statusCode = 502,
    response,
    validationError,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a9] = true;
    this.name = name8;
    this.type = "response_error";
    this.response = response;
    this.validationError = validationError;
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol9 in error;
  }
};
async function createGatewayErrorFromResponse({
  response,
  statusCode,
  defaultMessage = "Gateway request failed",
  cause,
  authMethod
}) {
  var _a11;
  const parseResult = await safeValidateTypes({
    value: response,
    schema: gatewayErrorResponseSchema
  });
  if (!parseResult.success) {
    const rawGenerationId = typeof response === "object" && response !== null && "generationId" in response ? response.generationId : void 0;
    return new GatewayResponseError({
      message: `Invalid error response format: ${defaultMessage}`,
      statusCode,
      response,
      validationError: parseResult.error,
      cause,
      generationId: rawGenerationId
    });
  }
  const validatedResponse = parseResult.value;
  const errorType = validatedResponse.error.type;
  const message = validatedResponse.error.message;
  const generationId = (_a11 = validatedResponse.generationId) != null ? _a11 : void 0;
  switch (errorType) {
    case "authentication_error":
      return GatewayAuthenticationError.createContextualError({
        apiKeyProvided: authMethod === "api-key",
        oidcTokenProvided: authMethod === "oidc",
        statusCode,
        cause,
        generationId
      });
    case "invalid_request_error":
      return new GatewayInvalidRequestError({
        message,
        statusCode,
        cause,
        generationId
      });
    case "rate_limit_exceeded":
      return new GatewayRateLimitError({
        message,
        statusCode,
        cause,
        generationId
      });
    case "model_not_found": {
      const modelResult = await safeValidateTypes({
        value: validatedResponse.error.param,
        schema: modelNotFoundParamSchema
      });
      return new GatewayModelNotFoundError({
        message,
        statusCode,
        modelId: modelResult.success ? modelResult.value.modelId : void 0,
        cause,
        generationId
      });
    }
    case "internal_server_error":
      return new GatewayInternalServerError({
        message,
        statusCode,
        cause,
        generationId
      });
    case "failed_dependency":
      return new GatewayFailedDependencyError({
        message,
        statusCode,
        cause,
        generationId
      });
    case "forbidden": {
      const ruleResult = await safeValidateTypes({
        value: validatedResponse.error.param,
        schema: forbiddenParamSchema
      });
      return new GatewayForbiddenError({
        message,
        statusCode,
        cause,
        generationId,
        ruleId: ruleResult.success ? ruleResult.value.ruleId : void 0
      });
    }
    default:
      return new GatewayInternalServerError({
        message,
        statusCode,
        cause,
        generationId
      });
  }
}
var gatewayErrorResponseSchema = lazySchema(
  () => zodSchema(
    object({
      error: object({
        message: string(),
        type: string().nullish(),
        param: unknown().nullish(),
        code: union([string(), number()]).nullish()
      }),
      generationId: string().nullish()
    })
  )
);
function extractApiCallResponse(error) {
  if (error.data !== void 0) {
    return error.data;
  }
  if (error.responseBody != null) {
    try {
      return secureJsonParse(error.responseBody);
    } catch (e) {
      return error.responseBody;
    }
  }
  return {};
}
var name9 = "GatewayTimeoutError";
var marker10 = `vercel.ai.gateway.error.${name9}`;
var symbol10 = Symbol.for(marker10);
var _a10, _b10;
var GatewayTimeoutError = class _GatewayTimeoutError extends (_b10 = GatewayError, _a10 = symbol10, _b10) {
  constructor({
    message = "Request timed out",
    statusCode = 408,
    cause,
    generationId
  } = {}) {
    super({ message, statusCode, cause, generationId });
    this[_a10] = true;
    this.name = name9;
    this.type = "timeout_error";
  }
  static isInstance(error) {
    return GatewayError.hasMarker(error) && symbol10 in error;
  }
  /**
   * Creates a helpful timeout error message with troubleshooting guidance
   */
  static createTimeoutError({
    originalMessage,
    statusCode = 408,
    cause,
    generationId
  }) {
    const message = `Gateway request timed out: ${originalMessage}

    This is a client-side timeout. To resolve this, increase your timeout configuration: https://vercel.com/docs/ai-gateway/capabilities/video-generation#extending-timeouts-for-node.js`;
    return new _GatewayTimeoutError({
      message,
      statusCode,
      cause,
      generationId
    });
  }
};
function isTimeoutError(error) {
  if (!(error instanceof Error)) {
    return false;
  }
  const errorCode = error.code;
  if (typeof errorCode === "string") {
    const undiciTimeoutCodes = [
      "UND_ERR_HEADERS_TIMEOUT",
      "UND_ERR_BODY_TIMEOUT",
      "UND_ERR_CONNECT_TIMEOUT"
    ];
    return undiciTimeoutCodes.includes(errorCode);
  }
  return false;
}
async function asGatewayError(error, authMethod) {
  var _a11;
  if (GatewayError.isInstance(error)) {
    return error;
  }
  if (isTimeoutError(error)) {
    return GatewayTimeoutError.createTimeoutError({
      originalMessage: error instanceof Error ? error.message : "Unknown error",
      cause: error
    });
  }
  if (APICallError.isInstance(error)) {
    if (error.cause && isTimeoutError(error.cause)) {
      return GatewayTimeoutError.createTimeoutError({
        originalMessage: error.message,
        cause: error
      });
    }
    return await createGatewayErrorFromResponse({
      response: extractApiCallResponse(error),
      statusCode: (_a11 = error.statusCode) != null ? _a11 : 500,
      defaultMessage: "Gateway request failed",
      cause: error,
      authMethod
    });
  }
  return await createGatewayErrorFromResponse({
    response: {},
    statusCode: 500,
    defaultMessage: error instanceof Error ? `Gateway request failed: ${error.message}` : "Unknown Gateway error",
    cause: error,
    authMethod
  });
}
var GATEWAY_AUTH_METHOD_HEADER = "ai-gateway-auth-method";
async function parseAuthMethod(headers) {
  const result = await safeValidateTypes({
    value: headers[GATEWAY_AUTH_METHOD_HEADER],
    schema: gatewayAuthMethodSchema
  });
  return result.success ? result.value : void 0;
}
var gatewayAuthMethodSchema = lazySchema(
  () => zodSchema(union([literal("api-key"), literal("oidc")]))
);
var KNOWN_MODEL_TYPES = [
  "embedding",
  "image",
  "language",
  "reranking",
  "speech",
  "transcription",
  "video"
];
var GatewayFetchMetadata = class {
  constructor(config) {
    this.config = config;
  }
  async getAvailableModels() {
    try {
      const { value } = await getFromApi({
        url: `${this.config.baseURL}/config`,
        headers: await resolve(this.config.headers()),
        successfulResponseHandler: createJsonResponseHandler(
          gatewayAvailableModelsResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        fetch: this.config.fetch
      });
      return value;
    } catch (error) {
      throw await asGatewayError(error);
    }
  }
  async getCredits() {
    try {
      const baseUrl = new URL(this.config.baseURL);
      const { value } = await getFromApi({
        url: `${baseUrl.origin}/v1/credits`,
        headers: await resolve(this.config.headers()),
        successfulResponseHandler: createJsonResponseHandler(
          gatewayCreditsResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        fetch: this.config.fetch
      });
      return value;
    } catch (error) {
      throw await asGatewayError(error);
    }
  }
};
var gatewayAvailableModelsResponseSchema = lazySchema(
  () => zodSchema(
    object({
      models: array(
        object({
          id: string(),
          name: string(),
          description: string().nullish(),
          pricing: object({
            input: string(),
            output: string(),
            input_cache_read: string().nullish(),
            input_cache_write: string().nullish()
          }).transform(
            ({ input, output, input_cache_read, input_cache_write }) => ({
              input,
              output,
              ...input_cache_read ? { cachedInputTokens: input_cache_read } : {},
              ...input_cache_write ? { cacheCreationInputTokens: input_cache_write } : {}
            })
          ).nullish(),
          specification: object({
            specificationVersion: literal("v3"),
            provider: string(),
            modelId: string()
          }),
          modelType: string().nullish()
        })
      ).transform(
        (models) => models.filter(
          (m) => m.modelType == null || KNOWN_MODEL_TYPES.includes(m.modelType)
        )
      )
    })
  )
);
var gatewayCreditsResponseSchema = lazySchema(
  () => zodSchema(
    object({
      balance: string(),
      total_used: string()
    }).transform(({ balance, total_used }) => ({
      balance,
      totalUsed: total_used
    }))
  )
);
var GatewaySpendReport = class {
  constructor(config) {
    this.config = config;
  }
  async getSpendReport(params) {
    try {
      const baseUrl = new URL(this.config.baseURL);
      const searchParams = new URLSearchParams();
      searchParams.set("start_date", params.startDate);
      searchParams.set("end_date", params.endDate);
      if (params.groupBy) {
        searchParams.set("group_by", params.groupBy);
      }
      if (params.datePart) {
        searchParams.set("date_part", params.datePart);
      }
      if (params.userId) {
        searchParams.set("user_id", params.userId);
      }
      if (params.model) {
        searchParams.set("model", params.model);
      }
      if (params.provider) {
        searchParams.set("provider", params.provider);
      }
      if (params.credentialType) {
        searchParams.set("credential_type", params.credentialType);
      }
      if (params.tags && params.tags.length > 0) {
        searchParams.set("tags", params.tags.join(","));
      }
      const { value } = await getFromApi({
        url: `${baseUrl.origin}/v1/report?${searchParams.toString()}`,
        headers: await resolve(this.config.headers()),
        successfulResponseHandler: createJsonResponseHandler(
          gatewaySpendReportResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        fetch: this.config.fetch
      });
      return value;
    } catch (error) {
      throw await asGatewayError(error);
    }
  }
};
var gatewaySpendReportResponseSchema = lazySchema(
  () => zodSchema(
    object({
      results: array(
        object({
          day: string().optional(),
          hour: string().optional(),
          user: string().optional(),
          model: string().optional(),
          tag: string().optional(),
          provider: string().optional(),
          credential_type: _enum(["byok", "system"]).optional(),
          total_cost: number(),
          market_cost: number().optional(),
          input_tokens: number().optional(),
          output_tokens: number().optional(),
          cached_input_tokens: number().optional(),
          cache_creation_input_tokens: number().optional(),
          reasoning_tokens: number().optional(),
          request_count: number().optional()
        }).transform(
          ({
            credential_type,
            total_cost,
            market_cost,
            input_tokens,
            output_tokens,
            cached_input_tokens,
            cache_creation_input_tokens,
            reasoning_tokens,
            request_count,
            ...rest
          }) => ({
            ...rest,
            ...credential_type !== void 0 ? { credentialType: credential_type } : {},
            totalCost: total_cost,
            ...market_cost !== void 0 ? { marketCost: market_cost } : {},
            ...input_tokens !== void 0 ? { inputTokens: input_tokens } : {},
            ...output_tokens !== void 0 ? { outputTokens: output_tokens } : {},
            ...cached_input_tokens !== void 0 ? { cachedInputTokens: cached_input_tokens } : {},
            ...cache_creation_input_tokens !== void 0 ? { cacheCreationInputTokens: cache_creation_input_tokens } : {},
            ...reasoning_tokens !== void 0 ? { reasoningTokens: reasoning_tokens } : {},
            ...request_count !== void 0 ? { requestCount: request_count } : {}
          })
        )
      )
    })
  )
);
var GatewayGenerationInfoFetcher = class {
  constructor(config) {
    this.config = config;
  }
  async getGenerationInfo(params) {
    try {
      const baseUrl = new URL(this.config.baseURL);
      const { value } = await getFromApi({
        url: `${baseUrl.origin}/v1/generation?id=${encodeURIComponent(params.id)}`,
        headers: await resolve(this.config.headers()),
        successfulResponseHandler: createJsonResponseHandler(
          gatewayGenerationInfoResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        fetch: this.config.fetch
      });
      return value;
    } catch (error) {
      throw await asGatewayError(error);
    }
  }
};
var gatewayGenerationInfoResponseSchema = lazySchema(
  () => zodSchema(
    object({
      data: object({
        id: string(),
        total_cost: number(),
        upstream_inference_cost: number(),
        usage: number(),
        created_at: string(),
        model: string(),
        is_byok: boolean(),
        provider_name: string(),
        streamed: boolean(),
        finish_reason: string(),
        latency: number(),
        generation_time: number(),
        native_tokens_prompt: number(),
        native_tokens_completion: number(),
        native_tokens_reasoning: number(),
        native_tokens_cached: number(),
        native_tokens_cache_creation: number(),
        billable_web_search_calls: number()
      }).transform(
        ({
          total_cost,
          upstream_inference_cost,
          created_at,
          is_byok,
          provider_name,
          finish_reason,
          generation_time,
          native_tokens_prompt,
          native_tokens_completion,
          native_tokens_reasoning,
          native_tokens_cached,
          native_tokens_cache_creation,
          billable_web_search_calls,
          ...rest
        }) => ({
          ...rest,
          totalCost: total_cost,
          upstreamInferenceCost: upstream_inference_cost,
          createdAt: created_at,
          isByok: is_byok,
          providerName: provider_name,
          finishReason: finish_reason,
          generationTime: generation_time,
          promptTokens: native_tokens_prompt,
          completionTokens: native_tokens_completion,
          reasoningTokens: native_tokens_reasoning,
          cachedTokens: native_tokens_cached,
          cacheCreationTokens: native_tokens_cache_creation,
          billableWebSearchCalls: billable_web_search_calls
        })
      )
    }).transform(({ data }) => data)
  )
);
var GatewayLanguageModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
    this.supportedUrls = { "*/*": [/.*/] };
  }
  get provider() {
    return this.config.provider;
  }
  async getArgs(options) {
    const { abortSignal: _abortSignal, ...optionsWithoutSignal } = options;
    return {
      args: this.maybeEncodeFileParts(optionsWithoutSignal),
      warnings: []
    };
  }
  async doGenerate(options) {
    const { args, warnings } = await this.getArgs(options);
    const { abortSignal } = options;
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const {
        responseHeaders,
        value: responseBody,
        rawValue: rawResponse
      } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          options.headers,
          this.getModelConfigHeaders(this.modelId, false),
          await resolve(this.config.o11yHeaders)
        ),
        body: args,
        successfulResponseHandler: createJsonResponseHandler(any()),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        ...responseBody,
        request: { body: args },
        response: { headers: responseHeaders, body: rawResponse },
        warnings
      };
    } catch (error) {
      throw await asGatewayError(error, await parseAuthMethod(resolvedHeaders));
    }
  }
  async doStream(options) {
    const { args, warnings } = await this.getArgs(options);
    const { abortSignal } = options;
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const { value: response, responseHeaders } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          options.headers,
          this.getModelConfigHeaders(this.modelId, true),
          await resolve(this.config.o11yHeaders)
        ),
        body: args,
        successfulResponseHandler: createEventSourceResponseHandler(any()),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        stream: response.pipeThrough(
          new TransformStream({
            start(controller) {
              if (warnings.length > 0) {
                controller.enqueue({ type: "stream-start", warnings });
              }
            },
            transform(chunk, controller) {
              if (chunk.success) {
                const streamPart = chunk.value;
                if (streamPart.type === "raw" && !options.includeRawChunks) {
                  return;
                }
                if (streamPart.type === "response-metadata" && streamPart.timestamp && typeof streamPart.timestamp === "string") {
                  streamPart.timestamp = new Date(streamPart.timestamp);
                }
                controller.enqueue(streamPart);
              } else {
                controller.error(
                  chunk.error
                );
              }
            }
          })
        ),
        request: { body: args },
        response: { headers: responseHeaders }
      };
    } catch (error) {
      throw await asGatewayError(error, await parseAuthMethod(resolvedHeaders));
    }
  }
  isFilePart(part) {
    return part && typeof part === "object" && "type" in part && part.type === "file";
  }
  /**
   * Encodes file parts in the prompt to base64. Mutates the passed options
   * instance directly to avoid copying the file data.
   * @param options - The options to encode.
   * @returns The options with the file parts encoded.
   */
  maybeEncodeFileParts(options) {
    for (const message of options.prompt) {
      for (const part of message.content) {
        if (this.isFilePart(part)) {
          const filePart = part;
          if (filePart.data instanceof Uint8Array) {
            const buffer = Uint8Array.from(filePart.data);
            const base64Data = Buffer.from(buffer).toString("base64");
            filePart.data = new URL(
              `data:${filePart.mediaType || "application/octet-stream"};base64,${base64Data}`
            );
          }
        }
      }
    }
    return options;
  }
  getUrl() {
    return `${this.config.baseURL}/language-model`;
  }
  getModelConfigHeaders(modelId, streaming) {
    return {
      "ai-language-model-specification-version": "3",
      "ai-language-model-id": modelId,
      "ai-language-model-streaming": String(streaming)
    };
  }
};
var GatewayEmbeddingModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
    this.maxEmbeddingsPerCall = 2048;
    this.supportsParallelCalls = true;
  }
  get provider() {
    return this.config.provider;
  }
  async doEmbed({
    values,
    headers,
    abortSignal,
    providerOptions
  }) {
    var _a11, _b11;
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const {
        responseHeaders,
        value: responseBody,
        rawValue
      } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          headers != null ? headers : {},
          this.getModelConfigHeaders(),
          await resolve(this.config.o11yHeaders)
        ),
        body: {
          values,
          ...providerOptions ? { providerOptions } : {}
        },
        successfulResponseHandler: createJsonResponseHandler(
          gatewayEmbeddingResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        embeddings: responseBody.embeddings,
        usage: (_a11 = responseBody.usage) != null ? _a11 : void 0,
        providerMetadata: responseBody.providerMetadata,
        response: { headers: responseHeaders, body: rawValue },
        warnings: (_b11 = responseBody.warnings) != null ? _b11 : []
      };
    } catch (error) {
      throw await asGatewayError(error, await parseAuthMethod(resolvedHeaders));
    }
  }
  getUrl() {
    return `${this.config.baseURL}/embedding-model`;
  }
  getModelConfigHeaders() {
    return {
      "ai-embedding-model-specification-version": "3",
      "ai-model-id": this.modelId
    };
  }
};
var gatewayEmbeddingWarningSchema = discriminatedUnion("type", [
  object({
    type: literal("unsupported"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("compatibility"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("other"),
    message: string()
  })
]);
var gatewayEmbeddingResponseSchema = lazySchema(
  () => zodSchema(
    object({
      embeddings: array(array(number())),
      usage: object({ tokens: number() }).nullish(),
      warnings: array(gatewayEmbeddingWarningSchema).optional(),
      providerMetadata: record(string(), record(string(), unknown())).optional()
    })
  )
);
function mapGatewayWarnings(warnings) {
  return (warnings != null ? warnings : []).map(
    (warning) => warning.type === "deprecated" ? { type: "other", message: warning.message } : warning
  );
}
var GatewayImageModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
    this.maxImagesPerCall = Number.MAX_SAFE_INTEGER;
  }
  get provider() {
    return this.config.provider;
  }
  async doGenerate({
    prompt,
    n,
    size,
    aspectRatio,
    seed,
    files,
    mask,
    providerOptions,
    headers,
    abortSignal
  }) {
    var _a11, _b11, _c;
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const {
        responseHeaders,
        value: responseBody,
        rawValue
      } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          headers != null ? headers : {},
          this.getModelConfigHeaders(),
          await resolve(this.config.o11yHeaders)
        ),
        body: {
          prompt,
          n,
          ...size && { size },
          ...aspectRatio && { aspectRatio },
          ...seed && { seed },
          ...providerOptions && { providerOptions },
          ...files && {
            files: files.map((file) => maybeEncodeImageFile(file))
          },
          ...mask && { mask: maybeEncodeImageFile(mask) }
        },
        successfulResponseHandler: createJsonResponseHandler(
          gatewayImageResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        images: responseBody.images,
        // Always base64 strings from server
        warnings: mapGatewayWarnings(responseBody.warnings),
        providerMetadata: responseBody.providerMetadata,
        response: {
          timestamp: /* @__PURE__ */ new Date(),
          modelId: this.modelId,
          headers: responseHeaders
        },
        ...responseBody.usage != null && {
          usage: {
            inputTokens: (_a11 = responseBody.usage.inputTokens) != null ? _a11 : void 0,
            outputTokens: (_b11 = responseBody.usage.outputTokens) != null ? _b11 : void 0,
            totalTokens: (_c = responseBody.usage.totalTokens) != null ? _c : void 0
          }
        }
      };
    } catch (error) {
      throw await asGatewayError(error, await parseAuthMethod(resolvedHeaders));
    }
  }
  getUrl() {
    return `${this.config.baseURL}/image-model`;
  }
  getModelConfigHeaders() {
    return {
      "ai-image-model-specification-version": "3",
      "ai-model-id": this.modelId
    };
  }
};
function maybeEncodeImageFile(file) {
  if (file.type === "file" && file.data instanceof Uint8Array) {
    return {
      ...file,
      data: convertUint8ArrayToBase64(file.data)
    };
  }
  return file;
}
var providerMetadataEntrySchema = object({
  images: array(unknown()).optional()
}).catchall(unknown());
var gatewayImageWarningSchema = discriminatedUnion("type", [
  object({
    type: literal("unsupported"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("compatibility"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("deprecated"),
    setting: string(),
    message: string()
  }),
  object({
    type: literal("other"),
    message: string()
  })
]);
var gatewayImageUsageSchema = object({
  inputTokens: number().nullish(),
  outputTokens: number().nullish(),
  totalTokens: number().nullish()
});
var gatewayImageResponseSchema = object({
  images: array(string()),
  // Always base64 strings over the wire
  warnings: array(gatewayImageWarningSchema).optional(),
  providerMetadata: record(string(), providerMetadataEntrySchema).optional(),
  usage: gatewayImageUsageSchema.optional()
});
var GatewayVideoModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
    this.maxVideosPerCall = Number.MAX_SAFE_INTEGER;
  }
  get provider() {
    return this.config.provider;
  }
  async doGenerate({
    prompt,
    n,
    aspectRatio,
    resolution,
    duration,
    fps,
    seed,
    generateAudio,
    image,
    frameImages,
    inputReferences,
    providerOptions,
    headers,
    abortSignal
  }) {
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const { responseHeaders, value: responseBody } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          headers != null ? headers : {},
          this.getModelConfigHeaders(),
          await resolve(this.config.o11yHeaders),
          { accept: "text/event-stream" }
        ),
        body: {
          prompt,
          n,
          ...aspectRatio && { aspectRatio },
          ...resolution && { resolution },
          ...duration && { duration },
          ...fps && { fps },
          ...seed && { seed },
          ...generateAudio !== void 0 && { generateAudio },
          ...providerOptions && { providerOptions },
          ...image && { image: maybeEncodeVideoFile(image) },
          ...frameImages && {
            frameImages: frameImages.map((frame) => ({
              ...frame,
              image: maybeEncodeVideoFile(frame.image)
            }))
          },
          ...inputReferences && {
            inputReferences: inputReferences.map(
              (reference) => maybeEncodeVideoFile(reference)
            )
          }
        },
        successfulResponseHandler: async ({
          response,
          url,
          requestBodyValues
        }) => {
          if (response.body == null) {
            throw new APICallError({
              message: "SSE response body is empty",
              url,
              requestBodyValues,
              statusCode: response.status
            });
          }
          const eventStream = parseJsonEventStream({
            stream: response.body,
            schema: gatewayVideoEventSchema
          });
          const reader = eventStream.getReader();
          const { done, value: parseResult } = await reader.read();
          reader.releaseLock();
          if (done || !parseResult) {
            throw new APICallError({
              message: "SSE stream ended without a data event",
              url,
              requestBodyValues,
              statusCode: response.status
            });
          }
          if (!parseResult.success) {
            throw new APICallError({
              message: "Failed to parse video SSE event",
              cause: parseResult.error,
              url,
              requestBodyValues,
              statusCode: response.status
            });
          }
          const event = parseResult.value;
          if (event.type === "error") {
            throw new APICallError({
              message: event.message,
              statusCode: event.statusCode,
              url,
              requestBodyValues,
              responseHeaders: Object.fromEntries([...response.headers]),
              responseBody: JSON.stringify(event),
              data: {
                error: {
                  message: event.message,
                  type: event.errorType,
                  param: event.param
                }
              }
            });
          }
          return {
            value: {
              videos: event.videos,
              warnings: event.warnings,
              providerMetadata: event.providerMetadata
            },
            responseHeaders: Object.fromEntries([...response.headers])
          };
        },
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        videos: responseBody.videos,
        warnings: mapGatewayWarnings(responseBody.warnings),
        providerMetadata: responseBody.providerMetadata,
        response: {
          timestamp: /* @__PURE__ */ new Date(),
          modelId: this.modelId,
          headers: responseHeaders
        }
      };
    } catch (error) {
      throw await asGatewayError(error, await parseAuthMethod(resolvedHeaders));
    }
  }
  getUrl() {
    return `${this.config.baseURL}/video-model`;
  }
  getModelConfigHeaders() {
    return {
      "ai-video-model-specification-version": "3",
      "ai-model-id": this.modelId
    };
  }
};
function maybeEncodeVideoFile(file) {
  if (file.type === "file" && file.data instanceof Uint8Array) {
    return {
      ...file,
      data: convertUint8ArrayToBase64(file.data)
    };
  }
  return file;
}
var providerMetadataEntrySchema2 = object({
  videos: array(unknown()).optional()
}).catchall(unknown());
var gatewayVideoDataSchema = union([
  object({
    type: literal("url"),
    url: string(),
    mediaType: string()
  }),
  object({
    type: literal("base64"),
    data: string(),
    mediaType: string()
  })
]);
var gatewayVideoWarningSchema = discriminatedUnion("type", [
  object({
    type: literal("unsupported"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("compatibility"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("deprecated"),
    setting: string(),
    message: string()
  }),
  object({
    type: literal("other"),
    message: string()
  })
]);
var gatewayVideoEventSchema = discriminatedUnion("type", [
  object({
    type: literal("result"),
    videos: array(gatewayVideoDataSchema),
    warnings: array(gatewayVideoWarningSchema).optional(),
    providerMetadata: record(string(), providerMetadataEntrySchema2).optional()
  }),
  object({
    type: literal("error"),
    message: string(),
    errorType: string(),
    statusCode: number(),
    param: unknown().nullable()
  })
]);
var GatewayRerankingModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
  }
  get provider() {
    return this.config.provider;
  }
  async doRerank({
    documents,
    query,
    topN,
    headers,
    abortSignal,
    providerOptions
  }) {
    var _a11;
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const {
        responseHeaders,
        value: responseBody,
        rawValue
      } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          headers != null ? headers : {},
          this.getModelConfigHeaders(),
          await resolve(this.config.o11yHeaders)
        ),
        body: {
          documents,
          query,
          ...topN != null ? { topN } : {},
          ...providerOptions ? { providerOptions } : {}
        },
        successfulResponseHandler: createJsonResponseHandler(
          gatewayRerankingResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        ranking: responseBody.ranking,
        providerMetadata: responseBody.providerMetadata,
        response: { headers: responseHeaders, body: rawValue },
        warnings: (_a11 = responseBody.warnings) != null ? _a11 : []
      };
    } catch (error) {
      throw await asGatewayError(error, await parseAuthMethod(resolvedHeaders));
    }
  }
  getUrl() {
    return `${this.config.baseURL}/reranking-model`;
  }
  getModelConfigHeaders() {
    return {
      "ai-reranking-model-specification-version": "3",
      "ai-model-id": this.modelId
    };
  }
};
var gatewayRerankingWarningSchema = discriminatedUnion("type", [
  object({
    type: literal("unsupported"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("compatibility"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("other"),
    message: string()
  })
]);
var gatewayRerankingResponseSchema = lazySchema(
  () => zodSchema(
    object({
      ranking: array(
        object({
          index: number(),
          relevanceScore: number()
        })
      ),
      warnings: array(gatewayRerankingWarningSchema).optional(),
      providerMetadata: record(string(), record(string(), unknown())).optional()
    })
  )
);
var GatewaySpeechModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
  }
  get provider() {
    return this.config.provider;
  }
  async doGenerate({
    text,
    voice,
    outputFormat,
    instructions,
    speed,
    language,
    providerOptions,
    headers,
    abortSignal
  }) {
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const {
        responseHeaders,
        value: responseBody,
        rawValue
      } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          headers != null ? headers : {},
          this.getModelConfigHeaders(),
          await resolve(this.config.o11yHeaders)
        ),
        body: {
          text,
          ...voice && { voice },
          ...outputFormat && { outputFormat },
          ...instructions && { instructions },
          ...speed != null && { speed },
          ...language && { language },
          ...providerOptions && { providerOptions }
        },
        successfulResponseHandler: createJsonResponseHandler(
          gatewaySpeechResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        audio: responseBody.audio,
        warnings: mapGatewayWarnings(responseBody.warnings),
        providerMetadata: responseBody.providerMetadata,
        response: {
          timestamp: /* @__PURE__ */ new Date(),
          modelId: this.modelId,
          headers: responseHeaders,
          body: rawValue
        }
      };
    } catch (error) {
      throw await asGatewayError(
        error,
        await parseAuthMethod(resolvedHeaders != null ? resolvedHeaders : {})
      );
    }
  }
  getUrl() {
    return `${this.config.baseURL}/speech-model`;
  }
  getModelConfigHeaders() {
    return {
      "ai-speech-model-specification-version": "3",
      "ai-model-id": this.modelId
    };
  }
};
var providerMetadataEntrySchema3 = object({}).catchall(unknown());
var gatewaySpeechWarningSchema = discriminatedUnion("type", [
  object({
    type: literal("unsupported"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("compatibility"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("deprecated"),
    setting: string(),
    message: string()
  }),
  object({
    type: literal("other"),
    message: string()
  })
]);
var gatewaySpeechResponseSchema = object({
  audio: string(),
  warnings: array(gatewaySpeechWarningSchema).optional(),
  providerMetadata: record(string(), providerMetadataEntrySchema3).optional()
});
var GatewayTranscriptionModel = class {
  constructor(modelId, config) {
    this.modelId = modelId;
    this.config = config;
    this.specificationVersion = "v3";
  }
  get provider() {
    return this.config.provider;
  }
  async doGenerate({
    audio,
    mediaType,
    providerOptions,
    headers,
    abortSignal
  }) {
    var _a11, _b11, _c;
    const resolvedHeaders = await resolve(this.config.headers());
    try {
      const {
        responseHeaders,
        value: responseBody,
        rawValue
      } = await postJsonToApi({
        url: this.getUrl(),
        headers: combineHeaders(
          resolvedHeaders,
          headers != null ? headers : {},
          this.getModelConfigHeaders(),
          await resolve(this.config.o11yHeaders)
        ),
        body: {
          audio: audio instanceof Uint8Array ? convertUint8ArrayToBase64(audio) : audio,
          mediaType,
          ...providerOptions && { providerOptions }
        },
        successfulResponseHandler: createJsonResponseHandler(
          gatewayTranscriptionResponseSchema
        ),
        failedResponseHandler: createJsonErrorResponseHandler({
          errorSchema: any(),
          errorToMessage: (data) => data
        }),
        ...abortSignal && { abortSignal },
        fetch: this.config.fetch
      });
      return {
        text: responseBody.text,
        segments: (_a11 = responseBody.segments) != null ? _a11 : [],
        language: (_b11 = responseBody.language) != null ? _b11 : void 0,
        durationInSeconds: (_c = responseBody.durationInSeconds) != null ? _c : void 0,
        warnings: mapGatewayWarnings(responseBody.warnings),
        providerMetadata: responseBody.providerMetadata,
        response: {
          timestamp: /* @__PURE__ */ new Date(),
          modelId: this.modelId,
          headers: responseHeaders,
          body: rawValue
        }
      };
    } catch (error) {
      throw await asGatewayError(
        error,
        await parseAuthMethod(resolvedHeaders != null ? resolvedHeaders : {})
      );
    }
  }
  getUrl() {
    return `${this.config.baseURL}/transcription-model`;
  }
  getModelConfigHeaders() {
    return {
      "ai-transcription-model-specification-version": "3",
      "ai-model-id": this.modelId
    };
  }
};
var providerMetadataEntrySchema4 = object({}).catchall(unknown());
var gatewayTranscriptionWarningSchema = discriminatedUnion("type", [
  object({
    type: literal("unsupported"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("compatibility"),
    feature: string(),
    details: string().optional()
  }),
  object({
    type: literal("deprecated"),
    setting: string(),
    message: string()
  }),
  object({
    type: literal("other"),
    message: string()
  })
]);
var gatewayTranscriptionResponseSchema = object({
  text: string(),
  segments: array(
    object({
      text: string(),
      startSecond: number(),
      endSecond: number()
    })
  ).optional(),
  language: string().nullish(),
  durationInSeconds: number().nullish(),
  warnings: array(gatewayTranscriptionWarningSchema).optional(),
  providerMetadata: record(string(), providerMetadataEntrySchema4).optional()
});
var exaSearchInputSchema = lazySchema(
  () => zodSchema(
    objectType({
      query: stringType().describe("Natural-language web search query. This is required."),
      type: enumType(["auto", "fast", "instant"]).optional().describe(
        "Search method. Use auto for the default balance of speed and quality."
      ),
      num_results: numberType().optional().describe("Maximum number of results to return (1-100, default: 10)."),
      category: enumType([
        "company",
        "people",
        "research paper",
        "news",
        "personal site",
        "financial report"
      ]).optional().describe("Optional content category to focus results."),
      user_location: stringType().optional().describe("Two-letter ISO country code such as 'US'."),
      include_domains: arrayType(stringType()).optional().describe("Only return results from these domains."),
      exclude_domains: arrayType(stringType()).optional().describe("Exclude results from these domains."),
      start_published_date: stringType().optional().describe("Only return links published after this ISO 8601 date."),
      end_published_date: stringType().optional().describe("Only return links published before this ISO 8601 date."),
      contents: objectType({
        text: unionType([
          booleanType(),
          objectType({
            max_characters: numberType().optional(),
            include_html_tags: booleanType().optional(),
            verbosity: enumType(["compact", "standard", "full"]).optional(),
            include_sections: arrayType(
              enumType([
                "header",
                "navigation",
                "banner",
                "body",
                "sidebar",
                "footer",
                "metadata"
              ])
            ).optional(),
            exclude_sections: arrayType(
              enumType([
                "header",
                "navigation",
                "banner",
                "body",
                "sidebar",
                "footer",
                "metadata"
              ])
            ).optional()
          })
        ]).optional(),
        highlights: unionType([
          booleanType(),
          objectType({
            query: stringType().optional(),
            max_characters: numberType().optional()
          })
        ]).optional(),
        max_age_hours: numberType().optional(),
        livecrawl_timeout: numberType().optional(),
        subpages: numberType().optional(),
        subpage_target: unionType([stringType(), arrayType(stringType())]).optional(),
        extras: objectType({
          links: numberType().optional(),
          image_links: numberType().optional()
        }).optional()
      }).optional().describe("Controls extracted page content and freshness.")
    })
  )
);
var exaSearchOutputSchema = lazySchema(
  () => zodSchema(
    unionType([
      objectType({
        requestId: stringType(),
        searchType: stringType().optional(),
        resolvedSearchType: stringType().optional(),
        results: arrayType(
          objectType({
            title: stringType(),
            url: stringType(),
            id: stringType(),
            publishedDate: stringType().nullable().optional(),
            author: stringType().nullable().optional(),
            image: stringType().nullable().optional(),
            favicon: stringType().nullable().optional(),
            text: stringType().optional(),
            highlights: arrayType(stringType()).optional(),
            highlightScores: arrayType(numberType()).optional(),
            summary: stringType().optional(),
            subpages: arrayType(anyType()).optional(),
            extras: objectType({
              links: arrayType(stringType()).optional(),
              imageLinks: arrayType(stringType()).optional()
            }).optional()
          })
        ),
        costDollars: objectType({
          total: numberType().optional(),
          search: recordType(numberType()).optional()
        }).optional()
      }),
      objectType({
        error: enumType([
          "api_error",
          "rate_limit",
          "timeout",
          "invalid_input",
          "configuration_error",
          "execution_error",
          "unknown"
        ]),
        statusCode: numberType().optional(),
        message: stringType()
      })
    ])
  )
);
var exaSearchToolFactory = createProviderToolFactoryWithOutputSchema({
  id: "gateway.exa_search",
  inputSchema: exaSearchInputSchema,
  outputSchema: exaSearchOutputSchema
});
var exaSearch = (config = {}) => exaSearchToolFactory(config);
var parallelSearchInputSchema = lazySchema(
  () => zodSchema(
    objectType({
      objective: stringType().describe(
        "Natural-language description of the web research goal, including source or freshness guidance and broader context from the task. Maximum 5000 characters."
      ),
      search_queries: arrayType(stringType()).optional().describe(
        "Optional search queries to supplement the objective. Maximum 200 characters per query."
      ),
      mode: enumType(["one-shot", "agentic"]).optional().describe(
        'Mode preset: "one-shot" for comprehensive results with longer excerpts (default), "agentic" for concise, token-efficient results for multi-step workflows.'
      ),
      max_results: numberType().optional().describe(
        "Maximum number of results to return (1-20). Defaults to 10 if not specified."
      ),
      source_policy: objectType({
        include_domains: arrayType(stringType()).optional().describe(
          "Limit results to these domains. Use plain domain names only — e.g. example.com or sub.example.gov, or a bare extension like .edu. Do not include a scheme, path, or port (e.g. not https://example.com/page)."
        ),
        exclude_domains: arrayType(stringType()).optional().describe(
          "Exclude results from these domains. Use plain domain names only — e.g. example.com or sub.example.gov, or a bare extension like .edu. Do not include a scheme, path, or port (e.g. not https://example.com/page)."
        ),
        after_date: stringType().optional().describe(
          "Only include results published after this date. Use an ISO 8601 calendar date formatted YYYY-MM-DD (e.g. 2025-01-01); do not include a time."
        )
      }).optional().describe(
        "Source policy for controlling which domains to include/exclude and freshness."
      ),
      excerpts: objectType({
        max_chars_per_result: numberType().optional().describe("Maximum characters per result."),
        max_chars_total: numberType().optional().describe("Maximum total characters across all results.")
      }).optional().describe("Excerpt configuration for controlling result length."),
      fetch_policy: objectType({
        max_age_seconds: numberType().optional().describe(
          "Maximum age in seconds for cached content. Set to 0 to always fetch fresh content."
        )
      }).optional().describe("Fetch policy for controlling content freshness.")
    })
  )
);
var parallelSearchOutputSchema = lazySchema(
  () => zodSchema(
    unionType([
      // Success response
      objectType({
        searchId: stringType(),
        results: arrayType(
          objectType({
            url: stringType(),
            title: stringType(),
            excerpt: stringType(),
            publishDate: stringType().nullable().optional(),
            relevanceScore: numberType().optional()
          })
        )
      }),
      // Error response
      objectType({
        error: enumType([
          "api_error",
          "rate_limit",
          "timeout",
          "invalid_input",
          "configuration_error",
          "unknown"
        ]),
        statusCode: numberType().optional(),
        message: stringType()
      })
    ])
  )
);
var parallelSearchToolFactory = createProviderToolFactoryWithOutputSchema({
  id: "gateway.parallel_search",
  inputSchema: parallelSearchInputSchema,
  outputSchema: parallelSearchOutputSchema
});
var parallelSearch = (config = {}) => parallelSearchToolFactory(config);
var perplexitySearchInputSchema = lazySchema(
  () => zodSchema(
    objectType({
      query: unionType([stringType(), arrayType(stringType())]).describe(
        "Search query (string) or multiple queries (array of up to 5 strings). Multi-query searches return combined results from all queries."
      ),
      max_results: numberType().optional().describe(
        "Maximum number of search results to return (1-20, default: 10)"
      ),
      max_tokens_per_page: numberType().optional().describe(
        "Maximum number of tokens to extract per search result page (256-2048, default: 2048)"
      ),
      max_tokens: numberType().optional().describe(
        "Maximum total tokens across all search results (default: 25000, max: 1000000)"
      ),
      country: stringType().optional().describe(
        "Two-letter ISO 3166-1 alpha-2 country code for regional search results (e.g., 'US', 'GB', 'FR')"
      ),
      search_domain_filter: arrayType(stringType()).optional().describe(
        "List of domains to include or exclude from search results (max 20). To include: ['nature.com', 'science.org']. To exclude: ['-example.com', '-spam.net']"
      ),
      search_language_filter: arrayType(stringType()).optional().describe(
        "List of ISO 639-1 language codes to filter results (max 10, lowercase). Examples: ['en', 'fr', 'de']"
      ),
      search_after_date: stringType().optional().describe(
        "Include only results published after this date. Format: 'MM/DD/YYYY' (e.g., '3/1/2025'). Cannot be used with search_recency_filter."
      ),
      search_before_date: stringType().optional().describe(
        "Include only results published before this date. Format: 'MM/DD/YYYY' (e.g., '3/15/2025'). Cannot be used with search_recency_filter."
      ),
      last_updated_after_filter: stringType().optional().describe(
        "Include only results last updated after this date. Format: 'MM/DD/YYYY' (e.g., '3/1/2025'). Cannot be used with search_recency_filter."
      ),
      last_updated_before_filter: stringType().optional().describe(
        "Include only results last updated before this date. Format: 'MM/DD/YYYY' (e.g., '3/15/2025'). Cannot be used with search_recency_filter."
      ),
      search_recency_filter: enumType(["day", "week", "month", "year"]).optional().describe(
        "Filter results by relative time period. Cannot be used with search_after_date or search_before_date."
      )
    })
  )
);
var perplexitySearchOutputSchema = lazySchema(
  () => zodSchema(
    unionType([
      // Success response
      objectType({
        results: arrayType(
          objectType({
            title: stringType(),
            url: stringType(),
            snippet: stringType(),
            date: stringType().optional(),
            lastUpdated: stringType().optional()
          })
        ),
        id: stringType()
      }),
      // Error response
      objectType({
        error: enumType([
          "api_error",
          "rate_limit",
          "timeout",
          "invalid_input",
          "unknown"
        ]),
        statusCode: numberType().optional(),
        message: stringType()
      })
    ])
  )
);
var perplexitySearchToolFactory = createProviderToolFactoryWithOutputSchema({
  id: "gateway.perplexity_search",
  inputSchema: perplexitySearchInputSchema,
  outputSchema: perplexitySearchOutputSchema
});
var perplexitySearch = (config = {}) => perplexitySearchToolFactory(config);
var gatewayTools = {
  /**
   * Search the web using Exa for current information and token-efficient
   * excerpts optimized for agent workflows.
   *
   * Supports search type, category, domain, date, location, and content
   * extraction controls.
   */
  exaSearch,
  /**
   * Search the web using Parallel AI's Search API for LLM-optimized excerpts.
   *
   * Takes a natural language objective and returns relevant excerpts,
   * replacing multiple keyword searches with a single call for broad
   * or complex queries. Supports different search types for depth vs
   * breadth tradeoffs.
   */
  parallelSearch,
  /**
   * Search the web using Perplexity's Search API for real-time information,
   * news, research papers, and articles.
   *
   * Provides ranked search results with advanced filtering options including
   * domain, language, date range, and recency filters.
   */
  perplexitySearch
};
async function getVercelRequestId() {
  var _a11;
  return (_a11 = distExports.getContext().headers) == null ? void 0 : _a11["x-vercel-id"];
}
var VERSION = "3.0.164";
var AI_GATEWAY_PROTOCOL_VERSION = "0.0.1";
function createGatewayProvider(options = {}) {
  var _a11, _b11;
  let pendingMetadata = null;
  let metadataCache = null;
  const cacheRefreshMillis = (_a11 = options.metadataCacheRefreshMillis) != null ? _a11 : 1e3 * 60 * 5;
  let lastFetchTime = 0;
  const baseURL = (_b11 = withoutTrailingSlash(options.baseURL)) != null ? _b11 : "https://ai-gateway.vercel.sh/v3/ai";
  const getHeaders = async () => {
    try {
      const auth = await getGatewayAuthToken(options);
      return withUserAgentSuffix(
        {
          Authorization: `Bearer ${auth.token}`,
          "ai-gateway-protocol-version": AI_GATEWAY_PROTOCOL_VERSION,
          [GATEWAY_AUTH_METHOD_HEADER]: auth.authMethod,
          ...options.headers
        },
        `ai-sdk/gateway/${VERSION}`
      );
    } catch (error) {
      throw GatewayAuthenticationError.createContextualError({
        apiKeyProvided: false,
        oidcTokenProvided: false,
        statusCode: 401,
        cause: error
      });
    }
  };
  const createO11yHeaders = () => {
    const deploymentId = loadOptionalSetting({
      settingValue: void 0,
      environmentVariableName: "VERCEL_DEPLOYMENT_ID"
    });
    const environment = loadOptionalSetting({
      settingValue: void 0,
      environmentVariableName: "VERCEL_ENV"
    });
    const region = loadOptionalSetting({
      settingValue: void 0,
      environmentVariableName: "VERCEL_REGION"
    });
    const projectId = loadOptionalSetting({
      settingValue: void 0,
      environmentVariableName: "VERCEL_PROJECT_ID"
    });
    return async () => {
      const requestId = await getVercelRequestId();
      return {
        ...deploymentId && { "ai-o11y-deployment-id": deploymentId },
        ...environment && { "ai-o11y-environment": environment },
        ...region && { "ai-o11y-region": region },
        ...requestId && { "ai-o11y-request-id": requestId },
        ...projectId && { "ai-o11y-project-id": projectId }
      };
    };
  };
  const createLanguageModel = (modelId) => {
    return new GatewayLanguageModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  const getAvailableModels = async () => {
    var _a12, _b12, _c;
    const now = (_c = (_b12 = (_a12 = options._internal) == null ? void 0 : _a12.currentDate) == null ? void 0 : _b12.call(_a12).getTime()) != null ? _c : Date.now();
    if (!pendingMetadata || now - lastFetchTime > cacheRefreshMillis) {
      lastFetchTime = now;
      pendingMetadata = new GatewayFetchMetadata({
        baseURL,
        headers: getHeaders,
        fetch: options.fetch
      }).getAvailableModels().then((metadata) => {
        metadataCache = metadata;
        return metadata;
      }).catch(async (error) => {
        throw await asGatewayError(
          error,
          await parseAuthMethod(await getHeaders())
        );
      });
    }
    return metadataCache ? Promise.resolve(metadataCache) : pendingMetadata;
  };
  const getCredits = async () => {
    return new GatewayFetchMetadata({
      baseURL,
      headers: getHeaders,
      fetch: options.fetch
    }).getCredits().catch(async (error) => {
      throw await asGatewayError(
        error,
        await parseAuthMethod(await getHeaders())
      );
    });
  };
  const getSpendReport = async (params) => {
    return new GatewaySpendReport({
      baseURL,
      headers: getHeaders,
      fetch: options.fetch
    }).getSpendReport(params).catch(async (error) => {
      throw await asGatewayError(
        error,
        await parseAuthMethod(await getHeaders())
      );
    });
  };
  const getGenerationInfo = async (params) => {
    return new GatewayGenerationInfoFetcher({
      baseURL,
      headers: getHeaders,
      fetch: options.fetch
    }).getGenerationInfo(params).catch(async (error) => {
      throw await asGatewayError(
        error,
        await parseAuthMethod(await getHeaders())
      );
    });
  };
  const provider = function(modelId) {
    if (new.target) {
      throw new Error(
        "The Gateway Provider model function cannot be called with the new keyword."
      );
    }
    return createLanguageModel(modelId);
  };
  provider.specificationVersion = "v3";
  provider.getAvailableModels = getAvailableModels;
  provider.getCredits = getCredits;
  provider.getSpendReport = getSpendReport;
  provider.getGenerationInfo = getGenerationInfo;
  provider.imageModel = (modelId) => {
    return new GatewayImageModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  provider.languageModel = createLanguageModel;
  const createEmbeddingModel = (modelId) => {
    return new GatewayEmbeddingModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  provider.embeddingModel = createEmbeddingModel;
  provider.textEmbeddingModel = createEmbeddingModel;
  provider.videoModel = (modelId) => {
    return new GatewayVideoModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  const createRerankingModel = (modelId) => {
    return new GatewayRerankingModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  provider.rerankingModel = createRerankingModel;
  provider.reranking = createRerankingModel;
  const createSpeechModel = (modelId) => {
    return new GatewaySpeechModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  provider.speechModel = createSpeechModel;
  provider.speech = createSpeechModel;
  const createTranscriptionModel = (modelId) => {
    return new GatewayTranscriptionModel(modelId, {
      provider: "gateway",
      baseURL,
      headers: getHeaders,
      fetch: options.fetch,
      o11yHeaders: createO11yHeaders()
    });
  };
  provider.transcriptionModel = createTranscriptionModel;
  provider.transcription = createTranscriptionModel;
  provider.chat = provider.languageModel;
  provider.embedding = provider.embeddingModel;
  provider.image = provider.imageModel;
  provider.video = provider.videoModel;
  provider.tools = gatewayTools;
  return provider;
}
var gateway = createGatewayProvider();
async function getGatewayAuthToken(options) {
  const apiKey = loadOptionalSetting({
    settingValue: options.apiKey,
    environmentVariableName: "AI_GATEWAY_API_KEY"
  });
  if (apiKey) {
    return {
      token: apiKey,
      authMethod: "api-key"
    };
  }
  const oidcToken = await distExports.getVercelOidcToken();
  return {
    token: oidcToken,
    authMethod: "oidc"
  };
}
export {
  GatewayAuthenticationError as G,
  GatewayError as a,
  gateway as g
};
