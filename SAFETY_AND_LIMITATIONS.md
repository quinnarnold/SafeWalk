# Safety and methodological limitations

SafeWalk is an experimental route-comparison tool. It must not be described as
predicting or guaranteeing personal safety.

## What the score represents

The current public pipeline uses a kernel-density estimate of selected
historical incident reports near street edges, split into four six-hour time
bins. Routing adds a city-specific penalty derived from that surface to edge
length. The score is relative and model-specific; it is not the probability
that an incident will occur.

## Important limitations

- Police and public incident datasets reflect reporting, recording,
  enforcement, geocoding, and publication practices.
- Missing or delayed reports are treated as absent data.
- Historical spatial patterns may not describe current conditions.
- A lower modeled score does not make a route safe.
- Routes may trade distance, accessibility, lighting, foot traffic,
  construction, weather, and other conditions that the model does not observe.
- Category choices, bandwidth, cutoff date, and routing penalties materially
  affect results.
- Comparisons across cities are not calibrated to a common probability scale.

Contributors should document parameter changes, test for geographic and
demographic disparities, and avoid labels or marketing claims that imply
certainty. User interfaces should keep the shortest route available and
explain that risk-weighted routes are estimates based on incomplete historical
data.

In an emergency, users should contact local emergency services.
