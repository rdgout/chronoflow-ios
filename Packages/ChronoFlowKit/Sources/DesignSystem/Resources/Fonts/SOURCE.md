# Font sources

Google Fonts commit [`24ddc1f324cac5d9f5aedca126d298f56e3f1640`](https://github.com/google/fonts/tree/24ddc1f324cac5d9f5aedca126d298f56e3f1640), fetched 2026-11-05. Both families are OFL licensed; their licenses are included separately. Full upstream TTF character sets are retained (including English and Dutch).

Regenerate with `make fonts`; verify with `sh Tools/fonts.sh --check`. fonttools 4.60.1 and brotli 1.1.0 are pinned in a repo-local venv. Source and output SHA-256 hashes, face names and axis cuts are in `manifest.json`. No variable axes remain in the output.

Fraunces source version 1.000 [b76b70a41] has opsz 9–144 (default 9), wght 100–900 (default 900), SOFT 0–100 (default 0), WONK 0–1 (default 1). Cuts pin SOFT=0 and WONK=1. The web's `@fontsource-variable/fraunces/files/fraunces-latin-opsz-normal.woff2` has the same version and retains opsz/wght only. Its outlines for A–Z, a–z, the wordmark and ëïéè were compared at opsz 20/32/48 and weight 400: exact matches to the Google source with SOFT=0 / WONK=1. No synthetic bold or optical-size substitution is used.

Figtree cuts: weights 400/500/600/700. Fraunces cuts: weights 400/500 × opsz 20/32/48. Unique CF-prefixed PostScript/family names keep the optical cuts distinct; original copyright/license records are preserved. Registration belongs after the overlay flush (Phase 3b), through `FontRegistry.register()`.
