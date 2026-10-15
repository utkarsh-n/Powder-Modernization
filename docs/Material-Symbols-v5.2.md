# Material symbols · 0.5.2

Every sidebar entry now has a stable SF Symbol tinted from its engine color: all 194 materials and 19 walls, plus the erase tool. There are 214 distinct symbol names, with no repeated symbol/color pairs. Search results, library filters, the current brush and the inspector use the same mapping.

The symbols suggest material or tool behavior: water uses a drop, sand an hourglass, glass overlapping panes, metal stacked plates, fire a flame, plant a leaf, wood a tree, uranium the radiation mark, plutonium an atom, the fan wall fan blades, and the stasis wall a pause control. Related materials use distinct variants where appropriate.

`MaterialSymbolCatalog.swift` assigns every actual engine identifier explicitly, including `116` and `HFLM`, whose display names differ from their identifiers. Icons use monochrome rendering so built-in SF Symbol palettes cannot replace the material tint. Dark pigments are lightened in dark appearance, and pale pigments are darkened in light appearance; the pigment hue is retained. Increased Contrast strengthens this adjustment. Simulation colors, behavior and saved data are unchanged. Symbols are hidden from accessibility because their existing row labels already name and describe each material.

## Verification

- The production catalog was enumerated against the linked engine: 194 materials + 19 walls + erase, with no omissions or stale mappings.
- Every symbol loaded through AppKit. Apple's installed SF Symbols availability metadata confirmed availability on macOS 14.0 or earlier.
- The original, dark and light symbol/color pairs were checked for duplicates: none.
- All 214 symbols were rendered into light and dark contact sheets. The running app's All Materials sidebar and current-brush icon were also visually inspected.
- The universal Release build passed for arm64 and x86_64. The extracted app passed strict ad-hoc signature verification and launched on Apple Silicon. Intel and macOS 14 are build/metadata verified, not separately runtime tested.

Run the catalog audit after building Release with `zsh scripts/verify-material-symbols.sh`. It links the actual production mappings, tint conversion and engine, exports `catalog.json`, and renders the contact sheets. It reads Apple's metadata from the installed SF Symbols app; it does not change the app's experiment.

Evidence: `evidence/material-symbols-v52.log`, `evidence/material-symbols-v52/catalog.json`, `evidence/mac-build-v52.log`, and `evidence/mac-package-v52.log`. Prior engine and Metal performance tests remain the earlier release's evidence and were not rerun for this presentation-only change.

[Apple SF Symbols](https://developer.apple.com/sf-symbols/) · [Apple symbol image guidance](https://developer.apple.com/documentation/swiftui/image/init(systemname:))

![Dark symbol catalog](../evidence/material-symbols-v52/symbols-dark.png)

![Light symbol catalog](../evidence/material-symbols-v52/symbols-light.png)
