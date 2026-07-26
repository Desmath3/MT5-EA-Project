// File: VWAP SWing bot.mq5
#property strict

#include <Trade\Trade.mqh>

bool IsOptimizationMode()
{
   return (MQLInfoInteger(MQL_OPTIMIZATION) == 1);
}

#include "VWAP Flip bot_Strategy.mqh"

enum ENUM_TRADE_DIRECTION
{
   TradeBoth = 0,
   TradeBuyOnly = 1,
   TradeSellOnly = 2
};

input group "General Settings"
input long EA_MagicNumber = 123456;
input int Slippage = 3;
input bool EnableHedge = true;
input ENUM_TRADE_DIRECTION TradeDirection = TradeBoth;

input group "Risk Management"
input double MaxTotalRiskPct = 10.0;
input double RiskPerGroupPct = 1.0;
input int AtrPeriod = 14;
input double AtrSlMultiplier = 4.0;
input int MaxGroupsPerSide = 5;

input group "Trade Management"
input double ProfitTargetRR = 20.0;
input int FlipFallback1HCandles = 60;
input double FlipFallbackReward = 5.0;
input double SequenceBE_StartR = 2.0;
input double BreakevenOffsetR = 0.0;
input int CooldownH1Candles = 1;
input bool EnableDailyClose = false;

input group "No Trade Zone"
input int NoTradeStartHour = 23;
input int NoTradeStartMin = 30;
input int NoTradeEndHour = 0;
input int NoTradeEndMin = 30;

input group "Session Management"
input bool TradeNewYork = true;
input bool TradeLondon = true;
input bool TradeTokyo = true;
input bool TradeSydney = true;

input group "Swing Anchored VWAP"
input int SwingPeriod = 50;
input int VwapAPTBase = 20;
input bool PlotSwingVWAP = true;
input color VwapUpColor = clrLime;
input color VwapDownColor = clrRed;
input int VwapLineWidth = 2;

struct SwingGroup
{
   ulong ticket;
   long magic;
   bool isBuy;
   datetime open_time;
   double initial_sl_distance;
   double initial_risk;
   bool present;
};

CTrade g_trade;
int g_atrHandle = INVALID_HANDLE;
SwingGroup g_groups[];

long g_nextBuyMagic = 0;
long g_nextSellMagic = 0;
datetime g_buyCooldownEnd = 0;
datetime g_sellCooldownEnd = 0;
datetime g_lastBarTime = 0;
int g_lastDailyCloseTradingKey = 0;
bool g_halted = false;

long BuyMagicMin()  { return EA_MagicNumber + 1000; }
long BuyMagicMax()  { return EA_MagicNumber + 49999; }
long SellMagicMin() { return EA_MagicNumber + 50000; }
long SellMagicMax() { return EA_MagicNumber + 99999; }

bool IsOurBuyMagic(long magic)  { return (magic >= BuyMagicMin() && magic <= BuyMagicMax()); }
bool IsOurSellMagic(long magic) { return (magic >= SellMagicMin() && magic <= SellMagicMax()); }
bool IsOurMagic(long magic)     { return (IsOurBuyMagic(magic) || IsOurSellMagic(magic)); }

void LogTrade(string side, string action, string reason, double price = 0.0, double vol = 0.0, double pnl = 0.0, double rr = 0.0)
{
   if(IsOptimizationMode()) return;
   PrintFormat("TRADE_EVENT | Side=%s | Action=%s | Reason=%s | Price=%.5f | Volume=%.2f | Profit=%.2f | R=%.2f",
               side, action, reason, price, vol, pnl, rr);
}

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &last_time)
{
   datetime t[1];
   if(CopyTime(_Symbol, tf, 0, 1, t) > 0 && t[0] != last_time)
   {
      last_time = t[0];
      return true;
   }
   return false;
}

double GetATR()
{
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double b[1];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, b) <= 0) return 0.0;
   return b[0];
}

double NormalizeLot(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step + 1e-8) * step;
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lots < minL) return 0.0;
   if(lots > maxL) lots = maxL;
   return lots;
}

double PriceValuePerLot()
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0) return 0.0;
   return tv / ts;
}

double CalcRiskMoney(double slDistPrice, double vol)
{
   double v = PriceValuePerLot();
   if(v <= 0.0 || slDistPrice <= 0.0 || vol <= 0.0) return 0.0;
   return slDistPrice * v * vol;
}

double CalcLotsFromRisk(double riskMoney, double slDistPrice)
{
   double v = PriceValuePerLot();
   if(v <= 0.0 || riskMoney <= 0.0 || slDistPrice <= 0.0) return 0.0;
   return NormalizeLot(riskMoney / (slDistPrice * v));
}

int GetNthSunday(int year, int month, int nth)
{
   MqlDateTime dt;
   dt.year = year; dt.mon = month; dt.day = 1;
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   dt.day_of_week = 0;
   dt.day_of_year = 0;
   datetime first = StructToTime(dt);
   MqlDateTime tmp;
   TimeToStruct(first, tmp);
   int dow = tmp.day_of_week;
   int firstSunday = 1 + ((7 - dow) % 7);
   return firstSunday + 7 * (nth - 1);
}

int GetNYOffsetSeconds(datetime gmt)
{
   MqlDateTime md;
   TimeToStruct(gmt, md);
   int year = md.year, month = md.mon, day = md.day, hour = md.hour;
   if(month > 3 && month < 11) return -4 * 3600;
   if(month < 3 || month > 11) return -5 * 3600;
   if(month == 3)
   {
      int secondSunday = GetNthSunday(year, 3, 2);
      if(day < secondSunday) return -5 * 3600;
      if(day > secondSunday) return -4 * 3600;
      return (hour >= 7 ? -4 * 3600 : -5 * 3600);
   }
   int firstSunday = GetNthSunday(year, 11, 1);
   if(day < firstSunday) return -4 * 3600;
   if(day > firstSunday) return -5 * 3600;
   return (hour >= 6 ? -5 * 3600 : -4 * 3600);
}

void GetNewYorkTime(datetime gmt, MqlDateTime &ny)
{
   TimeToStruct(gmt + GetNYOffsetSeconds(gmt), ny);
}

int GetNYTradingDayKey(datetime gmt)
{
   MqlDateTime ny;
   GetNewYorkTime(gmt, ny);
   datetime ny_dt = StructToTime(ny);
   datetime shifted = ny_dt - 17 * 3600;
   MqlDateTime sh;
   TimeToStruct(shifted, sh);
   return sh.year * 10000 + sh.mon * 100 + sh.day;
}

bool IsDailyCloseWindow(datetime gmt)
{
   if(!EnableDailyClose) return false;
   MqlDateTime ny;
   GetNewYorkTime(gmt, ny);
   int m = ny.hour * 60 + ny.min;
   return (m >= (17 * 60 - 10) && m < 17 * 60);
}

bool IsWithinSession()
{
   datetime g = TimeGMT();
   if(g == 0) return false;
   MqlDateTime ny;
   GetNewYorkTime(g, ny);
   int m = ny.hour * 60 + ny.min;
   if(TradeNewYork && m >= 8 * 60 && m < 17 * 60) return true;
   if(TradeLondon  && m >= 3 * 60 && m < 12 * 60) return true;
   if(TradeTokyo   && (m >= 19 * 60 || m < 4 * 60)) return true;
   if(TradeSydney  && (m >= 17 * 60 || m < 2 * 60)) return true;
   return false;
}

bool IsNoTradeZone()
{
   datetime g = TimeGMT();
   if(g == 0) return false;
   MqlDateTime ny;
   GetNewYorkTime(g, ny);
   int cur = ny.hour * 60 + ny.min;
   int s = NoTradeStartHour * 60 + NoTradeStartMin;
   int e = NoTradeEndHour * 60 + NoTradeEndMin;
   if(s < e) return (cur >= s && cur < e);
   return (cur >= s || cur < e);
}

bool IsMarketOpen()
{
   datetime now_gmt = TimeGMT();
   if(now_gmt == 0) return false;
   MqlDateTime ny;
   GetNewYorkTime(now_gmt, ny);
   int minutesNY = ny.hour * 60 + ny.min;
   ENUM_DAY_OF_WEEK nyDay = (ENUM_DAY_OF_WEEK)ny.day_of_week;
   if(nyDay == SATURDAY) return false;
   if(nyDay == SUNDAY && minutesNY < 17 * 60) return false;
   if(nyDay == FRIDAY && minutesNY >= 17 * 60) return false;
   if(minutesNY >= (17 * 60 - 1) && minutesNY < (17 * 60 + 5)) return false;
   return true;
}

int FindGroupByTicket(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_groups); i++)
      if(g_groups[i].ticket == ticket) return i;
   return -1;
}

void RemoveGroupAt(int idx)
{
   if(idx < 0 || idx >= ArraySize(g_groups)) return;
   int n = ArraySize(g_groups);
   for(int i = idx; i < n - 1; i++) g_groups[i] = g_groups[i + 1];
   ArrayResize(g_groups, n - 1);
}

void BootstrapMagicCounters()
{
   g_nextBuyMagic = BuyMagicMin();
   g_nextSellMagic = SellMagicMin();
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(IsOurBuyMagic(magic) && magic >= g_nextBuyMagic) g_nextBuyMagic = magic + 1;
      if(IsOurSellMagic(magic) && magic >= g_nextSellMagic) g_nextSellMagic = magic + 1;
   }
}

void SyncGroups()
{
   for(int i = 0; i < ArraySize(g_groups); i++) g_groups[i].present = false;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IsOurMagic(magic)) continue;
      bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      int idx = FindGroupByTicket(t);
      if(idx < 0)
      {
         SwingGroup g;
         g.ticket = t;
         g.magic = magic;
         g.isBuy = isBuy;
         g.open_time = (datetime)PositionGetInteger(POSITION_TIME);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double vol = PositionGetDouble(POSITION_VOLUME);
         g.initial_sl_distance = MathAbs(entry - sl);
         if(g.initial_sl_distance <= 0.0)
         {
            double atr = GetATR();
            if(atr > 0.0) g.initial_sl_distance = atr * AtrSlMultiplier;
         }
         g.initial_risk = CalcRiskMoney(g.initial_sl_distance, vol);
         g.present = true;
         int n = ArraySize(g_groups);
         ArrayResize(g_groups, n + 1);
         g_groups[n] = g;
      }
      else
      {
         g_groups[idx].present = true;
      }
   }

   for(int i = ArraySize(g_groups) - 1; i >= 0; i--)
      if(!g_groups[i].present) RemoveGroupAt(i);
}

bool ComputeR(int idx, double &rVal, double &profit, double &priceNow, double &volNow)
{
   rVal = 0.0; profit = 0.0; priceNow = 0.0; volNow = 0.0;
   if(idx < 0 || idx >= ArraySize(g_groups)) return false;
   if(!PositionSelectByTicket(g_groups[idx].ticket)) return false;
   bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return false;
   priceNow = (isBuy ? tk.bid : tk.ask);
   volNow = PositionGetDouble(POSITION_VOLUME);
   profit = PositionGetDouble(POSITION_PROFIT);
   double risk = g_groups[idx].initial_risk;
   if(risk <= 0.0)
   {
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      risk = CalcRiskMoney(MathAbs(entry - sl), volNow);
   }
   if(risk <= 0.0) return false;
   rVal = profit / risk;
   return true;
}

int CountSide(bool isBuy)
{
   int n = 0;
   for(int i = 0; i < ArraySize(g_groups); i++) if(g_groups[i].isBuy == isBuy) n++;
   return n;
}

bool LatestGroupPositive(bool isBuy)
{
   int idx = -1;
   datetime latest = 0;
   for(int i = 0; i < ArraySize(g_groups); i++)
   {
      if(g_groups[i].isBuy != isBuy) continue;
      if(g_groups[i].open_time >= latest)
      {
         latest = g_groups[i].open_time;
         idx = i;
      }
   }
   if(idx < 0) return true;
   double r, p, pr, v;
   if(!ComputeR(idx, r, p, pr, v)) return false;
   return (r > 0.0);
}

double TotalPotentialLoss()
{
   double total = 0.0;
   for(int i = 0; i < ArraySize(g_groups); i++)
   {
      if(!PositionSelectByTicket(g_groups[i].ticket)) continue;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double dist = (isBuy ? entry - sl : sl - entry);
      if(dist > 0.0) total += CalcRiskMoney(dist, vol);
   }
   return total;
}

long NextMagic(bool isBuy)
{
   long m = (isBuy ? g_nextBuyMagic : g_nextSellMagic);
   if(isBuy) g_nextBuyMagic++;
   else g_nextSellMagic++;
   return m;
}

bool OpenGroup(bool isBuy)
{
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return false;
   double atr = GetATR();
   if(atr <= 0.0) return false;
   double slDist = atr * AtrSlMultiplier;
   if(slDist <= 0.0) return false;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double capRisk = balance * (MaxTotalRiskPct / 100.0);
   double usedRisk = TotalPotentialLoss();
   double room = capRisk - usedRisk;
   if(room <= 0.0) return false;

   double desired = balance * (RiskPerGroupPct / 100.0);
   double riskMoney = MathMin(desired, room);
   double lots = CalcLotsFromRisk(riskMoney, slDist);
   if(lots <= 0.0) return false;

   ENUM_ORDER_TYPE ot = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double price = (isBuy ? tk.ask : tk.bid);
   double sl = (isBuy ? price - slDist : price + slDist);
   sl = NormalizeDouble(sl, _Digits);

   long magic = NextMagic(isBuy);
   g_trade.SetExpertMagicNumber((ulong)magic);
   g_trade.SetDeviationInPoints(Slippage);

   if(g_trade.PositionOpen(_Symbol, ot, lots, price, sl, 0.0, "VWAP SWing group"))
   {
      LogTrade((isBuy ? "BUY" : "SELL"), "GROUP_ENTRY", "Opened new independent group", price, lots, 0.0, 0.0);
      return true;
   }

   LogTrade((isBuy ? "BUY" : "SELL"), "ENTRY_FAIL", g_trade.ResultRetcodeDescription(), price, lots, 0.0, 0.0);
   return false;
}

bool CloseGroup(int idx, string action, string reason, double price, double pnl, double rr)
{
   if(idx < 0 || idx >= ArraySize(g_groups)) return false;
   ulong t = g_groups[idx].ticket;
   bool isBuy = g_groups[idx].isBuy;
   double vol = 0.0;
   if(PositionSelectByTicket(t)) vol = PositionGetDouble(POSITION_VOLUME);
   if(g_trade.PositionClose(t))
   {
      LogTrade((isBuy ? "BUY" : "SELL"), action, reason, price, vol, pnl, rr);
      RemoveGroupAt(idx);
      return true;
   }
   return false;
}

void ManageGroups()
{
   for(int i = ArraySize(g_groups) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(g_groups[i].ticket))
      {
         RemoveGroupAt(i);
         continue;
      }

      bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double r, pnl, px, vol;
      if(!ComputeR(i, r, pnl, px, vol)) continue;

      int open_shift = iBarShift(_Symbol, PERIOD_H1, g_groups[i].open_time, false);
      int now_shift = iBarShift(_Symbol, PERIOD_H1, TimeCurrent(), false);
      int bars_passed = 0;
      if(open_shift >= 0 && now_shift >= 0) bars_passed = MathMax(0, open_shift - now_shift);

      if(SequenceBE_StartR > 0.0 && r >= SequenceBE_StartR && g_groups[i].initial_sl_distance > 0.0)
      {
         double beSL = (isBuy ? entry + BreakevenOffsetR * g_groups[i].initial_sl_distance
                              : entry - BreakevenOffsetR * g_groups[i].initial_sl_distance);
         bool setSL = (isBuy ? (sl == 0.0 || beSL > sl + _Point) : (sl == 0.0 || beSL < sl - _Point));
         if(setSL)
         {
            beSL = NormalizeDouble(beSL, _Digits);
            g_trade.PositionModify(g_groups[i].ticket, beSL, tp);
         }
      }

      double targetRR = ProfitTargetRR;
      if(bars_passed >= FlipFallback1HCandles) targetRR = FlipFallbackReward;
      if(targetRR > 0.0 && r >= targetRR)
      {
         string rsn = (bars_passed >= FlipFallback1HCandles ? "Fallback RR target reached" : "Primary RR target reached");
         CloseGroup(i, "GROUP_CLOSE_PROFIT", rsn, px, pnl, r);
      }
   }
}

void HandleDailyClose()
{
   datetime now_gmt = TimeGMT();
   if(!IsDailyCloseWindow(now_gmt)) return;
   int key = GetNYTradingDayKey(now_gmt);
   if(g_lastDailyCloseTradingKey == key) return;
   g_lastDailyCloseTradingKey = key;

   bool hadOpen = (ArraySize(g_groups) > 0);
   bool closedAny = false;
   bool allClosed = true;
   for(int i = ArraySize(g_groups) - 1; i >= 0; i--)
   {
      double r, pnl, px, vol;
      if(!ComputeR(i, r, pnl, px, vol))
      {
         allClosed = false;
         continue;
      }
      if(r > 0.0)
      {
         if(CloseGroup(i, "GROUP_CLOSE_DAILY_TIME", "Daily close window reached; group closed (R > 0)", px, pnl, r))
            closedAny = true;
         else
            allClosed = false;
      }
      else
      {
         allClosed = false;
         LogTrade((g_groups[i].isBuy ? "BUY" : "SELL"), "GROUP_SKIP_DAILY_TIME", "Daily close window reached; group kept open (R <= 0)", px, vol, pnl, r);
      }
   }

   if(hadOpen && closedAny && allClosed)
   {
      g_halted = true;
      LogTrade("GLOBAL", "ALL_CLOSE_DAILY_TIME", "Daily close window reached; all open groups closed in profit", 0.0, 0.0, 0.0, 0.0);
   }
   else if(hadOpen && closedAny)
   {
      LogTrade("GLOBAL", "PARTIAL_CLOSE_DAILY_TIME", "Daily close window reached; only profitable groups were closed", 0.0, 0.0, 0.0, 0.0);
   }
   else if(hadOpen)
   {
      LogTrade("GLOBAL", "SKIP_CLOSE_DAILY_TIME", "Daily close window reached; no group met R > 0 close condition", 0.0, 0.0, 0.0, 0.0);
   }
}

bool CanOpenSide(bool isBuy, string &reason)
{
   bool dirOK = true;
   if(isBuy && TradeDirection == TradeSellOnly) dirOK = false;
   if(!isBuy && TradeDirection == TradeBuyOnly) dirOK = false;
   bool hedgeOK = (EnableHedge || CountSide(!isBuy) == 0);
   bool cooldownOK = (TimeCurrent() >= (isBuy ? g_buyCooldownEnd : g_sellCooldownEnd));
   bool sessionOK = IsWithinSession();
   bool marketOK = IsMarketOpen();
   bool ntzOK = !IsNoTradeZone();
   int sideCount = CountSide(isBuy);
   bool capOK = (MaxGroupsPerSide <= 0 || sideCount < MaxGroupsPerSide);
   bool swingGate = (sideCount == 0 || LatestGroupPositive(isBuy));
   bool haltOK = !g_halted;

   reason = StringFormat("dirOK=%s hedgeOK=%s cooldownOK=%s sessionOK=%s marketOK=%s noTradeZoneOK=%s capOK=%s swingGate=%s groups=%d",
                         (dirOK ? "true" : "false"),
                         (hedgeOK ? "true" : "false"),
                         (cooldownOK ? "true" : "false"),
                         (sessionOK ? "true" : "false"),
                         (marketOK ? "true" : "false"),
                         (ntzOK ? "true" : "false"),
                         (capOK ? "true" : "false"),
                         (swingGate ? "true" : "false"),
                         sideCount);

   return (dirOK && hedgeOK && cooldownOK && sessionOK && marketOK && ntzOK && capOK && swingGate && haltOK);
}

void ProcessSignals(bool is_new_bar)
{
   bool sellFlipThisBar = (is_new_bar && Strategy_SellFlipTriggered());
   bool buyFlipThisBar = (is_new_bar && Strategy_BuyFlipTriggered());

   if(sellFlipThisBar)
   {
      string reason;
      if(CanOpenSide(false, reason))
      {
         if(OpenGroup(false))
            Strategy_ConsumeSellFlip();
      }
      else
      {
         LogTrade("SELL", "ENTRY_SKIP_SELL_GATES", "SELL flip arrow but entry blocked: " + reason, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      }
   }

   if(buyFlipThisBar)
   {
      string reason;
      if(CanOpenSide(true, reason))
      {
         if(OpenGroup(true))
            Strategy_ConsumeBuyFlip();
      }
      else
      {
         LogTrade("BUY", "ENTRY_SKIP_BUY_GATES", "BUY flip arrow but entry blocked: " + reason, SymbolInfoDouble(_Symbol, SYMBOL_BID));
      }
   }
}

int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("This EA requires a hedging account type.");
      return(INIT_FAILED);
   }

   g_trade.SetDeviationInPoints(Slippage);
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, AtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   Strategy_Init(SwingPeriod, VwapAPTBase, PlotSwingVWAP, VwapUpColor, VwapDownColor, VwapLineWidth);
   Strategy_WarmStartFromHistory();

   SyncGroups();
   BootstrapMagicCounters();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.symbol != _Symbol || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!IsOurMagic(magic))
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   if(reason != DEAL_REASON_SL)
      return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   bool isBuy = IsOurBuyMagic(magic);
   if(pnl < 0.0 && CooldownH1Candles > 0)
   {
      datetime cd = TimeCurrent() + CooldownH1Candles * 3600;
      if(isBuy) g_buyCooldownEnd = cd; else g_sellCooldownEnd = cd;
      LogTrade((isBuy ? "BUY" : "SELL"), "COOLDOWN_SET", "Cooldown applied after SL loss close", trans.price, 0.0, pnl, 0.0);
   }
   else
   {
      if(isBuy) g_buyCooldownEnd = TimeCurrent(); else g_sellCooldownEnd = TimeCurrent();
      LogTrade((isBuy ? "BUY" : "SELL"), "COOLDOWN_SKIPPED", "SL close at breakeven/profit; cooldown not applied", trans.price, 0.0, pnl, 0.0);
   }
}

void OnTick()
{
   SyncGroups();
   HandleDailyClose();
   ManageGroups();
   if(g_halted) return;

   bool is_new_bar = IsNewBar(PERIOD_CURRENT, g_lastBarTime);
   if(is_new_bar)
   {
      Strategy_OnBarClose();
      ProcessSignals(is_new_bar);
   }
}
