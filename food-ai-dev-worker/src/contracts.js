// Provider-neutral wire shapes mirror FoodQuantityInterpretationContract,
// FoodMealProposal and AIComponentNutritionProposal in the iOS code. This is
// transport validation only; the Swift semantic firewall remains authoritative.
export const PROPOSAL_REQUEST_VERSION = "checked-quantity-binding-v1";
export const PROPOSAL_RESPONSE_VERSION = "grounded-estimate-proposal-v1";
export const FALLBACK_VERSION = "consumed-component-ai-nutrition-v1";

const units = ["grams", "millilitres", "count", "fraction"];
const scopes = ["componentAmount", "mealTotalAmount", "servingCount", "packageFraction", "naturalPortion", "unknownScope"];
const preparations = ["unknown", "raw", "dry", "cooked", "drained", "fried", "other"];
const permittedReasons = ["noApprovedRepresentativeBasis", "noUsefulTrustedNutrition"];
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const record = value => value !== null && typeof value === "object" && !Array.isArray(value);
const shape = (value, keys) => record(value) && Object.keys(value).length === keys.length && keys.every(key => own(value, key));
const str = (value, max, min = 1) => typeof value === "string" && value.length >= min && value.length <= max;
const nullableStr = (value, max) => value === null || str(value, max);
const num = value => typeof value === "number" && Number.isFinite(value);
const strings = (value, count, max) => Array.isArray(value) && value.length <= count && value.every(item => str(item, max));
const sameQuantity = (left, right) => left === null && right === null ||
  record(left) && record(right) && quantityKeys.every(key => left[key] === right[key]);
const quantityKeys = ["evidenceID", "originalText", "value", "unit", "scope"];

function validQuantity(value, binding = false) {
  if (!shape(value, binding ? [...quantityKeys, "componentName", "provenance"] : quantityKeys)) return false;
  if (!(value.evidenceID === null || str(value.evidenceID, 80))) return false;
  if (!(value.originalText === null || str(value.originalText, 120))) return false;
  if (!num(value.value) || value.value <= 0 || value.value > 100_000) return false;
  if (!units.includes(value.unit) || !scopes.includes(value.scope)) return false;
  if (["componentAmount", "mealTotalAmount"].includes(value.scope) && !["grams", "millilitres"].includes(value.unit)) return false;
  if (["servingCount", "naturalPortion"].includes(value.scope) && value.unit !== "count") return false;
  if (value.scope === "packageFraction" && (value.unit !== "fraction" || value.value > 1)) return false;
  if (binding) {
    if (!str(value.evidenceID, 80) || !str(value.originalText, 120) || value.provenance !== "userSupplied") return false;
    if (!(value.componentName === null || str(value.componentName, 160))) return false;
    if (value.scope === "mealTotalAmount" && value.componentName !== null) return false;
    if (value.scope !== "mealTotalAmount" && value.scope !== "unknownScope" && value.componentName === null) return false;
  }
  return true;
}

export function validateProposalRequest(body) {
  if (!shape(body, ["version", "description", "quantities"])) return false;
  if (body.version !== PROPOSAL_REQUEST_VERSION || !str(body.description, 4_000)) return false;
  if (!Array.isArray(body.quantities) || body.quantities.length > 20) return false;
  if (!body.quantities.every(item => validQuantity(item, true) && body.description.includes(item.originalText))) return false;
  return new Set(body.quantities.map(item => item.evidenceID)).size === body.quantities.length;
}

export function validateFallbackRequest(body) {
  if (!shape(body, ["version", "components"]) || body.version !== FALLBACK_VERSION) return false;
  if (!Array.isArray(body.components) || body.components.length < 1 || body.components.length > 6) return false;
  const keys = ["requestID", "componentID", "description", "mealContext", "preparation", "preparationText", "consumedGrams", "amountProvenance", "originalUserQuantity", "fallbackReason", "trustedCandidateIDs", "assumptions"];
  if (!body.components.every(item => {
    if (!shape(item, keys) || !str(item.requestID, 128) || !str(item.componentID, 80) || !str(item.description, 240) || !str(item.mealContext, 4_000)) return false;
    if (!preparations.includes(item.preparation) || !nullableStr(item.preparationText, 240)) return false;
    if (!num(item.consumedGrams) || item.consumedGrams <= 0 || item.consumedGrams > 10_000) return false;
    if (!str(item.amountProvenance, 80) || !permittedReasons.includes(item.fallbackReason)) return false;
    if (item.originalUserQuantity !== null && !validQuantity(item.originalUserQuantity)) return false;
    if (!strings(item.trustedCandidateIDs, 32, 120) || !strings(item.assumptions, 12, 300)) return false;
    return true;
  })) return false;
  return new Set(body.components.map(item => item.requestID)).size === body.components.length;
}

function validProposalQuantity(value, isUser) {
  if (value === null) return true;
  if (!validQuantity(value)) return false;
  if (isUser) return str(value.evidenceID, 80) && str(value.originalText, 120);
  return value.evidenceID === null && value.originalText === null && value.scope === "componentAmount";
}

export function validateProposalOutput(output, request) {
  if (!shape(output, ["components", "mealTotal", "question", "assumptions"])) return false;
  if (!Array.isArray(output.components) || output.components.length < 1 || output.components.length > 12) return false;
  if (!nullableStr(output.question, 280) || !strings(output.assumptions, 20, 300)) return false;
  if (!validProposalQuantity(output.mealTotal, true)) return false;
  const used = [];
  if (output.mealTotal) used.push(output.mealTotal);
  for (const item of output.components) {
    if (!shape(item, ["id", "name", "preparation", "preparationText", "userAmount", "estimatedAmount", "assumptions"])) return false;
    if (!str(item.id, 80) || !str(item.name, 240) || !preparations.includes(item.preparation) || !nullableStr(item.preparationText, 240)) return false;
    if (!validProposalQuantity(item.userAmount, true) || !validProposalQuantity(item.estimatedAmount, false)) return false;
    if (!strings(item.assumptions, 12, 300)) return false;
    if (item.userAmount) used.push(item.userAmount);
  }
  if (new Set(output.components.map(item => item.id)).size !== output.components.length) return false;
  if (used.length !== request.quantities.length || new Set(used.map(item => item.evidenceID)).size !== used.length) return false;
  for (const source of request.quantities) {
    const echo = used.find(item => item.evidenceID === source.evidenceID);
    if (!echo || echo.originalText !== source.originalText || echo.value !== source.value || echo.unit !== source.unit || echo.scope !== source.scope) return false;
    if (source.scope === "mealTotalAmount" && echo !== output.mealTotal) return false;
    if (source.scope !== "mealTotalAmount" && echo === output.mealTotal) return false;
  }
  return true;
}

export function validateFallbackOutput(output, request) {
  if (!shape(output, ["components"]) || !Array.isArray(output.components)) return false;
  if (output.components.length !== request.components.length) return false;
  const keys = ["requestID", "componentID", "description", "basis", "preparation", "preparationText", "consumedGrams", "amountProvenance", "originalUserQuantity", "calories", "protein", "carbohydrate", "fat", "calorieLower", "calorieUpper", "assumptions", "uncertainty"];
  const byID = new Map(request.components.map(item => [item.requestID, item]));
  const seen = new Set();
  for (const item of output.components) {
    if (!shape(item, keys) || !str(item.requestID, 128) || seen.has(item.requestID)) return false;
    seen.add(item.requestID);
    const source = byID.get(item.requestID);
    if (!source || item.componentID !== source.componentID || item.description !== source.description || item.basis !== "consumedComponent") return false;
    if (item.preparation !== source.preparation || item.preparationText !== source.preparationText || item.consumedGrams !== source.consumedGrams || item.amountProvenance !== source.amountProvenance) return false;
    if (!sameQuantity(item.originalUserQuantity, source.originalUserQuantity)) return false;
    if (![item.calories, item.protein, item.carbohydrate, item.fat, item.calorieLower, item.calorieUpper].every(value => num(value) && value >= 0)) return false;
    if (item.calorieLower > item.calories || item.calories > item.calorieUpper || item.calorieUpper > source.consumedGrams * 9) return false;
    if (item.protein + item.carbohydrate + item.fat > source.consumedGrams + 1e-8) return false;
    if (!strings(item.assumptions, 12, 300) || item.assumptions.length === 0 || !strings(item.uncertainty, 12, 300) || item.uncertainty.length === 0) return false;
  }
  return true;
}

const field = (type, extra = {}) => ({ type, ...extra });
const object = properties => ({ type: "object", properties, required: Object.keys(properties), additionalProperties: false });
const list = items => ({ type: "array", items });
const nullable = value => ({ anyOf: [value, { type: "null" }] });
const quantitySchema = object({
  evidenceID: field(["string", "null"]), originalText: field(["string", "null"]),
  value: field("number"), unit: field("string", { enum: units }), scope: field("string", { enum: scopes })
});
const componentSchema = object({
  id: field("string"), name: field("string"), preparation: field("string", { enum: preparations }),
  preparationText: field(["string", "null"]), userAmount: nullable(quantitySchema),
  estimatedAmount: nullable(quantitySchema), assumptions: list(field("string"))
});
export const proposalSchema = object({
  components: list(componentSchema), mealTotal: nullable(quantitySchema),
  question: field(["string", "null"]), assumptions: list(field("string"))
});
const nutritionSchema = object({
  requestID: field("string"), componentID: field("string"), description: field("string"),
  basis: field("string", { enum: ["consumedComponent"] }), preparation: field("string", { enum: preparations }),
  preparationText: field(["string", "null"]), consumedGrams: field("number"),
  amountProvenance: field("string"), originalUserQuantity: nullable(quantitySchema),
  calories: field("number"), protein: field("number"), carbohydrate: field("number"), fat: field("number"),
  calorieLower: field("number"), calorieUpper: field("number"),
  assumptions: list(field("string")), uncertainty: list(field("string"))
});
export const fallbackSchema = object({ components: list(nutritionSchema) });
