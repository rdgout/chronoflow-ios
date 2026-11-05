ChronoFlow is a jet-lag planner. A traveller enters their flights and a few facts about their sleep and health; ChronoFlow builds a day-by-day plan for when to sleep, when to seek or avoid bright light and when to have or skip caffeine, shown with their flights on one timeline. The look is **"Night sky calm"**: a calm night flight drifting toward dawn. Deep indigo, soft light surfaces, one warm dawn accent, generous rounded shapes. Quiet and reassuring, never clinical, never loud.

## Principles

1. **Calm over clever.** Few colours per screen, `shadow-soft`, lots of air. Nothing flashes, bounces or alarms. Warnings are calm but visible.
2. **Colour is never the only signal.** Every plan category carries an icon plus a pattern (hatch, dots) or a dashed border. Priority shows through borders and saturation, with a tag.
3. **Phone first.** Most use is on a phone, mid-trip, often offline. Design at 375 px, then widen to `max-w-6xl` (72 rem). Forms, settings, the wizard and reading pages use `max-w-2xl`; auth and error cards `max-w-md`.
4. **Times are the content.** Every time, duration, date and count that lines up uses tabular numerals (`tnum`).
5. **Dawn means "you" and "now".** `dawn` marks the active trip, the current day, progress and the primary emphasis on dark surfaces. Use it sparingly.
6. **Both themes are first-class.** Every screen ships light and dark. Dark is "night sky", not inverted light.

## Voice

- Short, plain, warm sentences in second person: "Seek bright light", "Keep lights dim and warm", "Have your last cup by 15:00".
- Promise a **body-clock shift**, never relief: "helps your clock shift", not "beat jet lag" or "feel great". Outcomes read "expected adapted by Oct 20".
- Caffeine is drinks, not milligrams: "1 cup of filter coffee", "an espresso", "your usual 2 cups, the last by 15:00".
- Never show the planner's internals: no rule IDs, model names, parameters, scores, evidence codes or "hours still to shift".
- Everything is translated into English and Dutch. Dutch runs about 20 % longer: never depend on a short English label fitting.
- No emoji, no exclamation marks, no stock photography. Real-looking data in mocks: Amsterdam → Tokyo, KL 861, +7 h, Oct 12–21.

## Colour

Components use the semantic token, never a raw value. Values are the OKLCH sources.

- Pages sit on `background`; cards, sheets and day headers on `card`; menus on `popover`; inset areas and timeline lanes on `surface-2`. Never pure white or pure black.
- Body text is `foreground`; secondary text `muted-foreground`. Both pass AA on `background`, `card` and `muted` in both themes.
- `primary` **flips hue between themes**: deep indigo buttons in light, dawn in dark (with `primary-foreground`). `ring` flips the same way.
- `dawn` is a fill or border only on light surfaces (2.4:1 on `background`). Dawn-coloured **text** uses `dawn-text` (the `text-dawn` utility already maps to it); inside `bg-sky` it switches back to the brighter `dawn`. Text on a dawn fill is `dawn-foreground`.
- `now` is only the timeline's now line. `destructive` is only errors and delete. Nothing else is red.
- `accent` is the hover fill (warm in light); `muted` is quiet fills, the active nav pill and progress tracks; `border` hairlines; `input` field borders.

### Plan categories

Six fills, each with an `-fg` text colour that passes on it. Always pair the fill with its icon and second signal (`CategorySwatch`, `categoryStyles`):

| Category | Fill | Second signal | Icon |
| --- | --- | --- | --- |
| Sleep · Nap · Rest | `cat-sleep` | solid · dots · hatch | Moon · Bed · Armchair |
| Seek bright light | `cat-light` | solid | Sun |
| Light is fine · Neutral light | `cat-moderate` | dots + dashed border · solid | CloudSun · Lamp |
| Avoid light | `cat-dark` | hatch | Glasses |
| Caffeine serving · routine · OK window | `cat-caffeine` | dots · hatch · solid | Coffee |
| No caffeine | `card` | dashed `cat-caffeine` border | Coffee with a 45° slash |
| Flight · transfer · movement · zone change | `cat-travel` | solid | Plane · ArrowLeftRight · Footprints · Globe |
| Layover | `cat-travel` | hatch | Timer |
| Info note | `card` | plain `border` | Info |

There are no melatonin, meal or exercise categories. Do not add them.

## The sky

`bg-sky` is the signature and the only gradient: `sky-top` (night indigo) → `sky-mid` (violet, 55 % in light, 60 % in dark) → `sky-horizon` (dawn), top to bottom. Use it only for moments that matter: the landing hero, the active trip card, the paywall header, zone-change cards, auth and error backdrops. Layer `pattern-dots` at 20 % for a starfield.

- Titles on the sky are `sky-title`. Over the light-theme horizon it drops to about 2.2:1, so longer copy sits on a `sky-copy-background` backplate in `sky-copy`.
- The call to action on the sky is a `dawn` pill button with `dawn-foreground`, never `primary`.

## Type

- **Fraunces** (variable, optical size) for h1–h3, weight 400–500, `letter-spacing: -0.01em`. Never bold. Styles: `hero` (landing), `page-title` / `page-title-lg`, `card-title`, `section-title`, `day-title`. Trip-card IATA codes are Fraunces at `page-title` size.
- **Figtree** 400/500/600/700 for everything else, including section labels inside cards: `body-lg`, `body`, `label`, `meta`, `eyebrow`, `block-label`, `priority-tag`.
- Eyebrows: `text-xs font-semibold uppercase tracking-widest text-dawn`. In-card section labels: `text-sm font-semibold uppercase tracking-wider text-muted-foreground`.
- Inline links in prose are underlined, `text-underline-offset: 0.2em`.
- Fonts ship as latin subsets (English and Dutch need nothing more).

## Shape, space and elevation

- Radii come from `radius` (14 px): `radius-3xl` for feature, trip and summary cards and dialogs; `radius-2xl` for tiles, day headers, list rows and choice cards; `radius-lg`/`radius-xl` for swatches and small cards; `radius-full` for app buttons, nav items, chips, badges, tags and progress bars. Pills are the most common shape; corners never go square.
- Spacing is the Tailwind 4 px grid (`spacing`). Page gutter `space-4`; cards `space-5` on phones, `space-6`/`space-8` wider; `space-6` between sections, `space-2`–`space-3` inside rows.
- `shadow-soft` is the only elevation. No hard or stacked shadows.

## App shell

- Sticky glass top header `h-14`: background at 72% over the content (`color-mix(in oklab, var(--background) 72%, transparent)`), `backdrop-filter: blur(20px) saturate(1.8)`, hairline bottom `border`. Desktop nav pills `rounded-full px-4 py-2`, active = `bg-muted text-foreground`.
- On phones a floating glass tab bar (`.cf-glass`, `rounded-full`, 16 px from the sides and 20 px above the safe area) with three tabs: **Today, My trips, Settings**. Tabs are 52 px tall, icon over label; the active tab is `text-dawn` with a 16% dawn tint behind it. Note: the bundled `AppShell` still labels the first tab "Dashboard" — use "Today" in new screens.
- Day headers stick below the app header (`top-14`) as `bg-card/95 backdrop-blur shadow-soft rounded-2xl`.
- Settings tabs render as pills. Sheets are bottom sheets on phones, side sheets on desktop. Toasts: one channel, bottom on phones.

## The plan timeline

- Four equal lanes, **Sleep, Light, Caffeine, Travel**, on `surface-2`, with an hour gutter. Blocks sit at their real time and length; on phones tiny blocks show their icon only.
- Priority: core ("Important") = 4 px left border in `foreground` at 70 %; recommended = default; optional = dashed and faded; info = 50 % saturation. Plus a `PriorityTag`.
- Plan days run from one main wake to the next, so a day can be shorter or longer than 24 h. Labels: "Departure day", "Travel day", "Arrival day", "Day 3".
- When the clock changes zone, show a full-width `ZoneChangeCard` in the list and a dotted `cat-travel` divider with a pill in the grid. Offsets use a true minus sign ("−1 h").
- Checked-off items fade and show a check icon. Checks only change progress, never the plan.

## States

Cover empty, loading (skeletons in the real layout), error with retry, disabled-with-a-reason and long Dutch strings, not just the happy path.

**Offline first.** Every screen reads the plan stored on the device, so Today, the trip page, item details and the Live Activity all work without a connection, and there is no offline screen. Only actions that need the server (creating or editing a trip, account and security changes, data download) are disabled offline, each with a short "Needs a connection" note on the row or button. Reminders are local notifications and never need a connection. Sync status stays quiet: one small "Synced 2 min ago" line in Settings, never a banner.

## Iconography

- **lucide**, stroke style only: 16 px (`size-4`) in UI, 20 px in the tab bar, 14 px in dense blocks. Category icons are fixed (see the table above). Decorative icons are `aria-hidden`; icon-only buttons carry an accessible name.
- Patterns: `pattern-hatch` (135° stripes of `currentColor` at 12 %, 2 px on / 6 px off), `pattern-dots` (1 px dots of `currentColor` at 16 % on a 7 px grid), `outline-dashed-cat` (2 px dashed border).
- The logo is the app icon `assets/Logos/chronoflow-app-icon.png`: a dawn crescent moon on a sky-gradient rounded square. In the header it sits at 32 px beside the wordmark, "ChronoFlow" set in Fraunces (`Wordmark`). Use the file as supplied; never redraw or recolour it, and keep it off `bg-sky`. The moon inside it is the same lucide `Moon` used for sleep, so the sky frame and walkthrough can echo it with the icon alone.

## Motion

Subtle colour and opacity transitions, sheet and dialog slide/fade, a spinner. No parallax, no springs. `prefers-reduced-motion` turns everything off except the spinner.

## Accessibility

- WCAG AA in both themes. Contrast fixes happen in tokens, not per component; text on a category fill that falls short gets a local backplate.
- Focus is visible: `focus-visible:outline-2 outline-ring` (or a 2 px ring).
- Touch targets at least 44 px on phones (`Button size="touch"`, Today rows `min-h-14`, day chips `min-h-11`).
- Known source gaps, kept exact: `input` borders sit under 3:1; `cat-dark` is close to `background` in dark and `cat-light`/`cat-moderate` close to `background` in light, so those blocks rely on their icon, pattern and label.

## Print

Print hides chrome (`.no-print`), keeps days from breaking across pages, and offers a black-on-white one-page "pocket guide" of each day's key times.

## Using the components

`components/bundle.js` exposes `window.ChronoFlow` (React 18 on the page). `components/bundle.css` is Tailwind v4 compiled from the components' own class strings and reads every value from the tokens, so load the tokens' CSS first. The dark theme is `[data-theme="dark"]` (the app's `.dark` class works too).
