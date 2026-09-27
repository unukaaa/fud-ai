# FOOD AI Agent Instructions

## Product principles

FOOD AI is an iOS calorie and food tracking app. Be **fast when clear, clarify when it matters, and make correction easy**. Prefer premium, minimal, native Apple-style UX; avoid unnecessary screens, controls, confirmations, and technical language.

## Engineering and nutrition

- Correctness and truthful nutrition provenance matter more than making every query appear successful. Never silently drop a meaningful food or invent deterministic nutrition. Preserve working behaviour unless the task requires a change.
- Prefer small, generic architectural fixes over query-, product-, or restaurant-specific patches. Do not build giant keyword or typo dictionaries.
- Pipeline: user input → Food Query Interpreter → structured food intents/components → Nutrition Resolution Engine → material clarification → Review Food → logging/history. The interpreter understands language; the resolver calculates nutrition. Keep them separate.
- Source preference: exact label/barcode → verified Australian restaurant/menu data → strong AUSNUT match → structured Australian food/takeaway estimate → AI estimate.
- Mixed-source meals retain component provenance. One verified component does not make the whole meal verified.

## Multi-food completeness

Every meaningful identified food component must end as verified restaurant, label/barcode, AUSNUT, structured estimate, AI estimate, or explicitly unresolved/needs clarification. Completeness asks whether every **food component** has an appropriate terminal resolution—not whether every word received nutrition. Quantities, conversational wording, and syntax are not phantom foods. Exhaust suitable fallback before declaring an understood food unresolved. Never double-count children of a configured restaurant meal.

## Restaurant architecture

Restaurant support should primarily be data/config driven. Avoid restaurant-specific Swift parsing or resolution branches unless explicitly approved and architecturally unavoidable. Current verified Australian datasets: KFC Australia, McDonald's Australia, and a limited Boost Juice Australia POC. Only official Australian nutrition may be marked verified; unsupported products must not acquire invented verified values. Future brand discovery should offer product choices for generic inputs such as “KFC”, “Maccas”, or “Boost”, rather than guessing what was eaten.

## Clarification and regression protection

**Assume the obvious. Clarify the consequential. Never interrogate.** Ask only when missing information materially changes identity or nutrition. Normally use at most one Quick Check with one or two meaningful groups. Do not re-ask supplied information or treat unmentioned optional extras as missing. Provide “Not sure” or best-estimate paths where appropriate.

Phase 2D clarification/logging is known-good unless a regression is proven: clear banana and sufficiently detailed eggs/toast go direct; materially ambiguous eggs/toast gets grouped Quick Check; quantities persist; successful logging gives brief confirmation and returns to Today. Do not rewrite this while fixing unrelated systems.

## Review Food, images, and search

- Review Food is the final correction point and must retain detailed editing. Do not redesign it during interpreter/resolver work unless requested. Normal confidence presentation is “✨ AI estimate” or “⚠️ Check estimate” for material uncertainty, never raw LOW/MEDIUM/HIGH labels.
- Photo path: user image → AI analysis → Review Food → saved meal → Today/history. Preserve the original image. Image fallback order: user image → trusted product/food image → cached image → neutral placeholder → emoji as a legacy last resort. Do not generate AI food images.
- Food Search should eventually distinguish clear known food (resolve), incomplete brand/product intent (suggest products), understood unsupported food (AUSNUT/structured/AI fallback), and genuinely unclear input (clarify). Suggestions and natural-language logging must use the same Nutrition Resolution Engine.

## Diagnostics

Prefer lightweight DEBUG-only resolution traces: original/interpreted query, components, quantities/modifiers, restaurant/brand context, deterministic candidates, selected resolver, terminal state, provenance, confidence, unresolved reason, and completeness decision. Keep diagnostics out of customer UI; never log credentials, API keys, or unnecessary personal information.

## Testing and Codex usage

Conserve agent usage. Default workflow: read this file → inspect relevant code/tests and git status → identify root cause → make the smallest generic change → run only focused relevant tests → inspect task-related diff → report and stop. Do not run the entire suite or an Xcode build after every small change; reserve broader regression/build checks for deliberate quality gates. Claim PASS only after genuine successful command exit. Arm64 simulator builds are valid; universal simulator builds may fail because LiteRTLM lacks x86_64 support. Do not fix unrelated dependency/build issues during another task.

Prefer minimal safe Swift concurrency changes. Do not introduce broad `@MainActor` annotations or refactors just to silence warnings; handle known warning debt separately.

## Git and scope hygiene

Always inspect git status before editing. Preserve user changes; do not clean, revert, overwrite, commit, or push unless expressly instructed. In particular, leave these known unrelated modified files untouched unless targeted: `project.pbxproj`, `Info.plist`, `InfoPlist.xcstrings`, `LocalModels.xcstrings`, `Localizable.xcstrings`, and `WeeklyChallenge.xcstrings`. Inspect the exact task-related diff before finishing.

Do not opportunistically redesign unrelated UI, expand restaurant datasets, clean warnings, refactor working architecture, change project settings/localization, or update dependencies. Report unrelated issues instead.

## Development direction

1. Stabilize Food Query Interpreter and multi-food completeness.
2. Build food/brand discovery.
3. Hungry Jack's Australia restaurant POC.
4. Review Food/provenance redesign.
5. Broader Australian restaurant coverage.
6. Later expose the Nutrition Resolution Engine to AI Coach.

Do not jump ahead unless instructed. For normal coding tasks, report root cause, implementation, focused tests with exact results, changed files, and remaining concerns; then stop unless broader validation, a commit, or a push was requested.
