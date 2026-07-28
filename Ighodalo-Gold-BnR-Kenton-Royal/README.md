# Ighodalo Gold BnR - Kenton Royal

Same breakout-and-retest strategy as `../Ighodalo-Gold-BnR/`. This build
previously had a hard-coded expiration check (2025-08-17 23:59:59 GMT) in
`OnInit`/`OnTick` that disabled trading and printed a message to contact
`@ighodaloxauusd@gmail.com` / `@__ighodalo` on X to renew - it read as a
time-limited copy distributed to a specific recipient ("Kenton Royal").

**The expiration check has been removed.** With it gone, this file is now
functionally identical to `../Ighodalo-Gold-BnR/Ighodalo Gold BnR.mq5` - the
only remaining differences are a UTF-8 BOM and whitespace. Kept as a
separate folder for now since merging/deleting it wasn't part of what was
asked; worth considering whether to fold it into `Ighodalo-Gold-BnR` and
drop this folder entirely as a follow-up.
