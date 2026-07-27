# MA Ribbon

Moving-average ribbon EA (`MA_Ribbon.mq5`, 2021 origin) using multiple EMAs
for trend analysis.

| File | What changed |
|---|---|
| `MA Ribbon 2025.mq5` / `v2.mq5` / `v3.mq5` / `v4.mq5` | Base line: EMA ribbon, reversal-close logic, fixed 30-pip partial close. Versions are incremental tweaks on the same input set. |
| `MA Ribbon upgrade.mq5` | Adds separate fixed take-profit (50 pips) and fixed stop-loss (30 pips) inputs alongside the partial-close input. |
| `MA Ribbon upgrade v2.mq5` | Adds the ability to enable/disable buy-close and sell-close (reversal-close) independently. |
| `MA Ribbon v5.mq5` | Removes the old fixed partial-close input in favor of new reward-based (R-multiple) parameters. |
| `MA Ribbon 2025 v6.mq5` / `MA Ribbon PV.mq5` | Reorganizes inputs into grouped "Strategy, Filters, and Risk Management" sections - a more structured input layout than the earlier flat list. |
| `2025-V1/MA Ribbon 2025 V1.mq5` | Copyright "MetaQuotes Ltd." with only boilerplate `OnInit` shown - looks like a MetaEditor wizard-generated template/stub rather than a hand-written iteration; kept as its own subfolder since it also has its own `.mqproj` MetaEditor project file. |
