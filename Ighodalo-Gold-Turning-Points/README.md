# Ighodalo Gold Turning Points

A DCA (dollar-cost-averaging) + scale-in EA. Each version's `.mq5` file is a
thin ~112-line entry point (`OnInit`/`OnDeinit`/`OnTick` wiring plus inputs)
that includes the real logic from matching `_Engine_Core.mqh`,
`_Engine_ScaleIn.mqh`, and `_Strategy.mqh` files - the differences between
versions live in those engine modules, not in the `.mq5` wrapper itself.

| Version | Files |
|---|---|
| Base | `Ighodalo Gold - Turning Points.mq5` + `..._Engine_Core.mqh` + `..._Engine_ScaleIn.mqh` + `..._Strategy.mqh` |
| V2 | `Ighodalo Gold - Turning Points - V2.mq5` + matching `V2_Engine_Core.mqh` / `V2_Engine_ScaleIn.mqh` / `V2_Strategy.mqh` |
| V3 | `Ighodalo Gold - Turning Points - V3.mq5` + matching `V3_Engine_Core.mqh` / `V3_Engine_ScaleIn.mqh` / `V3_Strategy.mqh` |

All three share the same margin-cap/DCA/scale-in architecture (risk-based
lot sizing, margin budget bisection search, session/New-York-time handling);
consult the version-specific `_Engine_Core.mqh` for the exact risk and
scale-in parameters each one uses.
