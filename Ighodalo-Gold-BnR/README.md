# Ighodalo Gold BnR

Breakout-and-retest EA with session filters (New York/London/Tokyo/Sydney)
and pivot-based left/right bar detection.

| File | What changed |
|---|---|
| `Ighodalo Gold BnR.mq5` | Base version. |
| `Ighodalo-Gold-BnR-Kenton-Royal/Ighodalo Gold BnR - Kenton Royal.mq5` (adjacent folder) | Same logic. Previously had a hard-coded expiration date (2025-08-17) and a "contact @ighodaloxauusd@gmail.com to renew" message baked into `OnInit`/`OnTick` - that's been removed, and with it gone the file is now functionally identical to this one (only a BOM/whitespace difference remains). |

Kept as separate folders for now; now that the expiration lock is gone,
`Ighodalo-Gold-BnR-Kenton-Royal` could reasonably be merged into this one.
