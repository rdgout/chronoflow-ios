# Plan copy source

Backend `afd80dc0`, read with git show. 289 keys; missing Dutch: 0.

Phase 19: `Tools/PlanCopyGen/no-health-data.json` removes retired medical questions and supplies the neutral replacement error (EN/NL); core output copy stays pinned.

Scope: PHP literals in Planner, Planning, trip/review actions and requests, explicit formatter/label keys, and every CopyLine in the S1–S6 and wizard fixtures.

Six duration-unit templates absent from the backend are the exact RN formatter en/nl values in `format-units.json`, preserving `intl-cases.ts`.

The runtime JSON uses the catalog positional formats and coded range cases; loading is explicit on a worker, never a static initializer.
