# Live on-device conversation verification — 0.6

The final canonical provider completed one benign two-turn consultation and returned a usable scene plan on this Mac. The first request was **“Build a glass container with water inside.”** The model asked only for the missing container shape. The probe selected **Circular**, accepted the recommended defaults, and requested a complete proposal. The second request used the same packed history as the controller: original request, retained choices, ordered offered options, and the latest answer.

The final production change separates the phases explicitly. Ordinary messages generate a consultation; **Use these choices** requests a nonoptional proposal schema. This avoids relying on the model to choose between an empty question array and an optional proposal. The proposal retained GLAS, WATR and the circular shape, without introducing material or reaction suggestions from the optional community references.

| Stage | Measured result |
| --- | --- |
| Initial consultation | 4.923 s; one shape question |
| Accepted choices → complete proposal | 5.533 s; zero further questions |
| Proposal → canonical AppleScenePlanner | 9.042 s; validated 65-command plan |
| Initial engine world | 5,770 GLAS and 1,260 WATR particles |
| After 45 engine steps | Same counts, all finite, zero water outside the glass chamber |

The plan uses 64 connected GLAS line segments for a hollow circle with center `(305.5, 195.33)` and radius `153.2` pixels, plus one water command. An independent coordinate check measured no segment gaps and approximately `2 × 10⁻¹³` pixels of radial error before rasterization. A flood fill from the canvas perimeter verified that the glass encloses 69,626 empty interior cells and that every water particle remains separated from the outside, both initially and after 45 steps. Water mean Y moved from 270 to 311.69 as it settled. The generated phrase “at rest” describes a passive starting scene; it is not evidence of physical equilibrium.

## Evidence correction

The first version of the probe incorrectly required a `.circle` command. Large circular shells are deliberately compiled as closed polylines to respect the bounded primitive radius. As a result, the original probe log reports `planChangedGeometry` **after** saving a successful live proposal and plan. Those original logs and result files remain unchanged. A separate, model-free review loaded the exact saved plan and verified its coordinates, hollow topology and 45-step engine behavior. No inference was rerun to obtain a more favorable result, and no production geometry was changed to satisfy the test.

- [Original live results and timings](../evidence/on-device-conversation-v6-final-circular/benign-water/result.json)
- [Saved live plan](../evidence/on-device-conversation-v6-final-circular/benign-water/plan.json)
- [Independent geometry and engine review](../evidence/on-device-conversation-v6-final-circular/benign-water/geometry-review.json)
- [Review log](../evidence/on-device-conversation-v6-final-circular/benign-water/geometry-review.log)
- [Original source hashes](../evidence/on-device-conversation-v6-final-circular/canonical-source-sha256.txt)

The reviewed plan SHA-256 is `3af9fbd473eeceec27ee3720b15151d5db138277feb3225329c11862167dc241`. Initial and after-45-step `.powderlab` files are stored beside the review. The reproducible offline check is `Native/scripts/review-saved-circular-scene.sh <directory-containing-plan.json>`; the live probe uses `Native/scripts/run-scene-consultation-probe.sh` with mode `canonical-circular`.

## Context and failure handling

The model reports a 4,096-token context on this host. With the real generated schemas included, the first request used 1,683 input tokens; the second used 1,498. Each reserved 1,800 output tokens and 256 tokens of additional overhead, for budgets of 3,739 and 3,554 respectively. The second request retained the actual offered question and explicit choices; it was not reduced to an isolated answer.

The adapter measures tokens on macOS 26.4 and later, and uses a conservative byte-based estimate on macOS 26.0–26.3. Response space can adapt between 1,200 and 1,800 tokens. If necessary, optional references and redundant assistant design snapshots are removed before older incidental assistant chatter. User turns, offered choices and the context for short replies are retained. If the remaining decisions cannot fit, the app asks for a shorter new conversation or Cloud rather than silently discarding choices. The older-OS estimate was not live-tested in this run.

One bounded retry can repair locally invalid structure, including an empty response with neither questions nor a proposal. Model refusals, guardrail errors and context errors are not retried. The newest explicit user revision takes precedence over older selections. Shared validation rejects bundled word alternatives such as `rectangular/circular`, while allowing numeric ratios such as `50/50`.

## Earlier failures and limits

Earlier evidence directories retain the initial refusal, minimal benign diagnostic, incomplete-proposal response and repeated-question loop. Removing unrelated examples from shared instructions allowed benign consultation; explicit phase selection then resolved the loop observed in the recorded case. The original request **“build a glass wall with explosive material inside”** was declined by the on-device provider in the baseline run. That refusal was respected, and the original request was not rephrased or retried to evade it. The baseline adapter exposed the normalized refusal rather than preserving whether the underlying service categorized it as a refusal or guardrail violation.

This is one successful live benign scenario, not a guarantee that every prompt, community design or complex machine will work. The scene planner remains bounded to supported layouts and components. Thirty-nine cloud package tests used injected HTTP transports; no live cloud credentials or billable cloud generation were used. Twelve current controller/provider-helper tests and one wall-worker regression passed in [the final focused run](../evidence/conversation-wall-final-tests.log).

All probes used isolated in-memory engine worlds and evidence files. They did not open the app, change the user's canvas, read credentials or write autosave state. Opening the final packaged GUI remains a separate approval decision handled by the parent task.
