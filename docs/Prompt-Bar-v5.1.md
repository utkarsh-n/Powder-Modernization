# Floating scene prompt bar · 0.5.1

The Mac workspace shows a floating prompt bar at the bottom of the canvas by default. It uses the native translucent `regularMaterial` appearance and keeps the existing On Device and Cloud providers.

| Action | Control |
| --- | --- |
| Show and focus the prompt | Sparkle toolbar button or **⇧⌘G** |
| Show or hide the bar | **⌥⌘P** or View → Show/Hide Prompt Bar |
| Hide the bar | **×** at its upper right |
| Generate the described scene | Arrow button or **⌘Return** |
| Stop an active request | Stop button in the bar |
| Choose a provider | On Device/Cloud menu |
| Configure the model or cloud key | Gear button or Intelligence Settings |
| Read the generated plan and observations | Scene-details button after a result is available |

The visibility preference persists between app launches. Within the current workspace, hiding and restoring the bar preserves the draft, selected provider, and generation progress. Hiding is separate from Cancel: an active request continues and can still install its result. Restore the bar to check progress or stop it. Draft and in-flight request retention across app restarts is not provided.

A successful request still creates a separate candidate, runs the existing 45-step check, and installs the initial scene paused as one undoable edit. Undo restores the previous experiment. This interface change does not change the providers' generation limits or establish that arbitrary requested machines will work. Provider behavior, requirements and earlier model evidence are documented in [Scene intelligence and rendering](Intelligence%20and%20Rendering.md).

## Validation scope

The 0.5.1 Release build passed for arm64 and x86_64. The packaged app passed strict ad-hoc signature verification and was launched from the extracted ZIP on Apple Silicon. Logs: `evidence/mac-build-v51.log` and `evidence/mac-package-v51.log`.

Native UI checks on October 2, 2026 verified:

- The bar is visible on launch without taking text focus. The sparkle action and **⇧⌘G** focus the prompt.
- **×** hides the bar and restores canvas focus. **⇧⌘G** restores the exact draft; **⌥⌘P** hides and restores it. **Escape** returns to the canvas.
- Typing a literal Space and pressing **⌘→** in the prompt left the test scene paused with 73,841 particles at step 0.
- The floating layout fits with the inspector both open and closed. Prompt and toolbar interaction did not paint the underlying scene.
- **⌘Return** started on-device planning with a disabled editor and Cancel control, then installed “Sand-Water Ecosystem” paused with 21,519 particles. Its draft, result status and plan button survived hiding/restoring the bar. Canvas Undo restored the original 73,841-particle example.

The runtime check used `--showcase`, keeping autosaved user experiments separate. Cloud generation, minimum-window sizing, cancellation during execution, and hidden in-flight completion were not re-exercised in this UI pass. Intel is compile-verified, not runtime-verified.

![Floating prompt bar](../evidence/mac-v51/floating-prompt.png)

The earlier 0.5 engine, worker, file-workflow and performance results remain separately recorded in [Mac v5](Mac-v5.md), [Engine Performance](Engine%20Performance.md), and [Rendering v5](Rendering-v5.md). They are not rerun or relabeled as evidence for this UI change.
