Welcome-only baselines are recorded with `SNAPSHOT_RECORD=1 python3 -I Scripts/launch-simulators.py --welcome`
from the repository root. The record pass selects only AppTests/WelcomeSnapshotTests and AppTests/WelcomeSnapshotGuardTests; comparisons and final checks clear
recording flags. It uses each D1c device's own display scale, including Duo on its separate runtime.

The 196 initial recordings were blank and have been discarded. Replacement recording and comparison
remain open after the subsequent composition/plain-sky decisions. The orchestrator reported that hosted
recording succeeded on all seven devices, with one intermittent 2400 ms comparison mismatch.
Use `SNAPSHOT_RECORD=all python3 -I Scripts/launch-simulators.py --welcome` to replace both launch
and Welcome references for the new decisions (`launch` records only launch). Every capture must come from a key, visible window, succeed through drawHierarchy, and
contain visible pixel variation. Independent final-screen guards require appearance and language
changes to produce different pixels, so a background-only or blank recording cannot pass.

Snapshots and capture guards require the ChronoFlow app host. Baselines stay beside the hosted tests.
Final references cover large and xxLarge; an AX5/XXXL equality guard compares both frames and pixels
with xxLarge in both languages and appearances on every D1c device. Missing baselines fail unless
recording is explicitly enabled. Comparison uses decoded RGBA pixels, not PNG byte identity.
