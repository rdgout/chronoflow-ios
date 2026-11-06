# Auth board references

`node Scripts/export-auth-boards.cjs` exports standalone HTML from the committed boards and the
actual component bundle, for Sign in none/wrong/locked/server, AuthStates and Field/Button/Notice,
in light and dark. Open `auth/*.html` in Chrome at 375 × 812 (AuthStates: 375 × 1900).
The exports preserve the board's sample field values for design comparison only. Native fields start
empty. Embedded source CSS and local committed fonts avoid the unavailable canvas `support.js` and
`/_blob` URLs. The user-authorized plain-sky change removes the obsolete dot div.

The controls export uses the bundle's Field normal/error/hint and Button outline/loading/disabled
states and info Notice. Focus uses the bundle's native `:focus-visible` rule when the field is focused.
The native adaptation grows 36/40-point field/button surfaces to at least 44 points, allows wrapping,
adds safe-area insets and scrolls. Text sizes remain those of the board, through the root xxLarge cap.

PNG browser exports and side-by-side visual acceptance remain open: Chrome headless exits 134 in
this sandbox. No hosted snapshots have been recorded. Auth snapshot recording belongs to the
orchestrator after review; these HTML source exports are independent of that recording.
