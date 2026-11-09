# Member trip wizard wire fixtures

Hand-built from the read-only web repo at `afd80dc0cd127e9ad864d8ac32699383826366c8`;
no backend was run and these are not captures.

- `input`, `review-request`: `tests/Support/Planning/MobileTripWizard.php` Tokyo route,
  `app/Data/Api/ApiTripInput*.php` full optional/default shape, and
  `app/Http/Requests/Api/V1/{TripJourney,ReviewTrip}Request.php` request identity/profile keys.
- `review`, `needs-answers`: `tests/Feature/Api/MemberTripReviewTest.php` assertions,
  `app/Actions/Api/PresentMobileReview.php`, `app/Planning/ReviewSummaryLine.php`,
  and `app/Data/Api/ApiReview*.php`. The adaptation value is from the pinned RN S1 plan.
  Dates are illustrative DTO values, not a claim that a backend calculation produced this summary.
- `snapshot`, `airports`: API DTOs and `tests/Feature/Api/MemberTripEditTest.php`.
- `save-request`, `save`, `expired`, `credits`, `throttled`: `MemberTripSaveTest.php`.
  POST returns 201, PUT returns 200. Only identity is accepted on save.
- `unknown-field`, `journey`, `profile`: `MemberTripReviewTest.php` and
  `TripJourneyRequestTest.php` validation assertions. The fixture deliberately retains
  unknown field names so they cannot silently disappear in error mapping.
- `capacity`: `app/Planning/TripDrafts.php` receipt-cap refusal (`errors.review`).

Mock generation uses the seven existing embedded RN plan templates (including the return
variant), documented in ../plans/SOURCE.md. Airport names and screening copy follow RN's
`src/data/mock/{fixture-data,wizard-review}.ts`; they are server copy keys/data, with display
localization deferred to the planned Phase 14 catalog. No UI is added in Phase 13.
