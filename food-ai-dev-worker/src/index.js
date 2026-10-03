import {
  FALLBACK_VERSION, PROPOSAL_REQUEST_VERSION, PROPOSAL_RESPONSE_VERSION,
  validateFallbackOutput, validateFallbackRequest,
  validateProposalOutput, validateProposalRequest
} from "./contracts.js";
import { configuredProvider, ProviderFailure } from "./provider.js";
import { createRemoteJWKSet, jwtVerify } from "jose";

const PREFIX = "/api/grounded-estimate/v1";
const MAX_REQUEST_BYTES = 32 * 1024;
const BODY_TIMEOUT_MS = 5_000;
const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers }
});
const error = (code, status, headers) => json({ error: code }, status, headers);

let cachedAccessKeys;

function accessIssuer(env) {
  if (typeof env?.ACCESS_TEAM_DOMAIN !== "string") return null;
  try {
    const url = new URL(env.ACCESS_TEAM_DOMAIN.trim());
    if (url.protocol !== "https:" || !url.hostname.endsWith(".cloudflareaccess.com")
      || url.username || url.password || url.pathname !== "/" || url.search || url.hash) return null;
    return url.origin;
  } catch { return null; }
}

function accessKeys(issuer) {
  if (cachedAccessKeys?.issuer !== issuer) {
    cachedAccessKeys = {
      issuer,
      keys: createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`), { timeoutDuration: 3_000 })
    };
  }
  return cachedAccessKeys.keys;
}

async function verifiedServiceIdentity(request, env, keyResolver) {
  const issuer = accessIssuer(env);
  const token = request.headers.get("Cf-Access-Jwt-Assertion");
  if (!issuer || !token) return null;
  try {
    const { payload } = await jwtVerify(token, keyResolver ?? accessKeys(issuer), {
      issuer, audience: env.ACCESS_POLICY_AUD.trim(), algorithms: ["RS256"]
    });
    // The application JWT represents a service token with common_name =
    // Client ID. This is distinct from getIdentity()'s mTLS common_name.
    return payload.type === "app" && payload.sub === "" && Number.isInteger(payload.exp)
      && payload.common_name === env.ACCESS_BUILDER_CLIENT_ID.trim()
      ? `service:${payload.common_name}` : null;
  } catch { return null; }
}

async function readBoundedJSON(request) {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) return { error: "invalid_request", status: 400 };
  const stated = Number(request.headers.get("content-length"));
  if (Number.isFinite(stated) && stated > MAX_REQUEST_BYTES) return { error: "payload_too_large", status: 413 };
  if (!request.body) return { error: "invalid_request", status: 400 };
  const reader = request.body.getReader();
  const chunks = [];
  let length = 0;
  const deadline = Date.now() + BODY_TIMEOUT_MS;
  try {
    while (true) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) return { error: "request_timeout", status: 408 };
      let timer;
      const step = await Promise.race([
        reader.read(),
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("body_timeout")), remaining); })
      ]).finally(() => clearTimeout(timer));
      if (step.done) break;
      length += step.value.byteLength;
      if (length > MAX_REQUEST_BYTES) return { error: "payload_too_large", status: 413 };
      chunks.push(step.value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return { body: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) };
  } catch (caught) {
    return caught?.message === "body_timeout" ? { error: "request_timeout", status: 408 } : { error: "invalid_request", status: 400 };
  } finally {
    if (length > MAX_REQUEST_BYTES || Date.now() >= deadline) reader.cancel().catch(() => {});
  }
}

async function identity(request, ctx, env, keyResolver) {
  if (!ctx?.access || typeof ctx.access.getIdentity !== "function") return null;
  if (typeof env?.ACCESS_POLICY_AUD !== "string" || !env.ACCESS_POLICY_AUD.trim()
    || typeof env?.DEV_OWNER_EMAIL !== "string" || !env.DEV_OWNER_EMAIL.trim()
    || typeof env?.ACCESS_BUILDER_CLIENT_ID !== "string" || !env.ACCESS_BUILDER_CLIENT_ID.trim()
    || !accessIssuer(env)) return null;
  // ctx.access is supplied by the Workers runtime after Access authentication;
  // request headers are never an identity source. Pin the Access application too.
  if (ctx.access.aud !== env.ACCESS_POLICY_AUD.trim()) return null;
  let value;
  try { value = await ctx.access.getIdentity(); }
  catch { value = null; }
  if (!value) return verifiedServiceIdentity(request, env, keyResolver);
  try {
    if (value?.service_token_status === true) {
      const clientID = value.service_token_id;
      return typeof clientID === "string" && clientID === env.ACCESS_BUILDER_CLIENT_ID.trim()
        ? `service:${clientID}` : null;
    }
    // A human identity cannot be inferred from a service-token claim or a
    // caller-supplied email header. Unknown identity shapes fail closed.
    if (value?.service_token_status !== false && value?.service_token_status !== undefined) return null;
    if (value?.service_token_id) return null;
    const email = typeof value?.email === "string" ? value.email.trim().toLowerCase() : "";
    return email && email === env.DEV_OWNER_EMAIL.trim().toLowerCase() ? `human:${email}` : null;
  } catch { return null; }
}

async function hashIdentity(email) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(email));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

/** Dependency injection is test-only; production uses the configured adapter. */
export function createWorker({ provider, serviceKeyResolver } = {}) {
  return {
    async fetch(request, env, ctx) {
      const path = new URL(request.url).pathname;
      if (path !== `${PREFIX}/proposal` && path !== `${PREFIX}/fallback-batch`) return error("not_found", 404);
      if (request.method !== "POST") return error("method_not_allowed", 405, { allow: "POST" });
      const user = await identity(request, ctx, env, serviceKeyResolver);
      if (!user) return error("unauthorized", 401);
      const adapter = provider ?? configuredProvider(env?.ACTIVE_PROVIDER);
      if (!adapter || !env?.OPENAI_API_KEY || !env?.DEV_REQUEST_RATE_LIMITER?.limit) return error("service_unavailable", 503);
      try {
        const limited = await env.DEV_REQUEST_RATE_LIMITER.limit({ key: await hashIdentity(user) });
        if (!limited?.success) return error("rate_limited", 429, { "retry-after": "60" });
      } catch { return error("service_unavailable", 503); }
      const parsed = await readBoundedJSON(request);
      if (parsed.error) return error(parsed.error, parsed.status);
      const proposal = path.endsWith("/proposal");
      const expectedVersion = proposal ? PROPOSAL_REQUEST_VERSION : FALLBACK_VERSION;
      if (parsed.body?.version !== expectedVersion) return error("unsupported_version", 400);
      if (proposal ? !validateProposalRequest(parsed.body) : !validateFallbackRequest(parsed.body)) {
        return error("invalid_request", 400);
      }
      try {
        const result = await adapter(proposal ? "proposal" : "fallback", parsed.body, env.OPENAI_API_KEY);
        const valid = proposal ? validateProposalOutput(result.output, parsed.body) : validateFallbackOutput(result.output, parsed.body);
        if (!valid) return error("provider_invalid_response", 502);
        if (proposal) return json({ version: PROPOSAL_RESPONSE_VERSION, proposal: result.output, usage: result.usage ?? null });
        const metadata = result.metadata;
        if (!metadata || !Number.isFinite(Date.parse(metadata.timestamp))) return error("provider_invalid_response", 502);
        const components = result.output.components.map(item => ({
          proposal: item,
          metadata: { provider: metadata.provider, model: metadata.model, timestamp: metadata.timestamp, contractVersion: FALLBACK_VERSION }
        }));
        return json({ version: FALLBACK_VERSION, components, usage: result.usage ?? null });
      } catch (caught) {
        if (caught instanceof ProviderFailure) return error(caught.category, caught.category === "provider_invalid_response" ? 502 : caught.category === "provider_timeout" ? 504 : 503);
        // No raw provider body, request, stack, user identity or secret in logs.
        console.error("food_ai_dev_provider_unavailable");
        return error("provider_unavailable", 503);
      }
    }
  };
}

export default createWorker();
