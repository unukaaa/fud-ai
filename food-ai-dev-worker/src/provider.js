import { fallbackSchema, proposalSchema } from "./contracts.js";

// The iOS wire contract never names a provider. Only this server-side adapter
// knows the model. A later provider can implement the same invoke interface.
const MODEL = "gpt-6-luna";
const ENDPOINT = "https://api.openai.com/v1/responses";
const PROVIDER_TIMEOUT_MS = 20_000;
const MAX_PROVIDER_RESPONSE_BYTES = 64 * 1024;

export class ProviderFailure extends Error {
  constructor(category) {
    super(category);
    this.name = "ProviderFailure";
    this.category = category;
  }
}

async function limitedText(response) {
  const stated = Number(response.headers.get("content-length"));
  if (Number.isFinite(stated) && stated > MAX_PROVIDER_RESPONSE_BYTES) throw new ProviderFailure("provider_invalid_response");
  if (!response.body) throw new ProviderFailure("provider_invalid_response");
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_PROVIDER_RESPONSE_BYTES) throw new ProviderFailure("provider_invalid_response");
      chunks.push(value);
    }
  } finally {
    if (length > MAX_PROVIDER_RESPONSE_BYTES) await reader.cancel().catch(() => {});
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

const proposalInstructions = `Interpret the food description into all meaningful components. Do not calculate nutrition, choose authoritative source IDs, or claim verification. Preserve independently checked USER_SUPPLIED quantity bindings exactly once: evidenceID, originalText, value, unit, scope and attached component. Never move a component amount to a meal total or vice versa. userAmount echoes original evidence; estimatedAmount is separate, with null evidenceID/originalText. Estimate plausible edible grams for missing amounts when defensible; never invent a grams-to-mL conversion. Preserve preparation and as-eaten basis, without double-counting a prepared dish and its ingredients. Retain assumptions. Normally ask zero questions; ask at most one only when the answer materially changes the estimate (for example regular versus no-sugar cola). Do not ask for minor variety or exact sauce grams. Your JSON is only a proposal and will be semantically validated by FOOD AI.`;

const fallbackInstructions = `Estimate nutrition independently for EACH requested consumed component amount. Do not re-decompose the meal, aggregate a meal, or replace trusted nutrition. Echo every requestID, componentID, description, preparation, preparationText, consumedGrams, amountProvenance and originalUserQuantity exactly. basis must be consumedComponent. Provide calories, protein, carbohydrate, fat and a plausible calorieLower/calorieUpper range for that consumed amount, plus nonempty assumptions and uncertainty. This is an AI estimate, never verified or source-backed nutrition. Return exactly one result per input component and no others.`;

export async function invokeOpenAI(task, input, apiKey, fetchImpl = fetch) {
  if (!apiKey) throw new ProviderFailure("service_unavailable");
  if (task !== "proposal" && task !== "fallback") throw new ProviderFailure("service_unavailable");
  const schema = task === "proposal" ? proposalSchema : fallbackSchema;
  const name = task === "proposal" ? "food_meal_proposal_v1" : "food_component_nutrition_v1";
  const body = {
    model: MODEL,
    reasoning: { effort: "low" },
    max_output_tokens: task === "proposal" ? 2_400 : 3_000,
    store: false,
    input: [
      { role: "system", content: task === "proposal" ? proposalInstructions : fallbackInstructions },
      { role: "user", content: JSON.stringify(input) }
    ],
    text: { format: { type: "json_schema", name, strict: true, schema } }
  };
  let response;
  try {
    response = await fetchImpl(ENDPOINT, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS)
    });
  } catch (error) {
    throw new ProviderFailure(error?.name === "TimeoutError" || error?.name === "AbortError" ? "provider_timeout" : "provider_unavailable");
  }
  // Never read, log or forward provider error bodies: they can contain input or
  // credentials. Billing/auth failures stay internal to this dev Worker.
  if (!response.ok) {
    response.body?.cancel().catch(() => {});
    throw new ProviderFailure("provider_unavailable");
  }
  let envelope;
  try { envelope = JSON.parse(await limitedText(response)); }
  catch { throw new ProviderFailure("provider_invalid_response"); }
  if (envelope.status !== "completed" || !Array.isArray(envelope.output)) throw new ProviderFailure("provider_invalid_response");
  const texts = envelope.output.flatMap(item => item.type === "message" && Array.isArray(item.content)
    ? item.content.filter(part => part.type === "output_text" && typeof part.text === "string").map(part => part.text) : []);
  if (texts.length !== 1) throw new ProviderFailure("provider_invalid_response");
  let output;
  try { output = JSON.parse(texts[0]); }
  catch { throw new ProviderFailure("provider_invalid_response"); }
  const inputTokens = envelope.usage?.input_tokens;
  const outputTokens = envelope.usage?.output_tokens;
  return {
    output,
    usage: {
      inputTokens: Number.isSafeInteger(inputTokens) && inputTokens >= 0 ? inputTokens : null,
      outputTokens: Number.isSafeInteger(outputTokens) && outputTokens >= 0 ? outputTokens : null
    },
    metadata: { provider: "openai", model: MODEL, timestamp: new Date().toISOString() }
  };
}

export function configuredProvider(name) {
  return name === "openai-luna" ? invokeOpenAI : null;
}
