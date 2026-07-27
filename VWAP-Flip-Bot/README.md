# VWAP Flip Bot

A DCA + scale-in EA trading VWAP flips, structured like the
`Ighodalo-Gold-Turning-Points` and `Saro-Trades` modular engines (a thin
`.mq5` entry point including `_Engine_Core.mqh` / `_Engine_ScaleIn.mqh` /
`_Strategy.mqh` / `_NewsFilter.mqh` modules).

## `V1/`
- `VWAP Flip bot.mq5` + matching `.mqh` engine modules - the original version.
- `News.mq5` - **not actually VWAP news-filter code.** Its header reads "Belema SFP EA (Enhanced) - v13.0", matching `Belema-SFP/Belema SFP V13.mq5` almost exactly. This looks like a copy-paste mistake (perhaps `News.mq5` was meant to hold the news-filter logic but a Belema SFP file got copied in by accident) rather than a real part of this strategy - kept as-is since it wasn't explicitly authorized to remove, but don't expect it to relate to VWAP at all.
- `Prompts.txt` - development notes/AI-assistant prompts used while building this EA, not source code.

## `V2/`
- `VWAP Flip bot V2.mq5` + matching `.mqh` engine modules - the next iteration of the same DCA + scale-in architecture.
- `VWAP Swing bot.mq5` - a related but distinct bot (internally `VWAP SWing bot.mq5`) that reuses the same `_Strategy.mqh` module rather than being a version of the Flip Bot itself.
- `News.mq5` / `Prompts.txt` - same caveats as in `V1/` (the `News.mq5` here is also actually Belema SFP v13 content, not news-filter logic).
- `compile_goat.ps1` / `compile_goat_swing.ps1` - PowerShell scripts that invoke MetaEditor from the "Goat Funded MT5 Terminal" prop-firm installation to compile these EAs and capture the compile log.
