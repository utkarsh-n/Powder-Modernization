# Powder 0.6.2 scene building

The **Built-in** scene builder keeps supported scene construction available without a language model. It interprets recognized material names, element codes and layout choices, then constructs an editable scene with the original simulation engine. It uses the app's macOS 14 baseline and needs neither Apple Intelligence nor an API key. It is deterministic game software, not another AI model. This guide reflects the implementation; final test and build verification is recorded separately below.

## Build and review

Choose **Built-in** in the provider menu, describe the container and contents, then answer any missing choices. For a vague request such as “build a glass wall with explosive material inside,” the builder asks for the enclosure shape and which **in-game** material to use: GUNP, PLEX or DESL. A container and a freestanding wall are different layouts; review the proposal to make sure the interpretation matches your intent.

Supported layouts are a closed rectangular chamber, a physically circular hollow chamber, an open tank, a vertical wall, separate material samples and the bounded concentric-ring arrangement described below. Balanced, compact, spacious and layered compositions are available. The builder supports up to eight distinct contents plus one solid container. Requests for complex machines or unsupported relationships ask for an explicit simplified arrangement; selecting that arrangement does not reproduce the original machine.

Examples for the bounded builder:

| Request | Layout interpretation |
| --- | --- |
| “Circular glass container with water inside” | Hollow GLAS chamber containing WATR |
| “Rectangular glass chamber with gunpowder inside” | GLAS enclosure with the game's GUNP particles |
| “Glass container with C4 inside” | GLAS enclosure with PLEX, displayed upstream as C-4 |
| “Open glass tank with water and sand” | Open GLAS container with WATR and SAND |

These are game-layout examples. The pinned original source describes GUNP as a powder that reacts to fire or spark, PLEX as a pressure-sensitive game explosive, and GLAS as breakable under pressure. A glass chamber is therefore not a promise of containment after activation. The builder adds no ignition source by default; explicitly requesting in-game ignition adds FIRE to the reviewed materials. Material provenance: [GUNP](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/elements/GUNP.cpp), [PLEX](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/elements/PLEX.cpp), [GLAS](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/elements/GLAS.cpp).

The proposal and isolated preview remain the review point. The 45-step trial reports observed early behavior; it does not prove that a complex mechanism works indefinitely. **Confirm scene** is the explicit action that replaces the canvas, and that replacement remains undoable. **Stop** cancels work without starting a fallback.

## A ring with a center and coating

The reported request was **“generate a ring of wood with a ball of fire inside wrapped with uranium.”** The added concentric layout assigns distinct roles to WOOD as the hollow outer ring, FIRE as the central ball and URAN as the coating. Because “wrapped” leaves the coating's position ambiguous, **Uranium placement?** offers **Around the fire ball** or **Outside the wood ring** before preparing the scene. This preserves the ring-and-ball relationship instead of replacing it with three rectangular material samples.

These shapes describe the **initial arrangement**. URAN retains the original game's falling-powder behavior, so its coating can settle under gravity instead of remaining a rigid shell. FIRE is explicitly requested here: it starts hot with the game's normal finite lifetime, and may decay or ignite nearby wood as the scene evolves. The app does not silently freeze either material to preserve the design. Original behavior sources: [URAN](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/elements/URAN.cpp) and [FIRE](../Native/Packages/PowderEngine/Sources/CBridge/Upstream/simulation/elements/FIRE.cpp).

The added parser supports these named concentric roles; it is not a general geometry interpreter. Review the coating choice, initial preview and trial separately. The live failure that motivated this addition is recorded in [the UI reproduction](../evidence/mac-fallback-v6.2-ui.md).

## Provider and fallback behavior

The selected provider and the source of a result are shown separately:

| Selected provider | Execution |
| --- | --- |
| Built-in | Uses the local catalog and layout parser directly |
| On Device | Recognized simple game layouts can use the local builder immediately; other requests use Apple Intelligence when available |
| Cloud | Uses the selected OpenAI model when a key is configured; otherwise continues locally |

If a model attempt is unavailable, declined, malformed or fails to complete, the router continues with the bounded local builder and identifies that result as **Built-in scene builder**. If the model's proposed relationships cannot be reproduced locally, the app offers explicit supported layout choices instead of silently substituting geometry. Plan validation requires the approved material set; empty-space carving is allowed, but unrequested particles are rejected.

Fallback never silently enables Cloud or supplies an API key. Cloud requests require Cloud to be selected and a configured key. Local follow-up choices stay on the local route while that provider selection is unchanged. Switching providers or configuring a Cloud key clears that follow-up override; a fresh typed revision follows the selected route. Retrying an already reviewed local proposal can still compile its exact local layout. Request identifiers, cancellation checks and isolated candidate worlds prevent late results from replacing the canvas.

## What Apple's APIs support

Apple documents separate availability states for an ineligible device, Apple Intelligence being disabled and a model that is not ready. Apps should check availability and present an alternative flow. The local builder provides that alternative without changing the model's requirements. [Apple model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason). Apple's design guidance also recommends a non-AI fallback where feasible and clearly identifying when AI is used. [Apple Generative AI guidance](https://developer.apple.com/design/human-interface-guidelines/generative-ai).

Apple distinguishes model refusal from input/output guardrail failure. Structured guided generation still uses the default checks. The documented permissive text-transformation option does not change that structured path; this release does not alter guardrail settings or rewrite a refused request to make the model accept it. A separately labeled game builder handles its own supported operations without another inference attempt. [Apple guidance on model safety](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output).

Generation options control sampling, temperature and response length. They do not promise that a model will accept a request. Apple warns that a hard response-token cap can end output early and yield malformed results. The existing adapter therefore validates every response and budgets instructions, history and generated schemas against the model's context size. [Apple generation options](https://developer.apple.com/documentation/foundationmodels/generationoptions), [Apple context guidance](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window).

## Scope and provenance

The local parser recognizes a finite vocabulary and bounded layouts. It does not understand every sentence, generate arbitrary precise geometry or reproduce any community machine from its title. Unknown or ambiguous requests need clarification or manual editing. Material codes are the least ambiguous input. Model-generated plans also remain subject to schema, material and engine validation. Read the proposal and preview before confirming; parsed language is not proof that every nuance was understood.

Community references retain their original source links and their description-based status. They are optional inspiration, not inspected save internals, verified machine blueprints or permission to add unrequested reactions. No community saves are executed by this workflow. See [community reference provenance](Community-References-v6.md).

## Earlier verification

Before the concentric extension, the full headless run passed **65 tests**: 11 local-builder, 18 routing, 15 controller, five session and 16 worker tests. A focused rerun passed 12 tests, including the declined glass/explosive request through local choices, preview, confirmation and Undo. This also covers removing an earlier ignition source after a negative instruction. The intelligence package passed 39 injected-transport tests, and the universal macOS build succeeded. These results apply to the earlier source snapshot, not the subsequent concentric extension. Evidence: [full headless run](../evidence/fallback-v6.2-tests.log), [focused rerun](../evidence/fallback-v6.2-final-local-tests.log), [Cloud package tests](../evidence/intelligence-package-v6.2-tests.log), [build log](../evidence/mac-build-v6.2.log).

These earlier checks are superseded by the final release verification below. The earlier Apple circular-water success and original refusal remain recorded in [live conversation verification](Conversation-Live-v6.md); they are historical provider evidence, not verification of the new fallback. No live paid Cloud request is claimed by the injected-transport tests.

## Final release verification — October 3, 2026

The final universal 0.6.2 build 10 passed. **69 headless app/engine tests** passed, including 15 local-builder tests, 18 routing tests, 15 conversation-controller tests, 5 session tests and 16 worker tests. The 15 local tests include both concentric uranium placements using real 45-step engine trials. The separate Cloud/conversation package passed **39 tests**. Total: 108 distinct tests, zero failures.

The final source, headless harness and release staging matched. The packaged ZIP contains arm64 and x86_64, retains the native icon, and a clean extracted app passed strict ad-hoc signature verification. No changes were made to the original simulation physics or Metal renderer.

Live GUI verification of the exact wood/fire/uranium request succeeded: it asked for uranium placement and composition, generated a labeled Built-in preview, completed the 45-step trial and enabled Confirm. The existing 18,432-particle canvas stayed paused and unchanged. The app was left open on the new preview.

Evidence: [final app tests](../evidence/fallback-v6.2-final-tests.log), [Cloud package tests](../evidence/intelligence-package-v6.2-tests.log), [final universal build](../evidence/mac-build-v6.2-final.log), [native UI verification](../evidence/mac-fallback-v6.2-ui.md), [release manifest](../evidence/mac-release-v6.2-source-manifest.json). Refusal/error routing tests inject service failures; no new paid Cloud call or attempt to override Apple's model controls was made. macOS 14 and Intel deployment compiled successfully, but runtime verification used this Apple Silicon development Mac.
