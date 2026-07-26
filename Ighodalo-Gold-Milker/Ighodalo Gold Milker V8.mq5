//+------------------------------------------------------------------+
//| Ighodalo Gold Milker.mq5 |
//| Copyright 2025, Ighodalo V8 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#property tester_file "News_Cache.csv"
// FIXED: Added definitions for EnumToString to fix undeclared identifier errors
string EnumToString(ENUM_POSITION_TYPE typ) { if(typ == POSITION_TYPE_BUY) return "BUY"; if(typ == POSITION_TYPE_SELL) return "SELL"; return "UNKNOWN"; }
string EnumToString(ENUM_ORDER_TYPE typ) { if(typ == ORDER_TYPE_BUY) return "ORDER_TYPE_BUY"; if(typ == ORDER_TYPE_SELL) return "ORDER_TYPE_SELL"; return "UNKNOWN"; }
// Input Parameters
input double InitialLotSize = 0.01;
input double LotMultiplier = 2.0;
input int MaxMartingaleSteps = 5;
input int MartingalePips = 10;
input int BaseTP_Pips = 20;
input bool UseDailyReset = true;
input double MaxDailyDrawdownPct = 1.0;
input double TargetProfitPct = 2.0;
input long EA_MagicNumber = 123456;
input int BasketThreshold = 3;
input int MaxBaskets = 10;
input int TimeToNewBasketDays = 2;
// Signal Parameters
input int SignalPeriod = 100;
input double SignalFactor = 2.0;
// Robustness Parameters
input double MaxGlobalDrawdownPct = 20.0;
input int Slippage = 3;
// Expanding Grid Parameter
input bool UseExpandingGrid = true;
// Hedge Option
input bool EnableHedge = true;
// Trade Direction
enum ENUM_TRADE_DIRECTION {TradeBoth, TradeBuyOnly, TradeSellOnly};
input ENUM_TRADE_DIRECTION TradeDirection = TradeBoth;
// News Management
input group "News Management"
input bool EnableNewsManagement = true;
input int NewsCheckIntervalSeconds = 3600;
input int MinsBefore = 5;
input int MinsAfter = 5;
// Premium/Discount Filter Inputs
input group "Premium/Discount Filter"
input ENUM_TIMEFRAMES FilterTimeframe = PERIOD_H4;
input int LookbackPeriod = 50;
input double ZonePercentage = 20.0;
input bool EnableObjectiveTarget = false;
// Trade Mode
enum TRADE_MODE { Normal, Flip };
input TRADE_MODE EaTradeMode = Flip;
input int FlipFallbackCandles = 6; // Number of H4 candles for fallback in Flip mode
// No Trade Zone
input group "No Trade Zone"
input int NoTradeStartHour = 23;
input int NoTradeStartMin = 30;
input int NoTradeEndHour = 0;
input int NoTradeEndMin = 30;
// Safe Mode Management
input group "Safe Mode Management"
input bool EnableSafeMode = false;
input double InitialRiskPct = 1.0;
input double MaxTotalRiskPct = 10.0;
input int AtrPeriod = 14;
input double AtrSlMultiplier = 10.0;
// Profit Keeper: Sequence Breakeven
input group "Profit Keeper: Sequence Breakeven"
input double SequenceBE_StartR = 1.0;
input int BreakevenOffsetPips = 0;
// Profit Keeper: Peak Drawdown Exit
input group "Profit Keeper: Peak Drawdown Exit"
input bool EnablePeakDrawdownExit = true;
input double PeakDrawdownStartR = 2.0;
input double PeakProfitDrawdownPercent = 30.0;
// Cooldown
input int CooldownH4Candles = 3;
input group "Session Management"
input bool TradeNewYork = true; // Trade during New York session (12:00-21:00 GMT)
input bool TradeLondon = true; // Trade during London session (7:00-12:00 GMT)
input bool TradeTokyo = true; // Trade during Tokyo session (0:00-7:00 GMT)
input bool TradeSydney = true; // Trade during Sydney session (22:00-0:00 GMT)
// Support/Resistance Feature
input group "Support/Resistance Filter"
input bool EnableSupportResistance = false;
input bool EnableM5_POI = true;
input bool EnableM15_POI = true;
input bool EnableM30_POI = true;
input bool EnableH1_POI = true;
input bool EnableH4_POI = true;
input bool EnableD1_POI = false;
input int MaxPOIPerTF = 7;
input int LevelMaxAgeCandles = 200;
input int LeftBars = 22;
input int RightBars = 22;
input int ReclaimLookbackCandles = 8;
input int ReclaimGraceCandles = 10;
input int LevelExpiryCandles = 15;
input int SignalExpiryCandles = 30;
input int MaxActiveSignals = 2;
// Power Candles
input int PowerCandlePeriods = 20;
input double PowerCandleMultiplier = 1.7;
input color BullPowerColor = clrLime;
input color BearPowerColor = clrRed;
input int MaxPowerCandlesToDisplay = 1000;
// Structure for martingale state
struct TradeGroup
{
   bool active;
   int step;
   double entryPrice;
   bool partialDone;
   double baseLot;
   double totalVol;
   double virtualSL;
   double virtualTP;
   double initial_entry;
   long managed_magics[];
   int num_managed;
   long original_magic;
   bool pending_close;
   datetime last_trade_time; // Used for grace period
   datetime open_time;
   TradeGroup(const TradeGroup &other)
   {
      active = other.active;
      step = other.step;
      entryPrice = other.entryPrice;
      partialDone = other.partialDone;
      baseLot = other.baseLot;
      totalVol = other.totalVol;
      virtualSL = other.virtualSL;
      virtualTP = other.virtualTP;
      initial_entry = other.initial_entry;
      num_managed = other.num_managed;
      original_magic = other.original_magic;
      pending_close = other.pending_close;
      last_trade_time = other.last_trade_time;
      open_time = other.open_time;
      ArrayResize(managed_magics, num_managed);
      ArrayCopy(managed_magics, other.managed_magics, 0, 0, num_managed);
   }
   TradeGroup()
   {
      active = false;
      step = 0;
      entryPrice = 0.0;
      partialDone = false;
      baseLot = 0.0;
      totalVol = 0.0;
      virtualSL = 0.0;
      virtualTP = 0.0;
      initial_entry = 0.0;
      num_managed = 0;
      original_magic = 0;
      pending_close = false;
      last_trade_time = 0;
      open_time = 0;
      ArrayResize(managed_magics, 0);
   }
};
// Structure for sequence state
struct SequenceState
{
   double max_risk_amount;
   double peak_profit;
};
// Structure for SFP levels and state
struct LevelInfo
{
   double price;
   ENUM_TIMEFRAMES timeframe;
   datetime time;
   bool isResistance;
   bool breakoutDetected;
   datetime breakoutTime;
   bool reclaimDetected;
   datetime reclaimTime;
   bool reclaimPowerCandleConfirmed;
   datetime reclaimPowerCandleTime;
   int tradesTaken;
   int barsBeyondLevel;
   bool expired;
};
LevelInfo levels[];
string powerCandleObjects[];
class CBBMartingaleEA
{
private:
   // Parameters
   double m_initLot;
   double m_lotMult;
   int m_maxSteps;
   int m_pips;
   int m_tpPips;
   bool m_dailyReset;
   double m_maxDD;
   double m_targetProfitPct;
   long m_magic;
   bool m_useTrail;
   int m_trailStart;
   int m_trailStep;
   bool m_useBE;
   int m_bePips;
   int m_beLock;
   bool m_usePartial;
   double m_partialPct;
   double m_riskPct;
   double m_globalMaxDD;
   int m_slippage;
   int m_basketThreshold;
   int m_maxBaskets;
   int m_timeToNewBasketDays;
   bool m_useExpandingGrid;
   int m_volPeriod;
   bool m_enableHedge;
   ENUM_TRADE_DIRECTION m_tradeDirection;
   // News Parameters
   bool m_enableNewsManagement;
   int m_newsCheckIntervalSeconds;
   int m_minsBefore;
   int m_minsAfter;
   // News State
   struct CachedNewsEvent { datetime time; string country; int importance; };
   CachedNewsEvent m_cached_news[];
   string m_news_cache_filename;
   string m_base_currency;
   string m_quote_currency;
   datetime m_nextNewsTime;
   datetime m_lastNewsCheck;
   datetime m_lastManagedNews;
   bool m_inSleepMode;
   bool m_pendingSleep;
   datetime m_sleepStart;
   datetime m_sleepEndTime;
   // State
   TradeGroup m_buy_baskets[];
   TradeGroup m_sell_baskets[];
   long m_buy_magics[];
   long m_sell_magics[];
   int m_day;
   double m_startEq;
   bool m_halted;
   bool m_globalHalted;
   datetime m_last_trade_time;
   int m_trade_mode; // 1 for Bullish (Buys Only), -1 for Bearish (Sells Only), 0 for Neutral
   // Handles
   int m_ind;
   CTrade m_trade;
   // Global start equity
   double m_globalStartEq;
   // Cached indicator values
   double m_upper[3], m_middle[3], m_lower[3], m_close[3];
   datetime m_last_bar_time;
   bool m_state_changed;
   // Filter
   datetime m_lastFilterTime;
   double m_discountThreshold;
   double m_premiumThreshold;
   // Safe Mode parameters
   bool m_enableSafeMode;
   double m_initialRiskPct;
   double m_maxTotalRiskPct;
   int m_atrPeriod;
   double m_atrSlMultiplier;
   // Profit Keeper
   double m_sequenceBE_StartR;
   int m_breakevenOffsetPips;
   bool m_enablePeakDrawdownExit;
   double m_peakDrawdownStartR;
   double m_peakProfitDrawdownPercent;
   // Sequence states
   SequenceState m_buy_sequence;
   SequenceState m_sell_sequence;
   // Optimized state variables
   int m_buyCount;
   int m_sellCount;
   double m_buyProfit;
   double m_sellProfit;
   // Cooldown
   datetime m_buyCooldownEndTime;
   datetime m_sellCooldownEndTime;
   // Session Management
   bool m_tradeNewYork;
   bool m_tradeLondon;
   bool m_tradeTokyo;
   bool m_tradeSydney;
   // SR
   bool m_enableSupportResistance;
   bool m_buySweepDetected;
   bool m_sellSweepDetected;
   datetime m_lastBuySweep;
   datetime m_lastSellSweep;
   // Objective Target
   bool m_enableObjectiveTarget;
   void Log(string message)
   {
      Print(TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ": " + message);
   }
   void UpdateCurrentTradeStates()
   {
      m_buyCount = 0;
      m_sellCount = 0;
      m_buyProfit = 0.0;
      m_sellProfit = 0.0;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatchesAny(pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(ptype == POSITION_TYPE_BUY)
         {
            m_buyCount++;
            m_buyProfit += profit;
         }
         else if(ptype == POSITION_TYPE_SELL)
         {
            m_sellCount++;
            m_sellProfit += profit;
         }
      }
   }
   double GetPipValue()
   {
      if(_Digits == 3 || _Digits == 5) return _Point * 10;
      if(_Digits == 2 || _Digits == 4) return _Point;
      return _Point;
   }
   double GetCustom35MinATR()
   {
      int synthetic_bars_needed = m_atrPeriod + 1;
      int m5_bars_needed = synthetic_bars_needed * 7;
      MqlRates m5_rates[];
      ArraySetAsSeries(m5_rates, true);
      if(CopyRates(_Symbol, PERIOD_M5, 0, m5_bars_needed, m5_rates) < m5_bars_needed)
        {
         return -1.0;
        }
      double sum_tr = 0;
      for(int i = 0; i < m_atrPeriod; i++)
        {
         int start_idx = i * 7;
         int end_idx = start_idx + 6;
         int prev_start_idx = (i + 1) * 7;
         int prev_end_idx = prev_start_idx + 6;
         if(prev_end_idx >= ArraySize(m5_rates))
           {
            return -1.0;
           }
         double high = 0;
         double low = 1e10;
         for(int j = start_idx; j <= end_idx; j++)
           {
            high = MathMax(high, m5_rates[j].high);
            low = MathMin(low, m5_rates[j].low);
           }
         double prev_close = m5_rates[prev_end_idx].close;
         double tr = MathMax(high, prev_close) - MathMin(low, prev_close);
         sum_tr += tr;
        }
      return sum_tr / m_atrPeriod;
   }
   void ResetTradeGroup(TradeGroup &group, long base_magic)
   {
      group.active = false;
      group.step = 0;
      group.entryPrice = 0.0;
      group.partialDone = false;
      group.baseLot = 0.0;
      group.totalVol = 0.0;
      group.virtualSL = 0.0;
      group.virtualTP = 0.0;
      group.initial_entry = 0.0;
      group.pending_close = false;
      group.last_trade_time = 0;
      group.open_time = 0;
      group.original_magic = base_magic;
      ArrayResize(group.managed_magics, 1);
      group.managed_magics[0] = base_magic;
      group.num_managed = 1;
      m_state_changed = true;
   }
   bool MagicMatches(const TradeGroup &group, long magic)
   {
      for(int k = 0; k < group.num_managed; k++)
      {
         if(group.managed_magics[k] == magic)
            return true;
      }
      return false;
   }
   bool MagicMatchesAny(long magic)
   {
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(magic == m_buy_magics[j] || magic == m_sell_magics[j])
            return true;
      }
      return false;
   }
   bool IsMarketOpen()
   {
      datetime time = TimeCurrent();
      if(time == 0)
         return false;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid == 0.0)
         return false;
      MqlDateTime str;
      TimeToStruct(time, str);
      ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)str.day_of_week;
      if(day == SUNDAY || day == SATURDAY)
         return false;
      datetime midnight = time - (time % 86400);
      uint session_index = 0;
      datetime from, to;
      while(SymbolInfoSessionTrade(_Symbol, day, session_index, from, to))
      {
         if(time >= midnight + from && time < midnight + to)
            return true;
         session_index++;
      }
      return false;
   }
   double GetEaFloatingProfit()
   {
      return m_buyProfit + m_sellProfit;
   }
   double GetBuyFloatingProfit()
   {
      return m_buyProfit;
   }
   double GetSellFloatingProfit()
   {
      return m_sellProfit;
   }
   int GetOpenBuyCount()
   {
      return m_buyCount;
   }
   int GetOpenSellCount()
   {
      return m_sellCount;
   }
   void CheckReset()
   {
      if(m_dailyReset && m_startEq > 0.0)
      {
         double max_loss_amount = m_startEq * (m_maxDD / 100.0);
         double current_floating_profit = GetEaFloatingProfit();
         if(current_floating_profit < 0 && MathAbs(current_floating_profit) >= max_loss_amount)
         {
            CloseAllPositions();
            m_halted = true;
            Log(StringFormat("Daily P/L drawdown reached (Loss: %.2f >= Limit: %.2f). Trading halted.", MathAbs(current_floating_profit), max_loss_amount));
            return;
         }
      }
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_globalMaxDD > 0 && m_globalStartEq > 0.0 && equity <= m_globalStartEq * (1.0 - m_globalMaxDD / 100.0))
      {
         CloseAllPositions();
         m_globalHalted = true;
         Log("Global equity drawdown reached. Trading halted permanently.");
      }
   }
   void CheckTargetProfit()
   {
      if(IsNoTradeZone()) return;
      if(m_targetProfitPct <= 0)
         return;
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double target_amount = balance * (m_targetProfitPct / 100.0);
      double current_profit = GetEaFloatingProfit();
      if(current_profit > 0 && current_profit >= target_amount)
      {
         Log(StringFormat("Target profit of %.2f%% reached (Profit: %.2f >= Target: %.2f). Closing all positions.", m_targetProfitPct, current_profit, target_amount));
         CloseAllPositions();
      }
   }
   void CloseAllPositions()
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatchesAny(pmagic)) continue;
         m_trade.PositionClose(ticket);
      }
      for(int j = 0; j < m_maxBaskets; j++)
      {
         ResetTradeGroup(m_buy_baskets[j], m_buy_magics[j]);
         ResetTradeGroup(m_sell_baskets[j], m_sell_magics[j]);
      }
   }
   void CloseGroup(TradeGroup &group, ENUM_POSITION_TYPE posType)
   {
      if(IsNoTradeZone()) return;
      bool allClosed = true;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatches(group, pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype == posType)
         {
            if(!m_trade.PositionClose(ticket))
            {
               allClosed = false;
            }
         }
      }
      if(allClosed)
      {
         long base = group.original_magic;
         ResetTradeGroup(group, base);
      }
      else
      {
         group.pending_close = true;
         m_state_changed = true;
      }
   }
   bool HasPosForGroup(const TradeGroup &group, ENUM_POSITION_TYPE posType)
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatches(group, pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype == posType)
         {
            return true;
         }
      }
      return false;
   }
   bool HasAnyBuyPos()
   {
      return m_buyCount > 0;
   }
   bool HasAnySellPos()
   {
      return m_sellCount > 0;
   }
   bool AnyBuyBasketActive()
   {
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_buy_baskets[j].active)
            return true;
      }
      return false;
   }
   bool AnySellBasketActive()
   {
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_sell_baskets[j].active)
            return true;
      }
      return false;
   }
   double GetGroupVolumeForGroup(const TradeGroup &group, ENUM_POSITION_TYPE posType)
   {
      double total = 0.0;
      int pos_total = PositionsTotal();
      for(int i = pos_total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatches(group, pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype == posType)
         {
            total += PositionGetDouble(POSITION_VOLUME);
         }
      }
      return total;
   }
   double CalcLotSize(double riskPct, double stopPips)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pipValue = tickValue * (GetPipValue() / tickSize);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double riskAmount = balance * (riskPct / 100.0);
      double lots = riskAmount / (stopPips * pipValue);
      if(lotStep <= 0)
         lotStep = 0.01;
      lots = MathRound(lots / lotStep) * lotStep;
      double finalLots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      double maxLots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if(finalLots > maxLots)
         finalLots = maxLots;
      return finalLots;
   }
   double NormalizeLot(double lots)
   {
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0)
         lotStep = 0.01;
      return MathRound(lots / lotStep) * lotStep;
   }
   bool OpenOrder(ENUM_ORDER_TYPE orderType, double volume, long magic)
   {
      if(!IsWithinSession())
      {
         return false;
      }
      if(!IsMarketOpen())
      {
         return false;
      }
      if(IsNoTradeZone())
      {
         return false;
      }
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double reqMargin = volume * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
      if(freeMargin < reqMargin)
      {
         return false;
      }
      bool allowBuy = false;
      bool allowSell = false;
      CheckPremiumDiscountFilter(allowBuy, allowSell);
      if((orderType == ORDER_TYPE_BUY && !allowBuy) || (orderType == ORDER_TYPE_SELL && !allowSell))
      {
         return false;
      }
      double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints(m_slippage);
      if(m_trade.PositionOpen(_Symbol, orderType, volume, 0, 0, "Ighodalo Gold Milker"))
      {
         m_last_trade_time = TimeCurrent();
         m_state_changed = true;
         return true;
      }
      else
      {
         return false;
      }
   }
   void UpdateGroupState(TradeGroup &group, ENUM_POSITION_TYPE posType)
   {
      double totalVol = 0.0;
      double weightedSum = 0.0;
      double sum_swap = 0.0;
      double sum_comm = 0.0; // FIXED: Deprecated POSITION_COMMISSION, set to 0
      int pos_total = PositionsTotal();
      for(int i = pos_total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatches(group, pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype == posType)
         {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            totalVol += vol;
            weightedSum += vol * price;
            sum_swap += PositionGetDouble(POSITION_SWAP);
            // sum_comm += PositionGetDouble(POSITION_COMMISSION); // FIXED: Removed deprecated
         }
      }
      if(totalVol <= 0.0)
      {
         return;
      }
      double newAvgEntry = weightedSum / totalVol;
      if(MathAbs(newAvgEntry - group.entryPrice) > _Point || group.virtualTP == 0.0)
      {
         group.entryPrice = newAvgEntry;
         group.totalVol = totalVol;
         int dir = (posType == POSITION_TYPE_BUY) ? 1 : -1;
         double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double pip_value = tick_value * (GetPipValue() / tick_size);
         long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         double spread_pips = spread_points * _Point / GetPipValue();
         double total_cost = MathMax(0, -(sum_swap + sum_comm));
         double extra_pips = (total_cost / (totalVol * pip_value)) + spread_pips + 2.0 + 2.0;
         double tp_pips = m_tpPips;
         group.virtualTP = NormalizeDouble(newAvgEntry + dir * (tp_pips + extra_pips) * GetPipValue(), _Digits);
         if(group.initial_entry == 0.0)
         {
            group.initial_entry = newAvgEntry;
         }
         m_state_changed = true;
      }
   }
   void ManageBuyBasket(TradeGroup &group)
   {
      if(group.pending_close && IsMarketOpen())
      {
         CloseGroup(group, POSITION_TYPE_BUY);
      }
      if(!HasPosForGroup(group, POSITION_TYPE_BUY))
      {
         if(group.active && (TimeCurrent() - group.last_trade_time > 5))
         {
            long base = group.original_magic;
            ResetTradeGroup(group, base);
         }
         return;
      }
      UpdateGroupState(group, POSITION_TYPE_BUY);
      if(!IsMarketOpen())
      {
         return;
      }
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double effectiveTP;
      bool checkTP = (EaTradeMode == Normal);
      if(EaTradeMode == Flip)
      {
         int bars_passed = Bars(_Symbol, PERIOD_H4, group.open_time, TimeCurrent());
         if(bars_passed >= FlipFallbackCandles) checkTP = true;
      }
      if(m_enableObjectiveTarget)
      {
         double obj = m_premiumThreshold;
         if(checkTP)
         {
            double dist_obj = MathAbs(obj - currentPrice);
            double dist_tp = MathAbs(group.virtualTP - currentPrice);
            if(dist_obj < dist_tp)
            {
               effectiveTP = MathMin(group.virtualTP, obj);
            }
            else
            {
               effectiveTP = group.virtualTP;
            }
         }
         else
         {
            effectiveTP = obj;
         }
      }
      else
      {
         effectiveTP = group.virtualTP;
      }
      if((checkTP || m_enableObjectiveTarget) && effectiveTP != 0.0 && currentPrice >= effectiveTP)
      {
         if(IsNoTradeZone()) return;
         Log("Virtual TP hit for BUY group at " + DoubleToString(effectiveTP, _Digits) + ". Closing group.");
         CloseGroup(group, POSITION_TYPE_BUY);
         return;
      }
      if(group.virtualSL != 0.0 && currentPrice <= group.virtualSL)
      {
         if(IsNoTradeZone()) return;
         Log("Virtual SL hit for BUY group at " + DoubleToString(group.virtualSL, _Digits) + ". Closing group.");
         CloseGroup(group, POSITION_TYPE_BUY);
         m_buyCooldownEndTime = TimeCurrent() + CooldownH4Candles * 14400;
         return;
      }
   }
   void ManageSellBasket(TradeGroup &group)
   {
      if(group.pending_close && IsMarketOpen())
      {
         CloseGroup(group, POSITION_TYPE_SELL);
      }
      if(!HasPosForGroup(group, POSITION_TYPE_SELL))
      {
         if(group.active && (TimeCurrent() - group.last_trade_time > 5))
         {
            long base = group.original_magic;
            ResetTradeGroup(group, base);
         }
         return;
      }
      UpdateGroupState(group, POSITION_TYPE_SELL);
      if(!IsMarketOpen())
      {
         return;
      }
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double effectiveTP;
      bool checkTP = (EaTradeMode == Normal);
      if(EaTradeMode == Flip)
      {
         int bars_passed = Bars(_Symbol, PERIOD_H4, group.open_time, TimeCurrent());
         if(bars_passed >= FlipFallbackCandles) checkTP = true;
      }
      if(m_enableObjectiveTarget)
      {
         double obj = m_discountThreshold;
         if(checkTP)
         {
            double dist_obj = MathAbs(obj - currentPrice);
            double dist_tp = MathAbs(group.virtualTP - currentPrice);
            if(dist_obj < dist_tp)
            {
               effectiveTP = MathMax(group.virtualTP, obj);
            }
            else
            {
               effectiveTP = group.virtualTP;
            }
         }
         else
         {
            effectiveTP = obj;
         }
      }
      else
      {
         effectiveTP = group.virtualTP;
      }
      if((checkTP || m_enableObjectiveTarget) && effectiveTP != 0.0 && currentPrice <= effectiveTP)
      {
         if(IsNoTradeZone()) return;
         Log("Virtual TP hit for SELL group at " + DoubleToString(effectiveTP, _Digits) + ". Closing group.");
         CloseGroup(group, POSITION_TYPE_SELL);
         return;
      }
      if(group.virtualSL != 0.0 && currentPrice >= group.virtualSL)
      {
         if(IsNoTradeZone()) return;
         Log("Virtual SL hit for SELL group at " + DoubleToString(group.virtualSL, _Digits) + ". Closing group.");
         CloseGroup(group, POSITION_TYPE_SELL);
         m_sellCooldownEndTime = TimeCurrent() + CooldownH4Candles * 14400;
         return;
      }
   }
   void ManageBuyBaskets()
   {
      for(int i = 0; i < m_maxBaskets; i++)
      {
         if(m_buy_baskets[i].active)
         {
            ManageBuyBasket(m_buy_baskets[i]);
         }
      }
   }
   void ManageSellBaskets()
   {
      for(int i = 0; i < m_maxBaskets; i++)
      {
         if(m_sell_baskets[i].active)
         {
            ManageSellBasket(m_sell_baskets[i]);
         }
      }
   }
   void MergeBaskets(TradeGroup &target, TradeGroup &source, ENUM_POSITION_TYPE posType)
   {
      for(int k = 0; k < source.num_managed; k++)
      {
         ArrayResize(target.managed_magics, target.num_managed + 1);
         target.managed_magics[target.num_managed] = source.managed_magics[k];
         target.num_managed++;
      }
      long base = source.original_magic;
      ResetTradeGroup(source, base);
      source.active = false;
      UpdateGroupState(target, posType);
      m_state_changed = true;
   }
   void CheckBuyMerges()
   {
      double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      for(int i = m_maxBaskets - 1; i > 0; i--)
      {
         if(m_buy_baskets[i].active && m_buy_baskets[i - 1].active && m_buy_baskets[i - 1].initial_entry > 0 && current_bid >= m_buy_baskets[i - 1].initial_entry)
         {
            MergeBaskets(m_buy_baskets[i - 1], m_buy_baskets[i], POSITION_TYPE_BUY);
         }
      }
   }
   void CheckSellMerges()
   {
      double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      for(int i = m_maxBaskets - 1; i > 0; i--)
      {
         if(m_sell_baskets[i].active && m_sell_baskets[i - 1].active && m_sell_baskets[i - 1].initial_entry > 0 && current_ask <= m_sell_baskets[i - 1].initial_entry)
         {
            MergeBaskets(m_sell_baskets[i - 1], m_sell_baskets[i], POSITION_TYPE_SELL);
         }
      }
   }
   void SaveState()
   {
      const int max_saved_magics = 32;
      string prefix;
      for(int i = 0; i < m_maxBaskets; i++)
      {
         prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Buy" + IntegerToString(i) + "_";
         GlobalVariableSet(prefix + "active", m_buy_baskets[i].active ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "step", (double)m_buy_baskets[i].step);
         GlobalVariableSet(prefix + "entryPrice", m_buy_baskets[i].entryPrice);
         GlobalVariableSet(prefix + "partialDone", m_buy_baskets[i].partialDone ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "baseLot", m_buy_baskets[i].baseLot);
         GlobalVariableSet(prefix + "totalVol", m_buy_baskets[i].totalVol);
         GlobalVariableSet(prefix + "virtualSL", m_buy_baskets[i].virtualSL);
         GlobalVariableSet(prefix + "virtualTP", m_buy_baskets[i].virtualTP);
         GlobalVariableSet(prefix + "initial_entry", m_buy_baskets[i].initial_entry);
         GlobalVariableSet(prefix + "num_managed", (double)m_buy_baskets[i].num_managed);
         GlobalVariableSet(prefix + "original_magic", (double)m_buy_baskets[i].original_magic);
         GlobalVariableSet(prefix + "pending_close", m_buy_baskets[i].pending_close ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "open_time", (double)m_buy_baskets[i].open_time);
         for(int k = 0; k < m_buy_baskets[i].num_managed && k < max_saved_magics; k++)
         {
            GlobalVariableSet(prefix + "magic" + IntegerToString(k), (double)m_buy_baskets[i].managed_magics[k]);
         }
         prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Sell" + IntegerToString(i) + "_";
         GlobalVariableSet(prefix + "active", m_sell_baskets[i].active ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "step", (double)m_sell_baskets[i].step);
         GlobalVariableSet(prefix + "entryPrice", m_sell_baskets[i].entryPrice);
         GlobalVariableSet(prefix + "partialDone", m_sell_baskets[i].partialDone ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "baseLot", m_sell_baskets[i].baseLot);
         GlobalVariableSet(prefix + "totalVol", m_sell_baskets[i].totalVol);
         GlobalVariableSet(prefix + "virtualSL", m_sell_baskets[i].virtualSL);
         GlobalVariableSet(prefix + "virtualTP", m_sell_baskets[i].virtualTP);
         GlobalVariableSet(prefix + "initial_entry", m_sell_baskets[i].initial_entry);
         GlobalVariableSet(prefix + "num_managed", (double)m_sell_baskets[i].num_managed);
         GlobalVariableSet(prefix + "original_magic", (double)m_sell_baskets[i].original_magic);
         GlobalVariableSet(prefix + "pending_close", m_sell_baskets[i].pending_close ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "open_time", (double)m_sell_baskets[i].open_time);
         for(int k = 0; k < m_sell_baskets[i].num_managed && k < max_saved_magics; k++)
         {
            GlobalVariableSet(prefix + "magic" + IntegerToString(k), (double)m_sell_baskets[i].managed_magics[k]);
         }
      }
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_BuySeq_MaxRisk", m_buy_sequence.max_risk_amount);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_BuySeq_PeakProfit", m_buy_sequence.peak_profit);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_SellSeq_MaxRisk", m_sell_sequence.max_risk_amount);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_SellSeq_PeakProfit", m_sell_sequence.peak_profit);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_LastTradeTime", (double)m_last_trade_time);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_TradeMode", (double)m_trade_mode);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_BuyCooldownEndTime", (double)m_buyCooldownEndTime);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_SellCooldownEndTime", (double)m_sellCooldownEndTime);
   }
   void SaveIfChanged()
   {
      if(m_state_changed)
      {
         SaveState();
         m_state_changed = false;
      }
   }
   void LoadState()
   {
      const int max_saved_magics = 32;
      string prefix;
      for(int i = 0; i < m_maxBaskets; i++)
      {
         prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Buy" + IntegerToString(i) + "_";
         if(GlobalVariableCheck(prefix + "active"))
         {
            m_buy_baskets[i].active = GlobalVariableGet(prefix + "active") == 1.0;
            m_buy_baskets[i].step = (int)GlobalVariableGet(prefix + "step");
            m_buy_baskets[i].entryPrice = GlobalVariableGet(prefix + "entryPrice");
            m_buy_baskets[i].partialDone = GlobalVariableGet(prefix + "partialDone") == 1.0;
            m_buy_baskets[i].baseLot = GlobalVariableGet(prefix + "baseLot");
            m_buy_baskets[i].totalVol = GlobalVariableGet(prefix + "totalVol");
            m_buy_baskets[i].virtualSL = GlobalVariableGet(prefix + "virtualSL");
            m_buy_baskets[i].virtualTP = GlobalVariableGet(prefix + "virtualTP");
            m_buy_baskets[i].initial_entry = GlobalVariableGet(prefix + "initial_entry");
            m_buy_baskets[i].open_time = (datetime)GlobalVariableGet(prefix + "open_time");
            double dnum = GlobalVariableGet(prefix + "num_managed");
            int num = (int)dnum;
            num = MathMin(num, max_saved_magics);
            ArrayResize(m_buy_baskets[i].managed_magics, num);
            m_buy_baskets[i].num_managed = num;
            m_buy_baskets[i].original_magic = (long)GlobalVariableGet(prefix + "original_magic");
            m_buy_baskets[i].pending_close = GlobalVariableGet(prefix + "pending_close") == 1.0;
            for(int k = 0; k < num; k++)
            {
               string key = prefix + "magic" + IntegerToString(k);
               if(GlobalVariableCheck(key))
               {
                  m_buy_baskets[i].managed_magics[k] = (long)GlobalVariableGet(key);
               }
               else
               {
                  m_buy_baskets[i].managed_magics[k] = 0;
               }
            }
            if(m_buy_baskets[i].step > m_maxSteps)
               m_buy_baskets[i].step = m_maxSteps;
            if(m_buy_baskets[i].num_managed <= 0)
            {
               ArrayResize(m_buy_baskets[i].managed_magics, 1);
               m_buy_baskets[i].num_managed = 1;
               m_buy_baskets[i].managed_magics[0] = m_buy_baskets[i].original_magic;
            }
         }
         prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Sell" + IntegerToString(i) + "_";
         if(GlobalVariableCheck(prefix + "active"))
         {
            m_sell_baskets[i].active = GlobalVariableGet(prefix + "active") == 1.0;
            m_sell_baskets[i].step = (int)GlobalVariableGet(prefix + "step");
            m_sell_baskets[i].entryPrice = GlobalVariableGet(prefix + "entryPrice");
            m_sell_baskets[i].partialDone = GlobalVariableGet(prefix + "partialDone") == 1.0;
            m_sell_baskets[i].baseLot = GlobalVariableGet(prefix + "baseLot");
            m_sell_baskets[i].totalVol = GlobalVariableGet(prefix + "totalVol");
            m_sell_baskets[i].virtualSL = GlobalVariableGet(prefix + "virtualSL");
            m_sell_baskets[i].virtualTP = GlobalVariableGet(prefix + "virtualTP");
            m_sell_baskets[i].initial_entry = GlobalVariableGet(prefix + "initial_entry");
            m_sell_baskets[i].open_time = (datetime)GlobalVariableGet(prefix + "open_time");
            double dnum = GlobalVariableGet(prefix + "num_managed");
            int num = (int)dnum;
            num = MathMin(num, max_saved_magics);
            ArrayResize(m_sell_baskets[i].managed_magics, num);
            m_sell_baskets[i].num_managed = num;
            m_sell_baskets[i].original_magic = (long)GlobalVariableGet(prefix + "original_magic");
            m_sell_baskets[i].pending_close = GlobalVariableGet(prefix + "pending_close") == 1.0;
            for(int k = 0; k < num; k++)
            {
               string key = prefix + "magic" + IntegerToString(k);
               if(GlobalVariableCheck(key))
               {
                  m_sell_baskets[i].managed_magics[k] = (long)GlobalVariableGet(key);
               }
               else
               {
                  m_sell_baskets[i].managed_magics[k] = 0;
               }
            }
            if(m_sell_baskets[i].step > m_maxSteps)
               m_sell_baskets[i].step = m_maxSteps;
            if(m_sell_baskets[i].num_managed <= 0)
            {
               ArrayResize(m_sell_baskets[i].managed_magics, 1);
               m_sell_baskets[i].num_managed = 1;
               m_sell_baskets[i].managed_magics[0] = m_sell_baskets[i].original_magic;
            }
         }
      }
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_BuySeq_MaxRisk"))
         m_buy_sequence.max_risk_amount = GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_BuySeq_MaxRisk");
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_BuySeq_PeakProfit"))
         m_buy_sequence.peak_profit = GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_BuySeq_PeakProfit");
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_SellSeq_MaxRisk"))
         m_sell_sequence.max_risk_amount = GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_SellSeq_MaxRisk");
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_SellSeq_PeakProfit"))
         m_sell_sequence.peak_profit = GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_SellSeq_PeakProfit");
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_EA_LastTradeTime"))
      {
         m_last_trade_time = (datetime)GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_EA_LastTradeTime");
      }
      else
      {
         m_last_trade_time = 0;
      }
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_EA_TradeMode"))
      {
         m_trade_mode = (int)GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_EA_TradeMode");
      }
      else
      {
         m_trade_mode = 0;
      }
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_EA_BuyCooldownEndTime"))
         m_buyCooldownEndTime = (datetime)GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_EA_BuyCooldownEndTime");
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "IGM_EA_SellCooldownEndTime"))
         m_sellCooldownEndTime = (datetime)GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "IGM_EA_SellCooldownEndTime");
   }
   string CurrencyToCountryCode(string currency)
   {
      if(currency == "USD") return "US";
      if(currency == "EUR") return "EU";
      if(currency == "GBP") return "GB";
      if(currency == "JPY") return "JP";
      if(currency == "CAD") return "CA";
      if(currency == "AUD") return "AU";
      if(currency == "NZD") return "NZ";
      if(currency == "CHF") return "CH";
      if(currency == "CNY") return "CN";
      return "";
     }
   void LoadNewsFromCache()
     {
      ArrayFree(m_cached_news);
      int file_handle = FileOpen(m_news_cache_filename, FILE_READ|FILE_CSV|FILE_COMMON, ',');
      if(file_handle == INVALID_HANDLE)
        {
         return;
        }
      // Skip the header row
      FileReadString(file_handle);
      FileReadString(file_handle);
      FileReadString(file_handle);
      int count = 0;
      while(!FileIsEnding(file_handle))
        {
         string time_str = FileReadString(file_handle);
         datetime event_time = StringToTime(time_str);
         string country = FileReadString(file_handle);
         int importance = (int)StringToInteger(FileReadString(file_handle));
         if(event_time < StringToTime("2020.01.01") || event_time > StringToTime("2030.12.31")) continue;
         int size = ArraySize(m_cached_news);
         ArrayResize(m_cached_news, size + 1, 1000);
         m_cached_news[size].time = event_time;
         m_cached_news[size].country = country;
         m_cached_news[size].importance = importance;
         count++;
        }
      FileClose(file_handle);
     }
   void DownloadAndCacheNews()
     {
      int file_handle = FileOpen(m_news_cache_filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(file_handle == INVALID_HANDLE)
        {
         return;
        }
      FileWrite(file_handle, "time_as_string", "country", "importance");
      datetime from = TimeCurrent() - (86400 * 90);
      datetime to = TimeCurrent() + (86400 * 90); // One year into the future
      MqlCalendarValue values[];
      int total_saved = 0;
      if(CalendarValueHistory(values, from, to))
        {
         for(int i = 0; i < ArraySize(values); i++)
           {
            MqlCalendarEvent event_details;
            if(CalendarEventById(values[i].event_id, event_details))
              {
               MqlCalendarCountry country_details;
               if(CalendarCountryById(event_details.country_id, country_details))
                 {
                  FileWrite(file_handle, TimeToString(values[i].time, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                            country_details.code, event_details.importance);
                  total_saved++;
                 }
              }
           }
        }
      FileClose(file_handle);
     }
   datetime GetNextHighImpactNewsTime()
     {
      datetime next_event_time = 0;
      datetime now = TimeGMT();
      string relevant_countries[2];
      relevant_countries[0] = CurrencyToCountryCode(m_base_currency);
      relevant_countries[1] = CurrencyToCountryCode(m_quote_currency);
      if(MQLInfoInteger(MQL_TESTER))
        {
         for(int i = 0; i < ArraySize(m_cached_news); i++)
           {
            if(m_cached_news[i].time > now && m_cached_news[i].importance == CALENDAR_IMPORTANCE_HIGH)
              {
               if(m_cached_news[i].country == relevant_countries[0] || m_cached_news[i].country == relevant_countries[1])
                 {
                  if(next_event_time == 0 || m_cached_news[i].time < next_event_time)
                    {
                     next_event_time = m_cached_news[i].time;
                    }
                 }
              }
           }
        }
      else
        {
         datetime to = now + 86400 * 7; // Check for news up to 7 days ahead
         MqlCalendarValue values[];
         for(int c = 0; c < 2; c++)
           {
            if(relevant_countries[c] == "") continue;
            if(CalendarValueHistory(values, now, to, relevant_countries[c]))
              {
               for(int i = 0; i < ArraySize(values); i++)
                 {
                  MqlCalendarEvent event_details;
                  if(CalendarEventById(values[i].event_id, event_details))
                    {
                     if(event_details.importance == CALENDAR_IMPORTANCE_HIGH)
                       {
                        if(next_event_time == 0 || values[i].time < next_event_time)
                          {
                           next_event_time = values[i].time;
                          }
                       }
                    }
                 }
              }
           }
        }
      return next_event_time;
     }
   void ManagePositionsBeforeNews()
     {
      double pip = GetPipValue();
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_buy_baskets[j].active)
         {
            double profit = 0.0;
            int total = PositionsTotal();
            for(int i = total - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket == 0) continue;
               long pmagic = PositionGetInteger(POSITION_MAGIC);
               if(MagicMatches(m_buy_baskets[j], pmagic))
               {
                  profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               }
            }
            if(profit > 0)
            {
               double be_price = m_buy_baskets[j].entryPrice + BreakevenOffsetPips * pip;
               for(int i = total - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(ticket == 0) continue;
                  long pmagic = PositionGetInteger(POSITION_MAGIC);
                  if(MagicMatches(m_buy_baskets[j], pmagic))
                  {
                     double existing_tp = PositionGetDouble(POSITION_TP);
                     m_trade.PositionModify(ticket, be_price, existing_tp);
                  }
               }
            }
         }
         if(m_sell_baskets[j].active)
         {
            double profit = 0.0;
            int total = PositionsTotal();
            for(int i = total - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket == 0) continue;
               long pmagic = PositionGetInteger(POSITION_MAGIC);
               if(MagicMatches(m_sell_baskets[j], pmagic))
               {
                  profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               }
            }
            if(profit > 0)
            {
               double be_price = m_sell_baskets[j].entryPrice - BreakevenOffsetPips * pip;
               for(int i = total - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(ticket == 0) continue;
                  long pmagic = PositionGetInteger(POSITION_MAGIC);
                  if(MagicMatches(m_sell_baskets[j], pmagic))
                  {
                     double existing_tp = PositionGetDouble(POSITION_TP);
                     m_trade.PositionModify(ticket, be_price, existing_tp);
                  }
               }
            }
         }
      }
     }
   void CheckNewsEvents()
     {
      if(!m_enableNewsManagement) return;
      datetime now_gmt = TimeGMT();
      if(m_pendingSleep && now_gmt >= m_sleepStart)
        {
         m_pendingSleep = false;
         m_inSleepMode = true;
        }
      if(m_inSleepMode && now_gmt >= m_sleepEndTime)
        {
         m_inSleepMode = false;
        }
      if(now_gmt - m_lastNewsCheck >= m_newsCheckIntervalSeconds)
        {
         m_lastNewsCheck = now_gmt;
         m_nextNewsTime = GetNextHighImpactNewsTime();
        }
      if(m_nextNewsTime > 0 && m_nextNewsTime != m_lastManagedNews)
        {
         long time_to_news = m_nextNewsTime - now_gmt;
         if(time_to_news <= m_minsBefore * 60 && time_to_news > 0)
           {
            ManagePositionsBeforeNews();
            m_lastManagedNews = m_nextNewsTime;
            m_pendingSleep = true;
            m_sleepStart = now_gmt + 60;
            m_sleepEndTime = m_nextNewsTime + m_minsAfter * 60 - 60;
           }
        }
     }
   void CalculateThresholds()
   {
      double highs[], lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      if(CopyHigh(_Symbol, FilterTimeframe, 1, LookbackPeriod, highs) < LookbackPeriod || CopyLow(_Symbol, FilterTimeframe, 1, LookbackPeriod, lows) < LookbackPeriod)
      {
         return;
      }
      double rangeHigh = highs[0];
      double rangeLow = lows[0];
      for(int i = 1; i < LookbackPeriod; i++)
      {
         rangeHigh = MathMax(rangeHigh, highs[i]);
         rangeLow = MathMin(rangeLow, lows[i]);
      }
      double rangeSize = rangeHigh - rangeLow;
      if(rangeSize == 0)
      {
         return;
      }
      m_premiumThreshold = rangeHigh - (rangeSize * ZonePercentage / 100.0);
      m_discountThreshold = rangeLow + (rangeSize * ZonePercentage / 100.0);
   }
   void UpdateLines()
   {
      string discountLine = "DiscountThresholdLine";
      string premiumLine = "PremiumThresholdLine";
      long chart_id = ChartID();
      if(ObjectFind(chart_id, discountLine) < 0)
      {
         ObjectCreate(chart_id, discountLine, OBJ_HLINE, 0, 0, m_discountThreshold);
         ObjectSetInteger(chart_id, discountLine, OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(chart_id, discountLine, OBJPROP_STYLE, STYLE_DASH);
      }
      else
      {
         ObjectSetDouble(chart_id, discountLine, OBJPROP_PRICE, m_discountThreshold);
      }
      if(ObjectFind(chart_id, premiumLine) < 0)
      {
         ObjectCreate(chart_id, premiumLine, OBJ_HLINE, 0, 0, m_premiumThreshold);
         ObjectSetInteger(chart_id, premiumLine, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(chart_id, premiumLine, OBJPROP_STYLE, STYLE_DASH);
      }
      else
      {
         ObjectSetDouble(chart_id, premiumLine, OBJPROP_PRICE, m_premiumThreshold);
      }
   }
   void CheckPremiumDiscountFilter(bool &isBuyZone, bool &isSellZone)
   {
      isBuyZone = false;
      isSellZone = false;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      isBuyZone = ask < m_discountThreshold;
      isSellZone = bid > m_premiumThreshold;
   }
   bool IsNoTradeZone()
   {
      datetime now = TimeCurrent();
      MqlDateTime s;
      TimeToStruct(now, s);
      int current_min = s.hour * 60 + s.min;
      int start_min = NoTradeStartHour * 60 + NoTradeStartMin;
      int end_min = NoTradeEndHour * 60 + NoTradeEndMin;
      if(start_min < end_min)
      {
         return current_min >= start_min && current_min < end_min;
      }
      else
      {
         return current_min >= start_min || current_min < end_min;
      }
   }
   double GetBuyTotalPotentialLoss()
   {
      double total_loss = 0.0;
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_buy_baskets[j].active && m_buy_baskets[j].virtualSL > 0)
         {
            total_loss += m_buy_baskets[j].totalVol * (m_buy_baskets[j].entryPrice - m_buy_baskets[j].virtualSL) * (tick_value / tick_size);
         }
      }
      return total_loss;
   }
   double GetSellTotalPotentialLoss()
   {
      double total_loss = 0.0;
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_sell_baskets[j].active && m_sell_baskets[j].virtualSL > 0)
         {
            total_loss += m_sell_baskets[j].totalVol * (m_sell_baskets[j].virtualSL - m_sell_baskets[j].entryPrice) * (tick_value / tick_size);
         }
      }
      return total_loss;
   }
   double GetBuyWeightedAvgEntry()
   {
      double weighted_sum = 0.0;
      double total_vol = 0.0;
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_buy_baskets[j].active)
         {
            weighted_sum += m_buy_baskets[j].entryPrice * m_buy_baskets[j].totalVol;
            total_vol += m_buy_baskets[j].totalVol;
         }
      }
      if(total_vol == 0) return 0.0;
      return weighted_sum / total_vol;
   }
   double GetSellWeightedAvgEntry()
   {
      double weighted_sum = 0.0;
      double total_vol = 0.0;
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_sell_baskets[j].active)
         {
            weighted_sum += m_sell_baskets[j].entryPrice * m_sell_baskets[j].totalVol;
            total_vol += m_sell_baskets[j].totalVol;
         }
      }
      if(total_vol == 0) return 0.0;
      return weighted_sum / total_vol;
   }
   void CloseAllBuys()
   {
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_buy_baskets[j].active)
         {
            CloseGroup(m_buy_baskets[j], POSITION_TYPE_BUY);
         }
      }
   }
   void CloseAllSells()
   {
      for(int j = 0; j < m_maxBaskets; j++)
      {
         if(m_sell_baskets[j].active)
         {
            CloseGroup(m_sell_baskets[j], POSITION_TYPE_SELL);
         }
      }
   }
   void ResetBuySequence()
   {
      m_buy_sequence.max_risk_amount = 0.0;
      m_buy_sequence.peak_profit = 0.0;
   }
   void ResetSellSequence()
   {
      m_sell_sequence.max_risk_amount = 0.0;
      m_sell_sequence.peak_profit = 0.0;
   }
   void ManageBuySequenceBreakeven()
   {
      if(m_sequenceBE_StartR <= 0 || m_buy_sequence.max_risk_amount <= 0) return;
      double profit = GetBuyFloatingProfit();
      if(profit >= m_buy_sequence.max_risk_amount * m_sequenceBE_StartR)
      {
         double avg_entry = GetBuyWeightedAvgEntry();
         double new_sl = avg_entry + m_breakevenOffsetPips * GetPipValue();
         for(int j = 0; j < m_maxBaskets; j++)
         {
            if(m_buy_baskets[j].active && m_buy_baskets[j].virtualSL < new_sl)
            {
               m_buy_baskets[j].virtualSL = new_sl;
            }
         }
      }
   }
   void ManageSellSequenceBreakeven()
   {
      if(m_sequenceBE_StartR <= 0 || m_sell_sequence.max_risk_amount <= 0) return;
      double profit = GetSellFloatingProfit();
      if(profit >= m_sell_sequence.max_risk_amount * m_sequenceBE_StartR)
      {
         double avg_entry = GetSellWeightedAvgEntry();
         double new_sl = avg_entry - m_breakevenOffsetPips * GetPipValue();
         for(int j = 0; j < m_maxBaskets; j++)
         {
            if(m_sell_baskets[j].active && (m_sell_baskets[j].virtualSL > new_sl || m_sell_baskets[j].virtualSL == 0))
            {
               m_sell_baskets[j].virtualSL = new_sl;
            }
         }
      }
   }
   void ManageBuyPeakDrawdown()
   {
      if(IsNoTradeZone()) return;
      if(!m_enablePeakDrawdownExit || m_buy_sequence.max_risk_amount <= 0) return;
      double profit = GetBuyFloatingProfit();
      if(profit >= m_buy_sequence.max_risk_amount * m_peakDrawdownStartR)
      {
         if(profit > m_buy_sequence.peak_profit)
         {
            m_buy_sequence.peak_profit = profit;
         }
         if(m_buy_sequence.peak_profit > 0 && profit < m_buy_sequence.peak_profit * (1 - m_peakProfitDrawdownPercent / 100.0))
         {
            Log("Peak drawdown exit for buys.");
            CloseAllBuys();
         }
      }
   }
   void ManageSellPeakDrawdown()
   {
      if(IsNoTradeZone()) return;
      if(!m_enablePeakDrawdownExit || m_sell_sequence.max_risk_amount <= 0) return;
      double profit = GetSellFloatingProfit();
      if(profit >= m_sell_sequence.max_risk_amount * m_peakDrawdownStartR)
      {
         if(profit > m_sell_sequence.peak_profit)
         {
            m_sell_sequence.peak_profit = profit;
         }
         if(m_sell_sequence.peak_profit > 0 && profit < m_sell_sequence.peak_profit * (1 - m_peakProfitDrawdownPercent / 100.0))
         {
            Log("Peak drawdown exit for sells.");
            CloseAllSells();
         }
      }
   }
   bool IsWithinSession()
   {
      datetime time = TimeGMT();
      MqlDateTime str;
      TimeToStruct(time, str);
      int minutes = str.hour * 60 + str.min;
      if(m_tradeNewYork && minutes >= 12 * 60 && minutes < 21 * 60) return true;
      if(m_tradeLondon && minutes >= 7 * 60 && minutes < 12 * 60) return true;
      if(m_tradeTokyo && minutes >= 0 && minutes < 7 * 60) return true;
      if(m_tradeSydney && (minutes >= 22 * 60 || minutes < 5 * 60)) return true;
      return false;
   }
   // SR Functions
   bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int idx)
   {
      int total_bars_tf = iBars(_Symbol, tf);
      if(idx < RightBars || idx + LeftBars >= total_bars_tf) return false;
      double value = iHigh(_Symbol, tf, idx);
      for(int i = idx - RightBars; i <= idx + LeftBars; i++)
      {
         if(i == idx) continue;
         if(iHigh(_Symbol, tf, i) >= value) return false;
      }
      return true;
   }
   bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int idx)
   {
      int total_bars_tf = iBars(_Symbol, tf);
      if(idx < RightBars || idx + LeftBars >= total_bars_tf) return false;
      double value = iLow(_Symbol, tf, idx);
      for(int i = idx - RightBars; i <= idx + LeftBars; i++)
      {
         if(i == idx) continue;
         if(iLow(_Symbol, tf, i) <= value) return false;
      }
      return true;
   }
   void DetectPivots(ENUM_TIMEFRAMES tf)
   {
      int totalBars = iBars(_Symbol, tf);
      if(totalBars < LeftBars + RightBars + 1) return;
      int lookback = 200; // FIXED: Added loop for multiple pivots
      for(int idx = RightBars; idx < totalBars && idx < RightBars + lookback; idx++)
      {
         datetime pivot_time = iTime(_Symbol, tf, idx);
         datetime end_plot_time = iTime(_Symbol, _Period, 0);
         if(IsPivotHighTF(tf, idx))
         {
            double pivot_price = iHigh(_Symbol, tf, idx);
            bool exists = false;
            for(int i = 0; i < ArraySize(levels); i++)
            {
               if(levels[i].timeframe == tf && levels[i].isResistance && levels[i].time == pivot_time)
               {
                  exists = true;
                  break;
               }
            }
            if(!exists) AddLevel(pivot_price, tf, pivot_time, true, end_plot_time);
         }
         if(IsPivotLowTF(tf, idx))
         {
            double pivot_price = iLow(_Symbol, tf, idx);
            bool exists = false;
            for(int i = 0; i < ArraySize(levels); i++)
            {
               if(levels[i].timeframe == tf && !levels[i].isResistance && levels[i].time == pivot_time)
               {
                  exists = true;
                  break;
               }
            }
            if(!exists) AddLevel(pivot_price, tf, pivot_time, false, end_plot_time);
         }
      }
   }
   void AddLevel(double price, ENUM_TIMEFRAMES tf, datetime time, bool isResistance, datetime end_plot_time)
   {
      int count = 0;
      int oldest_index = -1;
      datetime oldest_time = D'3000.01.01';
      for(int i = 0; i < ArraySize(levels); i++)
      {
         if(levels[i].timeframe == tf && levels[i].isResistance == isResistance && !levels[i].expired)
         {
            count++;
            if(levels[i].time < oldest_time)
            {
               oldest_time = levels[i].time;
               oldest_index = i;
            }
         }
      }
      if(count >= MaxPOIPerTF && MaxPOIPerTF > 0 && oldest_index >= 0)
      {
         string tfStr = EnumToString(tf);
         string typeStr = levels[oldest_index].isResistance ? "Resistance" : "Support";
         string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[oldest_index].time);
         ObjectDelete(0, name);
         ObjectDelete(0, name + "_Label");
         ArrayRemove(levels, oldest_index, 1);
      }
      int n = ArraySize(levels);
      ArrayResize(levels, n + 1);
      levels[n].price = price;
      levels[n].timeframe = tf;
      levels[n].time = time;
      levels[n].isResistance = isResistance;
      levels[n].breakoutDetected = false;
      levels[n].breakoutTime = 0;
      levels[n].reclaimDetected = false;
      levels[n].reclaimTime = 0;
      levels[n].reclaimPowerCandleConfirmed = false;
      levels[n].reclaimPowerCandleTime = 0;
      levels[n].tradesTaken = 0;
      levels[n].barsBeyondLevel = 0;
      levels[n].expired = false;
      string tfStr = EnumToString(tf);
      string typeStr = isResistance ? "Resistance" : "Support";
      string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(time);
      if(ObjectCreate(0, name, OBJ_TREND, 0, time, price, end_plot_time, price))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, isResistance ? clrRed : clrBlue);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_RAY, true);
         string label_name = name + "_Label";
         if(ObjectCreate(0, label_name, OBJ_TEXT, 0, time, price))
         {
            ObjectSetString(0, label_name, OBJPROP_TEXT, tfStr + " " + typeStr);
            ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, label_name, OBJPROP_COLOR, isResistance ? clrRed : clrBlue);
            ObjectSetInteger(0, label_name, OBJPROP_XOFFSET, 10);
            ObjectSetInteger(0, label_name, OBJPROP_YOFFSET, isResistance ? -10 : 10);
            ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, false);
         }
      }
   }
   void UpdateLevels()
   {
      ENUM_TIMEFRAMES enabledTFs[] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
      bool enables[] = {EnableM5_POI, EnableM15_POI, EnableM30_POI, EnableH1_POI, EnableH4_POI, EnableD1_POI};
      for(int i = 0; i < ArraySize(enabledTFs); i++)
      {
         if(enables[i]) DetectPivots(enabledTFs[i]);
      }
   }
   void UpdateLevelExpiry()
   {
      int shift = 1;
      double current_close = iClose(_Symbol, _Period, shift);
      for(int i = ArraySize(levels) - 1; i >= 0; i--)
      {
         double level_price = levels[i].price;
         bool beyond = levels[i].isResistance ? current_close > level_price : current_close < level_price;
         if(beyond)
         {
            levels[i].barsBeyondLevel++;
            if(levels[i].barsBeyondLevel > LevelExpiryCandles)
            {
               levels[i].expired = true;
               string tfStr = EnumToString(levels[i].timeframe);
               string typeStr = levels[i].isResistance ? "Resistance" : "Support";
               string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[i].time);
               ObjectDelete(0, name);
               ObjectDelete(0, name + "_Label");
               ArrayRemove(levels, i, 1);
            }
         }
         else
         {
            levels[i].barsBeyondLevel = 0;
         }
      }
   }
   // FIXED: Added for age expiration
   void UpdateOldLevels()
   {
      if(LevelMaxAgeCandles <= 0) return;
      for(int i = ArraySize(levels) - 1; i >= 0; i--)
      {
         int bars_since = iBarShift(_Symbol, levels[i].timeframe, levels[i].time);
         if(bars_since > LevelMaxAgeCandles)
         {
            levels[i].expired = true;
            string tfStr = EnumToString(levels[i].timeframe);
            string typeStr = levels[i].isResistance ? "Resistance" : "Support";
            string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[i].time);
            ObjectDelete(0, name);
            ObjectDelete(0, name + "_Label");
            ArrayRemove(levels, i, 1);
         }
      }
   }
   bool IsPowerCandle(int shift, bool isBullish)
   {
      if(shift + PowerCandlePeriods >= iBars(_Symbol, _Period)) return false;
      double sum_range = 0;
      for(int i = 0; i < PowerCandlePeriods; i++)
      {
         if(shift + i >= iBars(_Symbol, _Period)) return false;
         double open_i = iOpen(_Symbol, _Period, shift + i);
         double close_i = iClose(_Symbol, _Period, shift + i);
         sum_range += MathAbs(close_i - open_i);
      }
      double avg_range = sum_range / PowerCandlePeriods;
      double open_curr = iOpen(_Symbol, _Period, shift);
      double close_curr = iClose(_Symbol, _Period, shift);
      double body_curr = MathAbs(close_curr - open_curr);
      bool is_large = body_curr > avg_range * PowerCandleMultiplier;
      bool is_correct_direction = (isBullish && close_curr > open_curr) || (!isBullish && close_curr < open_curr);
      return is_large && is_correct_direction;
   }
   void PlotPowerCandle(int shift, bool isBullish)
   {
      if(shift >= iBars(_Symbol, _Period)) return;
      datetime t = iTime(_Symbol, _Period, shift);
      double price = isBullish ? iLow(_Symbol, _Period, shift) : iHigh(_Symbol, _Period, shift);
      color paint = isBullish ? BullPowerColor : BearPowerColor;
      int arrow_code = isBullish ? 233 : 234;
      string name = "PowerCandle_" + TimeToString(t) + "_" + IntegerToString(shift);
      if(ObjectFind(0, name) == -1)
      {
         if(ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
         {
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow_code);
            ObjectSetInteger(0, name, OBJPROP_COLOR, paint);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
            int size = ArraySize(powerCandleObjects);
            ArrayResize(powerCandleObjects, size + 1);
            powerCandleObjects[size] = name;
            if(ArraySize(powerCandleObjects) > MaxPowerCandlesToDisplay)
            {
               string old_name = powerCandleObjects[0];
               ObjectDelete(0, old_name);
               ArrayRemove(powerCandleObjects, 0, 1);
            }
         }
      }
   }
   void UpdateIndicatorPlots()
   {
      int prev_completed_bar_shift = 1;
      if(iBars(_Symbol, _Period) <= prev_completed_bar_shift) return;
      if(IsPowerCandle(prev_completed_bar_shift, true)) PlotPowerCandle(prev_completed_bar_shift, true);
      if(IsPowerCandle(prev_completed_bar_shift, false)) PlotPowerCandle(prev_completed_bar_shift, false);
   }
   bool ProcessResistanceLevel(int level_idx)
   {
      int current_bar_shift = 1;
      if(iBars(_Symbol, _Period) <= current_bar_shift) return false;
      datetime current_time = iTime(_Symbol, _Period, current_bar_shift);
      double current_high = iHigh(_Symbol, _Period, current_bar_shift);
      double current_close = iClose(_Symbol, _Period, current_bar_shift);
      double level_price = levels[level_idx].price;
      if(levels[level_idx].expired) return false;
      if(current_close > level_price)
      {
         levels[level_idx].barsBeyondLevel++;
         if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
         {
            levels[level_idx].expired = true;
            return false;
         }
      }
      else
      {
         levels[level_idx].barsBeyondLevel = 0;
      }
      if(current_high > level_price && current_close < level_price && levels[level_idx].reclaimTime == 0)
      {
         levels[level_idx].breakoutDetected = true;
         levels[level_idx].breakoutTime = current_time;
         levels[level_idx].reclaimDetected = true;
         levels[level_idx].reclaimTime = current_time;
      }
      if(!levels[level_idx].reclaimDetected)
      {
         if(!levels[level_idx].breakoutDetected && current_close > level_price)
         {
            levels[level_idx].breakoutDetected = true;
            levels[level_idx].breakoutTime = current_time;
         }
         if(levels[level_idx].breakoutDetected)
         {
            int breakout_shift = iBarShift(_Symbol, _Period, levels[level_idx].breakoutTime);
            int bars_after_breakout = breakout_shift - current_bar_shift;
            if(bars_after_breakout > ReclaimLookbackCandles)
            {
               levels[level_idx].breakoutDetected = false;
            }
            if(current_close < level_price)
            {
               levels[level_idx].reclaimDetected = true;
               levels[level_idx].reclaimTime = current_time;
            }
         }
      }
      if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
      {
         int reclaim_shift = iBarShift(_Symbol, _Period, levels[level_idx].reclaimTime);
         int bars_after_reclaim = reclaim_shift - current_bar_shift;
         if(bars_after_reclaim > ReclaimGraceCandles)
         {
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].breakoutDetected = false;
            return false;
         }
         double atr = GetCustom35MinATR();
         if(atr <= 0) return false;
         double max_dist = atr * 0.2;
         for(int j = reclaim_shift - 1; j >= current_bar_shift; j--)
         {
            double close_j = iClose(_Symbol, _Period, j);
            double high_j = iHigh(_Symbol, _Period, j);
            if(close_j < level_price && IsPowerCandle(j, false) && MathAbs(high_j - level_price) <= max_dist)
            {
               levels[level_idx].reclaimPowerCandleConfirmed = true;
               levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, j);
               break;
            }
         }
      }
      if(levels[level_idx].reclaimPowerCandleConfirmed)
      {
         m_sellSweepDetected = true;
         m_lastSellSweep = TimeCurrent();
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         return true;
      }
      return false;
   }
   bool ProcessSupportLevel(int level_idx)
   {
      int current_bar_shift = 1;
      if(iBars(_Symbol, _Period) <= current_bar_shift) return false;
      datetime current_time = iTime(_Symbol, _Period, current_bar_shift);
      double current_low = iLow(_Symbol, _Period, current_bar_shift);
      double current_close = iClose(_Symbol, _Period, current_bar_shift);
      double level_price = levels[level_idx].price;
      if(levels[level_idx].expired) return false;
      if(current_close < level_price)
      {
         levels[level_idx].barsBeyondLevel++;
         if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
         {
            levels[level_idx].expired = true;
            return false;
         }
      }
      else
      {
         levels[level_idx].barsBeyondLevel = 0;
      }
      if(current_low < level_price && current_close > level_price && levels[level_idx].reclaimTime == 0)
      {
         levels[level_idx].breakoutDetected = true;
         levels[level_idx].breakoutTime = current_time;
         levels[level_idx].reclaimDetected = true;
         levels[level_idx].reclaimTime = current_time;
      }
      if(!levels[level_idx].reclaimDetected)
      {
         if(!levels[level_idx].breakoutDetected && current_close < level_price)
         {
            levels[level_idx].breakoutDetected = true;
            levels[level_idx].breakoutTime = current_time;
         }
         if(levels[level_idx].breakoutDetected)
         {
            int breakout_shift = iBarShift(_Symbol, _Period, levels[level_idx].breakoutTime);
            int bars_after_breakout = breakout_shift - current_bar_shift;
            if(bars_after_breakout > ReclaimLookbackCandles)
            {
               levels[level_idx].breakoutDetected = false;
            }
            if(current_close > level_price)
            {
               levels[level_idx].reclaimDetected = true;
               levels[level_idx].reclaimTime = current_time;
            }
         }
      }
      if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
      {
         int reclaim_shift = iBarShift(_Symbol, _Period, levels[level_idx].reclaimTime);
         int bars_after_reclaim = reclaim_shift - current_bar_shift;
         if(bars_after_reclaim > ReclaimGraceCandles)
         {
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].breakoutDetected = false;
            return false;
         }
         double atr = GetCustom35MinATR();
         if(atr <= 0) return false;
         double max_dist = atr * 0.2;
         for(int j = reclaim_shift - 1; j >= current_bar_shift; j--)
         {
            double close_j = iClose(_Symbol, _Period, j);
            double low_j = iLow(_Symbol, _Period, j);
            if(close_j > level_price && IsPowerCandle(j, true) && MathAbs(low_j - level_price) <= max_dist)
            {
               levels[level_idx].reclaimPowerCandleConfirmed = true;
               levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, j);
               break;
            }
         }
      }
      if(levels[level_idx].reclaimPowerCandleConfirmed)
      {
         m_buySweepDetected = true;
         m_lastBuySweep = TimeCurrent();
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         return true;
      }
      return false;
   }
   void CheckSweeps()
   {
      m_buySweepDetected = false;
      m_sellSweepDetected = false;
      for(int i = ArraySize(levels) - 1; i >= 0; i--)
      {
         if(levels[i].isResistance)
         {
            if(ProcessResistanceLevel(i)) m_sellSweepDetected = true;
         }
         else
         {
            if(ProcessSupportLevel(i)) m_buySweepDetected = true;
         }
      }
   }
   bool HasRecentBuySweep()
   {
      return m_buySweepDetected || (TimeCurrent() - m_lastBuySweep < PeriodSeconds(_Period) * SignalExpiryCandles);
   }
   bool HasRecentSellSweep()
   {
      return m_sellSweepDetected || (TimeCurrent() - m_lastSellSweep < PeriodSeconds(_Period) * SignalExpiryCandles);
   }
public:
   CBBMartingaleEA()
   {
      m_initLot = InitialLotSize;
      m_lotMult = LotMultiplier;
      m_maxSteps = MaxMartingaleSteps;
      m_pips = MartingalePips;
      m_tpPips = BaseTP_Pips;
      m_dailyReset = UseDailyReset;
      m_maxDD = MaxDailyDrawdownPct;
      m_targetProfitPct = TargetProfitPct;
      m_magic = EA_MagicNumber;
      m_useTrail = false;
      m_trailStart = 0;
      m_trailStep = 0;
      m_useBE = false;
      m_bePips = 0;
      m_beLock = 0;
      m_usePartial = false;
      m_partialPct = 0;
      m_riskPct = 0;
      m_globalMaxDD = MaxGlobalDrawdownPct;
      m_slippage = Slippage;
      m_basketThreshold = BasketThreshold;
      m_maxBaskets = MaxBaskets;
      m_timeToNewBasketDays = TimeToNewBasketDays;
      m_useExpandingGrid = UseExpandingGrid;
      m_volPeriod = 20;
      m_enableHedge = EnableHedge;
      m_tradeDirection = TradeDirection;
      m_enableNewsManagement = EnableNewsManagement;
      m_newsCheckIntervalSeconds = NewsCheckIntervalSeconds;
      m_minsBefore = MinsBefore;
      m_minsAfter = MinsAfter;
      m_day = 0;
      m_startEq = 0.0;
      m_halted = false;
      m_globalHalted = false;
      m_last_bar_time = 0;
      m_last_trade_time = 0;
      m_trade_mode = 0;
      m_nextNewsTime = 0;
      m_lastNewsCheck = 0;
      m_lastManagedNews = 0;
      m_inSleepMode = false;
      m_pendingSleep = false;
      m_sleepStart = 0;
      m_sleepEndTime = 0;
      m_state_changed = false;
      m_lastFilterTime = 0;
      m_discountThreshold = 0.0;
      m_premiumThreshold = 0.0;
      m_trade.SetExpertMagicNumber((ulong)m_magic);
      // Safe Mode
      m_enableSafeMode = EnableSafeMode;
      m_initialRiskPct = InitialRiskPct;
      m_maxTotalRiskPct = MaxTotalRiskPct;
      m_atrPeriod = AtrPeriod;
      m_atrSlMultiplier = AtrSlMultiplier;
      // Profit Keeper
      m_sequenceBE_StartR = SequenceBE_StartR;
      m_breakevenOffsetPips = BreakevenOffsetPips;
      m_enablePeakDrawdownExit = EnablePeakDrawdownExit;
      m_peakDrawdownStartR = PeakDrawdownStartR;
      m_peakProfitDrawdownPercent = PeakProfitDrawdownPercent;
      // Sequence states
      m_buy_sequence.max_risk_amount = 0.0;
      m_buy_sequence.peak_profit = 0.0;
      m_sell_sequence.max_risk_amount = 0.0;
      m_sell_sequence.peak_profit = 0.0;
      // Optimized
      m_buyCount = 0;
      m_sellCount = 0;
      m_buyProfit = 0.0;
      m_sellProfit = 0.0;
      // Cooldown
      m_buyCooldownEndTime = 0;
      m_sellCooldownEndTime = 0;
      // Session Management
      m_tradeNewYork = TradeNewYork;
      m_tradeLondon = TradeLondon;
      m_tradeTokyo = TradeTokyo;
      m_tradeSydney = TradeSydney;
      // SR
      m_enableSupportResistance = EnableSupportResistance;
      m_buySweepDetected = false;
      m_sellSweepDetected = false;
      m_lastBuySweep = 0;
      m_lastSellSweep = 0;
      // Objective Target
      m_enableObjectiveTarget = EnableObjectiveTarget;
   }
   int OnInit()
   {
      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Print("This EA requires a hedging account type.");
         return(INIT_FAILED);
      }
      ChartSetInteger(0, CHART_SHOW_GRID, false);
      int bars = Bars(_Symbol, PERIOD_M6);
      if(bars < SignalPeriod + 3)
      {
         Print("Insufficient historical bars for indicators.");
         return(INIT_FAILED);
      }
      m_ind = iBands(_Symbol, PERIOD_M6, SignalPeriod, 0, SignalFactor, PRICE_CLOSE);
      if(m_ind == INVALID_HANDLE)
      {
         Print("Failed to create indicator");
         return(INIT_FAILED);
      }
      m_globalStartEq = AccountInfoDouble(ACCOUNT_BALANCE);
      ArrayResize(m_buy_baskets, m_maxBaskets);
      ArrayResize(m_sell_baskets, m_maxBaskets);
      ArrayResize(m_buy_magics, m_maxBaskets);
      ArrayResize(m_sell_magics, m_maxBaskets);
      for(int i = 0; i < m_maxBaskets; i++)
      {
         m_buy_magics[i] = m_magic + i;
         m_sell_magics[i] = m_magic + m_maxBaskets + i;
         ResetTradeGroup(m_buy_baskets[i], m_buy_magics[i]);
         ResetTradeGroup(m_sell_baskets[i], m_sell_magics[i]);
      }
      LoadState();
      if(m_enableNewsManagement)
        {
         m_base_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
         m_quote_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
         m_news_cache_filename = "News_Cache.csv";
         if(MQLInfoInteger(MQL_TESTER))
           {
            LoadNewsFromCache();
           }
         else
           {
            DownloadAndCacheNews();
           }
         m_nextNewsTime = GetNextHighImpactNewsTime();
         m_lastNewsCheck = TimeGMT();
        }
      datetime tf_time[1];
      if(CopyTime(_Symbol, FilterTimeframe, 0, 1, tf_time) > 0)
      {
         m_lastFilterTime = tf_time[0];
      }
      CalculateThresholds();
      UpdateLines();
      if(m_enableSupportResistance) UpdateLevels();
      return(INIT_SUCCEEDED);
   }
   void OnDeinit(const int reason)
   {
      if(m_ind != INVALID_HANDLE)
      {
         IndicatorRelease(m_ind);
      }
   }
   void OnTick()
   {
      if(m_inSleepMode) return;
      UpdateCurrentTradeStates();
      if(!HasAnyBuyPos()) ResetBuySequence();
      if(!HasAnySellPos()) ResetSellSequence();
      datetime tf_time[1];
      if(CopyTime(_Symbol, FilterTimeframe, 0, 1, tf_time) > 0 && tf_time[0] != m_lastFilterTime)
      {
         m_lastFilterTime = tf_time[0];
         CalculateThresholds();
         UpdateLines();
      }
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      if(dt.day != m_day || m_day == 0)
      {
         if(m_day == 0);
         m_day = dt.day;
         m_startEq = AccountInfoDouble(ACCOUNT_BALANCE);
         m_halted = false;
         for(int i = 0; i < m_maxBaskets; i++)
         {
            if(!HasPosForGroup(m_buy_baskets[i], POSITION_TYPE_BUY))
            {
               m_buy_baskets[i].active = false;
               m_state_changed = true;
            }
            else
            {
               m_buy_baskets[i].active = true;
               m_buy_baskets[i].virtualTP = 0.0;
               m_state_changed = true;
               UpdateGroupState(m_buy_baskets[i], POSITION_TYPE_BUY);
            }
            if(!HasPosForGroup(m_sell_baskets[i], POSITION_TYPE_SELL))
            {
               m_sell_baskets[i].active = false;
               m_state_changed = true;
            }
            else
            {
               m_sell_baskets[i].active = true;
               m_sell_baskets[i].virtualTP = 0.0;
               m_state_changed = true;
               UpdateGroupState(m_sell_baskets[i], POSITION_TYPE_SELL);
            }
         }
      }
      if(m_halted || m_globalHalted)
      {
         return;
      }
      CheckReset();
      if(m_halted || m_globalHalted)
      {
         return;
      }
      CheckTargetProfit();
      CheckNewsEvents();
      ManageBuyBaskets();
      ManageSellBaskets();
      if(m_enableSafeMode)
      {
         if(HasAnyBuyPos())
         {
            ManageBuySequenceBreakeven();
            ManageBuyPeakDrawdown();
         }
         if(HasAnySellPos())
         {
            ManageSellSequenceBreakeven();
            ManageSellPeakDrawdown();
         }
      }
      CheckBuyMerges();
      CheckSellMerges();
      bool is_new_bar = false;
      datetime time[1];
      if(CopyTime(_Symbol, PERIOD_M6, 0, 1, time) > 0 && time[0] != m_last_bar_time)
      {
         m_last_bar_time = time[0];
         is_new_bar = true;
         if(m_enableSupportResistance)
         {
            UpdateLevels();
            UpdateLevelExpiry();
            UpdateOldLevels(); // FIXED: Added call for age expiration
            CheckSweeps();
            UpdateIndicatorPlots();
         }
         if(CopyBuffer(m_ind, 1, 0, 3, m_upper) < 3 || CopyBuffer(m_ind, 0, 0, 3, m_middle) < 3 || CopyBuffer(m_ind, 2, 0, 3, m_lower) < 3)
         {
            return;
         }
         if(CopyClose(_Symbol, PERIOD_M6, 0, 3, m_close) < 3)
         {
            return;
         }
         if(m_close[1] > m_upper[1])
         {
            if(m_trade_mode != 1)
            {
               m_trade_mode = 1;
               m_state_changed = true;
            }
         }
         else if(m_close[1] < m_lower[1])
         {
            if(m_trade_mode != -1)
            {
               m_trade_mode = -1;
               m_state_changed = true;
            }
         }
         double dynLot = m_initLot;
         if(m_enableSafeMode)
         {
            double atr = GetCustom35MinATR();
            if(atr > 0)
              {
               double sl_pips = atr * m_atrSlMultiplier / GetPipValue();
               dynLot = CalcLotSize(m_initialRiskPct, sl_pips);
              }
         }
         dynLot = NormalizeLot(dynLot);
         // --- SELL ENTRY LOGIC ---
         if(m_trade_mode == -1 && !AnySellBasketActive() && !HasAnySellPos() && (m_tradeDirection != TradeBuyOnly) && (m_enableHedge || !HasAnyBuyPos()) && TimeCurrent() >= m_sellCooldownEndTime && (!m_enableSupportResistance || HasRecentSellSweep()))
         {
            if(m_enableSafeMode)
            {
               double current_risk = GetSellTotalPotentialLoss();
               double proposed_risk = dynLot * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
               double balance = AccountInfoDouble(ACCOUNT_BALANCE);
               if(current_risk + proposed_risk > balance * m_maxTotalRiskPct / 100.0)
               {
                  return;
               }
            }
            if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[0]))
            {
               Log("Opened SELL trade triggered by candle closed below lower level.");
               ResetTradeGroup(m_sell_baskets[0], m_sell_magics[0]);
               m_sell_baskets[0].active = true;
               m_sell_baskets[0].step = 1;
               m_sell_baskets[0].baseLot = dynLot;
               m_sell_baskets[0].last_trade_time = TimeCurrent();
               m_sell_baskets[0].open_time = TimeCurrent();
               m_state_changed = true;
               if(m_enableSafeMode)
               {
                  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                  m_sell_sequence.max_risk_amount = balance * m_maxTotalRiskPct / 100.0;
                  double atr = GetCustom35MinATR();
                  if(atr > 0)
                     {
                      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                      m_sell_baskets[0].virtualSL = price + atr * m_atrSlMultiplier;
                     }
               }
               SaveIfChanged();
               return;
            }
         }
         // --- BUY ENTRY LOGIC ---
         if(m_trade_mode == 1 && !AnyBuyBasketActive() && !HasAnyBuyPos() && (m_tradeDirection != TradeSellOnly) && (m_enableHedge || !HasAnySellPos()) && TimeCurrent() >= m_buyCooldownEndTime && (!m_enableSupportResistance || HasRecentBuySweep()))
         {
            if(m_enableSafeMode)
            {
               double current_risk = GetBuyTotalPotentialLoss();
               double proposed_risk = dynLot * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
               double balance = AccountInfoDouble(ACCOUNT_BALANCE);
               if(current_risk + proposed_risk > balance * m_maxTotalRiskPct / 100.0)
               {
                  return;
               }
            }
            if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[0]))
            {
               Log("Opened BUY trade triggered by candle closed above upper level.");
               ResetTradeGroup(m_buy_baskets[0], m_buy_magics[0]);
               m_buy_baskets[0].active = true;
               m_buy_baskets[0].step = 1;
               m_buy_baskets[0].baseLot = dynLot;
               m_buy_baskets[0].last_trade_time = TimeCurrent();
               m_buy_baskets[0].open_time = TimeCurrent();
               m_state_changed = true;
               if(m_enableSafeMode)
               {
                  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                  m_buy_sequence.max_risk_amount = balance * m_maxTotalRiskPct / 100.0;
                  double atr = GetCustom35MinATR();
                  if(atr > 0)
                     {
                      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                      m_buy_baskets[0].virtualSL = price - atr * m_atrSlMultiplier;
                     }
               }
               SaveIfChanged();
               return;
            }
         }
      }
      if(m_trade_mode == 1 && (m_tradeDirection != TradeSellOnly) && (m_enableHedge || !HasAnySellPos()))
      {
         for(int i = 0; i < m_maxBaskets; i++)
         {
            if(!m_buy_baskets[i].active || !HasPosForGroup(m_buy_baskets[i], POSITION_TYPE_BUY))
               continue;
            double current = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double diff = m_buy_baskets[i].entryPrice - current;
            double threshold = m_pips * (m_useExpandingGrid ? m_buy_baskets[i].step : 1) * GetPipValue();
            if(diff >= threshold)
            {
               bool added = false;
               int next = i + 1;
               if(i < m_maxBaskets - 1 && m_buy_baskets[i].step >= m_basketThreshold && !m_buy_baskets[next].active)
               {
                  double dynLot = m_buy_baskets[i].baseLot * MathPow(m_lotMult, m_buy_baskets[i].step);
                  dynLot = NormalizeLot(dynLot);
                  if(m_enableSafeMode)
                  {
                     double current_risk = GetBuyTotalPotentialLoss();
                     double proposed_risk = dynLot * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
                     double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                     if(current_risk + proposed_risk > m_buy_sequence.max_risk_amount)
                     {
                        continue;
                     }
                  }
                  if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[next]))
                  {
                     Log("Opened BUY trade triggered by new basket start.");
                     ResetTradeGroup(m_buy_baskets[next], m_buy_magics[next]);
                     m_buy_baskets[next].active = true;
                     m_buy_baskets[next].step = 1;
                     m_buy_baskets[next].baseLot = dynLot;
                     m_buy_baskets[next].last_trade_time = TimeCurrent();
                     m_buy_baskets[next].open_time = TimeCurrent();
                     if(m_enableSafeMode)
                     {
                        double atr = GetCustom35MinATR();
                        if(atr > 0)
                        {
                           m_buy_baskets[next].virtualSL = m_buy_baskets[next].entryPrice - atr * m_atrSlMultiplier;
                        }
                     }
                     m_state_changed = true;
                     added = true;
                  }
               }
               double vol = m_buy_baskets[i].baseLot * MathPow(m_lotMult, m_buy_baskets[i].step);
               vol = NormalizeLot(vol);
               if(m_enableSafeMode)
               {
                  double current_risk = GetBuyTotalPotentialLoss();
                  double proposed_risk = vol * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
                  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                  if(current_risk + proposed_risk > m_buy_sequence.max_risk_amount)
                  {
                     continue;
                  }
               }
               if(m_buy_baskets[i].step < m_maxSteps && OpenOrder(ORDER_TYPE_BUY, vol, m_buy_magics[i]))
               {
                  Log("Opened BUY trade triggered by martingale step.");
                  m_buy_baskets[i].step++;
                  m_buy_baskets[i].last_trade_time = TimeCurrent();
                  m_state_changed = true;
                  added = true;
               }
               if(added)
               {
                  SaveIfChanged();
                  return;
               }
            }
         }
      }
      if(m_trade_mode == -1 && (m_tradeDirection != TradeBuyOnly) && (m_enableHedge || !HasAnyBuyPos()))
      {
         for(int i = 0; i < m_maxBaskets; i++)
         {
            if(!m_sell_baskets[i].active || !HasPosForGroup(m_sell_baskets[i], POSITION_TYPE_SELL))
               continue;
            double current = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double diff = current - m_sell_baskets[i].entryPrice;
            double threshold = m_pips * (m_useExpandingGrid ? m_sell_baskets[i].step : 1) * GetPipValue();
            if(diff >= threshold)
            {
               bool added = false;
               int next = i + 1;
               if(i < m_maxBaskets - 1 && m_sell_baskets[i].step >= m_basketThreshold && !m_sell_baskets[next].active)
               {
                  double dynLot = m_sell_baskets[i].baseLot * MathPow(m_lotMult, m_sell_baskets[i].step);
                  dynLot = NormalizeLot(dynLot);
                  if(m_enableSafeMode)
                  {
                     double current_risk = GetSellTotalPotentialLoss();
                     double proposed_risk = dynLot * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
                     double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                     if(current_risk + proposed_risk > m_sell_sequence.max_risk_amount)
                     {
                        continue;
                     }
                  }
                  if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[next]))
                  {
                     Log("Opened SELL trade triggered by new basket start.");
                     ResetTradeGroup(m_sell_baskets[next], m_sell_magics[next]);
                     m_sell_baskets[next].active = true;
                     m_sell_baskets[next].step = 1;
                     m_sell_baskets[next].baseLot = dynLot;
                     m_sell_baskets[next].last_trade_time = TimeCurrent();
                     m_sell_baskets[next].open_time = TimeCurrent();
                     if(m_enableSafeMode)
                     {
                        double atr = GetCustom35MinATR();
                        if(atr > 0)
                        {
                           m_sell_baskets[next].virtualSL = m_sell_baskets[next].entryPrice + atr * m_atrSlMultiplier;
                        }
                     }
                     m_state_changed = true;
                     added = true;
                  }
               }
               double vol = m_sell_baskets[i].baseLot * MathPow(m_lotMult, m_sell_baskets[i].step);
               vol = NormalizeLot(vol);
               if(m_enableSafeMode)
               {
                  double current_risk = GetSellTotalPotentialLoss();
                  double proposed_risk = vol * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
                  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                  if(current_risk + proposed_risk > m_sell_sequence.max_risk_amount)
                  {
                     continue;
                  }
               }
               if(m_sell_baskets[i].step < m_maxSteps && OpenOrder(ORDER_TYPE_SELL, vol, m_sell_magics[i]))
               {
                  Log("Opened SELL trade triggered by martingale step.");
                  m_sell_baskets[i].step++;
                  m_sell_baskets[i].last_trade_time = TimeCurrent();
                  m_state_changed = true;
                  added = true;
               }
               if(added)
               {
                  SaveIfChanged();
                  return;
               }
            }
         }
      }
      if(m_timeToNewBasketDays > 0 && TimeCurrent() - m_last_trade_time >= m_timeToNewBasketDays * 86400)
      {
         int buy_count = GetOpenBuyCount();
         int sell_count = GetOpenSellCount();
         if(buy_count != sell_count)
         {
            ENUM_ORDER_TYPE preferred_type = (buy_count > sell_count) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(preferred_type == ORDER_TYPE_BUY && m_trade_mode == 1 && (m_tradeDirection != TradeSellOnly) && (m_enableHedge || !HasAnySellPos()))
            {
               int max_i = -1;
               for(int j = 0; j < m_maxBaskets; j++) if(m_buy_baskets[j].active) max_i = j;
               if(max_i >= 0 && max_i < m_maxBaskets - 1 && !m_buy_baskets[max_i + 1].active)
               {
                  double dynLot = (m_enableSafeMode) ? CalcLotSize(m_initialRiskPct, GetCustom35MinATR() * m_atrSlMultiplier / GetPipValue()) : m_initLot;
                  dynLot = NormalizeLot(dynLot);
                  if(m_enableSafeMode)
                  {
                     double current_risk = GetBuyTotalPotentialLoss();
                     double proposed_risk = dynLot * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
                     double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                     if(current_risk + proposed_risk > m_buy_sequence.max_risk_amount)
                     {
                        return;
                     }
                  }
                  int next = max_i + 1;
                  if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[next]))
                  {
                     Log("Opened BUY trade triggered by time-based new basket.");
                     ResetTradeGroup(m_buy_baskets[next], m_buy_magics[next]);
                     m_buy_baskets[next].active = true;
                     m_buy_baskets[next].step = 1;
                     m_buy_baskets[next].baseLot = dynLot;
                     m_buy_baskets[next].last_trade_time = TimeCurrent();
                     m_buy_baskets[next].open_time = TimeCurrent();
                     if(m_enableSafeMode)
                     {
                        double atr = GetCustom35MinATR();
                        if(atr > 0)
                        {
                           m_buy_baskets[next].virtualSL = m_buy_baskets[next].entryPrice - atr * m_atrSlMultiplier;
                        }
                     }
                     m_state_changed = true;
                     SaveIfChanged();
                     return;
                  }
               }
            }
            else if(preferred_type == ORDER_TYPE_SELL && m_trade_mode == -1 && (m_tradeDirection != TradeBuyOnly) && (m_enableHedge || !HasAnyBuyPos()))
            {
               int max_i = -1;
               for(int j = 0; j < m_maxBaskets; j++) if(m_sell_baskets[j].active) max_i = j;
               if(max_i >= 0 && max_i < m_maxBaskets - 1 && !m_sell_baskets[max_i + 1].active)
               {
                  double dynLot = (m_enableSafeMode) ? CalcLotSize(m_initialRiskPct, GetCustom35MinATR() * m_atrSlMultiplier / GetPipValue()) : m_initLot;
                  dynLot = NormalizeLot(dynLot);
                  if(m_enableSafeMode)
                  {
                     double current_risk = GetSellTotalPotentialLoss();
                     double proposed_risk = dynLot * (GetCustom35MinATR() * m_atrSlMultiplier) * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
                     double balance = AccountInfoDouble(ACCOUNT_BALANCE);
                     if(current_risk + proposed_risk > m_sell_sequence.max_risk_amount)
                     {
                        return;
                     }
                  }
                  int next = max_i + 1;
                  if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[next]))
                  {
                     Log("Opened SELL trade triggered by time-based new basket.");
                     ResetTradeGroup(m_sell_baskets[next], m_sell_magics[next]);
                     m_sell_baskets[next].active = true;
                     m_sell_baskets[next].step = 1;
                     m_sell_baskets[next].baseLot = dynLot;
                     m_sell_baskets[next].last_trade_time = TimeCurrent();
                     m_sell_baskets[next].open_time = TimeCurrent();
                     if(m_enableSafeMode)
                     {
                        double atr = GetCustom35MinATR();
                        if(atr > 0)
                        {
                           m_sell_baskets[next].virtualSL = m_sell_baskets[next].entryPrice + atr * m_atrSlMultiplier;
                        }
                     }
                     m_state_changed = true;
                     SaveIfChanged();
                     return;
                  }
               }
            }
         }
      }
      SaveIfChanged();
   }
};
// --- EA Instance and Functions ---
CBBMartingaleEA ea;
int OnInit()
{
     datetime ExpirationDate = D'2025.11.17 23:59:59';
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Please contact developer.");
      return(INIT_FAILED);
     }
   return ea.OnInit();
}
void OnDeinit(const int reason)
{
   ea.OnDeinit(reason);
}
void OnTick()
{
      datetime ExpirationDate = D'2025.11.17 23:59:59';
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Please contact developer.");
      return;
     }
   ea.OnTick();
}
//+------------------------------------------------------------------+