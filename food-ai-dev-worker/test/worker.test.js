import test from "node:test";
import assert from "node:assert/strict";
import { createWorker } from "../src/index.js";
import { ProviderFailure, invokeOpenAI } from "../src/provider.js";
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";

const base = "https://food-ai-dev.example/api/grounded-estimate/v1";
const accessContext = identity => ({ access: { aud: "test-audience", getIdentity: async () => identity } });
const ctx = accessContext({ email: "owner@example.com", service_token_status: false });
const env = () => ({
  DEV_OWNER_EMAIL: "owner@example.com", ACCESS_POLICY_AUD: "test-audience",
  ACCESS_BUILDER_CLIENT_ID: "approved-builder.access", ACCESS_TEAM_DOMAIN: "https://team.cloudflareaccess.com",
  OPENAI_API_KEY: "test-only-placeholder",
  ACTIVE_PROVIDER: "openai-luna", DEV_REQUEST_RATE_LIMITER: { limit: async () => ({ success: true }) }
});
const binding = { evidenceID: "q1", originalText: "180 g", value: 180, unit: "grams", scope: "componentAmount", componentName: "rice", provenance: "userSupplied" };
const request = { version: "checked-quantity-binding-v1", description: "180 g rice with lentils and spinach", quantities: [binding] };
const quantityEcho = { evidenceID: "q1", originalText: "180 g", value: 180, unit: "grams", scope: "componentAmount" };
const proposal = {
  components: [
    { id: "rice", name: "rice", preparation: "cooked", preparationText: null, userAmount: quantityEcho, estimatedAmount: null, assumptions: ["as eaten"] },
    { id: "lentils", name: "lentils", preparation: "cooked", preparationText: null, userAmount: null, estimatedAmount: { evidenceID: null, originalText: null, value: 80, unit: "grams", scope: "componentAmount" }, assumptions: ["typical portion"] },
    { id: "spinach", name: "spinach", preparation: "cooked", preparationText: null, userAmount: null, estimatedAmount: { evidenceID: null, originalText: null, value: 40, unit: "grams", scope: "componentAmount" }, assumptions: ["typical portion"] }
  ], mealTotal: null, question: null, assumptions: []
};
const fallbackComponent = (id, grams = 100) => ({
  requestID: `request-${id}`, componentID: id, description: id, mealContext: `${id} meal`,
  preparation: "cooked", preparationText: null, consumedGrams: grams,
  amountProvenance: "estimated", originalUserQuantity: null,
  fallbackReason: "noApprovedRepresentativeBasis", trustedCandidateIDs: [], assumptions: ["typical preparation"]
});
const fallbackRequest = (ids = ["fish"]) => ({ version: "consumed-component-ai-nutrition-v1", components: ids.map(id => fallbackComponent(id)) });
const nutrition = source => ({
  requestID: source.requestID, componentID: source.componentID, description: source.description,
  basis: "consumedComponent", preparation: source.preparation, preparationText: source.preparationText,
  consumedGrams: source.consumedGrams, amountProvenance: source.amountProvenance,
  originalUserQuantity: source.originalUserQuantity, calories: 120, protein: 5,
  carbohydrate: 15, fat: 4, calorieLower: 100, calorieUpper: 140,
  assumptions: ["typical preparation"], uncertainty: ["recipe varies"]
});
const metadata = { provider: "openai", model: "gpt-6-luna", timestamp: "2026-10-02T00:00:00.000Z" };
const call = (path, body, options = {}) => new Request(`${base}/${path}`, {
  method: options.method ?? "POST",
  headers: { "content-type": "application/json", ...(options.headers ?? {}) },
  body: options.method === "GET" ? undefined : JSON.stringify(body)
});
const goodProvider = async (task, input) => ({
  output: task === "proposal" ? proposal : { components: input.components.map(nutrition) },
  usage: { inputTokens: 25, outputTokens: 40 }, metadata
});

test("valid proposal retains checked rice binding and never calculates nutrition", async () => {
  const response = await createWorker({ provider: goodProvider }).fetch(call("proposal", request), env(), ctx);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.version, "grounded-estimate-proposal-v1");
  assert.deepEqual(body.proposal.components[0].userAmount, quantityEcho);
  assert.equal(body.proposal.mealTotal, null);
  assert.equal(body.proposal.components[0].calories, undefined);
});

test("fallback batch returns one independently bound result per component", async () => {
  const input = fallbackRequest(["fish", "salad"]);
  const response = await createWorker({ provider: goodProvider }).fetch(call("fallback-batch", input), env(), ctx);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.components.length, 2);
  assert.deepEqual(body.components.map(item => item.proposal.requestID), ["request-fish", "request-salad"]);
  assert.equal(body.components[0].metadata.contractVersion, "consumed-component-ai-nutrition-v1");
});

test("unmatched or altered fallback component rejects the whole batch", async () => {
  const input = fallbackRequest(["fish", "salad"]);
  const worker = createWorker({ provider: async (_, value) => ({ output: { components: value.components.map((item, i) => ({ ...nutrition(item), consumedGrams: i ? 999 : item.consumedGrams })) }, metadata }) });
  const response = await worker.fetch(call("fallback-batch", input), env(), ctx);
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "provider_invalid_response" });
});

test("provider cannot move explicit component grams to meal total", async () => {
  const altered = structuredClone(proposal);
  altered.components[0].userAmount = null;
  altered.mealTotal = { ...quantityEcho, scope: "mealTotalAmount" };
  const response = await createWorker({ provider: async () => ({ output: altered, metadata }) }).fetch(call("proposal", request), env(), ctx);
  assert.equal(response.status, 502);
});

test("owner and exact Builder service identities are independently authorized", async () => {
  const worker = createWorker({ provider: goodProvider });
  assert.equal((await worker.fetch(call("proposal", request), env(), ctx)).status, 200);
  assert.equal((await worker.fetch(call("proposal", request), env(), accessContext({
    service_token_status: true, service_token_id: "approved-builder.access"
  }))).status, 200);
});

test("a signed Access application JWT authorizes only the approved Builder Client ID", async () => {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...await exportJWK(publicKey), kid: "test-key", alg: "RS256", use: "sig" };
  const resolver = createLocalJWKSet({ keys: [jwk] });
  const sign = (clientID, options = {}) => new SignJWT({ type: "app", sub: "", common_name: clientID })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuer(options.issuer ?? "https://team.cloudflareaccess.com")
    .setAudience(options.audience ?? "test-audience")
    .setIssuedAt()
    .setExpirationTime(options.expiration ?? "5m")
    .sign(privateKey);
  let calls = 0;
  const worker = createWorker({ serviceKeyResolver: resolver, provider: async (...args) => { calls++; return goodProvider(...args); } });
  const serviceContext = accessContext(null);
  const send = (token, context = serviceContext) => worker.fetch(call("proposal", request, { headers: { "Cf-Access-Jwt-Assertion": token } }), env(), context);
  assert.equal((await send(await sign("approved-builder.access"))).status, 200);
  assert.equal(calls, 1);
  assert.equal((await send(await sign("different-builder.access"))).status, 401);
  assert.equal((await send(await sign("approved-builder.access", { audience: "other-audience" }))).status, 401);
  assert.equal((await send(await sign("approved-builder.access", { issuer: "https://other.cloudflareaccess.com" }))).status, 401);
  assert.equal((await send(await sign("approved-builder.access", { expiration: "-5m" }))).status, 401);
  const valid = await sign("approved-builder.access");
  assert.equal((await send(`${valid.slice(0, -1)}${valid.endsWith("A") ? "B" : "A"}`)).status, 401);
  assert.equal((await worker.fetch(call("proposal", request), env(), serviceContext)).status, 401);
  assert.equal((await send(valid, {})).status, 401);
  assert.equal(calls, 1);
  assert.equal((await worker.fetch(new Request("https://food-ai-dev.example/__dev/access-shape"), env(), serviceContext)).status, 404);
});

test("missing, wrong, forged or unsupported Access identity never invokes provider", async () => {
  let calls = 0;
  const worker = createWorker({ provider: async () => { calls++; return goodProvider(); } });
  const denied = [
    {},
    accessContext({ email: "stranger@example.com", service_token_status: false }),
    accessContext({ service_token_status: true, service_token_id: "different-builder.access" }),
    accessContext({ service_token_status: false, service_token_id: "approved-builder.access" }),
    accessContext({ email: "owner@example.com", service_token_status: false, service_token_id: "approved-builder.access" }),
    accessContext({ email: "owner@example.com", service_token_status: true, service_token_id: "different-builder.access" }),
    accessContext({ email: "owner@example.com", service_token_id: "different-builder.access" }),
    accessContext({}),
    { access: { aud: "wrong-audience", getIdentity: async () => ({ email: "owner@example.com" }) } },
    { access: { aud: "test-audience", getIdentity: async () => { throw new Error("private identity detail"); } } }
  ];
  for (const context of denied) assert.equal((await worker.fetch(call("proposal", request), env(), context)).status, 401);
  const forgedHeaders = { "cf-access-authenticated-user-email": "owner@example.com", "cf-access-jwt-assertion": "forged" };
  assert.equal((await worker.fetch(call("proposal", request, { headers: forgedHeaders }), env(), {})).status, 401);
  assert.equal(calls, 0);
});

test("missing owner allowlist, provider secret, or rate binding fails closed", async () => {
  const worker = createWorker({ provider: goodProvider });
  const missingOwner = env(); delete missingOwner.DEV_OWNER_EMAIL;
  const missingAudience = env(); delete missingAudience.ACCESS_POLICY_AUD;
  const missingBuilder = env(); delete missingBuilder.ACCESS_BUILDER_CLIENT_ID;
  const missingTeam = env(); delete missingTeam.ACCESS_TEAM_DOMAIN;
  const missingKey = env(); delete missingKey.OPENAI_API_KEY;
  const missingLimiter = env(); delete missingLimiter.DEV_REQUEST_RATE_LIMITER;
  assert.equal((await worker.fetch(call("proposal", request), missingOwner, ctx)).status, 401);
  assert.equal((await worker.fetch(call("proposal", request), missingAudience, ctx)).status, 401);
  assert.equal((await worker.fetch(call("proposal", request), missingBuilder, ctx)).status, 401);
  assert.equal((await worker.fetch(call("proposal", request), missingTeam, ctx)).status, 401);
  assert.equal((await worker.fetch(call("proposal", request), missingKey, ctx)).status, 503);
  assert.equal((await worker.fetch(call("proposal", request), missingLimiter, ctx)).status, 503);
});

test("method, version, malformed request and oversized request are bounded", async () => {
  const worker = createWorker({ provider: goodProvider });
  assert.equal((await worker.fetch(call("proposal", request, { method: "GET" }), env(), ctx)).status, 405);
  const unsupported = await worker.fetch(call("proposal", { ...request, version: "future" }), env(), ctx);
  assert.equal(unsupported.status, 400);
  assert.deepEqual(await unsupported.json(), { error: "unsupported_version" });
  const malformed = new Request(`${base}/proposal`, { method: "POST", headers: { "content-type": "application/json" }, body: "{" });
  assert.equal((await worker.fetch(malformed, env(), ctx)).status, 400);
  const huge = new Request(`${base}/proposal`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...request, description: "a".repeat(35_000) }) });
  assert.equal((await worker.fetch(huge, env(), ctx)).status, 413);
});

test("rate limit prevents model call", async () => {
  const limited = env(); limited.DEV_REQUEST_RATE_LIMITER = { limit: async () => ({ success: false }) };
  let calls = 0;
  const response = await createWorker({ provider: async () => { calls++; return goodProvider(); } }).fetch(call("proposal", request), limited, ctx);
  assert.equal(response.status, 429);
  assert.equal(calls, 0);
});

test("provider timeout, outage and malformed response use stable safe categories", async () => {
  for (const [category, status] of [["provider_timeout", 504], ["provider_unavailable", 503], ["provider_invalid_response", 502]]) {
    const worker = createWorker({ provider: async () => { throw new ProviderFailure(category); } });
    const response = await worker.fetch(call("proposal", request), env(), ctx);
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { error: category });
  }
});

test("OpenAI adapter pins model, low reasoning, bounded output and strict schema", async () => {
  let outbound;
  const fakeFetch = async (_url, init) => {
    outbound = JSON.parse(init.body);
    return new Response(JSON.stringify({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify(proposal) }] }], usage: { input_tokens: 25, output_tokens: 40 } }), { status: 200 });
  };
  const result = await invokeOpenAI("proposal", request, "test-only-placeholder", fakeFetch);
  assert.equal(result.output.components.length, 3);
  assert.equal(outbound.model, "gpt-6-luna");
  assert.equal(outbound.reasoning.effort, "low");
  assert.equal(outbound.store, false);
  assert.equal(outbound.text.format.strict, true);
  assert.ok(outbound.max_output_tokens <= 3_000);
});

test("OpenAI adapter never returns provider error body", async () => {
  await assert.rejects(() => invokeOpenAI("proposal", request, "test-only-placeholder", async () => new Response("sensitive upstream details", { status: 503 })),
    error => error instanceof ProviderFailure && error.category === "provider_unavailable" && !error.message.includes("sensitive"));
});

test("OpenAI adapter rejects oversized and malformed provider envelopes", async () => {
  await assert.rejects(() => invokeOpenAI("proposal", request, "test-only-placeholder", async () => new Response("x".repeat(70_000), { status: 200 })),
    error => error instanceof ProviderFailure && error.category === "provider_invalid_response");
  await assert.rejects(() => invokeOpenAI("proposal", request, "test-only-placeholder", async () => new Response("not-json", { status: 200 })),
    error => error instanceof ProviderFailure && error.category === "provider_invalid_response");
});

test("OpenAI adapter classifies a timed-out provider without exposing details", async () => {
  await assert.rejects(() => invokeOpenAI("proposal", request, "test-only-placeholder", async () => {
    throw new DOMException("private transport detail", "TimeoutError");
  }), error => error instanceof ProviderFailure && error.category === "provider_timeout" && !error.message.includes("private"));
});
