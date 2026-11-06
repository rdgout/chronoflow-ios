# Designed app icons — 6 November 2026

The user's canvas export, `_design/canvas/AppIcon.dc.html`, selects `AppIcon-default.png`,
`AppIcon-dark.png` and `AppIcon-tinted.png`. Dark is **opaque**: it retains the night sky and ember
horizon. The transparent version is explicitly an alternative on the board, so it stays a design
source. These are the intended legacy designs; the supported Composer build does **not** ship these pixels on iOS 17–25. See the limitation below.
All supplied files under `_design/icon/` and the board are retained unchanged, including SVG masters,
the hand-written Composer starter and reference previews. Previews are approximations, not shipped
glass images. Some board-linked layer/preview PNGs were not included in the supplied export.

`make assets` / AssetGen generates and commits:

- `App/Assets.xcassets/ChronoFlow.appiconset`: exact copies of the three supplied 1024² PNG masters
  and single-size universal iOS any/dark/tinted metadata. The old RN AppIcon set is removed.
- `App/ChronoFlow.icon`: generated JSON derived from the supplied starter and three 1024² PNG layers
  rendered with `rsvg-convert` from its sky/moon SVGs and `layers/background-dark.svg`.
  The moon keeps glass, neutral shadow (0.5) and translucency (0.4); the sky has neither glass nor
  shadow. Every layer has a base `image-name`; Sky uses `background.png` with a dark specialization
  for `background-dark.png`. The document uses `supported-platforms.squares: "shared"`, matching
  the supplied starter and Xcode's Icon Composer template. The canvas fill comes from `colors.json`.
  Clear and tinted treatments are left to the system.

Regeneration requires Homebrew `librsvg`; this run used rsvg-convert 2.63.4 / cairo 1.18.6. Flat masters
are copied rather than reinterpreted from SVG to preserve the delivered pixels. Layer rasterization
is deterministic and preserves the SVG canvas/alpha. AssetGen tests check all eight output files,
freshness, exact flat-master bytes, dimensions/alpha, appearance metadata, glass settings, the
dark sky, base image names on every layer, image references and the supported-platforms schema;
they reject obsolete files in generated icon directories. Existing splash outputs are unchanged.

## Xcode 27.2 integration

Both the catalog set and Composer bundle have the primary name `ChronoFlow`, matching
`ASSETCATALOG_COMPILER_APPICON_NAME`. The catalog is renamed from AppIcon to match the requested
`ChronoFlow.icon` basename. The `.icon` is a single resource file reference, not a recursively copied
directory. XcodeGen 2.46.0 emits the legacy `wrapper.icon` file type; `options.postGenCommand` invokes
`Scripts/configure-icon-project.py` to set `folder.iconcomposer.icon` deterministically and
idempotently. This is part of generation from `project.yml`; the generated project is never committed.

## Legacy-icon limitation — second fix round

**Supported outcome:** iOS 26+ uses the layered Liquid Glass icon. iOS 17 uses a Composer-generated
flat default; iOS 18–25 can use Composer-generated dark and tinted flats. **The supplied
AppIcon-default/dark/tinted PNGs are not preserved as the legacy app icons.** The authored flat
catalog remains generated and checked as a design control, not evidence of what the app ships.
OQ 18 records this limitation; the original dual-source goal is not achieved.

[Apple's current Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
explicitly says a Composer file replaces the existing icon asset catalog, and Xcode creates images
for older releases from that file. Apple directs apps that need their existing icons on older releases
to continue using asset catalogs. It documents no setting to combine an authored legacy bitmap
with a Composer primary icon. [Apple DTS](https://developer.apple.com/forums/thread/813010) requires
the primary icon setting to match the Composer basename; using different primary names is not a
documented OS-version selector. The installed `AssetCatalogCompiler.xcspec` exposes the primary
name and include-all settings but no legacy-source override. Keeping additional icons under other
names would not establish that older systems select them as the primary icon.

The previous `--enable-icon-stack-fallback-generation=disabled` workaround is undocumented.
The user's combined compilation with that flag succeeded, but its stored flats differ from the
supplied PNGs. Removed it from `project.yml`; `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`
remains enabled. No binary CAR editing, alternate-icon switching, deployment-target changes,
compatibility opt-out or custom runtime icon selection is introduced.

### Observed content, independently of rendition filenames

Read the supplied `icon-car-info.json` and the existing `build/icon-actool/Assets.car` without
running actool or assetutil. `Scripts/icon-pixels.m` opens the catalog through host CoreUI using
`dlopen`, selects the phone's 1024-square multisize icon for each appearance, and reads the stored
`_CUIThemePixelRendition.unslicedImage`. It refuses a different image/rendition class, so this is
not an IconServices rendering of the glass stack. All three selected bitmap names match the UUID
names in the saved metadata. All are opaque. Decode both those bitmaps and the authored PNGs
into sRGB, RGBA8, premultiplied alpha, then SHA-256 the pixel bytes:

| Appearance | Stored bitmap RGBA SHA-256 | Designed PNG RGBA SHA-256 |
| --- | --- | --- |
| Any | `275859459d4a513afaaba5a2df0df90f80c83665858bb86d34949c83c84e098b` | `cae48743d30f54466f41a40588924b84e1a1534df302cdfb198f46384cb30ae9` |
| Dark | `cbda7aeaf30a772813e8e1489c25d7b0d52c4adc079a192df00a2a0d752aa4a0` | `6cb182e55862db9bc0ba9502fd2a9c700805f82846dc331c7d1e3ac08e8967f1` |
| Tinted | `92cf05b75ac21555bacb0ee699c57b486ef15669191a6feb1631055c136706b1` | `c97233d1b86272964b0e5bde6d1572124fb718ec3fc8bac92171cc2bbe544ca0` |

This proves the stored images are **not simply renamed designed PNGs**. Apple's documented
behavior identifies Composer-generated replacements as the expected source. An independent
Composer-only compilation is still required to prove that attribution by content; this sandbox
has not run the host's compiler controls. Do not describe that remaining check as passed.

### Reproducible host probe and audit

`make icon-probe` prints and executes four unthinned compilations with the same platform,
deployment target, primary name and include-all setting:

1. `flat`: asset catalog alone, to establish the compiler's treatment of the authored PNGs.
2. `composer`: `.icon` alone, to establish generated fallback content independently of the catalog.
3. `combined`: both inputs with supported settings, matching the project.
4. `combined-disabled`: both inputs plus the old undocumented flag, to measure whether it changes content.

An optional `ICON_EXISTING` catalog is also classified. Each appearance is compared by decoded
pixel digest against the source PNG, flat-only control and Composer-only control. The probe writes
`build/icon-probe/report.json`, complete `assetutil --info` output and PNG exports in each case's
`pixels/` directory. UUID filenames and CAR compression do not affect the comparison. It saves
the report **before** its assertions, so unexpected compiler behavior remains inspectable. It fails
if flat-only differs from the source PNGs or supported combined output differs from Composer-only;
if either happens, paste the report back for investigation rather than changing the acceptance check.
The old flag's result is reported independently, not assumed to work or fail on a given toolchain.

`Scripts/check-app-icon.py` requires those fresh controls, validates their source hashes and Xcode
version, verifies the flat-only control against the designed PNGs, and compares the shipped bitmap
pixels with the Composer-only control. It also checks all three phone icon appearances, opacity,
1024-square dimensions, all three Liquid Glass stack appearances, and the built app's primary-icon
metadata. It explicitly prints whether each designed PNG was preserved. `--flat-only` instead requires
the designed pixels and does not require the glass stack. The helper is compiled under `build/`;
private CoreUI APIs exist only in this Mac audit utility and are never linked into the iOS app.
A host CoreUI API change fails the audit rather than selecting a rendered stack silently.

Run these commands **in order**, from the host (the existing catalog is the one from the failing audit):

```sh
cd /Users/rickgout/Sites/chronoflow-ios-icon
make generate
make quick
make icon-probe ICON_EXISTING=build/icon-actool/Assets.car
python3 -I Scripts/check-app-icon.py build/icon-probe/combined/Assets.car

xcodebuild -project ChronoFlow.xcodeproj -scheme ChronoFlow -configuration Debug \
  -derivedDataPath build/DerivedData -onlyUsePackageVersionsFromResolvedFile \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=27.2' build-for-testing
make icon-audit
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AppIconTests"
```

For a fresh checkout without the earlier catalog, omit `ICON_EXISTING=...`. To classify just that
catalog after creating the controls, run `python3 -I Scripts/check-app-icon.py build/icon-actool/Assets.car`.
To audit the authored control explicitly, run
`python3 -I Scripts/check-app-icon.py --flat-only build/icon-probe/flat/Assets.car`.

The unthinned probe establishes legacy content independently of the installed simulator OS.
The hosted suite checks primary fallback image loading, appearance keys and the glass stack;
the host audit owns pixel provenance. No hosted assertion depends on original rendition filenames.
Build, independent compiler controls and hosted AppIconTests remain host acceptance gates;
passing the Mac fixtures or decoding the saved CAR does not complete those gates. Inspect the icon
in Icon Composer/Home Screen for default/dark/clear/tinted appearance intent. No simulator matrix
is needed for this icon-only change. Splash assets and launch behavior are unchanged.
