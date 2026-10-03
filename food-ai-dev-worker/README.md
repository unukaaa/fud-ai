# FOOD AI isolated development Worker

Owner-controlled development Worker, deployed only to
`food-ai-dev-api-20261002.unukabrandon.workers.dev`. Cloudflare's global All
Workers Access policy protects production and preview traffic. The Worker also
fails closed when its Access identity/audience check, owner or Builder allowlist,
rate-limit binding, or API secret is absent. No iOS journey is mounted.

The endpoint is a provider-interaction boundary, not a nutrition engine:

- `POST /api/grounded-estimate/v1/proposal` takes the existing
  `FoodQuantityInterpretationContract` JSON (`version`, `description`,
  `quantities`) and returns a versioned `FoodMealProposal` JSON proposal.
- `POST /api/grounded-estimate/v1/fallback-batch` takes independently eligible
  `AIComponentNutritionRequest` objects, at most six, and returns one
  `AIComponentNutritionProposal` per request. The Worker does not decide
  fallback eligibility or aggregate nutrition.

The Swift semantic firewall, trusted grounding, estimate methodology,
component fallback validator and complete-only aggregation remain authoritative.
The Worker validates shape, size, ID/quantity echoes and batch membership;
those checks do not replace FOOD AI's semantic validation.

The active development adapter uses OpenAI Responses with `gpt-6-luna`, low
reasoning, structured JSON output and `store: false`. Provider selection is a
server configuration concern, not a client request field. Provider errors and
keys are never returned to callers. Only non-content error categories are
logged. There is no hard global dollar cap in this stateless Worker: the rate
limit is local to a Cloudflare location and the owner must separately cap or
monitor the OpenAI project budget.

For any later authorized deployment or configuration change, preserve these gates:

1. Keep Cloudflare Access protection on **all traffic**, not previews only.
   Only the approved owner email or exact Builder service identity may pass
   the Worker's second authorization check.
2. Keep `OPENAI_API_KEY`, `DEV_OWNER_EMAIL`, `ACCESS_POLICY_AUD`,
   `ACCESS_BUILDER_CLIENT_ID`, and `ACCESS_TEAM_DOMAIN` in Worker secrets.
   Never paste their values into source or chat.
3. Maintain the OpenAI project budget and design a native owner login flow
   without a static Builder service token in the iOS binary.
4. Verify the development rate-limit `namespace_id` does not collide with any
   binding already used in the owner's account; Cloudflare shares counters for
   bindings using the same ID. The Worker name was checked absent, but no
   account-wide binding inventory was available in this local preflight.

`DEV_OWNER_EMAIL` is a second, Worker-side allowlist check against the
Access-authenticated email; it is not an iOS credential. The approved Builder
service identity is checked against a Cloudflare-signed Access assertion, not
against caller-supplied identity headers. No RevenueCat, KV,
D1, upstream domain, static asset, Discord, GitHub or Deepgram configuration is
present. The only Cloudflare binding is the isolated development rate limiter.

The reused architecture remains subject to the accompanying MIT licence.
