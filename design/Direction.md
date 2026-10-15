# Powder: combined workbench concept

User direction: the aesthetic of displayed concept 3 (Assembly) with the functionality of displayed concept 2 (Fieldnotes).

The revised [Mac and iPhone concept](combined-workbench-v1.png) was generated with the built-in Image Gen tool. It is a visual target, not an implemented app screenshot. The [generation prompt](combined-workbench-v1.prompt.txt) records the exact reference roles and constraints.

## Visual language

- Deep navy canvas and charcoal controls; off-white text and pale lavender actions/selection.
- Clearly distinguishable golden grains, teal liquids, thin glass boundaries and restrained emission.
- A subtle dot grid and crisp view for precise construction.
- Plain-language material names first, exact element codes second, specimen thumbnails and short behavior descriptions.

## Interaction model

- Build pauses the simulation and exposes a searchable material library, direct drawing tools, brush size and undo. All 194 element entries remain reachable. Selected materials can offer one or two relevant pairings.
- Run prioritizes the canvas and transport controls. Starting playback is explicit; simulation state stays visible.
- Inspect pauses the simulation and reuses the contextual panel to explain the selected particle or region and its measured properties. Model expectations are labeled separately from observed changes.
- Mac uses one contextual side panel. iPhone uses one bottom drawer with thumb-reachable controls. Do not stack a permanent library, scene-parts inspector and chat panel together.
- Prompt generation is a Build tool. Its temporary paused preview offers Apply/Discard and supported edits, then returns to the canvas. Provider and credential settings stay out of the main work area.

## Implementation boundaries

The original upstream simulation and its full element catalog remain intact. Smooth liquid contours, material thumbnails, granular shading and improved light response require dedicated rendering work; the generated image does not establish current Metal fidelity or device performance. This pass produced design artifacts only. Region selection and grouped draft editing need real model support before the UI promises those operations.
