# Trip and plan fixtures

RN commit: `e24872afd47ff671fbbab315665920f2805054df`. Contracts pin: web `afd80dc0cd127e9ad864d8ac32699383826366c8`.

`plans/S1.json` through `S6-RETURN-10N.json` are byte-for-byte copies of tracked
`src/data/mock/fixtures/plans/` files at that RN commit (seven fixtures, including S6).

`trips/list.json` and `trips/detail.json` are constructed envelopes, not live captures.
Plan, notices and timeline are the complete S1 parts. The airport/card/leg values
come from the existing RN-derived Debug seed. Envelopes follow web
`app/Data/Api/ApiTrip{List,ListItem,Detail}.php` and generated Data/Api, Data/Trips
and Data/Plan at the contracts pin. IDs, input hash and version are artificial;
check state starts empty. No mock-only form or revision is included.
