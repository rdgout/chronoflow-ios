# Designed app icons — 6 November 2026

The user's canvas export, `_design/canvas/AppIcon.dc.html`, selects `AppIcon-default.png`,
`AppIcon-dark.png` and `AppIcon-tinted.png`. Dark is **opaque**: it retains the night sky and ember
horizon. The transparent version is explicitly an alternative on the board, so it stays a design
source. iOS 17 uses default; iOS 18–25 can use the designed dark and grayscale tinted variants.
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

Offline evidence in the installed Xcode 27.2 (27B52) toolchain:

- `Contents/SharedFrameworks/XCBuild.framework/Versions/A/PlugIns/XCBBuildService.bundle/Contents/PlugIns/XCBSpecifications.ideplugin/Contents/Resources/StandardFileTypes.xcspec`
  declares `folder.iconcomposer.icon`, extension `icon`, based on `folder.abstractassetcatalog`.
- The adjacent `AssetCatalogCompiler.xcspec` groups both `folder.assetcatalog` and
  `folder.iconcomposer.icon` as actool inputs. It maps `ASSETCATALOG_COMPILER_APPICON_NAME` to
  `--app-icon` and `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` to `--include-all-app-icons`.
- `Contents/Developer/usr/share/man/man1/actool.1` documents primary-icon compilation into Assets.car
  for iOS 11+, and the partial Info.plist that Xcode merges into the app.
- The Icon Composer file template contains `fill`, `groups` and `supported-platforms`, with
  `squares` encoded as the string `"shared"`. Individual group/fill decoder round-trips do not
  establish document validity; the host's full actool compilation remains the acceptance check.
- The installed AssetCatalogFoundation contains `enable-icon-stack-fallback-generation` and the
  fallback-generation option. The project passes `--enable-icon-stack-fallback-generation=disabled`
  and includes all app icons to retain supplied flat renditions alongside the stack. These settings
  require the combined compilation check below; merely having source files is insufficient.

[Apple's Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
notes that Composer can replace existing icon catalogs with generated older-platform images.
[Apple DTS](https://developer.apple.com/forums/thread/813010) confirms the primary setting must match
the Composer basename. The undocumented fallback flag is toolchain-dependent; its presence alone
does not prove that a compiler honors it. The audit rejects missing designed renditions, including
when a compiler substitutes Composer-generated flat images. A failed audit blocks acceptance.

## Verification

Verified here: `make generate` produces exactly one Composer reference in Resources with
`folder.iconcomposer.icon`; `make quick` passes (304 Swift host tests and 69 Python fixtures, plus
strict formatting lint); hosted AppIconTests type-check with Swift 6, root MainActor isolation and
an iOS 17 simulator target; flat-only actool compilation passes;
assetutil reports `AppIcon-default.png`, `AppIcon-dark.png` (`UIAppearanceDark`) and
`AppIcon-tinted.png` (`ISAppearanceTintable`), all opaque 1024² `Icon Image` renditions named ChronoFlow.
The installed Composer app's own Assets.car confirms assetutil calls the layered root `IconImageStack`.

The host's `.icon` compilation and build-for-testing **failed** with “The layer ‘Sky’ does not have
an image name.” The generator fix restores its required base `image-name`, retains the dark
specialization and corrects `supported-platforms.squares` from an array to `"shared"`.
This is a document error; the earlier sandbox Launch Services failure did not identify the cause
of the host build failure. Combined compilation, the catalog audit and hosted tests still require
the host commands below after regeneration. Do not infer successful older-iOS fallback or glass
rendering from the passing generator or flat-only checks.

Run these from `/Users/rickgout/Sites/chronoflow-ios-icon` on the host:

```sh
make generate
make quick

mkdir -p build/icon-actool
xcrun actool App/Assets.xcassets App/ChronoFlow.icon \
  --compile build/icon-actool --platform iphonesimulator \
  --minimum-deployment-target 17.0 --target-device iphone \
  --app-icon ChronoFlow --include-all-app-icons \
  --enable-icon-stack-fallback-generation=disabled \
  --output-partial-info-plist build/icon-actool/partial.plist \
  --output-format human-readable-text --warnings --errors --notices
python3 -I Scripts/check-app-icon.py build/icon-actool/Assets.car

xcodebuild -project ChronoFlow.xcodeproj -scheme ChronoFlow -configuration Debug \
  -derivedDataPath build/DerivedData -onlyUsePackageVersionsFromResolvedFile \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=27.2' build-for-testing
python3 -I Scripts/check-app-icon.py build/DerivedData/Build/Products/Debug-iphonesimulator/ChronoFlow.app
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AppIconTests"
```

The direct actool check is unthinned, so it checks fallback preservation independently of the running
simulator's OS. The built-app check also verifies the primary icon metadata. The hosted suite loads
the primary fallback image and checks that the designed source rendition names, dark/tintable
appearance keys and `ChronoFlow.iconstack` are present in Assets.car. iOS has no public assetutil
equivalent; the host audit
associates those appearances with the ChronoFlow renditions and checks for the glass stack.
The combined check must pass before ticking the plan's delivery verification task. Inspect the
icon in Icon Composer/Home Screen for the board's default/dark/clear/tinted appearance intent.
No splash/launch asset, storyboard or compatibility opt-out is changed.
