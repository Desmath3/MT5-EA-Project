//+------------------------------------------------------------------+
//| Ighodalo Gold Milker.mq5 |
//| Copyright 2025, Ighodalo V3 C |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#define PIP_SIZE (_Point * 10)
#property tester_file "News_Cache.csv"
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
// Dynamic TP Option
input bool UseDynamicTP = false;
input double DynamicTPFactor = 1.0;
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
input bool PartialCloseBeforeNews = false;
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
      ArrayResize(managed_magics, 0);
   }
};
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
   bool m_useDynamicTP;
   double m_dynamicTPFactor;
   int m_volPeriod;
   bool m_enableHedge;
   ENUM_TRADE_DIRECTION m_tradeDirection;
   // News Parameters
   bool m_enableNewsManagement;
   int m_newsCheckIntervalSeconds;
   int m_minsBefore;
   int m_minsAfter;
   bool m_partialCloseBeforeNews;
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
      double profit = 0;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatchesAny(pmagic)) continue;
         profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
      return profit;
   }
   int GetOpenBuyCount()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatchesAny(pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype == POSITION_TYPE_BUY) count++;
      }
      return count;
   }
   int GetOpenSellCount()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatchesAny(pmagic)) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype == POSITION_TYPE_SELL) count++;
      }
      return count;
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
            PrintFormat("Daily P/L drawdown reached (Loss: %.2f >= Limit: %.2f). Trading halted.", MathAbs(current_floating_profit), max_loss_amount);
            return;
         }
      }
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_globalMaxDD > 0 && m_globalStartEq > 0.0 && equity <= m_globalStartEq * (1.0 - m_globalMaxDD / 100.0))
      {
         CloseAllPositions();
         m_globalHalted = true;
         Print("Global equity drawdown reached. Trading halted permanently.");
      }
   }
   void CheckTargetProfit()
   {
      if(m_targetProfitPct <= 0)
         return;
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double target_amount = balance * (m_targetProfitPct / 100.0);
      double current_profit = GetEaFloatingProfit();
      if(current_profit > 0 && current_profit >= target_amount)
      {
         PrintFormat("Target profit of %.2f%% reached (Profit: %.2f >= Target: %.2f). Closing all positions.", m_targetProfitPct, current_profit, target_amount);
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
               Print("Failed to close position #", ticket, ": ", m_trade.ResultRetcodeDescription());
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
         Print("Some positions in ", EnumToString(posType), " group failed to close. Marked pending_close.");
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
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype != POSITION_TYPE_BUY) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         for(int j = 0; j < m_maxBaskets; j++)
         {
            if(pmagic == m_buy_magics[j])
               return true;
         }
      }
      return false;
   }
   bool HasAnySellPos()
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ptype != POSITION_TYPE_SELL) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         for(int j = 0; j < m_maxBaskets; j++)
         {
            if(pmagic == m_sell_magics[j])
               return true;
         }
      }
      return false;
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
      double pipValue = tickValue * (PIP_SIZE / tickSize);
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
      if(!IsMarketOpen())
      {
         Print("Market is closed. Cannot open order.");
         return false;
      }
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double reqMargin = volume * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
      if(freeMargin < reqMargin)
      {
         Print("Insufficient margin to open order.");
         return false;
      }
      double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints(m_slippage);
      if(m_trade.PositionOpen(_Symbol, orderType, volume, 0, 0, "Ighodalo Gold Milker"))
      {
         Print("Order opened: ", EnumToString(orderType), " volume: ", volume, " price: ", price, " magic:", magic);
         m_last_trade_time = TimeCurrent();
         m_state_changed = true;
         return true;
      }
      else
      {
         Print("Failed to open order: ", m_trade.ResultRetcode(), ", ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }
   double GetCustomVolMeasure()
     {
      int synthetic_bars_needed = m_volPeriod + 1;
      int m5_bars_needed = synthetic_bars_needed * 7;
      MqlRates m5_rates[];
      ArraySetAsSeries(m5_rates, true);
 
      if(CopyRates(_Symbol, PERIOD_M5, 0, m5_bars_needed, m5_rates) < m5_bars_needed)
        {
         Print("Not enough M5 history to calculate custom volatility.");
         return -1.0;
        }
 
      double sum_tr = 0;
      for(int i = 0; i < m_volPeriod; i++)
        {
         int start_idx = i * 7;
         int end_idx = start_idx + 6;
         int prev_start_idx = (i + 1) * 7;
         int prev_end_idx = prev_start_idx + 6;
    
         if(prev_end_idx >= ArraySize(m5_rates))
           {
            Print("Not enough M5 rates for previous close in custom calc.");
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
 
      return sum_tr / m_volPeriod;
     }
   void UpdateGroupState(TradeGroup &group, ENUM_POSITION_TYPE posType)
   {
      double totalVol = 0.0;
      double weightedSum = 0.0;
      double sum_swap = 0.0;
      double sum_comm = 0.0;
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
            sum_comm += PositionGetDouble(POSITION_COMMISSION);
         }
      }
      if(totalVol <= 0.0)
      {
         return;
      }
      double newAvgEntry = weightedSum / totalVol;
      if(MathAbs(newAvgEntry - group.entryPrice) > _Point || group.virtualTP == 0.0)
      {
         Print("Detected position change in ", EnumToString(posType), " group. Recalculating state.");
         group.entryPrice = newAvgEntry;
         group.totalVol = totalVol;
         int dir = (posType == POSITION_TYPE_BUY) ? 1 : -1;
         double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double pip_value = tick_value * (PIP_SIZE / tick_size);
         long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         double spread_pips = spread_points * _Point / PIP_SIZE;
         double total_cost = MathMax(0, -(sum_swap + sum_comm));
         double extra_pips = (total_cost / (totalVol * pip_value)) + spread_pips + 2.0 + 2.0;
         double tp_pips = m_tpPips;
         if(m_useDynamicTP)
           {
            double vol = GetCustomVolMeasure();
            if(vol > 0)
              {
               tp_pips = (vol / PIP_SIZE) * m_dynamicTPFactor;
              }
           }
         group.virtualTP = NormalizeDouble(newAvgEntry + dir * (tp_pips + extra_pips) * PIP_SIZE, _Digits);
         if(group.initial_entry == 0.0)
         {
            group.initial_entry = newAvgEntry;
         }
         Print(EnumToString(posType), " group updated: New average entry = ", newAvgEntry, ", New TP = ", group.virtualTP, " (extra pips: ", extra_pips, ")");
         m_state_changed = true;
      }
   }
   void ManageBuyBasket(TradeGroup &group)
   {
      if(group.pending_close && IsMarketOpen())
      {
         Print("Retrying pending close for buy group magic ", group.original_magic);
         CloseGroup(group, POSITION_TYPE_BUY);
      }
      if(!HasPosForGroup(group, POSITION_TYPE_BUY))
      {
         if(group.active && (TimeCurrent() - group.last_trade_time > 5))
         {
            long base = group.original_magic;
            ResetTradeGroup(group, base);
            Print("Buy group was active but no positions found after grace period. Resetting.");
         }
         return;
      }
      UpdateGroupState(group, POSITION_TYPE_BUY);
      if(!IsMarketOpen())
      {
         return;
      }
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(group.virtualTP != 0.0 && currentPrice >= group.virtualTP)
      {
         Print("Virtual TP hit for BUY group at ", group.virtualTP, ". Closing group.");
         CloseGroup(group, POSITION_TYPE_BUY);
         return;
      }
      if(group.virtualSL != 0.0 && currentPrice <= group.virtualSL)
      {
         Print("Virtual SL hit for BUY group at ", group.virtualSL, ". Closing group.");
         CloseGroup(group, POSITION_TYPE_BUY);
         return;
      }
   }
   void ManageSellBasket(TradeGroup &group)
   {
      if(group.pending_close && IsMarketOpen())
      {
         Print("Retrying pending close for sell group magic ", group.original_magic);
         CloseGroup(group, POSITION_TYPE_SELL);
      }
      if(!HasPosForGroup(group, POSITION_TYPE_SELL))
      {
         if(group.active && (TimeCurrent() - group.last_trade_time > 5))
         {
            long base = group.original_magic;
            ResetTradeGroup(group, base);
            Print("Sell group was active but no positions found after grace period. Resetting.");
         }
         return;
      }
      UpdateGroupState(group, POSITION_TYPE_SELL);
      if(!IsMarketOpen())
      {
         return;
      }
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(group.virtualTP != 0.0 && currentPrice <= group.virtualTP)
      {
         Print("Virtual TP hit for SELL group at ", group.virtualTP, ". Closing group.");
         CloseGroup(group, POSITION_TYPE_SELL);
         return;
      }
      if(group.virtualSL != 0.0 && currentPrice >= group.virtualSL)
      {
         Print("Virtual SL hit for SELL group at ", group.virtualSL, ". Closing group.");
         CloseGroup(group, POSITION_TYPE_SELL);
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
      Print("Merged ", EnumToString(posType), " basket.");
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
         for(int k = 0; k < m_sell_baskets[i].num_managed && k < max_saved_magics; k++)
         {
            GlobalVariableSet(prefix + "magic" + IntegerToString(k), (double)m_sell_baskets[i].managed_magics[k]);
         }
      }
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_LastTradeTime", (double)m_last_trade_time);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_TradeMode", (double)m_trade_mode);
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
      Print("--- NEWS [TESTER MODE]: Initializing news system for backtest. ---");
      ArrayFree(m_cached_news);
      int file_handle = FileOpen(m_news_cache_filename, FILE_READ|FILE_CSV|FILE_COMMON, ',');
      if(file_handle == INVALID_HANDLE)
        {
         Print("--- NEWS [TESTER MODE] ERROR: Could not find news file '", m_news_cache_filename, "'. Please run the EA on a live chart for 1 minute to create it. ---");
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
      Print("--- NEWS [TESTER MODE]: Successfully loaded ", count, " news events into memory for this test run. ---");
     }
   void DownloadAndCacheNews()
     {
      Print("--- NEWS [LIVE MODE]: Initializing. Attempting to download and cache news history for tester use... ---");
      int file_handle = FileOpen(m_news_cache_filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(file_handle == INVALID_HANDLE)
        {
         Print("--- NEWS [LIVE MODE] ERROR: Could not create the cache file. Check terminal permissions. ---");
         return;
        }
      Print("--- NEWS [LIVE MODE]: Cache file '", m_news_cache_filename, "' opened for writing. ---");
      FileWrite(file_handle, "time_as_string", "country", "importance");
      datetime from = TimeCurrent() - (86400 * 90);
      datetime to = TimeCurrent() + (86400 * 90); // One year into the future
      Print("--- NEWS [LIVE MODE]: Requesting news history from server. This may take a moment... ---");
      MqlCalendarValue values[];
      int total_saved = 0;
      if(CalendarValueHistory(values, from, to))
        {
         Print("--- NEWS [LIVE MODE]: Received ", ArraySize(values), " total events from server. Filtering and saving... ---");
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
      else
        {
         Print("--- NEWS [LIVE MODE] ERROR: Call to CalendarValueHistory failed. Terminal may not be connected or news is disabled in settings. ---");
        }
      FileClose(file_handle);
      Print("--- NEWS [LIVE MODE]: Saved ", total_saved, " events. News cache file has been created successfully. You can now use the Strategy Tester. ---");
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
      if(next_event_time > 0)
        {
         Print("--- NEWS: Next high-impact news for ", _Symbol, " found at: ", TimeToString(next_event_time), ". ---");
        }
      else
        {
         Print("--- NEWS: No upcoming high-impact news found for ", _Symbol, ". ---");
        }
      return next_event_time;
     }
   void ManagePositionsBeforeNews()
     {
      Print("--- NEWS: Starting position management before high-impact news at ", TimeToString(m_nextNewsTime), ". ---");
      double atr = GetCustomVolMeasure();
      if(atr <= 0)
        {
         Print("--- NEWS: Failed to get volatility. Skipping management. ---");
         return;
        }
      int partial = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         long pmagic = PositionGetInteger(POSITION_MAGIC);
         if(!MagicMatchesAny(pmagic)) continue;
         double profit = PositionGetDouble(POSITION_PROFIT);
         Print("--- NEWS: Checking position #", ticket, ": Profit=", DoubleToString(profit, 2), " ---");
         if(profit >= 0 && m_partialCloseBeforeNews)
           {
            double volume = PositionGetDouble(POSITION_VOLUME);
            double close_vol = volume * 0.5;
            double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            close_vol = vol_step * MathRound(close_vol / vol_step);
            if(close_vol > 0 && close_vol < volume)
              {
               if(m_trade.PositionClosePartial(ticket, close_vol))
                 {
                  Print("--- NEWS: Partial closed #", ticket, ": ", DoubleToString(close_vol, 2), " lots. ---");
                  partial++;
                 }
               else
                  Print("--- NEWS: Failed partial close #", ticket, ": ", GetLastError(), " ---");
              }
           }
        }
      Print("--- NEWS: Management complete. Partial: ", partial, " ---");
     }
   void CheckNewsEvents()
     {
      if(!m_enableNewsManagement) return;
      datetime now_gmt = TimeGMT();
      if(m_pendingSleep && now_gmt >= m_sleepStart)
        {
         m_pendingSleep = false;
         m_inSleepMode = true;
         Print("--- NEWS: Entering sleep mode. ---");
        }
      if(m_inSleepMode && now_gmt >= m_sleepEndTime)
        {
         m_inSleepMode = false;
         Print("--- NEWS: Exiting sleep mode. ---");
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
      m_useDynamicTP = UseDynamicTP;
      m_dynamicTPFactor = DynamicTPFactor;
      m_volPeriod = 20;
      m_enableHedge = EnableHedge;
      m_tradeDirection = TradeDirection;
      m_enableNewsManagement = EnableNewsManagement;
      m_newsCheckIntervalSeconds = NewsCheckIntervalSeconds;
      m_minsBefore = MinsBefore;
      m_minsAfter = MinsAfter;
      m_partialCloseBeforeNews = PartialCloseBeforeNews;
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
      m_trade.SetExpertMagicNumber((ulong)m_magic);
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
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      if(dt.day != m_day || m_day == 0)
      {
         if(m_day == 0) Print("EA initializing state for existing trades...");
         m_day = dt.day;
         m_startEq = AccountInfoDouble(ACCOUNT_BALANCE);
         m_halted = false;
         if(m_day != 0) Print("Daily reset performed.");
         for(int i = 0; i < m_maxBaskets; i++)
         {
            if(!HasPosForGroup(m_buy_baskets[i], POSITION_TYPE_BUY))
            {
               m_buy_baskets[i].active = false;
               m_state_changed = true;
            }
            else
            {
               Print("Buy basket ", i, " found. Re-activating for management.");
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
               Print("Sell basket ", i, " found. Re-activating for management.");
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
      if(m_inSleepMode)
         {
          CheckBuyMerges();
          CheckSellMerges();
          SaveIfChanged();
          return;
         }
      bool is_new_bar = false;
      datetime time[1];
      if(CopyTime(_Symbol, PERIOD_M6, 0, 1, time) > 0 && time[0] != m_last_bar_time)
      {
         m_last_bar_time = time[0];
         is_new_bar = true;
      }
      if(is_new_bar)
      {
         if(CopyBuffer(m_ind, 1, 0, 3, m_upper) < 3 || CopyBuffer(m_ind, 0, 0, 3, m_middle) < 3 || CopyBuffer(m_ind, 2, 0, 3, m_lower) < 3)
         {
            Print("Failed to copy indicator buffers");
            return;
         }
         if(CopyClose(_Symbol, PERIOD_M6, 0, 3, m_close) < 3)
         {
            Print("Failed to copy close prices");
            return;
         }
         if(m_close[1] > m_upper[1])
         {
            if(m_trade_mode != 1)
            {
               Print("Bar closed above upper level. Switching to BUYS ONLY mode.");
               m_trade_mode = 1;
               m_state_changed = true;
            }
         }
         else if(m_close[1] < m_lower[1])
         {
            if(m_trade_mode != -1)
            {
               Print("Bar closed below lower level. Switching to SELLS ONLY mode.");
               m_trade_mode = -1;
               m_state_changed = true;
            }
         }
         double dynLot = (m_riskPct > 0.0) ? CalcLotSize(m_riskPct, m_tpPips) : m_initLot;
         dynLot = NormalizeLot(dynLot);
         // --- SELL ENTRY LOGIC ---
         if(m_trade_mode == -1 && !AnySellBasketActive() && !HasAnySellPos() && (m_tradeDirection != TradeBuyOnly) && (m_enableHedge || !HasAnyBuyPos()))
         {
            if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[0]))
            {
               ResetTradeGroup(m_sell_baskets[0], m_sell_magics[0]);
               m_sell_baskets[0].active = true;
               m_sell_baskets[0].step = 1;
               m_sell_baskets[0].baseLot = dynLot;
               m_sell_baskets[0].last_trade_time = TimeCurrent();
               m_state_changed = true;
               Print("SELL signal: Current candle closed below lower level");
               SaveIfChanged();
               return;
            }
         }
         // --- BUY ENTRY LOGIC ---
         if(m_trade_mode == 1 && !AnyBuyBasketActive() && !HasAnyBuyPos() && (m_tradeDirection != TradeSellOnly) && (m_enableHedge || !HasAnySellPos()))
         {
            if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[0]))
            {
               ResetTradeGroup(m_buy_baskets[0], m_buy_magics[0]);
               m_buy_baskets[0].active = true;
               m_buy_baskets[0].step = 1;
               m_buy_baskets[0].baseLot = dynLot;
               m_buy_baskets[0].last_trade_time = TimeCurrent();
               m_state_changed = true;
               Print("BUY signal: Current candle closed above upper level");
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
            double threshold = m_pips * (m_useExpandingGrid ? m_buy_baskets[i].step : 1) * PIP_SIZE;
            if(diff >= threshold)
            {
               bool added = false;
               int next = i + 1;
               if(i < m_maxBaskets - 1 && m_buy_baskets[i].step >= m_basketThreshold && !m_buy_baskets[next].active)
               {
                  double dynLot = (m_riskPct > 0.0) ? CalcLotSize(m_riskPct, m_tpPips) : m_initLot;
                  dynLot = NormalizeLot(dynLot);
                  if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[next]))
                  {
                     ResetTradeGroup(m_buy_baskets[next], m_buy_magics[next]);
                     m_buy_baskets[next].active = true;
                     m_buy_baskets[next].step = 1;
                     m_buy_baskets[next].baseLot = dynLot;
                     m_buy_baskets[next].last_trade_time = TimeCurrent();
                     m_state_changed = true;
                     Print("Started new buy basket ", next);
                     added = true;
                  }
               }
               if(m_buy_baskets[i].step < m_maxSteps)
               {
                  double vol = NormalizeLot(m_buy_baskets[i].baseLot * MathPow(m_lotMult, m_buy_baskets[i].step));
                  if(OpenOrder(ORDER_TYPE_BUY, vol, m_buy_magics[i]))
                  {
                     m_buy_baskets[i].step++;
                     m_buy_baskets[i].last_trade_time = TimeCurrent();
                     m_state_changed = true;
                     Print("BUY martingale step ", m_buy_baskets[i].step, " triggered for basket ", i, " at threshold ", threshold / PIP_SIZE, " pips");
                     added = true;
                  }
               }
               else
               {
                  Print("Max martingale steps reached for buy basket ", i, " (step=", m_buy_baskets[i].step, ").");
               }
               if(!added)
               {
                  Print("Failed to add martingale or new basket for buy basket ", i);
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
            double threshold = m_pips * (m_useExpandingGrid ? m_sell_baskets[i].step : 1) * PIP_SIZE;
            if(diff >= threshold)
            {
               bool added = false;
               int next = i + 1;
               if(i < m_maxBaskets - 1 && m_sell_baskets[i].step >= m_basketThreshold && !m_sell_baskets[next].active)
               {
                  double dynLot = (m_riskPct > 0.0) ? CalcLotSize(m_riskPct, m_tpPips) : m_initLot;
                  dynLot = NormalizeLot(dynLot);
                  if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[next]))
                  {
                     ResetTradeGroup(m_sell_baskets[next], m_sell_magics[next]);
                     m_sell_baskets[next].active = true;
                     m_sell_baskets[next].step = 1;
                     m_sell_baskets[next].baseLot = dynLot;
                     m_sell_baskets[next].last_trade_time = TimeCurrent();
                     m_state_changed = true;
                     Print("Started new sell basket ", next);
                     added = true;
                  }
               }
               if(m_sell_baskets[i].step < m_maxSteps)
               {
                  double vol = NormalizeLot(m_sell_baskets[i].baseLot * MathPow(m_lotMult, m_sell_baskets[i].step));
                  if(OpenOrder(ORDER_TYPE_SELL, vol, m_sell_magics[i]))
                  {
                     m_sell_baskets[i].step++;
                     m_sell_baskets[i].last_trade_time = TimeCurrent();
                     m_state_changed = true;
                     Print("SELL martingale step ", m_sell_baskets[i].step, " triggered for basket ", i, " at threshold ", threshold / PIP_SIZE, " pips");
                     added = true;
                  }
               }
               else
               {
                  Print("Max martingale steps reached for sell basket ", i, " (step=", m_sell_baskets[i].step, ").");
               }
               if(!added)
               {
                  Print("Failed to add martingale or new basket for sell basket ", i);
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
                  double dynLot = (m_riskPct > 0.0) ? CalcLotSize(m_riskPct, m_tpPips) : m_initLot;
                  dynLot = NormalizeLot(dynLot);
                  int next = max_i + 1;
                  if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[next]))
                  {
                     ResetTradeGroup(m_buy_baskets[next], m_buy_magics[next]);
                     m_buy_baskets[next].active = true;
                     m_buy_baskets[next].step = 1;
                     m_buy_baskets[next].baseLot = dynLot;
                     m_buy_baskets[next].last_trade_time = TimeCurrent();
                     m_state_changed = true;
                     Print("Time-based trigger: Started new buy basket ", next);
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
                  double dynLot = (m_riskPct > 0.0) ? CalcLotSize(m_riskPct, m_tpPips) : m_initLot;
                  dynLot = NormalizeLot(dynLot);
                  int next = max_i + 1;
                  if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[next]))
                  {
                     ResetTradeGroup(m_sell_baskets[next], m_sell_magics[next]);
                     m_sell_baskets[next].active = true;
                     m_sell_baskets[next].step = 1;
                     m_sell_baskets[next].baseLot = dynLot;
                     m_sell_baskets[next].last_trade_time = TimeCurrent();
                     m_state_changed = true;
                     Print("Time-based trigger: Started new sell basket ", next);
                     SaveIfChanged();
                     return;
                  }
               }
            }
         }
      }
      CheckBuyMerges();
      CheckSellMerges();
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