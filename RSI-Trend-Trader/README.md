# RSI Trend Trader

RSI-based trend-following EA (`RSI_ReversalEA.mq5`) with session filters
(New York/London/Tokyo/Sydney), ATR-based risk, and both fixed-risk and
percent-risk sizing options. Distinct engine from `../BB-Trend-Trader/`
despite the similar naming - confirmed via diff, not the same codebase with
RSI swapped in. Only one version exists in this repo.

Shares its `RSI_ReversalEA.mq5` origin with `../RSI/` (same session-filter
and RSI input structure), but this version is larger (355 vs 338 lines) with
added inline comments and further changes on top - see that folder's README.
