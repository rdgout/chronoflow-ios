# Trip timeline performance

The timeline uses one Canvas per lazily mounted day. Layout and text preparation run in
`PlanDecoder`; the latest layout is reused across marks and language changes. A separate
worker rasterises static day drawings. A four-day LRU bounds that cache; off-screen views
release their images. The draw closure blits the prepared image and adds the minute-driven
now line. Packing, dates, text layout, patterns and symbol rendering stay outside it.

S3 scrolling acceptance budget: hitch time ratio ≤ 5 ms/s (0.5%); aim for ≤ 1 ms/s.
At 60 Hz a frame has 16.67 ms, at 120 Hz 8.33 ms. These are acceptance targets, not measured
claims. Synthetic 30/60-day benchmarks and the Release UI runner are documented below
in the performance extension. No simulator or physical-device measurements were run here.
