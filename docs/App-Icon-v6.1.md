# Powder app icon — v0.6.1

Verified on October 3, 2026. The app uses a native Icon Composer document with a generated foreground image and a native background. The project still targets macOS 14; creating the icon does not raise the app's minimum operating-system version.

## Artwork and native composition

The foreground was generated with the built-in **imagegen** tool. Its concept is a glass simulation vessel containing amber powder, an aqua wave, and a mint energy bead. The exact generation prompt and provenance are recorded in [generation-prompt.md](</path/to/developer/Documents/AI Stuff/Powder Modernization/design/app-icon-v6.1/generation-prompt.md>).

The original PNG is 1254 × 1254 pixels and has an alpha channel. It is retained unchanged at [PowderChamber.png](</path/to/developer/Documents/AI Stuff/Powder Modernization/Native/App/AppIcon.icon/Assets/PowderChamber.png>). Its SHA-256 is `c87b8e0491fe7a93b16dc20e862e0f6b504ae19a761dc99a8b8f00e032cfde5d`.

The artwork contains baked intrinsic glass highlights, shading, and material texture. Those features are not procedural Icon Composer glass, and the sand, liquid, and bead are not separate native layers. The native document supplies the background, foreground placement, silhouette masking, appearance adaptation, and a restrained group shadow. Extra native foreground specular and translucency are disabled to avoid doubling the artwork's effects.

The canonical [icon.json](</path/to/developer/Documents/AI Stuff/Powder Modernization/Native/App/AppIcon.icon/icon.json>) is byte-identical to the successfully rendered and compiled probe document: SHA-256 `592c9fe6b6e50466d5a066b85ebb8625f045090811351bff0304c0fa64b3758e`.

| Setting | Tested value and reason |
| --- | --- |
| Background | `fill.solid = srgb:0.075,0.105,0.145,1.0`; an opaque graphite/blue-gray native background |
| Platform | `supported-platforms.squares = ["macOS"]` |
| Group | One group named `Chamber`, containing the generated foreground |
| Foreground | `image-name = PowderChamber.png`; assets live inside the document's `Assets` directory |
| Scale | `1024 / 1254 = 0.8165869218500797`, mapping the original square into the 1024-point composition without rewriting the image |
| Translation | `translation-in-points = [0, 0]`; the vessel stays centered with the image's existing margins |
| Shadow | `kind = neutral`, `opacity = 0.15` |
| Specular | `false` |
| Translucency | `{ "enabled": false, "value": 0 }` |

These values were accepted by the installed tools and visually inspected in Default, Dark, and TintedDark output. The JSON format is an implementation format verified with this toolchain, not a separately guaranteed public schema.

## Apple guidance and operating-system behavior

Apple's current guidance favors a simple, recognizable composition, clearly defined foreground edges, and square, unmasked artwork. macOS icons use a 1024 × 1024 layout; the system applies the final enclosure. [App icons — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons)

Apple's current Icon Composer documentation explicitly compares macOS 26 and 27 rendering. Refraction has no visible effect before version 27, and the newer inside/outside specular placement falls back to enabled highlights on earlier versions. Xcode generates flattened icon images for deployment targets that predate the modern appearance system. [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

The native appearance system supplies Default, Dark, ClearLight, ClearDark, TintedLight, and TintedDark renditions. Icon Composer presents the clear/tinted family under Mono controls. No six-image substitution scheme is implemented in the app. [Icon Composer](https://developer.apple.com/icon-composer/)

## Verified tools and project integration

| Tool | Installed version |
| --- | --- |
| Xcode | 27.0, build `27A5194q` |
| Icon Composer / `ictool` | 2.0, build `109.4` |
| XcodeGen | 2.46.0 |

The selected developer directory is `/Applications/Xcode-beta.app/Contents/Developer`. Icon Composer 2 declares macOS 26.4 as its own minimum system version; this is a requirement for that design tool, not for the resulting Powder application.

The installed macOS Xcode template provided the starting structure: `Icon Composer Icon.xctemplate/___FILEBASENAME___.icon/icon.json`, with `fill`, `groups`, and `supported-platforms`. The build system recognizes Icon Composer documents as asset-compiler inputs. XcodeGen 2.46 emits a `wrapper.icon` file reference, which the tested Xcode 27 build correctly passes to `actool`.

The canonical package is `Native/App/AppIcon.icon`. The existing recursive `App` source entry includes it; no duplicate resource entry is needed. `Native/project.yml` now sets:

```yaml
MARKETING_VERSION: '0.6.1'
CURRENT_PROJECT_VERSION: '9'
# Under PowderMac.settings.base:
ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

The app icon setting matches the document name without its extension. The asset compiler supplies `CFBundleIconFile` and `CFBundleIconName`; no handwritten icon plist override is required.

## Reproducing the native exports

Run from the `Native` directory, choosing a writable output directory. These commands render the existing document; they do not launch Icon Composer's UI:

```sh
icon_tool='/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool'
icon_output='/private/tmp/powder-icon-review'
mkdir -p "$icon_output"
for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  "$icon_tool" App/AppIcon.icon --export-image \
    --output-file "$icon_output/$rendition.png" \
    --platform macOS --rendition "$rendition" \
    --width 1024 --height 1024 --scale 1
done
```

The exact generated foreground and schema were compiled separately with:

```sh
mkdir -p "$icon_output/compiled"
xcrun actool App/AppIcon.icon \
  --compile "$icon_output/compiled" \
  --platform macosx --minimum-deployment-target 14.0 \
  --target-device mac --app-icon AppIcon \
  --output-partial-info-plist "$icon_output/partial.plist" \
  --output-format human-readable-text --warnings --notices
```

The research probe used the document name `Chamber`; canonical commands above use `AppIcon`. All six probe exports exited successfully. The actual artwork probe produced `Assets.car` (3,459,896 bytes) and `Chamber.icns` (77,928 bytes). A separate tiny XcodeGen app built successfully with a macOS 14 deployment target and contained both compiled resources, both icon plist keys, and `LSMinimumSystemVersion = 14.0`.

This verifies export, compilation, packaging, and fallback generation. It does not claim a runtime test on a Mac running macOS 14. Final Powder release building and visual inspection are performed separately. No GUI was launched by these research probes. Machine-readable details are in [app-icon-v6.1-research.json](</path/to/developer/Documents/AI Stuff/Powder Modernization/evidence/app-icon-v6.1-research.json>).

## Final release check

Powder 0.6.1 (9) built successfully for arm64 and x86_64. The final app contains `Assets.car` (3,459,896 bytes) and `AppIcon.icns` (77,928 bytes), with both icon plist keys set to `AppIcon`. The clean extracted ZIP passed strict ad-hoc signature verification. Its standard About panel displayed the new icon and correct version during a live GUI check. The existing 18,432-particle experiment restored paused. Details are in `evidence/mac-icon-ui-v6.1-notes.md` and `evidence/release-v6.1-summary.json`.
