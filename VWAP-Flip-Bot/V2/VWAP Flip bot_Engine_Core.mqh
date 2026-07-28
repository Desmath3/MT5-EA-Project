//file_name: VWAP Flip bot_Engine_Core.mqh
//+------------------------------------------------------------------+
//| VWAP Flip bot – Engine (DCA + Scale-in + Risk)  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "VWAP Flip bot_NewsFilter.mqh"

//------------------------------------------------------------------
// EnumToString helpers (fix undeclared identifier errors)
//------------------------------------------------------------------
string EnumToString(ENUM_POSITION_TYPE typ)
{
   if(typ == POSITION_TYPE_BUY)  return "BUY";
   if(typ == POSITION_TYPE_SELL) return "SELL";
   return "UNKNOWN";
}
string EnumToString(ENUM_ORDER_TYPE typ)
{
   if(typ == ORDER_TYPE_BUY)        return "ORDER_TYPE_BUY";
   if(typ == ORDER_TYPE_SELL)       return "ORDER_TYPE_SELL";
   if(typ == ORDER_TYPE_BUY_LIMIT)  return "ORDER_TYPE_BUY_LIMIT";
   if(typ == ORDER_TYPE_SELL_LIMIT) return "ORDER_TYPE_SELL_LIMIT";
   return "UNKNOWN";
}

// Simplified TradeGroup struct for single group per direction
struct PosInfo
{
   ulong  ticket;
   double vol;
   double entry;
};

struct TradeGroup
{
   bool     active;
   double   entryPrice;
   bool     partialDone;
   double   totalVol;
   double   virtualSL;
   double   virtualTP;
   double   initial_entry;
   datetime open_time;
   datetime expiry_time;
   double   initial_sl_distance;

   TradeGroup()
   {
      active              = false;
      entryPrice          = 0.0;
      partialDone         = false;
      totalVol            = 0.0;
      virtualSL           = 0.0;
      virtualTP           = 0.0;
      initial_entry       = 0.0;
      open_time           = 0;
      expiry_time         = 0;
      initial_sl_distance = 0.0;
   }

   TradeGroup(const TradeGroup &other)
   {
      active              = other.active;
      entryPrice          = other.entryPrice;
      partialDone         = other.partialDone;
      totalVol            = other.totalVol;
      virtualSL           = other.virtualSL;
      virtualTP           = other.virtualTP;
      initial_entry       = other.initial_entry;
      open_time           = other.open_time;
      expiry_time         = other.expiry_time;
      initial_sl_distance = other.initial_sl_distance;
   }
};

//+------------------------------------------------------------------+
//| Main EA Class                                                    |
//+------------------------------------------------------------------+
class CBBMartingaleEA
{
private:
   struct PositionCache
   {
      ulong              ticket;
      long               magic;
      ENUM_POSITION_TYPE type;
      double             volume;
      double             profit;
      double             swap;
      double             open_price;
   };

   PositionCache pos_cache[];

   // Helper: are we in optimization mode?
   bool IsOptimizationMode()
   {
      return (MQLInfoInteger(MQL_OPTIMIZATION) == 1);
   }

   // IsNewBar helpers
   datetime last_bar_time_period;

   // Debounce for state saving
   datetime m_lastStateSave;

   // Parameters & State
   bool                 m_dailyReset;
   double               m_maxDD;
   double               m_profitTargetRR;
   long                 m_magic;
   double               m_globalMaxDD;
   int                  m_slippage;
   bool                 m_enableHedge;
   ENUM_TRADE_DIRECTION m_tradeDirection;

   // State
   TradeGroup m_buy_group;
   TradeGroup m_sell_group;
   long       m_buy_magic;
   long       m_sell_magic;
   int        m_day;        // NY "trading day" key
   double     m_startEq;
   bool       m_halted;
   bool       m_globalHalted;
   datetime   m_last_trade_time;

   // Global start equity
   double m_globalStartEq;

   // Indicator caching
   datetime m_last_bar_time;
   bool     m_state_changed;

   // Risk Management params
   double m_maxTotalRiskPct;
   int    m_atrPeriod;
   double m_atrSlMultiplier;
   double m_maxMarginUsagePct;

   // Targets & dynamic risk
   double m_startBalanceInput;
   double m_targetBalance;
   bool   m_enableTargetBalance;
   bool   m_enableDynamicRisk;
   bool   m_targetBalanceHit;

   // Profit keeper / BE
   double   m_sequenceBE_StartR;
   double   m_breakevenOffsetR;
   bool     m_enablePeakDrawdownExit;
   double   m_peakDrawdownStartR;
   double   m_peakProfitDrawdownPercent;
   int      m_tradeExpiryCandles;

   // Partial TP
   bool   m_enablePartialTP;
   double m_partialTP_RR;
   double m_partialTP_Percent;
   double m_buy_peakR;
   double m_sell_peakR;

   // Cooldowns
   datetime m_buyCooldownEndTime;
   datetime m_sellCooldownEndTime;

   // Sessions
   bool m_tradeNewYork;
   bool m_tradeLondon;
   bool m_tradeTokyo;
   bool m_tradeSydney;
   bool m_enableDailyClose;
   int  m_lastDailyCloseTradingKey;

   CTrade m_trade;

   // Cache / perf
   double   m_cachedATR;
   datetime m_lastATRUpdate;
   int      m_cachedBuyCount;
   int      m_cachedSellCount;
   double   m_cachedBuyProfit;
   double   m_cachedSellProfit;
   datetime m_lastPositionUpdate;
   bool     m_positionsDirty;

   // ATR source buffer
   MqlRates m_m5rates_buffer[];

   // DCA parameters
   int    m_dcaParts;
   int    m_pendingExpiryCandles;
   double m_initialDCAOffsetATR;
   double m_lotSizeMultiple;
   double m_dcaSLPercent;

   // Scale-in parameters
   bool   m_enableScaleIn;
   double m_scaleInMinATRFracToSL;
   double m_scaleInAddATRMultiplier;
   double m_scaleInMaxExposure; // numeric 0,1,2
   int    m_scaleInMaxTopUps;
   int    m_buyScaleInCount;
   int    m_sellScaleInCount;
   double m_initialATR_buy;
   double m_initialEntry_buy;
   double m_lastEntry_buy;
   double m_initialATR_sell;
   double m_initialEntry_sell;
   double m_lastEntry_sell;

   // Attempt debounce
   datetime m_last_buy_attempt;
   datetime m_last_sell_attempt;

   // News filter / execution freeze
   CNewsFilter m_newsFilter;
   bool        m_slOnlyMode;

   //----------------------------------------------------------------
   // NEW: Compute current risk base based on percentage (dynamic or fixed)
   //----------------------------------------------------------------
   double GetCurrentRiskBase()
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double pct     = m_maxTotalRiskPct;

      if(m_enableDynamicRisk)
      {
         double B0 = m_startBalanceInput;
         if(balance < B0)
            pct = 0.5;
         else if(balance < B0 * 1.02)
            pct = 1.0;
         else
            pct = 1.5;
      }

      return balance * (pct / 100.0);
   }

   //----------------------------------------------------------------
   // NEW: Margin estimation helpers (for grid-level cap + brokers that
   //      do NOT reserve pending margin inside ACCOUNT_MARGIN)
   //----------------------------------------------------------------
   bool CalcOrderMargin(ENUM_ORDER_TYPE dir, const string sym, double vol, double price, double &outMargin)
   {
      outMargin = 0.0;
      if(vol <= 0.0 || price <= 0.0) return false;
      return OrderCalcMargin(dir, sym, vol, price, outMargin);
   }

   double EstimateMarginForAllOpenPositions()
   {
      double total = 0.0;
      int    n     = PositionsTotal();

      for(int i = 0; i < n; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         string sym = PositionGetString(POSITION_SYMBOL);
         if(sym == "") continue;

         double vol = PositionGetDouble(POSITION_VOLUME);
         if(vol <= 0.0) continue;

         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         ENUM_ORDER_TYPE    dir   = (ptype == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

         MqlTick tick;
         if(!SymbolInfoTick(sym, tick)) continue;

         double price = (dir == ORDER_TYPE_BUY ? tick.ask : tick.bid);
         if(price <= 0.0) continue;

         double m = 0.0;
         if(CalcOrderMargin(dir, sym, vol, price, m))
            total += m;
      }
      return total;
   }

   double EstimateMarginForAllPendingOrders()
   {
      double total = 0.0;
      int    n     = OrdersTotal();

      for(int i = 0; i < n; i++)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(!OrderSelect(ticket)) continue;

         string sym = OrderGetString(ORDER_SYMBOL);
         if(sym == "") continue;

         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         bool isPending = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_SELL_LIMIT ||
                           ot == ORDER_TYPE_BUY_STOP   || ot == ORDER_TYPE_SELL_STOP  ||
                           ot == ORDER_TYPE_BUY_STOP_LIMIT || ot == ORDER_TYPE_SELL_STOP_LIMIT);

         if(!isPending) continue;

         double vol = OrderGetDouble(ORDER_VOLUME_CURRENT);
         if(vol <= 0.0) continue;

         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         if(price <= 0.0) continue;

         ENUM_ORDER_TYPE dir = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_STOP_LIMIT)
                               ? ORDER_TYPE_BUY
                               : ORDER_TYPE_SELL;

         double m = 0.0;
         if(CalcOrderMargin(dir, sym, vol, price, m))
            total += m;
      }
      return total;
   }

   // Returns an "effective used margin" for cap calculations:
   // - If broker already reserves pending margin in ACCOUNT_MARGIN, we use ACCOUNT_MARGIN.
   // - If not, we add estimated pending margin to avoid grid overflow.
   double GetEffectiveUsedMarginForCap()
   {
      double used = AccountInfoDouble(ACCOUNT_MARGIN);

      // Estimate totals (positions + pending) and compare to used.
      double posEst = EstimateMarginForAllOpenPositions();
      double penEst = EstimateMarginForAllPendingOrders();

      double expected = posEst + penEst;

      double base = MathMax(used, expected);
      double tol  = MathMax(10.0, 0.01 * base); // currency tolerance

      bool includesPending = (MathAbs(used - expected) <= tol);

      if(includesPending)
         return used;

      // Broker likely not reserving pending margin inside ACCOUNT_MARGIN.
      return used + penEst;
   }

   double GetRemainingMarginBudgetForCap()
   {
      if(m_maxMarginUsagePct <= 0.0)
         return DBL_MAX;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return 0.0;

      double capMargin = equity * (m_maxMarginUsagePct / 100.0);
      double usedEff   = GetEffectiveUsedMarginForCap();

      double remaining = capMargin - usedEff;
      if(remaining < 0.0) remaining = 0.0;
      return remaining;
   }

   //----------------------------------------------------------------
   // Max Volume for Margin Cap (pre-adjusts volume per trade)
   // UPDATED: supports a grid-level remaining margin budget
   //----------------------------------------------------------------
   double GetMaxVolumeForMarginCap(ENUM_ORDER_TYPE direction,
                                   double          price,
                                   string          side,
                                   string          context,
                                   double          remainingBudget = -1.0)
   {
      if(m_maxMarginUsagePct <= 0.0)
         return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      double maxAddMarg = 0.0;

      if(remainingBudget >= 0.0)
      {
         maxAddMarg = remainingBudget;
      }
      else
      {
         maxAddMarg = GetRemainingMarginBudgetForCap();
      }

      if(maxAddMarg <= 0.0)
         return 0.0;

      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0.0) lotStep = 0.01;

      double low  = minLot;
      double high = maxLot;

      // Bisection
      for(int iter = 0; iter < 24; iter++)
      {
         double mid = (low + high) / 2.0;

         // normalize mid to step (floor) to keep OrderCalcMargin stable
         mid = NormalizeLot(mid);
         if(mid < minLot)
         {
            high = (low + high) / 2.0;
            continue;
         }

         double addMargin = 0.0;
         if(CalcOrderMargin(direction, _Symbol, mid, price, addMargin))
         {
            if(addMargin <= maxAddMarg)
               low = mid;
            else
               high = mid;
         }
         else
         {
            high = mid;
         }
      }

      double maxVol = NormalizeLot(low);
      if(maxVol < minLot)
         return 0.0;

      return maxVol;
   }

   //----------------------------------------------------------------
   // Logging helpers (disabled in optimization)
   //----------------------------------------------------------------
   void Log(string message)
   {
      if(IsOptimizationMode())
         return;

      Print(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + ": " + message);
   }

   void LogTradeEvent(string side,
                      string action,
                      string reason,
                      double price  = 0.0,
                      double volume = 0.0,
                      double profit = 0.0,
                      double rValue = 0.0)
   {
      string msg = StringFormat(
         "TRADE_EVENT | Side=%s | Action=%s | Reason=%s | Price=%.5f | Volume=%.2f | Profit=%.2f | R=%.2f",
         side, action, reason, price, volume, profit, rValue
      );
      Log(msg);
   }

   void LogMarginVolumeReduced(string side,
                               double proposedVol,
                               double actualVol,
                               double price,
                               string context)
   {
      string reason = StringFormat(
         "Volume reduced from %.2f to %.2f due to margin cap (%.2f%%)",
         proposedVol, actualVol, m_maxMarginUsagePct
      );
      LogTradeEvent(side,
                    "MARGIN_VOLUME_REDUCED",
                    reason,
                    price,
                    actualVol,
                    0.0,
                    0.0);
   }

   //----------------------------------------------------------------
   int GetPendingCount(long magic, ENUM_ORDER_TYPE ord_type)
   {
      int count = 0;
      int total = OrdersTotal();

      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) != magic) continue;
         if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != ord_type) continue;
         count++;
      }
      return count;
   }

   void UpdateCachedTradeStatesOptimized()
   {
      int total        = PositionsTotal();
      int cached_total = 0;

      ArrayResize(pos_cache, total);

      m_cachedBuyCount   = 0;
      m_cachedSellCount  = 0;
      m_cachedBuyProfit  = 0.0;
      m_cachedSellProfit = 0.0;

      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic != m_buy_magic && magic != m_sell_magic) continue;

         pos_cache[cached_total].ticket     = ticket;
         pos_cache[cached_total].magic      = magic;
         pos_cache[cached_total].type       = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         pos_cache[cached_total].volume     = PositionGetDouble(POSITION_VOLUME);
         pos_cache[cached_total].profit     = PositionGetDouble(POSITION_PROFIT);
         pos_cache[cached_total].swap       = PositionGetDouble(POSITION_SWAP);
         pos_cache[cached_total].open_price = PositionGetDouble(POSITION_PRICE_OPEN);

         // Include commission and swaps in cached profit for BE / scale-in SL
         double commission = PositionGetDouble(POSITION_COMMISSION);
         double net_profit = pos_cache[cached_total].profit
                             + pos_cache[cached_total].swap
                             + commission;

         if(pos_cache[cached_total].type == POSITION_TYPE_BUY)
         {
            m_cachedBuyCount++;
            m_cachedBuyProfit += net_profit;
         }
         else if(pos_cache[cached_total].type == POSITION_TYPE_SELL)
         {
            m_cachedSellCount++;
            m_cachedSellProfit += net_profit;
         }

         cached_total++;
      }

      ArrayResize(pos_cache, cached_total);
      m_lastPositionUpdate = TimeCurrent();
      m_positionsDirty     = false;
   }

   double GetPipValue()
   {
      if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      {
         int    mod        = _Digits % 2;
         double multiplier = (mod == 0) ? 10 : 100; // Even digits (*10), odd (*100)
         return _Point * multiplier;
      }

      if(_Digits == 3 || _Digits == 5) return _Point * 10;
      if(_Digits == 2 || _Digits == 4) return _Point;
      return _Point;
   }

   // ----------------------------------------------------------------
   // Custom 35-minute ATR (existing logic)
   // ----------------------------------------------------------------
   double GetCustom35MinATR()
   {
      int synthetic_bars_needed = m_atrPeriod + 1;
      int m5_bars_needed        = synthetic_bars_needed * 7;

      ArraySetAsSeries(m_m5rates_buffer, true);

      if(CopyRates(_Symbol, PERIOD_M5, 0, m5_bars_needed, m_m5rates_buffer) < m5_bars_needed)
         return -1.0;

      double sum_tr = 0.0;

      for(int i = 0; i < m_atrPeriod; i++)
      {
         int start_idx      = i * 7;
         int end_idx        = start_idx + 6;
         int prev_start_idx = (i + 1) * 7;
         int prev_end_idx   = prev_start_idx + 6;

         if(prev_end_idx >= ArraySize(m_m5rates_buffer))
            return -1.0;

         double high = 0.0;
         double low  = 1e10;

         for(int j = start_idx; j <= end_idx; j++)
         {
            high = MathMax(high, m_m5rates_buffer[j].high);
            low  = MathMin(low,  m_m5rates_buffer[j].low);
         }

         double prev_close = m_m5rates_buffer[prev_end_idx].close;
         double tr         = MathMax(high, prev_close) - MathMin(low, prev_close);
         sum_tr += tr;
      }

      return sum_tr / m_atrPeriod;
   }

   double GetCachedATR()
   {
      datetime currentTime = TimeCurrent();
      if((currentTime - m_lastATRUpdate) < 60 && m_cachedATR > 0)
         return m_cachedATR;

      m_cachedATR      = GetCustom35MinATR();
      m_lastATRUpdate  = currentTime;
      return m_cachedATR;
   }

   void ResetTradeGroup(TradeGroup &group)
   {
      group.active              = false;
      group.entryPrice          = 0.0;
      group.partialDone         = false;
      group.totalVol            = 0.0;
      group.virtualSL           = 0.0;
      group.virtualTP           = 0.0;
      group.initial_entry       = 0.0;
      group.open_time           = 0;
      group.expiry_time         = 0;
      group.initial_sl_distance = 0.0;

      m_state_changed  = true;
      m_positionsDirty = true;
   }

   bool MagicMatches(long magic, bool isBuy)
   {
      return magic == (isBuy ? m_buy_magic : m_sell_magic);
   }

   bool IsMarketOpen()
   {
      datetime now_gmt = TimeGMT();
      if(now_gmt == 0) return false;

      MqlDateTime ny;
      GetNewYorkTime(now_gmt, ny);

      int minutesNY = ny.hour * 60 + ny.min;
      ENUM_DAY_OF_WEEK nyDay = (ENUM_DAY_OF_WEEK)ny.day_of_week;

      // Hard NY market-close guards to prevent entries during FX close windows.
      if(nyDay == SATURDAY) return false;
      if(nyDay == SUNDAY && minutesNY < 17 * 60) return false;
      if(nyDay == FRIDAY && minutesNY >= 17 * 60) return false;
      if(minutesNY >= (17 * 60 - 1) && minutesNY < (17 * 60 + 5)) return false;

      datetime server_time = TimeCurrent();
      if(server_time == 0) return false;

      MqlDateTime srv;
      TimeToStruct(server_time, srv);
      ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)srv.day_of_week;

      datetime midnight      = server_time - (server_time % 86400);
      uint     session_index = 0;
      datetime from, to;

      while(SymbolInfoSessionTrade(_Symbol, day, session_index, from, to))
      {
         if(server_time >= midnight + from && server_time < midnight + to)
            return true;
         session_index++;
      }

      return false;
   }

   double GetEaFloatingProfit()  { return m_cachedBuyProfit + m_cachedSellProfit; }
   double GetBuyFloatingProfit() { return m_cachedBuyProfit; }
   double GetSellFloatingProfit(){ return m_cachedSellProfit; }
   int    GetOpenBuyCount()      { return m_cachedBuyCount; }
   int    GetOpenSellCount()     { return m_cachedSellCount; }

   //----------------------------------------------------------------
   // RAW position checks
   //----------------------------------------------------------------
   bool HasAnyBuyPosRaw()
   {
      int total = PositionsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_buy_magic) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
         return true;
      }
      return false;
   }

   bool HasAnySellPosRaw()
   {
      int total = PositionsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_sell_magic) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
         return true;
      }
      return false;
   }

   //----------------------------------------------------------------
   // Group / position helpers
   //----------------------------------------------------------------
   void CloseAllPositions()
   {
      for(int i = 0; i < ArraySize(pos_cache); i++)
         m_trade.PositionClose(pos_cache[i].ticket);

      ResetTradeGroup(m_buy_group);
      ResetTradeGroup(m_sell_group);

      CancelAllPendingByMagic(m_buy_magic);
      CancelAllPendingByMagic(m_sell_magic);

      m_positionsDirty = true;
   }

   void CloseBuyPositions()  { CloseGroup(m_buy_group,  POSITION_TYPE_BUY,  m_buy_magic); }
   void CloseSellPositions() { CloseGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic); }

   void CloseGroup(TradeGroup         &group,
                   ENUM_POSITION_TYPE  posType,
                   long               magic)
   {
      bool allClosed = true;

      for(int i = 0; i < ArraySize(pos_cache); i++)
      {
         if(pos_cache[i].magic != magic) continue;
         if(pos_cache[i].type  != posType) continue;

         if(!m_trade.PositionClose(pos_cache[i].ticket))
            allClosed = false;
      }

      // Always cancel remaining pendings for this trade idea after a group-close trigger.
      CancelAllPendingByMagic(magic);

      if(allClosed)
         ResetTradeGroup(group);

      m_positionsDirty = true;
      m_state_changed  = true;
   }

   void PartialCloseGroup(TradeGroup         &group,
                          ENUM_POSITION_TYPE  posType,
                          double             pct,
                          long               magic)
   {
      if(pct <= 0 || pct > 100) return;

      double total_vol = GetGroupVolumeForGroup(group, posType, magic);
      double to_close  = total_vol * (pct / 100.0);
      if(to_close <= 0) return;

      PosInfo pos_list[];
      int     count = 0;

      for(int k = 0; k < ArraySize(pos_cache); k++)
      {
         if(pos_cache[k].magic != magic) continue;
         if(pos_cache[k].type  != posType) continue;

         int size = ArraySize(pos_list);
         ArrayResize(pos_list, size + 1);

         pos_list[size].ticket = pos_cache[k].ticket;
         pos_list[size].vol    = pos_cache[k].volume;
         pos_list[size].entry  = pos_cache[k].open_price;

         count++;
      }

      // Sort for price priority
      if(posType == POSITION_TYPE_BUY)
      {
         for(int a = 0; a < count - 1; a++)
            for(int b = a + 1; b < count; b++)
               if(pos_list[a].entry < pos_list[b].entry)
               {
                  PosInfo tmp = pos_list[a];
                  pos_list[a] = pos_list[b];
                  pos_list[b] = tmp;
               }
      }
      else
      {
         for(int a = 0; a < count - 1; a++)
            for(int b = a + 1; b < count; b++)
               if(pos_list[a].entry > pos_list[b].entry)
               {
                  PosInfo tmp = pos_list[a];
                  pos_list[a] = pos_list[b];
                  pos_list[b] = tmp;
               }
      }

      double closed    = 0.0;
      bool   allClosed = true;
      double min_lot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

      for(int p = 0; p < count; p++)
      {
         if(closed >= to_close)
         {
            allClosed = false;
            break;
         }

         double this_close = MathMin(pos_list[p].vol, to_close - closed);
         this_close        = NormalizeLot(this_close);

         if(this_close < min_lot) break;

         ulong ticket = pos_list[p].ticket;

         if(this_close == pos_list[p].vol)
         {
            if(!m_trade.PositionClose(ticket))
               allClosed = false;
         }
         else
         {
            if(!m_trade.PositionClosePartial(ticket, this_close, m_slippage))
               allClosed = false;
            allClosed = false;
         }

         closed += this_close;
      }

      if(allClosed)
         ResetTradeGroup(group);
      else
         UpdateGroupStateOptimized(group, posType, magic);

      m_positionsDirty = true;
      m_state_changed  = true;
   }

   bool HasPosForGroup(const TradeGroup     &group,
                       ENUM_POSITION_TYPE    posType,
                       long                 magic)
   {
      for(int i = 0; i < ArraySize(pos_cache); i++)
      {
         if(pos_cache[i].magic != magic) continue;
         if(pos_cache[i].type  != posType) continue;
         return true;
      }
      return false;
   }

   bool HasAnyBuyPos()  { return m_cachedBuyCount  > 0; }
   bool HasAnySellPos() { return m_cachedSellCount > 0; }

   bool AnyBuyGroupActive()  { return m_buy_group.active;  }
   bool AnySellGroupActive() { return m_sell_group.active; }

   double GetGroupVolumeForGroup(const TradeGroup     &group,
                                 ENUM_POSITION_TYPE    posType,
                                 long                 magic)
   {
      double total = 0.0;

      for(int i = 0; i < ArraySize(pos_cache); i++)
      {
         if(pos_cache[i].magic != magic) continue;
         if(pos_cache[i].type  != posType) continue;
         total += pos_cache[i].volume;
      }

      return total;
   }

   double CalcLotSize(double riskPct,
                      double stopPips)
   {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double tickValue= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pipValue = tickValue * (GetPipValue() / tickSize);
      double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;

      double riskAmount = balance * (riskPct / 100.0);
      double lots       = riskAmount / (stopPips * pipValue);
      lots              = MathRound(lots / lotStep) * lotStep;

      double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double finalLots = MathMax(lots, minLot);
      double maxLots   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

      if(finalLots > maxLots)
         finalLots = maxLots;

      return finalLots;
   }

   double NormalizeLot(double lots)
   {
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;

      lots = MathFloor(lots / lotStep + 1e-8) * lotStep;
      return lots;
   }

   //----------------------------------------------------------------
   // Margin usage cap helper
   // UPDATED: uses effective used margin (includes pending if not reserved)
   //----------------------------------------------------------------
   bool CheckMarginCapForOrder(ENUM_ORDER_TYPE direction,
                               double          volume,
                               double          price,
                               string          side,
                               string          context)
   {
      if(m_maxMarginUsagePct <= 0.0)
         return true;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
      {
         LogTradeEvent(side,
                       "MARGIN_CAP_BLOCK",
                       "Equity <= 0 while checking margin cap (" + context + ")",
                       price,
                       volume);
         return false;
      }

      double usedEff = GetEffectiveUsedMarginForCap();

      double addMargin = 0.0;
      if(!CalcOrderMargin(direction, _Symbol, volume, price, addMargin))
      {
         LogTradeEvent(side,
                       "MARGIN_CAP_BLOCK",
                       "OrderCalcMargin failed (" + context + ")",
                       price,
                       volume);
         return false;
      }

      double newUsage = 100.0 * (usedEff + addMargin) / equity;
      if(newUsage > m_maxMarginUsagePct)
      {
         string reason = StringFormat(
            "Margin usage %.2f%% would exceed cap %.2f%% (%s)",
            newUsage, m_maxMarginUsagePct, context
         );
         LogTradeEvent(side,
                       "MARGIN_CAP_BLOCK",
                       reason,
                       price,
                       volume);
         return false;
      }

      return true;
   }

   //----------------------------------------------------------------
   // NEW YORK TIME HELPERS
   //----------------------------------------------------------------
   int GetNthSunday(int year, int month, int nth)
   {
      MqlDateTime dt;
      dt.year = year; dt.mon = month; dt.day = 1;
      dt.hour = 0; dt.min  = 0; dt.sec  = 0;
      dt.day_of_week = 0;
      dt.day_of_year = 0;

      datetime first = StructToTime(dt);

      MqlDateTime tmp;
      TimeToStruct(first, tmp);

      int dow          = tmp.day_of_week; // 0=Sunday
      int daysToSunday = (7 - dow) % 7;
      int firstSunday  = 1 + daysToSunday;
      int nthSundayDate= firstSunday + 7 * (nth - 1);

      return nthSundayDate;
   }

   int GetNYOffsetSeconds(datetime gmt)
   {
      MqlDateTime md;
      TimeToStruct(gmt, md);

      int year  = md.year;
      int month = md.mon;
      int day   = md.day;
      int hour  = md.hour;

      if(month > 3 && month < 11)
         return -4 * 3600;

      if(month < 3 || month > 11)
         return -5 * 3600;

      if(month == 3)
      {
         int secondSunday = GetNthSunday(year, 3, 2);

         if(day < secondSunday)
            return -5 * 3600;
         if(day > secondSunday)
            return -4 * 3600;

         // DST starts at 07:00 UTC on the second Sunday in March.
         return (hour >= 7 ? -4 * 3600 : -5 * 3600);
      }

      // month == 11
      int firstSunday = GetNthSunday(year, 11, 1);

      if(day < firstSunday)
         return -4 * 3600;
      if(day > firstSunday)
         return -5 * 3600;

      // DST ends at 06:00 UTC on the first Sunday in November.
      return (hour >= 6 ? -5 * 3600 : -4 * 3600);
   }

   void GetNewYorkTime(datetime gmt, MqlDateTime &ny)
   {
      int      offset = GetNYOffsetSeconds(gmt);
      datetime ny_dt  = gmt + offset;
      TimeToStruct(ny_dt, ny);
   }

   int GetNYTradingDayKey(datetime gmt)
   {
      MqlDateTime ny;
      GetNewYorkTime(gmt, ny);

      datetime ny_dt   = StructToTime(ny);
      datetime shifted = ny_dt - 17 * 3600;

      MqlDateTime sh;
      TimeToStruct(shifted, sh);

      return sh.year * 10000 + sh.mon * 100 + sh.day;
   }

   bool IsDailyCloseWindow(datetime gmt)
   {
      if(!m_enableDailyClose)
         return false;

      MqlDateTime ny;
      GetNewYorkTime(gmt, ny);

      int minutesNY = ny.hour * 60 + ny.min;
      const int nyCloseMinutes   = 17 * 60;
      const int closeLeadMinutes = 10; // fixed lead for daily close

      return (minutesNY >= (nyCloseMinutes - closeLeadMinutes) &&
              minutesNY < nyCloseMinutes);
   }

   datetime GetNYCloseTimeGMTForDate(int year, int mon, int day)
   {
      MqlDateTime ny_close;
      ny_close.year        = year;
      ny_close.mon         = mon;
      ny_close.day         = day;
      ny_close.hour        = 17;
      ny_close.min         = 0;
      ny_close.sec         = 0;
      ny_close.day_of_week = 0;
      ny_close.day_of_year = 0;

      // "NY local" pseudo-time (same representation used by GetNewYorkTime).
      datetime ny_close_dt = StructToTime(ny_close);

      // Solve gmt + offset(gmt) = ny_close_dt. Offset has only two states, so this converges quickly.
      datetime gmt = ny_close_dt + 5 * 3600;
      for(int i = 0; i < 3; i++)
      {
         int offset = GetNYOffsetSeconds(gmt);
         gmt = ny_close_dt - offset;
      }

      return gmt;
   }

   datetime GMTToServerTime(datetime gmt_time)
   {
      datetime server_now = TimeCurrent();
      datetime gmt_now    = TimeGMT();

      if(server_now == 0 || gmt_now == 0)
         return gmt_time;

      return gmt_time + (server_now - gmt_now);
   }

   void PlotMarketCloseLines()
   {
      if(IsOptimizationMode())
         return;

      datetime now_gmt = TimeGMT();
      if(now_gmt == 0)
         return;

      // Remove legacy NY-close markers from earlier implementation.
      for(int obj = ObjectsTotal(0) - 1; obj >= 0; obj--)
      {
         string oname = ObjectName(0, obj);
         if(StringFind(oname, "IGM_NY_CLOSE_") == 0)
            ObjectDelete(0, oname);
      }

      MqlDateTime ny_now;
      GetNewYorkTime(now_gmt, ny_now);

      datetime ny_now_dt   = StructToTime(ny_now);
      datetime ny_midnight = ny_now_dt - (ny_now.hour * 3600 + ny_now.min * 60 + ny_now.sec);
      const int lookbackDays = 120;

      for(int i = 0; i <= lookbackDays; i++)
      {
         datetime day_dt = ny_midnight - (i * 86400);

         MqlDateTime d;
         TimeToStruct(day_dt, d);

         ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)d.day_of_week;
         if(dow == SATURDAY || dow == SUNDAY)
            continue;

         // Use broker session schedule directly so lines match actual tradable close on this server.
         uint session_index = 0;
         datetime from, to;
         bool hasSession = false;
         datetime close_offset = 0;

         while(SymbolInfoSessionTrade(_Symbol, dow, session_index, from, to))
         {
            hasSession = true;
            if(to > close_offset)
               close_offset = to;
            session_index++;
         }

         if(!hasSession || close_offset <= 0)
            continue;

         datetime close_server = day_dt + close_offset;
         string name = StringFormat("IGM_MKT_CLOSE_%04d%02d%02d", d.year, d.mon, d.day);

         if(ObjectFind(0, name) == -1)
         {
            if(!ObjectCreate(0, name, OBJ_VLINE, 0, close_server, 0.0))
               continue;
         }
         else
         {
            ObjectMove(0, name, 0, close_server, 0.0);
         }

         ObjectSetInteger(0, name, OBJPROP_COLOR,      clrDarkGray);
         ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DOT);
         ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, name, OBJPROP_BACK,       true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
      }
   }
   //----------------------------------------------------------------
   // ORDER OPEN HELPERS
   //----------------------------------------------------------------
   bool OpenMarketOrderSingle(ENUM_ORDER_TYPE orderType,
                              double          volume,
                              long            magic,
                              double          sl = 0.0)
   {
      if(volume <= 0) return false;
      if(!IsWithinSession()) return false;
      if(!IsMarketOpen())    return false;
      if(IsNoTradeZone())    return false;

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
      {
         string side0 = (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
         LogTradeEvent(side0,
                       "ENTRY_FAIL",
                       "SymbolInfoTick failed",
                       0.0,
                       volume);
         return false;
      }

      double price = (orderType == ORDER_TYPE_BUY ? tick.ask : tick.bid);
      string side  = (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");

      // Correct margin requirement check using OrderCalcMargin
      double reqMargin = 0.0;
      if(!CalcOrderMargin(orderType, _Symbol, volume, price, reqMargin))
      {
         LogTradeEvent(side,
                       "ENTRY_FAIL",
                       "OrderCalcMargin failed (market)",
                       price,
                       volume);
         return false;
      }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(freeMargin < reqMargin)
      {
         LogTradeEvent(side,
                       "ENTRY_FAIL",
                       "Insufficient margin",
                       price,
                       volume);
         return false;
      }

      if(!CheckMarginCapForOrder(orderType, volume, price, side, "Market"))
         return false;

      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints(m_slippage);

      if(m_trade.PositionOpen(_Symbol,
                              orderType,
                              volume,
                              price,
                              sl,
                              "VWAP Flip bot DCA"))
      {
         m_last_trade_time = TimeCurrent();
         m_state_changed   = true;
         m_positionsDirty  = true;
         return true;
      }
      else
      {
         LogTradeEvent(side,
                       "ENTRY_FAIL",
                       m_trade.ResultRetcodeDescription(),
                       price,
                       volume);
         return false;
      }
   }

   bool OpenMarketOrder(ENUM_ORDER_TYPE orderType,
                        double          volume,
                        long            magic,
                        double          sl = 0.0)
   {
      if(volume <= 0) return false;

      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;

      if(m_lotSizeMultiple > 0.0)
      {
         double unit = NormalizeLot(m_lotSizeMultiple);
         if(unit < minLot) unit = minLot;

         int n = (int)MathFloor(volume / unit + 1e-8);
         if(n <= 0)
         {
            double vNorm = NormalizeLot(volume);
            if(vNorm < minLot) return false;
            return OpenMarketOrderSingle(orderType, vNorm, magic, sl);
         }

         bool anySuccess = false;

         for(int i = 0; i < n; i++)
         {
            if(OpenMarketOrderSingle(orderType, unit, magic, sl))
               anySuccess = true;
         }

         return anySuccess;
      }
      else
      {
         double vNorm = NormalizeLot(volume);
         if(vNorm < minLot) return false;
         return OpenMarketOrderSingle(orderType, vNorm, magic, sl);
      }
   }

   bool PlaceLimitOrderSingle(ENUM_ORDER_TYPE orderType,
                              double          volume,
                              double          price,
                              double          sl,
                              long            magic)
   {
      if(volume <= 0)        return false;
      if(!IsWithinSession()) return false;
      if(!IsMarketOpen())    return false;
      if(IsNoTradeZone())    return false;

      double exec_price = NormalizeDouble(price, _Digits);
      double sl_price   = (sl > 0.0 ? NormalizeDouble(sl, _Digits) : 0.0);

      // If limit is too close to market, convert to market order.
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
      {
         int    stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         int    freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
         double min_dist     = MathMax(stops_level, freeze_level) * _Point;

         bool too_close = false;
         if(orderType == ORDER_TYPE_BUY_LIMIT)
            too_close = (exec_price >= (tick.bid - min_dist));
         else if(orderType == ORDER_TYPE_SELL_LIMIT)
            too_close = (exec_price <= (tick.ask + min_dist));

         if(too_close)
         {
            string side = (orderType == ORDER_TYPE_BUY_LIMIT ? "BUY" : "SELL");
            string info = StringFormat(
               "Limit too close to market; converted to market. price=%.*f bid=%.*f ask=%.*f minDist=%.*f",
               _Digits, exec_price,
               _Digits, tick.bid,
               _Digits, tick.ask,
               _Digits, min_dist
            );

            LogTradeEvent(side,
                          "LIMIT_TO_MARKET",
                          info,
                          exec_price,
                          volume);

            ENUM_ORDER_TYPE marketType = (orderType == ORDER_TYPE_BUY_LIMIT ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
            return OpenMarketOrderSingle(marketType, volume, magic, sl_price);
         }
      }

      string side = (orderType == ORDER_TYPE_BUY_LIMIT ? "BUY" : "SELL");
      ENUM_ORDER_TYPE dirForMargin = (orderType == ORDER_TYPE_BUY_LIMIT ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

      if(!CheckMarginCapForOrder(dirForMargin, volume, exec_price, side, "DCA_LIMIT"))
         return false;

      m_trade.SetExpertMagicNumber((ulong)magic);
      m_trade.SetDeviationInPoints(m_slippage);

      if(m_trade.OrderOpen(_Symbol,
                           orderType,
                           volume,
                           0.0,
                           exec_price,
                           sl_price,
                           0.0,
                           ORDER_TIME_GTC,
                           0,
                           "VWAP Flip bot DCA Pending"))
      {
         m_state_changed = true;
         return true;
      }
      else
      {
         LogTradeEvent(side,
                       "PENDING_FAIL",
                       m_trade.ResultRetcodeDescription(),
                       exec_price,
                       volume);
         return false;
      }
   }

   bool PlaceLimitOrder(ENUM_ORDER_TYPE orderType,
                        double          volume,
                        double          price,
                        double          sl,
                        long            magic)
   {
      if(volume <= 0) return false;

      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;

      if(m_lotSizeMultiple > 0.0)
      {
         double unit = NormalizeLot(m_lotSizeMultiple);
         if(unit < minLot) unit = minLot;

         int n = (int)MathFloor(volume / unit + 1e-8);
         if(n <= 0)
         {
            double vNorm = NormalizeLot(volume);
            if(vNorm < minLot) return false;
            return PlaceLimitOrderSingle(orderType, vNorm, price, sl, magic);
         }

         bool anySuccess = false;

         for(int i = 0; i < n; i++)
         {
            if(PlaceLimitOrderSingle(orderType, unit, price, sl, magic))
               anySuccess = true;
         }

         return anySuccess;
      }
      else
      {
         double vNorm = NormalizeLot(volume);
         if(vNorm < minLot) return false;
         return PlaceLimitOrderSingle(orderType, vNorm, price, sl, magic);
      }
   }
   //----------------------------------------------------------------
   // Daily / Global DD checks
   //----------------------------------------------------------------
   void CheckReset()
   {
      if(m_dailyReset && m_startEq > 0.0)
      {
         double maxLossAmount           = m_startEq * (m_maxDD / 100.0);
         double current_floating_profit = GetEaFloatingProfit();

         if(current_floating_profit < 0 &&
            MathAbs(current_floating_profit) >= maxLossAmount)
         {
            CloseAllPositions();
            m_halted = true;

            LogTradeEvent("GLOBAL",
                          "ALL_CLOSE_DAILY_DD",
                          "Daily P/L drawdown reached",
                          0.0,
                          0.0,
                          current_floating_profit,
                          0.0);
            return;
         }
      }

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_globalMaxDD > 0 &&
         m_globalStartEq > 0.0 &&
         equity <= m_globalStartEq * (1.0 - m_globalMaxDD / 100.0))
      {
         CloseAllPositions();
         m_globalHalted = true;

         LogTradeEvent("GLOBAL",
                       "ALL_CLOSE_GLOBAL_DD",
                       "Global equity drawdown reached",
                       0.0,
                       0.0,
                       equity - m_globalStartEq,
                       0.0);
      }
   }

   //----------------------------------------------------------------
   // Group state / management
   //----------------------------------------------------------------
   void UpdateGroupState(TradeGroup         &group,
                         ENUM_POSITION_TYPE  posType,
                         long               magic)
   {
      double totalVol      = 0.0;
      double weightedSum   = 0.0;
      double sum_swap      = 0.0;
      double extreme_entry = (posType == POSITION_TYPE_BUY ? -DBL_MAX : DBL_MAX);

      for(int i = 0; i < ArraySize(pos_cache); i++)
      {
         if(pos_cache[i].magic != magic) continue;
         if(pos_cache[i].type  != posType) continue;

         double vol   = pos_cache[i].volume;
         double price = pos_cache[i].open_price;

         totalVol    += vol;
         weightedSum += vol * price;
         sum_swap    += pos_cache[i].swap;

         if(posType == POSITION_TYPE_BUY)
            extreme_entry = MathMax(extreme_entry, price);
         else
            extreme_entry = MathMin(extreme_entry, price);
      }

      if(totalVol <= 0.0)
         return;

      double newAvgEntry = weightedSum / totalVol;

      if(MathAbs(newAvgEntry - group.entryPrice) > _Point)
      {
         group.entryPrice = newAvgEntry;
         group.totalVol   = totalVol;
         m_state_changed  = true;
      }

      if(posType == POSITION_TYPE_BUY)
         m_lastEntry_buy = extreme_entry;
      else
         m_lastEntry_sell = extreme_entry;
   }

   void UpdateGroupStateOptimized(TradeGroup         &group,
                                  ENUM_POSITION_TYPE  posType,
                                  long               magic)
   {
      if(!m_positionsDirty && (TimeCurrent() - group.open_time) < 5)
         return;

      UpdateGroupState(group, posType, magic);
   }

   //----------------------------------------------------------------
   // BUY / SELL group managers
   //----------------------------------------------------------------
   void ManageBuyGroup()
   {
      if(!m_buy_group.active && !HasAnyBuyPos())
         return;

      if(HasPosForGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic) &&
         !m_buy_group.active)
      {
         m_buy_group.active = true;
         m_state_changed    = true;
      }

      if(!HasPosForGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic))
      {
         int pendingBuy = GetPendingCount(m_buy_magic, ORDER_TYPE_BUY_LIMIT);

         if(m_buy_group.active &&
            m_buy_group.open_time > 0 &&
            pendingBuy > 0)
         {
            CancelAllPendingByMagic(m_buy_magic);

            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            LogTradeEvent("BUY",
                          "PENDING_CLEANUP_AFTER_GROUP_CLOSE",
                          "Cancelled leftover BUY pending orders after group had no open positions",
                          currentPrice,
                          0.0,
                          0.0,
                          0.0);

            ResetTradeGroup(m_buy_group);
            return;
         }

         if(m_buy_group.active &&
            (TimeCurrent() - m_buy_group.open_time > 5) &&
            pendingBuy == 0)
         {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            LogTradeEvent("BUY",
                          "GROUP_CLOSE_EXTERNAL_SL",
                          "Assumed physical SL hit (external close)",
                          currentPrice,
                          m_buy_group.totalVol,
                          0.0,
                          0.0);

            ResetTradeGroup(m_buy_group);
         }
         return;
      }

      UpdateGroupStateOptimized(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);

      if(m_buy_group.virtualSL == 0.0)
      {
         double physSL    = -1.0;
         bool   consistent= true;

         for(int i = 0; i < ArraySize(pos_cache); i++)
         {
            if(pos_cache[i].magic != m_buy_magic) continue;
            if(pos_cache[i].type  != POSITION_TYPE_BUY) continue;

            ulong ticket = pos_cache[i].ticket;
            if(!PositionSelectByTicket(ticket)) continue;

            double thisSL = PositionGetDouble(POSITION_SL);

            if(physSL < 0.0)
               physSL = thisSL;
            else if(MathAbs(thisSL - physSL) > _Point)
               consistent = false;
         }

         if(consistent && physSL > 0.0)
         {
            m_buy_group.virtualSL = NormalizeDouble(physSL, _Digits);
            m_state_changed       = true;

            LogTradeEvent("BUY",
                          "SL_SYNC_FROM_PHYSICAL",
                          "Synced virtual SL from physical",
                          m_buy_group.virtualSL,
                          m_buy_group.totalVol);
         }
      }

      if(!IsMarketOpen()) return;

      if(m_buy_group.initial_sl_distance <= 0.0 &&
         m_buy_group.virtualSL != 0.0 &&
         m_buy_group.entryPrice != 0.0)
      {
         double dist = m_buy_group.entryPrice - m_buy_group.virtualSL;
         if(dist > 0.0)
         {
            m_buy_group.initial_sl_distance = dist;
            m_state_changed                 = true;
         }
      }

      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      int open_shift = iBarShift(_Symbol, PERIOD_H1, m_buy_group.open_time, false);
      int now_shift  = iBarShift(_Symbol, PERIOD_H1, TimeCurrent(), false);

      int bars_passed = 0;
      if(open_shift >= 0 && now_shift >= 0)
         bars_passed = MathMax(0, open_shift - now_shift);

      double targetRR = m_profitTargetRR;
      if(bars_passed >= FlipFallback1HCandles)
         targetRR = FlipFallbackReward;

      double pip_size   = GetPipValue();
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pip_value  = tick_value * (pip_size / tick_size);

      double riskBase = GetCurrentRiskBase();
      double profit   = GetBuyFloatingProfit();
      double R_current= (riskBase > 0.0 ? profit / riskBase : 0.0);

      if(!m_slOnlyMode)
      {
      // Partial TP
      if(m_enablePartialTP &&
         !m_buy_group.partialDone &&
         riskBase > 0.0 &&
         R_current >= m_partialTP_RR)
      {
         LogTradeEvent("BUY",
                       "PARTIAL_TP",
                       "Partial TP RR threshold reached",
                       currentPrice,
                       m_buy_group.totalVol,
                       profit,
                       R_current);

         PartialCloseGroup(m_buy_group,
                           POSITION_TYPE_BUY,
                           m_partialTP_Percent,
                           m_buy_magic);

         m_buy_group.partialDone = true;
         m_state_changed         = true;
      }

      // Profit or fallback RR target
      if(riskBase > 0.0 && targetRR > 0.0 && R_current >= targetRR)
      {
         string reason = (bars_passed >= FlipFallback1HCandles ?
                          "Fallback RR target reached" :
                          "Primary RR target reached");

         LogTradeEvent("BUY",
                       "GROUP_CLOSE_PROFIT",
                       reason,
                       currentPrice,
                       m_buy_group.totalVol,
                       profit,
                       R_current);

         CloseGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
         return;
      }

      }

      // Virtual SL -> loss/BE close
      if(m_buy_group.virtualSL != 0.0 && currentPrice <= m_buy_group.virtualSL)
      {
         LogTradeEvent("BUY",
                       "GROUP_CLOSE_SL",
                       "Virtual SL hit",
                       currentPrice,
                       m_buy_group.totalVol,
                       profit,
                       R_current);

         CloseGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
         bool applyCooldown = (R_current < 0.0 && CooldownH1Candles > 0);
         if(applyCooldown)
         {
            m_buyCooldownEndTime = TimeCurrent() + CooldownH1Candles * 3600;
            LogTradeEvent("BUY",
                          "COOLDOWN_SET",
                          "Cooldown applied after loss on SL close",
                          currentPrice,
                          0.0,
                          profit,
                          R_current);
         }
         else
         {
            m_buyCooldownEndTime = TimeCurrent();
            LogTradeEvent("BUY",
                          "COOLDOWN_SKIPPED",
                          "SL close at breakeven/profit; cooldown not applied",
                          currentPrice,
                          0.0,
                          profit,
                          R_current);
         }
         return;
      }

      ApplyPhysicalSLToGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
   }

   void ManageSellGroup()
   {
      if(!m_sell_group.active && !HasAnySellPos())
         return;

      if(HasPosForGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic) &&
         !m_sell_group.active)
      {
         m_sell_group.active = true;
         m_state_changed     = true;
      }

      if(!HasPosForGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic))
      {
         int pendingSell = GetPendingCount(m_sell_magic, ORDER_TYPE_SELL_LIMIT);

         if(m_sell_group.active &&
            m_sell_group.open_time > 0 &&
            pendingSell > 0)
         {
            CancelAllPendingByMagic(m_sell_magic);

            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            LogTradeEvent("SELL",
                          "PENDING_CLEANUP_AFTER_GROUP_CLOSE",
                          "Cancelled leftover SELL pending orders after group had no open positions",
                          currentPrice,
                          0.0,
                          0.0,
                          0.0);

            ResetTradeGroup(m_sell_group);
            return;
         }

         if(m_sell_group.active &&
            (TimeCurrent() - m_sell_group.open_time > 5) &&
            pendingSell == 0)
         {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            LogTradeEvent("SELL",
                          "GROUP_CLOSE_EXTERNAL_SL",
                          "Assumed physical SL hit (external close)",
                          currentPrice,
                          m_sell_group.totalVol,
                          0.0,
                          0.0);

            ResetTradeGroup(m_sell_group);
         }
         return;
      }

      UpdateGroupStateOptimized(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);

      if(m_sell_group.virtualSL == 0.0)
      {
         double physSL    = -1.0;
         bool   consistent= true;

         for(int i = 0; i < ArraySize(pos_cache); i++)
         {
            if(pos_cache[i].magic != m_sell_magic) continue;
            if(pos_cache[i].type  != POSITION_TYPE_SELL) continue;

            ulong ticket = pos_cache[i].ticket;
            if(!PositionSelectByTicket(ticket)) continue;

            double thisSL = PositionGetDouble(POSITION_SL);

            if(physSL < 0.0)
               physSL = thisSL;
            else if(MathAbs(thisSL - physSL) > _Point)
               consistent = false;
         }

         if(consistent && physSL > 0.0)
         {
            m_sell_group.virtualSL = NormalizeDouble(physSL, _Digits);
            m_state_changed        = true;

            LogTradeEvent("SELL",
                          "SL_SYNC_FROM_PHYSICAL",
                          "Synced virtual SL from physical",
                          m_sell_group.virtualSL,
                          m_sell_group.totalVol);
         }
      }

      if(!IsMarketOpen()) return;

      if(m_sell_group.initial_sl_distance <= 0.0 &&
         m_sell_group.virtualSL != 0.0 &&
         m_sell_group.entryPrice != 0.0)
      {
         double dist = m_sell_group.virtualSL - m_sell_group.entryPrice;
         if(dist > 0.0)
         {
            m_sell_group.initial_sl_distance = dist;
            m_state_changed                  = true;
         }
      }

      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      int open_shift = iBarShift(_Symbol, PERIOD_H1, m_sell_group.open_time, false);
      int now_shift  = iBarShift(_Symbol, PERIOD_H1, TimeCurrent(), false);

      int bars_passed = 0;
      if(open_shift >= 0 && now_shift >= 0)
         bars_passed = MathMax(0, open_shift - now_shift);

      double targetRR = m_profitTargetRR;
      if(bars_passed >= FlipFallback1HCandles)
         targetRR = FlipFallbackReward;

      double pip_size   = GetPipValue();
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pip_value  = tick_value * (pip_size / tick_size);

      double riskBase = GetCurrentRiskBase();
      double profit   = GetSellFloatingProfit();
      double R_current= (riskBase > 0.0 ? profit / riskBase : 0.0);

      if(!m_slOnlyMode)
      {
      // Partial TP
      if(m_enablePartialTP &&
         !m_sell_group.partialDone &&
         riskBase > 0.0 &&
         R_current >= m_partialTP_RR)
      {
         LogTradeEvent("SELL",
                       "PARTIAL_TP",
                       "Partial TP RR threshold reached",
                       currentPrice,
                       m_sell_group.totalVol,
                       profit,
                       R_current);

         PartialCloseGroup(m_sell_group,
                           POSITION_TYPE_SELL,
                           m_partialTP_Percent,
                           m_sell_magic);

         m_sell_group.partialDone = true;
         m_state_changed          = true;
      }

      // Profit or fallback RR target
      if(riskBase > 0.0 && targetRR > 0.0 && R_current >= targetRR)
      {
         string reason = (bars_passed >= FlipFallback1HCandles ?
                          "Fallback RR target reached" :
                          "Primary RR target reached");

         LogTradeEvent("SELL",
                       "GROUP_CLOSE_PROFIT",
                       reason,
                       currentPrice,
                       m_sell_group.totalVol,
                       profit,
                       R_current);

         CloseGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
         return;
      }

      }

      // Virtual SL -> loss/BE close
      if(m_sell_group.virtualSL != 0.0 && currentPrice >= m_sell_group.virtualSL)
      {
         LogTradeEvent("SELL",
                       "GROUP_CLOSE_SL",
                       "Virtual SL hit",
                       currentPrice,
                       m_sell_group.totalVol,
                       profit,
                       R_current);

         CloseGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
         bool applyCooldown = (R_current < 0.0 && CooldownH1Candles > 0);
         if(applyCooldown)
         {
            m_sellCooldownEndTime = TimeCurrent() + CooldownH1Candles * 3600;
            LogTradeEvent("SELL",
                          "COOLDOWN_SET",
                          "Cooldown applied after loss on SL close",
                          currentPrice,
                          0.0,
                          profit,
                          R_current);
         }
         else
         {
            m_sellCooldownEndTime = TimeCurrent();
            LogTradeEvent("SELL",
                          "COOLDOWN_SKIPPED",
                          "SL close at breakeven/profit; cooldown not applied",
                          currentPrice,
                          0.0,
                          profit,
                          R_current);
         }
         return;
      }

      ApplyPhysicalSLToGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
   }

   //----------------------------------------------------------------
   // Breakeven, peak drawdown, and scale-in logic
   //----------------------------------------------------------------
   #include "VWAP Flip bot_Engine_ScaleIn.mqh"

   //----------------------------------------------------------------
   // Sync virtual SL to physical
   //----------------------------------------------------------------
   void ApplyPhysicalSLToGroup(TradeGroup         &group,
                               ENUM_POSITION_TYPE  posType,
                               long               magic)
   {
      if(!group.active || group.virtualSL == 0.0)
         return;

      double targetSL = NormalizeDouble(group.virtualSL, _Digits);

      if(m_positionsDirty)
         UpdateCachedTradeStatesOptimized();

      bool allSet = false;
      int  retries= 0;

      while(!allSet && retries < 10)
      {
         allSet = true;

         for(int i = 0; i < ArraySize(pos_cache); i++)
         {
            if(pos_cache[i].magic != magic) continue;
            if(pos_cache[i].type  != posType) continue;

            ulong ticket = pos_cache[i].ticket;
            if(!PositionSelectByTicket(ticket)) continue;

            double curSL = PositionGetDouble(POSITION_SL);
            double curTP = PositionGetDouble(POSITION_TP);

            if(MathAbs(curSL - targetSL) <= _Point)
               continue;
            m_trade.SetExpertMagicNumber((ulong)magic);
            m_trade.SetDeviationInPoints(m_slippage);

            if(!m_trade.PositionModify(ticket, targetSL, curTP))
            {
               LogTradeEvent(EnumToString(posType),
                             "SL_MODIFY_FAIL",
                             m_trade.ResultRetcodeDescription(),
                             0.0,
                             0.0,
                             0.0,
                             0.0);
               allSet = false;
            }
         }

         if(!allSet)
         {
            Sleep(50);
            m_positionsDirty = true;
            UpdateCachedTradeStatesOptimized();
            retries++;
         }
      }

      if(!allSet)
      {
         LogTradeEvent(EnumToString(posType),
                       "SL_SET_RETRY_FAIL",
                       "Failed to set SL after 10 retries",
                       0.0,
                       0.0,
                       0.0,
                       0.0);
      }
   }

   //----------------------------------------------------------------
   // Session Management
   //----------------------------------------------------------------
   bool IsWithinSession()
   {
      datetime time_gmt = TimeGMT();
      if(time_gmt == 0) return false;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid == 0.0) return false;

      MqlDateTime ny;
      GetNewYorkTime(time_gmt, ny);

      int minutesNY = ny.hour * 60 + ny.min;

      if(m_tradeNewYork && minutesNY >= 8 * 60 && minutesNY < 17 * 60) return true;
      if(m_tradeLondon  && minutesNY >= 3 * 60 && minutesNY < 12 * 60) return true;
      if(m_tradeTokyo   && (minutesNY >= 19 * 60 || minutesNY < 4 * 60)) return true;
      if(m_tradeSydney  && (minutesNY >= 17 * 60 || minutesNY < 2 * 60)) return true;

      return false;
   }

   //----------------------------------------------------------------
   // Swing Anchored VWAP Strategy
   //----------------------------------------------------------------
   // Included inside CBBMartingaleEA::private, declares members & methods
   #include "VWAP Flip bot_Strategy.mqh"

   //----------------------------------------------------------------
   // Pending expiry for DCA grids
   //----------------------------------------------------------------
   void CheckPendingExpiry(TradeGroup &group,
                           long        magic,
                           bool        isBuy)
   {
      if(!group.active || TimeCurrent() <= group.expiry_time)
         return;

      int  total       = OrdersTotal();
      bool hasPendings = false;

      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) != magic) continue;

         hasPendings = true;
         m_trade.OrderDelete(ticket);
      }

      if(hasPendings)
      {
         string side = isBuy ? "BUY" : "SELL";
         LogTradeEvent(side,
                       "PENDING_CANCEL_EXPIRED",
                       "DCA pending orders expired and cancelled");

         group.expiry_time = 0;
         m_state_changed   = true;
      }
   }

   void CancelAllPendingByMagic(long magic)
   {
      const int maxRetries = 5;

      for(int attempt = 0; attempt < maxRetries; attempt++)
      {
         int total = OrdersTotal();

         for(int i = total - 1; i >= 0; i--)
         {
            ulong ticket = OrderGetTicket(i);
            if(ticket == 0) continue;
            if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
            if(OrderGetInteger(ORDER_MAGIC) != magic) continue;

            ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            bool isPending = (ot == ORDER_TYPE_BUY_LIMIT  || ot == ORDER_TYPE_SELL_LIMIT ||
                              ot == ORDER_TYPE_BUY_STOP   || ot == ORDER_TYPE_SELL_STOP  ||
                              ot == ORDER_TYPE_BUY_STOP_LIMIT || ot == ORDER_TYPE_SELL_STOP_LIMIT);
            if(!isPending) continue;

            if(!m_trade.OrderDelete(ticket) && attempt == maxRetries - 1)
            {
               string side = (magic == m_buy_magic ? "BUY" : (magic == m_sell_magic ? "SELL" : "GLOBAL"));
               double price = OrderGetDouble(ORDER_PRICE_OPEN);
               double vol   = OrderGetDouble(ORDER_VOLUME_CURRENT);

               LogTradeEvent(side,
                             "PENDING_CANCEL_FAIL",
                             m_trade.ResultRetcodeDescription(),
                             price,
                             vol);
            }
         }

         bool stillLeft = false;
         int total2 = OrdersTotal();

         for(int j = total2 - 1; j >= 0; j--)
         {
            ulong ticket2 = OrderGetTicket(j);
            if(ticket2 == 0) continue;
            if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
            if(OrderGetInteger(ORDER_MAGIC) != magic) continue;

            ENUM_ORDER_TYPE ot2 = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            bool isPending2 = (ot2 == ORDER_TYPE_BUY_LIMIT  || ot2 == ORDER_TYPE_SELL_LIMIT ||
                               ot2 == ORDER_TYPE_BUY_STOP   || ot2 == ORDER_TYPE_SELL_STOP  ||
                               ot2 == ORDER_TYPE_BUY_STOP_LIMIT || ot2 == ORDER_TYPE_SELL_STOP_LIMIT);
            if(!isPending2) continue;

            stillLeft = true;
            break;
         }

         if(!stillLeft)
            break;

         Sleep(50);
      }
   }

public:
   //----------------------------------------------------------------
   // Constructor
   //----------------------------------------------------------------
   CBBMartingaleEA()
   {
      last_bar_time_period = 0;
      m_lastStateSave      = 0;

      m_dailyReset        = true;
      m_maxDD             = MaxDailyDrawdownPct;
      m_profitTargetRR    = ProfitTargetRR;
      m_magic             = EA_MagicNumber;
      m_globalMaxDD       = MaxGlobalDrawdownPct;
      m_slippage          = Slippage;
      m_enableHedge       = EnableHedge;
      m_tradeDirection    = TradeDirection;

      m_day                    = 0;
      m_lastDailyCloseTradingKey = 0;
      m_startEq                = 0.0;
      m_halted          = false;
      m_globalHalted    = false;
      m_last_trade_time = 0;

      m_globalStartEq  = 0.0;
      m_last_bar_time  = 0;
      m_state_changed  = false;

      m_maxTotalRiskPct   = MaxTotalRiskPct;
      m_atrPeriod         = AtrPeriod;
      m_atrSlMultiplier   = AtrSlMultiplier;
      m_maxMarginUsagePct = MaxMarginUsagePct;

      m_startBalanceInput   = StartBalance;
      m_targetBalance       = TargetBalance;
      m_enableTargetBalance = EnableTargetBalance;
      m_enableDynamicRisk   = EnableDynamicRisk;
      m_targetBalanceHit    = false;

      m_sequenceBE_StartR         = SequenceBE_StartR;
      m_breakevenOffsetR          = BreakevenOffsetR;
      m_enablePeakDrawdownExit    = EnablePeakDrawdownExit;
      m_peakDrawdownStartR        = PeakDrawdownStartR;
      m_peakProfitDrawdownPercent = PeakProfitDrawdownPercent;
      m_tradeExpiryCandles        = TradeExpiryCandles;

      m_enablePartialTP   = EnablePartialTP;
      m_partialTP_RR      = PartialTP_RR;
      m_partialTP_Percent = PartialTP_Percent;

      m_buy_peakR  = 0.0;
      m_sell_peakR = 0.0;

      m_buyCooldownEndTime  = 0;
      m_sellCooldownEndTime = 0;

      m_tradeNewYork    = TradeNewYork;
      m_tradeLondon     = TradeLondon;
      m_tradeTokyo      = TradeTokyo;
      m_tradeSydney     = TradeSydney;
      m_enableDailyClose= EnableDailyClose;

      m_cachedATR          = 0.0;
      m_lastATRUpdate      = 0;
      m_cachedBuyCount     = 0;
      m_cachedSellCount    = 0;
      m_cachedBuyProfit    = 0.0;
      m_cachedSellProfit   = 0.0;
      m_lastPositionUpdate = 0;
      m_positionsDirty     = true;

      ArrayResize(m_m5rates_buffer, (AtrPeriod + 1) * 7 + 10);

      m_dcaParts             = DCAParts;
      m_pendingExpiryCandles = PendingExpiryCandles;
      m_initialDCAOffsetATR  = InitialDCAOffsetATR;
      m_lotSizeMultiple      = LotSizeMultiple;
      m_dcaSLPercent         = DCA_SL_Percent;

      m_enableScaleIn           = EnableScaleIn;
      m_scaleInMinATRFracToSL   = ScaleIn_MinATRFracToSL;
      m_scaleInAddATRMultiplier = ScaleIn_AddATRMultiplier;
      m_scaleInMaxExposure      = (double)ScaleInMaxExposure; // 0,1,2
      m_scaleInMaxTopUps        = ScaleIn_MaxTopUps;

      m_buyScaleInCount  = 0;
      m_sellScaleInCount = 0;

      m_initialATR_buy   = 0.0;
      m_initialEntry_buy = 0.0;
      m_lastEntry_buy    = 0.0;

      m_initialATR_sell   = 0.0;
      m_initialEntry_sell = 0.0;
      m_lastEntry_sell    = 0.0;

      m_last_buy_attempt  = 0;
      m_last_sell_attempt = 0;

      m_slOnlyMode = false;
      m_newsFilter.Configure(EnableNewsFilter,
                             NewsBlockBeforeMin,
                             NewsBlockAfterMin);

      // Initialize swing strategy state
      Strategy_Init(SwingPeriod, VwapAPTBase, PlotSwingVWAP, VwapUpColor, VwapDownColor, VwapLineWidth);
   }

   //----------------------------------------------------------------
   // Lifecycle
   //----------------------------------------------------------------
   int OnInit()
   {
      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Print("This EA requires a hedging account type.");
         return(INIT_FAILED);
      }

      ChartSetInteger(0, CHART_SHOW_GRID, false);

      m_globalStartEq = AccountInfoDouble(ACCOUNT_BALANCE);
      m_buy_magic     = m_magic + 1;
      m_sell_magic    = m_magic + 2;

      ResetTradeGroup(m_buy_group);
      ResetTradeGroup(m_sell_group);

      LoadState();

      // Warm strategy state from history so startup does not wait many live bars.
      Strategy_WarmStartFromHistory();

      if(!m_enableTargetBalance)
         m_targetBalanceHit = false;


      PlotMarketCloseLines();

      m_newsFilter.Init(_Symbol);

      return(INIT_SUCCEEDED);
   }

   void OnDeinit(const int reason)
   {
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans,
                           const MqlTradeRequest     &request,
                           const MqlTradeResult      &result)
   {
      m_positionsDirty = true;

      if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
         trans.type == TRADE_TRANSACTION_ORDER_DELETE)
         m_state_changed = true;

      // SAFETY: if a NEW entry (including pending fills) breaches margin cap, close it immediately.
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == _Symbol && m_maxMarginUsagePct > 0.0)
      {
         // Determine if this is an entry deal
         bool isEntry = false;
         if(HistoryDealSelect(trans.deal))
         {
            long entry = (long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            isEntry = (entry == DEAL_ENTRY_IN);
         }

         if(isEntry)
         {
            ulong posTicket = trans.position;
            if(posTicket != 0 && PositionSelectByTicket(posTicket))
            {
               long               magic = PositionGetInteger(POSITION_MAGIC);
               ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

               if(magic == m_buy_magic || magic == m_sell_magic)
               {
                  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
                  if(equity > 0.0)
                  {
                     double usage = 100.0 * AccountInfoDouble(ACCOUNT_MARGIN) / equity;
                     if(usage > (m_maxMarginUsagePct + 0.05)) // small tolerance
                     {
                        string side = (ptype == POSITION_TYPE_BUY ? "BUY" : "SELL");
                        double vol  = PositionGetDouble(POSITION_VOLUME);
                        double prof = PositionGetDouble(POSITION_PROFIT);

                        string reason = StringFormat("Margin usage %.2f%% exceeded cap %.2f%% after entry fill; emergency close of last position + cancel remaining pendings.",
                                                     usage, m_maxMarginUsagePct);

                        LogTradeEvent(side,
                                      "MARGIN_CAP_EMERGENCY_CLOSE",
                                      reason,
                                      trans.price,
                                      vol,
                                      prof,
                                      0.0);

                        m_trade.SetExpertMagicNumber((ulong)magic);
                        m_trade.SetDeviationInPoints(m_slippage);

                        if(!m_trade.PositionClose(posTicket))
                        {
                           LogTradeEvent(side,
                                         "MARGIN_CAP_EMERGENCY_CLOSE_FAIL",
                                         m_trade.ResultRetcodeDescription(),
                                         trans.price,
                                         vol,
                                         prof,
                                         0.0);
                        }

                        // Cancel remaining pendings on this side to avoid repeated breaches
                        CancelAllPendingByMagic(magic);
                        m_positionsDirty = true;
                        m_state_changed  = true;
                     }
                  }
               }
            }
         }
      }

      if(trans.type == TRADE_TRANSACTION_DEAL_ADD &&
         trans.symbol == _Symbol)
      {
         ulong posTicket = trans.position;

         if(posTicket != 0 && PositionSelectByTicket(posTicket))
         {
            long               magic = PositionGetInteger(POSITION_MAGIC);
            ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            datetime           now   = TimeCurrent();
            if(magic == m_buy_magic && ptype == POSITION_TYPE_BUY)
            {
               if(m_buy_group.open_time == 0)
               {
                  m_buy_group.open_time = now;
                  m_state_changed       = true;
               }

               int exposureMode = (int)MathRound(m_scaleInMaxExposure);
               if(exposureMode == 0 && m_buyScaleInCount > 0)
               {
                  double be_after_fill;
                  if(ComputeGroupBreakevenPrice(POSITION_TYPE_BUY, m_buy_magic, be_after_fill))
                  {
                     m_buy_group.virtualSL = NormalizeDouble(be_after_fill, _Digits);
                     m_state_changed       = true;
                  }
               }

               ApplyPhysicalSLToGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
            }
            else if(magic == m_sell_magic && ptype == POSITION_TYPE_SELL)
            {
               if(m_sell_group.open_time == 0)
               {
                  m_sell_group.open_time = now;
                  m_state_changed        = true;
               }

               int exposureMode = (int)MathRound(m_scaleInMaxExposure);
               if(exposureMode == 0 && m_sellScaleInCount > 0)
               {
                  double be_after_fill;
                  if(ComputeGroupBreakevenPrice(POSITION_TYPE_SELL, m_sell_magic, be_after_fill))
                  {
                     m_sell_group.virtualSL = NormalizeDouble(be_after_fill, _Digits);
                     m_state_changed        = true;
                  }
               }

               ApplyPhysicalSLToGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
            }

            if(!m_enableHedge)
            {
               if(magic == m_buy_magic && ptype == POSITION_TYPE_BUY)
                  CancelAllPendingByMagic(m_sell_magic);
               if(magic == m_sell_magic && ptype == POSITION_TYPE_SELL)
                  CancelAllPendingByMagic(m_buy_magic);
            }
         }
      }
   }

   //----------------------------------------------------------------
   // State save/load (GlobalVariables disabled in optimization)
   //----------------------------------------------------------------
   void SaveState()
   {
      if(IsOptimizationMode())
         return;

      string prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Buy_";

      GlobalVariableSet(prefix + "active",              m_buy_group.active ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "entryPrice",          m_buy_group.entryPrice);
      GlobalVariableSet(prefix + "partialDone",         m_buy_group.partialDone ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "totalVol",            m_buy_group.totalVol);
      GlobalVariableSet(prefix + "virtualSL",           m_buy_group.virtualSL);
      GlobalVariableSet(prefix + "virtualTP",           m_buy_group.virtualTP);
      GlobalVariableSet(prefix + "initial_entry",       m_buy_group.initial_entry);
      GlobalVariableSet(prefix + "open_time",           (double)m_buy_group.open_time);
      GlobalVariableSet(prefix + "expiry_time",         (double)m_buy_group.expiry_time);
      GlobalVariableSet(prefix + "initial_sl_distance", m_buy_group.initial_sl_distance);
      GlobalVariableSet(prefix + "cooldown_end",        (double)m_buyCooldownEndTime);
      GlobalVariableSet(prefix + "initialATR",          m_initialATR_buy);
      GlobalVariableSet(prefix + "initialEntry",        m_initialEntry_buy);
      GlobalVariableSet(prefix + "lastEntry",           m_lastEntry_buy);

      prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Sell_";

      GlobalVariableSet(prefix + "active",              m_sell_group.active ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "entryPrice",          m_sell_group.entryPrice);
      GlobalVariableSet(prefix + "partialDone",         m_sell_group.partialDone ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "totalVol",            m_sell_group.totalVol);
      GlobalVariableSet(prefix + "virtualSL",           m_sell_group.virtualSL);
      GlobalVariableSet(prefix + "virtualTP",           m_sell_group.virtualTP);
      GlobalVariableSet(prefix + "initial_entry",       m_sell_group.initial_entry);
      GlobalVariableSet(prefix + "open_time",           (double)m_sell_group.open_time);
      GlobalVariableSet(prefix + "expiry_time",         (double)m_sell_group.expiry_time);
      GlobalVariableSet(prefix + "initial_sl_distance", m_sell_group.initial_sl_distance);
      GlobalVariableSet(prefix + "cooldown_end",        (double)m_sellCooldownEndTime);
      GlobalVariableSet(prefix + "initialATR",          m_initialATR_sell);
      GlobalVariableSet(prefix + "initialEntry",        m_initialEntry_sell);
      GlobalVariableSet(prefix + "lastEntry",           m_lastEntry_sell);

      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_LastTradeTime",
                        (double)m_last_trade_time);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "IGM_EA_TargetHit",
                        m_targetBalanceHit ? 1.0 : 0.0);
   }

   void SaveIfChanged()
   {
      if(IsOptimizationMode())
         return;

      if(!m_state_changed || (TimeCurrent() - m_lastStateSave) < 5)
         return;

      SaveState();
      m_lastStateSave = TimeCurrent();
      m_state_changed = false;
   }

   void LoadState()
   {
      if(IsOptimizationMode())
         return;

      string prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Buy_";

      if(GlobalVariableCheck(prefix + "active"))
      {
         m_buy_group.active              = (GlobalVariableGet(prefix + "active") == 1.0);
         m_buy_group.entryPrice          = GlobalVariableGet(prefix + "entryPrice");
         m_buy_group.partialDone         = (GlobalVariableGet(prefix + "partialDone") == 1.0);
         m_buy_group.totalVol            = GlobalVariableGet(prefix + "totalVol");
         m_buy_group.virtualSL           = GlobalVariableGet(prefix + "virtualSL");
         m_buy_group.virtualTP           = GlobalVariableGet(prefix + "virtualTP");
         m_buy_group.initial_entry       = GlobalVariableGet(prefix + "initial_entry");
         m_buy_group.open_time           = (datetime)GlobalVariableGet(prefix + "open_time");
         m_buy_group.expiry_time         = (datetime)GlobalVariableGet(prefix + "expiry_time");
         m_buy_group.initial_sl_distance = GlobalVariableGet(prefix + "initial_sl_distance");
         m_buyCooldownEndTime            = (datetime)GlobalVariableGet(prefix + "cooldown_end");
         m_initialATR_buy                = GlobalVariableGet(prefix + "initialATR");
         m_initialEntry_buy              = GlobalVariableGet(prefix + "initialEntry");
         m_lastEntry_buy                 = GlobalVariableGet(prefix + "lastEntry");
      }

      prefix = _Symbol + IntegerToString(m_magic) + "IGM_EA_Sell_";

      if(GlobalVariableCheck(prefix + "active"))
      {
         m_sell_group.active              = (GlobalVariableGet(prefix + "active") == 1.0);
         m_sell_group.entryPrice          = GlobalVariableGet(prefix + "entryPrice");
         m_sell_group.partialDone         = (GlobalVariableGet(prefix + "partialDone") == 1.0);
         m_sell_group.totalVol            = GlobalVariableGet(prefix + "totalVol");
         m_sell_group.virtualSL           = GlobalVariableGet(prefix + "virtualSL");
         m_sell_group.virtualTP           = GlobalVariableGet(prefix + "virtualTP");
         m_sell_group.initial_entry       = GlobalVariableGet(prefix + "initial_entry");
         m_sell_group.open_time           = (datetime)GlobalVariableGet(prefix + "open_time");
         m_sell_group.expiry_time         = (datetime)GlobalVariableGet(prefix + "expiry_time");
         m_sell_group.initial_sl_distance = GlobalVariableGet(prefix + "initial_sl_distance");
         m_sellCooldownEndTime            = (datetime)GlobalVariableGet(prefix + "cooldown_end");
         m_initialATR_sell                = GlobalVariableGet(prefix + "initialATR");
         m_initialEntry_sell              = GlobalVariableGet(prefix + "initialEntry");
         m_lastEntry_sell                 = GlobalVariableGet(prefix + "lastEntry");
      }

      string key;

      key = _Symbol + IntegerToString(m_magic) + "IGM_EA_LastTradeTime";
      if(GlobalVariableCheck(key))
         m_last_trade_time = (datetime)GlobalVariableGet(key);

      key = _Symbol + IntegerToString(m_magic) + "IGM_EA_TargetHit";
      if(GlobalVariableCheck(key))
         m_targetBalanceHit = (GlobalVariableGet(key) == 1.0);
   }

   bool IsNewBar(ENUM_TIMEFRAMES tf,
                 datetime        &last_time)
   {
      datetime time[1];

      if(CopyTime(_Symbol, tf, 0, 1, time) > 0 && time[0] != last_time)
      {
         last_time = time[0];
         return true;
      }

      return false;
   }

   //----------------------------------------------------------------
   // No Trade Zone
   //----------------------------------------------------------------
   bool IsNoTradeZone()
   {
      datetime now_gmt = TimeGMT();
      if(now_gmt == 0)
         return false;

      MqlDateTime ny;
      GetNewYorkTime(now_gmt, ny);

      int current_min = ny.hour * 60 + ny.min;
      int start_min   = NoTradeStartHour * 60 + NoTradeStartMin;
      int end_min     = NoTradeEndHour   * 60 + NoTradeEndMin;

      if(start_min < end_min)
         return (current_min >= start_min && current_min < end_min);
      else
         return (current_min >= start_min || current_min < end_min);
   }

   //----------------------------------------------------------------
   // Risk potentials
   //----------------------------------------------------------------
   double GetBuyTotalPotentialLoss()
   {
      double total_loss = 0.0;

      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(m_buy_group.active && m_buy_group.virtualSL > 0)
      {
         total_loss += m_buy_group.totalVol *
                       (m_buy_group.entryPrice - m_buy_group.virtualSL) *
                       (tick_value / tick_size);
      }

      return total_loss;
   }

   double GetSellTotalPotentialLoss()
   {
      double total_loss = 0.0;

      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(m_sell_group.active && m_sell_group.virtualSL > 0)
      {
         total_loss += m_sell_group.totalVol *
                       (m_sell_group.virtualSL - m_sell_group.entryPrice) *
                       (tick_value / tick_size);
      }

      return total_loss;
   }

   double GetBuyWeightedAvgEntry()
   {
      return (m_buy_group.active ? m_buy_group.entryPrice : 0.0);
   }

   double GetSellWeightedAvgEntry()
   {
      return (m_sell_group.active ? m_sell_group.entryPrice : 0.0);
   }

   //----------------------------------------------------------------
   // Reset helpers
   //----------------------------------------------------------------
   void ResetBuyVars()
   {
      m_initialATR_buy   = 0.0;
      m_initialEntry_buy = 0.0;
      m_lastEntry_buy    = 0.0;
   }

   void ResetSellVars()
   {
      m_initialATR_sell   = 0.0;
      m_initialEntry_sell = 0.0;
      m_lastEntry_sell    = 0.0;
   }

   void ResetBuySequence()
   {
      m_buy_peakR       = 0.0;
      m_buyScaleInCount = 0;
      ResetBuyVars();
   }

   void ResetSellSequence()
   {
      m_sell_peakR       = 0.0;
      m_sellScaleInCount = 0;
      ResetSellVars();
   }
   //----------------------------------------------------------------
   // Main OnTick
   //----------------------------------------------------------------
   void OnTick()
   {
      UpdateCachedTradeStatesOptimized();

      datetime ExpirationDate = D'2026.05.31 23:59:59';
      if(TimeCurrent() > ExpirationDate)
      {
         Print("EA expired. Please contact developer.");
         return;
      }

      datetime now_gmt   = TimeGMT();
      int      tradingKey= GetNYTradingDayKey(now_gmt);

      if(m_day == 0 || tradingKey != m_day)
      {
         m_day     = tradingKey;
         m_startEq = AccountInfoDouble(ACCOUNT_BALANCE);
         m_halted  = false;


         PlotMarketCloseLines();
         if(m_positionsDirty || ArraySize(pos_cache) == 0)
            UpdateCachedTradeStatesOptimized();

         bool hasBuyPos   = HasPosForGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
         int  pendingBuy  = GetPendingCount(m_buy_magic, ORDER_TYPE_BUY_LIMIT);
         bool hasBuyPend  = (pendingBuy > 0);

         if(!hasBuyPos && !hasBuyPend)
         {
            m_buy_group.active = false;
            m_state_changed    = true;
         }
         else
         {
            m_buy_group.active = true;
            m_state_changed    = true;

            if(hasBuyPos)
            {
               m_buy_group.virtualTP = 0.0;
               UpdateGroupStateOptimized(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
            }
         }

         bool hasSellPos   = HasPosForGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
         int  pendingSell  = GetPendingCount(m_sell_magic, ORDER_TYPE_SELL_LIMIT);
         bool hasSellPend  = (pendingSell > 0);

         if(!hasSellPos && !hasSellPend)
         {
            m_sell_group.active = false;
            m_state_changed     = true;
         }
         else
         {
            m_sell_group.active = true;
            m_state_changed     = true;

            if(hasSellPos)
            {
               m_sell_group.virtualTP = 0.0;
               UpdateGroupStateOptimized(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
            }
         }
      }

      m_newsFilter.Update();
      if(m_newsFilter.IsNewsWindowActive())
      {
         m_slOnlyMode = true;
         ManageBuyGroup();
         ManageSellGroup();
         m_slOnlyMode = false;

         SaveIfChanged();
         return;
      }

      if(m_enableDailyClose &&
         m_lastDailyCloseTradingKey != tradingKey &&
         IsDailyCloseWindow(now_gmt))
      {
         if(m_positionsDirty || ArraySize(pos_cache) == 0)
            UpdateCachedTradeStatesOptimized();

         double riskBase = GetCurrentRiskBase();
         double floatingBeforeClose = GetEaFloatingProfit();

         bool hadOpenGroup = false;
         bool leftAnyOpen  = false;
         bool closedAny    = false;

         if(HasAnyBuyPos())
         {
            hadOpenGroup = true;

            double buyProfit = GetBuyFloatingProfit();
            double buyR      = (riskBase > 0.0 ? buyProfit / riskBase : 0.0);

            if(buyR > 0.0)
            {
               LogTradeEvent("BUY",
                             "GROUP_CLOSE_DAILY_TIME",
                             "Daily close window reached; BUY group closed (R > 0)",
                             SymbolInfoDouble(_Symbol, SYMBOL_BID),
                             m_buy_group.totalVol,
                             buyProfit,
                             buyR);

               CloseGroup(m_buy_group, POSITION_TYPE_BUY, m_buy_magic);
               closedAny = true;
            }
            else
            {
               leftAnyOpen = true;

               LogTradeEvent("BUY",
                             "GROUP_SKIP_DAILY_TIME",
                             "Daily close window reached; BUY group kept open (R <= 0)",
                             SymbolInfoDouble(_Symbol, SYMBOL_BID),
                             m_buy_group.totalVol,
                             buyProfit,
                             buyR);
            }
         }

         if(HasAnySellPos())
         {
            hadOpenGroup = true;

            double sellProfit = GetSellFloatingProfit();
            double sellR      = (riskBase > 0.0 ? sellProfit / riskBase : 0.0);

            if(sellR > 0.0)
            {
               LogTradeEvent("SELL",
                             "GROUP_CLOSE_DAILY_TIME",
                             "Daily close window reached; SELL group closed (R > 0)",
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK),
                             m_sell_group.totalVol,
                             sellProfit,
                             sellR);

               CloseGroup(m_sell_group, POSITION_TYPE_SELL, m_sell_magic);
               closedAny = true;
            }
            else
            {
               leftAnyOpen = true;

               LogTradeEvent("SELL",
                             "GROUP_SKIP_DAILY_TIME",
                             "Daily close window reached; SELL group kept open (R <= 0)",
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK),
                             m_sell_group.totalVol,
                             sellProfit,
                             sellR);
            }
         }

         m_lastDailyCloseTradingKey = tradingKey;
         m_state_changed            = true;

         if(hadOpenGroup && !leftAnyOpen)
         {
            m_halted = true;

            LogTradeEvent("GLOBAL",
                          "ALL_CLOSE_DAILY_TIME",
                          "Daily close window reached; all open groups closed in profit",
                          0.0,
                          0.0,
                          floatingBeforeClose,
                          0.0);
         }
         else if(hadOpenGroup && closedAny)
         {
            LogTradeEvent("GLOBAL",
                          "PARTIAL_CLOSE_DAILY_TIME",
                          "Daily close window reached; only profitable groups were closed",
                          0.0,
                          0.0,
                          floatingBeforeClose,
                          0.0);
         }
         else if(hadOpenGroup)
         {
            LogTradeEvent("GLOBAL",
                          "SKIP_CLOSE_DAILY_TIME",
                          "Daily close window reached; no group met R > 0 close condition",
                          0.0,
                          0.0,
                          floatingBeforeClose,
                          0.0);
         }

         SaveIfChanged();
         return;
      }
      if(m_halted || m_globalHalted)
      {
         SaveIfChanged();
         return;
      }

      if(m_enableTargetBalance && m_targetBalanceHit)
      {
         SaveIfChanged();
         return;
      }

      bool is_new_period_bar = IsNewBar(PERIOD_CURRENT, last_bar_time_period);

      if(is_new_period_bar || m_positionsDirty)
         UpdateCachedTradeStatesOptimized();

      if(!HasAnyBuyPos())
         ResetBuySequence();

      if(!HasAnySellPos())
         ResetSellSequence();

      if(is_new_period_bar)
      {
         Strategy_OnBarClose();

         CheckReset();

         if(m_halted || m_globalHalted)
         {
            SaveIfChanged();
            return;
         }
      }

      ManageBuyGroup();
      ManageSellGroup();

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

      CheckPendingExpiry(m_buy_group,  m_buy_magic,  true);
      CheckPendingExpiry(m_sell_group, m_sell_magic, false);

      double atr = GetCachedATR();
      if(atr <= 0.0)
      {
         SaveIfChanged();
         return;
      }

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

      if(m_enableTargetBalance && !m_targetBalanceHit)
      {
         double metric = MathMax(balance, equity);

         if(metric >= m_targetBalance)
         {
            if(m_positionsDirty || ArraySize(pos_cache) == 0)
               UpdateCachedTradeStatesOptimized();

            CloseAllPositions();
            CancelAllPendingByMagic(m_buy_magic);
            CancelAllPendingByMagic(m_sell_magic);

            m_targetBalanceHit = true;
            m_state_changed    = true;

            LogTradeEvent("GLOBAL",
                          "ALL_CLOSE_TARGET_BALANCE",
                          "Account reached target balance",
                          0.0,
                          0.0,
                          metric - m_globalStartEq,
                          0.0);

            SaveIfChanged();
            return;
         }
      }

      double sequenceRiskPct = m_maxTotalRiskPct;
      if(m_enableDynamicRisk)
      {
         double B0 = m_startBalanceInput;
         if(balance < B0)
            sequenceRiskPct = 0.5;
         else if(balance < B0 * 1.02)
            sequenceRiskPct = 1.0;
         else
            sequenceRiskPct = 1.5;
      }

      int dcaParts = (m_dcaParts <= 0 ? 1 : m_dcaParts);

      double dcaPercent = m_dcaSLPercent;
      if(dcaPercent < 0.0) dcaPercent = 0.0;
      if(dcaPercent > 100.0) dcaPercent = 100.0;

      double riskPct_per_entry = sequenceRiskPct / dcaParts;
      double sequenceRiskAmount = balance * (sequenceRiskPct / 100.0);

      double pip_size2   = GetPipValue();
      double tick_value2 = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size2  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pip_value2  = tick_value2 * (pip_size2 / tick_size2);

      double total_sl_distance = atr * m_atrSlMultiplier;
      double offset            = m_initialDCAOffsetATR * atr;

      double dca_span = total_sl_distance * (dcaPercent / 100.0);
      double interval = dca_span / dcaParts;

      double global_max_risk = balance * m_maxTotalRiskPct / 100.0;

      //----------------------------------------------------------------
      // SELL ENTRY (DCA)
      //----------------------------------------------------------------
      bool sellFlipThisBar = (is_new_period_bar && Strategy_SellFlipTriggered());

      if(!m_targetBalanceHit &&
         sellFlipThisBar &&
         !AnySellGroupActive() &&
         !HasAnySellPosRaw() &&
         (m_tradeDirection != TradeBuyOnly) &&
         (m_enableHedge || !HasAnyBuyPosRaw()) &&
         TimeCurrent() >= m_sellCooldownEndTime &&
         GetPendingCount(m_sell_magic, ORDER_TYPE_SELL_LIMIT) == 0 &&
         (TimeCurrent() - m_last_sell_attempt >= 60))
      {
         Strategy_ConsumeSellFlip();
         m_last_sell_attempt = TimeCurrent();

         double current_risk         = GetBuyTotalPotentialLoss();
         double actual_proposed_risk = 0.0;

         double lot_parts[];
         ArrayResize(lot_parts, dcaParts);

         bool   valid     = true;
         double totalLots = 0.0;

         // GRID-LEVEL margin budget (prevents total pending grid from exceeding cap)
         double remainingMarginBudget = GetRemainingMarginBudgetForCap();

         double baseAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         for(int k = 0; k < dcaParts; k++)
         {
            double effective_dist_k = total_sl_distance - k * interval;
            double effective_pips_k = effective_dist_k / pip_size2;

            if(effective_pips_k <= 0.0)
            {
               valid = false;
               break;
            }

            double proposed = CalcLotSize(riskPct_per_entry, effective_pips_k);

            ENUM_ORDER_TYPE dir         = ORDER_TYPE_SELL;
            double          limit_price = baseAsk + offset + k * interval;

            double maxVol = GetMaxVolumeForMarginCap(dir, limit_price, "SELL", "DCA_LIMIT", remainingMarginBudget);
            double actual = MathMin(proposed, maxVol);
            actual        = NormalizeLot(actual);

            double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

            if(actual >= minL && remainingMarginBudget > 0.0)
            {
               // consume margin budget
               double mNeed = 0.0;
               if(!CalcOrderMargin(dir, _Symbol, actual, limit_price, mNeed))
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               if(mNeed > remainingMarginBudget)
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               remainingMarginBudget -= mNeed;
               if(remainingMarginBudget < 0.0) remainingMarginBudget = 0.0;

               lot_parts[k]         = actual;
               totalLots           += actual;
               actual_proposed_risk += actual * effective_pips_k * pip_value2;

               if(actual < proposed)
                  LogMarginVolumeReduced("SELL", proposed, actual, limit_price, "DCA");
            }
            else
            {
               lot_parts[k] = 0.0;
            }
         }

         if(!valid)
         {
            double current_ask_log = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            LogTradeEvent("SELL",
                          "ENTRY_SKIP_SELL_DCA_INVALID",
                          "SELL DCA grid invalid (non-positive effective distance or lot).",
                          current_ask_log,
                          0.0,
                          0.0,
                          0.0);

            SaveIfChanged();
            return;
         }

         double allowedRisk_sell = global_max_risk - current_risk;
         if(allowedRisk_sell <= 0.0)
         {
            string reason = StringFormat(
               "SELL DCA blocked: no remaining global risk capacity (current=%.2f, cap=%.2f)",
               current_risk,
               global_max_risk
            );

            double current_ask_log2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            LogTradeEvent("SELL",
                          "ENTRY_SKIP_SELL_GLOBAL_RISK",
                          reason,
                          current_ask_log2,
                          0.0,
                          0.0,
                          0.0);

            SaveIfChanged();
            return;
         }

         if(actual_proposed_risk > allowedRisk_sell)
         {
            double scale = allowedRisk_sell / actual_proposed_risk;
            if(scale <= 0.0)
            {
               string reason = StringFormat(
                  "SELL DCA blocked: global risk cap too tight to allocate any risk (current=%.2f, cap=%.2f)",
                  current_risk,
                  global_max_risk
               );

               double current_ask_log3 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

               LogTradeEvent("SELL",
                             "ENTRY_SKIP_SELL_GLOBAL_RISK",
                             reason,
                             current_ask_log3,
                             0.0,
                             0.0,
                             0.0);

               SaveIfChanged();
               return;
            }

            double minLot          = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double scaledRisk      = 0.0;
            double scaledTotalLots = 0.0;

            for(int k = 0; k < dcaParts; k++)
            {
               if(lot_parts[k] <= 0.0)
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               double scaledVol = NormalizeLot(lot_parts[k] * scale);
               if(scaledVol < minLot)
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               lot_parts[k] = scaledVol;

               double effective_dist_k = total_sl_distance - k * interval;
               double effective_pips_k = effective_dist_k / pip_size2;

               if(effective_pips_k <= 0.0)
                  continue;

               scaledTotalLots += scaledVol;
               scaledRisk      += scaledVol * effective_pips_k * pip_value2;
            }

            actual_proposed_risk = scaledRisk;
            totalLots            = scaledTotalLots;

            if(actual_proposed_risk <= 0.0 || totalLots <= 0.0)
            {
               string reason = StringFormat(
                  "SELL DCA blocked: after risk scaling no valid volume remains (current=%.2f, cap=%.2f)",
                  current_risk,
                  global_max_risk
               );

               double current_ask_log4 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

               LogTradeEvent("SELL",
                             "ENTRY_SKIP_SELL_GLOBAL_RISK",
                             reason,
                             current_ask_log4,
                             0.0,
                             0.0,
                             0.0);

               SaveIfChanged();
               return;
            }

            double riskAfterScale   = current_risk + actual_proposed_risk;
            double current_ask_log5 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            string infoScale = StringFormat(
               "SELL DCA risk scaled to fit cap: scale=%.4f, current=%.2f, new_total=%.2f, cap=%.2f",
               scale,
               current_risk,
               riskAfterScale,
               global_max_risk
            );

            LogTradeEvent("SELL",
                          "DCA_RISK_SCALED",
                          infoScale,
                          current_ask_log5,
                          totalLots,
                          0.0,
                          0.0);
         }

         double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl_price    = current_ask + offset + total_sl_distance;

         bool all_placed = true;

         for(int k = 0; k < dcaParts; k++)
         {
            if(lot_parts[k] <= 0.0) continue;

            double limit_price = current_ask + offset + k * interval;

            if(!PlaceLimitOrder(ORDER_TYPE_SELL_LIMIT,
                                lot_parts[k],
                                limit_price,
                                sl_price,
                                m_sell_magic))
            {
               all_placed = false;
            }
         }

         ResetTradeGroup(m_sell_group);

         m_sell_group.active              = true;
         m_sell_group.open_time           = 0;
         m_sell_group.expiry_time         = TimeCurrent() + m_pendingExpiryCandles * PeriodSeconds(PERIOD_CURRENT);
         m_sell_group.initial_sl_distance = total_sl_distance;
         m_sell_group.virtualSL           = sl_price;

         m_state_changed = true;

         m_initialATR_sell   = atr;
         m_initialEntry_sell = current_ask + offset;
         m_lastEntry_sell    = current_ask + offset;

         LogTradeEvent("SELL",
                       "DCA_ENTRY",
                       "New SELL DCA grid created",
                       current_ask,
                       totalLots,
                       0.0,
                       0.0);

         if(!all_placed)
         {
            LogTradeEvent("SELL",
                          "DCA_ENTRY_PARTIAL",
                          "Not all SELL limit orders placed",
                          current_ask,
                          totalLots);
         }

         SaveIfChanged();
         return;
      }
      else if(sellFlipThisBar)
      {
         bool cond_targetOK      = !m_targetBalanceHit;
         bool cond_groupFlat     = !AnySellGroupActive();
         bool cond_noSellPos     = !HasAnySellPosRaw();
         bool cond_dirOK         = (m_tradeDirection != TradeBuyOnly);
         bool cond_hedgeOK       = (m_enableHedge || !HasAnyBuyPosRaw());
         bool cond_cooldownOK    = (TimeCurrent() >= m_sellCooldownEndTime);
         int  pendingSell        = GetPendingCount(m_sell_magic, ORDER_TYPE_SELL_LIMIT);
         bool cond_noPendings    = (pendingSell == 0);
         bool cond_attemptOK     = (TimeCurrent() - m_last_sell_attempt >= 60);

         string reason = StringFormat(
            "SELL flip arrow but entry blocked: targetOK=%s, groupFlat=%s, noSellPos=%s, dirOK=%s, hedgeOK=%s, cooldownOK=%s, noPendings=%s, attemptCooldownOK=%s, pendings=%d",
            (cond_targetOK    ? "true" : "false"),
            (cond_groupFlat   ? "true" : "false"),
            (cond_noSellPos   ? "true" : "false"),
            (cond_dirOK       ? "true" : "false"),
            (cond_hedgeOK     ? "true" : "false"),
            (cond_cooldownOK  ? "true" : "false"),
            (cond_noPendings  ? "true" : "false"),
            (cond_attemptOK   ? "true" : "false"),
            pendingSell
         );

         double current_ask_log = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         LogTradeEvent("SELL",
                       "ENTRY_SKIP_SELL_GATES",
                       reason,
                       current_ask_log,
                       0.0,
                       0.0,
                       0.0);
      }

      //----------------------------------------------------------------
      // BUY ENTRY (DCA)
      //----------------------------------------------------------------
      bool buyFlipThisBar = (is_new_period_bar && Strategy_BuyFlipTriggered());

      if(!m_targetBalanceHit &&
         buyFlipThisBar &&
         !AnyBuyGroupActive() &&
         !HasAnyBuyPosRaw() &&
         (m_tradeDirection != TradeSellOnly) &&
         (m_enableHedge || !HasAnySellPosRaw()) &&
         TimeCurrent() >= m_buyCooldownEndTime &&
         GetPendingCount(m_buy_magic, ORDER_TYPE_BUY_LIMIT) == 0 &&
         (TimeCurrent() - m_last_buy_attempt >= 60))
      {
         Strategy_ConsumeBuyFlip();
         m_last_buy_attempt = TimeCurrent();

         double current_risk         = GetSellTotalPotentialLoss();
         double actual_proposed_risk = 0.0;

         double lot_parts[];
         ArrayResize(lot_parts, dcaParts);

         bool   valid     = true;
         double totalLots = 0.0;

         // GRID-LEVEL margin budget
         double remainingMarginBudget = GetRemainingMarginBudgetForCap();

         double baseBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         for(int k = 0; k < dcaParts; k++)
         {
            double effective_dist_k = total_sl_distance - k * interval;
            double effective_pips_k = effective_dist_k / pip_size2;

            if(effective_pips_k <= 0)
            {
               valid = false;
               break;
            }

            double proposed = CalcLotSize(riskPct_per_entry, effective_pips_k);

            ENUM_ORDER_TYPE dir         = ORDER_TYPE_BUY;
            double          limit_price = baseBid - offset - k * interval;

            double maxVol = GetMaxVolumeForMarginCap(dir, limit_price, "BUY", "DCA_LIMIT", remainingMarginBudget);
            double actual = MathMin(proposed, maxVol);
            actual        = NormalizeLot(actual);

            double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

            if(actual >= minL && remainingMarginBudget > 0.0)
            {
               double mNeed = 0.0;
               if(!CalcOrderMargin(dir, _Symbol, actual, limit_price, mNeed))
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               if(mNeed > remainingMarginBudget)
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               remainingMarginBudget -= mNeed;
               if(remainingMarginBudget < 0.0) remainingMarginBudget = 0.0;

               lot_parts[k]         = actual;
               totalLots           += actual;
               actual_proposed_risk += actual * effective_pips_k * pip_value2;

               if(actual < proposed)
                  LogMarginVolumeReduced("BUY", proposed, actual, limit_price, "DCA");
            }
            else
            {
               lot_parts[k] = 0.0;
            }
         }

         if(!valid)
         {
            double current_bid_log = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            LogTradeEvent("BUY",
                          "ENTRY_SKIP_BUY_DCA_INVALID",
                          "BUY DCA grid invalid (non-positive effective distance or lot).",
                          current_bid_log,
                          0.0,
                          0.0,
                          0.0);

            SaveIfChanged();
            return;
         }

         double allowedRisk_buy = global_max_risk - current_risk;
         if(allowedRisk_buy <= 0.0)
         {
            string reason = StringFormat(
               "BUY DCA blocked: no remaining global risk capacity (current=%.2f, cap=%.2f)",
               current_risk,
               global_max_risk
            );

            double current_bid_log2 = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            LogTradeEvent("BUY",
                          "ENTRY_SKIP_BUY_GLOBAL_RISK",
                          reason,
                          current_bid_log2,
                          0.0,
                          0.0,
                          0.0);

            SaveIfChanged();
            return;
         }

         if(actual_proposed_risk > allowedRisk_buy)
         {
            double scale = allowedRisk_buy / actual_proposed_risk;
            if(scale <= 0.0)
            {
               string reason = StringFormat(
                  "BUY DCA blocked: global risk cap too tight to allocate any risk (current=%.2f, cap=%.2f)",
                  current_risk,
                  global_max_risk
               );

               double current_bid_log3 = SymbolInfoDouble(_Symbol, SYMBOL_BID);

               LogTradeEvent("BUY",
                             "ENTRY_SKIP_BUY_GLOBAL_RISK",
                             reason,
                             current_bid_log3,
                             0.0,
                             0.0,
                             0.0);

               SaveIfChanged();
               return;
            }

            double minLot          = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double scaledRisk      = 0.0;
            double scaledTotalLots = 0.0;

            for(int k = 0; k < dcaParts; k++)
            {
               if(lot_parts[k] <= 0.0)
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               double scaledVol = NormalizeLot(lot_parts[k] * scale);
               if(scaledVol < minLot)
               {
                  lot_parts[k] = 0.0;
                  continue;
               }

               lot_parts[k] = scaledVol;

               double effective_dist_k = total_sl_distance - k * interval;
               double effective_pips_k = effective_dist_k / pip_size2;

               if(effective_pips_k <= 0.0)
                  continue;

               scaledTotalLots += scaledVol;
               scaledRisk      += scaledVol * effective_pips_k * pip_value2;
            }

            actual_proposed_risk = scaledRisk;
            totalLots            = scaledTotalLots;

            if(actual_proposed_risk <= 0.0 || totalLots <= 0.0)
            {
               string reason = StringFormat(
                  "BUY DCA blocked: after risk scaling no valid volume remains (current=%.2f, cap=%.2f)",
                  current_risk,
                  global_max_risk
               );

               double current_bid_log4 = SymbolInfoDouble(_Symbol, SYMBOL_BID);

               LogTradeEvent("BUY",
                             "ENTRY_SKIP_BUY_GLOBAL_RISK",
                             reason,
                             current_bid_log4,
                             0.0,
                             0.0,
                             0.0);

               SaveIfChanged();
               return;
            }

            double riskAfterScale   = current_risk + actual_proposed_risk;
            double current_bid_log5 = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            string infoScale = StringFormat(
               "BUY DCA risk scaled to fit cap: scale=%.4f, current=%.2f, new_total=%.2f, cap=%.2f",
               scale,
               current_risk,
               riskAfterScale,
               global_max_risk
            );

            LogTradeEvent("BUY",
                          "DCA_RISK_SCALED",
                          infoScale,
                          current_bid_log5,
                          totalLots,
                          0.0,
                          0.0);
         }

         double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl_price    = current_bid - offset - total_sl_distance;

         bool all_placed = true;

         for(int k = 0; k < dcaParts; k++)
         {
            if(lot_parts[k] <= 0.0) continue;

            double limit_price = current_bid - offset - k * interval;

            if(!PlaceLimitOrder(ORDER_TYPE_BUY_LIMIT,
                                lot_parts[k],
                                limit_price,
                                sl_price,
                                m_buy_magic))
            {
               all_placed = false;
            }
         }

         ResetTradeGroup(m_buy_group);

         m_buy_group.active              = true;
         m_buy_group.open_time           = 0;
         m_buy_group.expiry_time         = TimeCurrent() + m_pendingExpiryCandles * PeriodSeconds(PERIOD_CURRENT);
         m_buy_group.initial_sl_distance = total_sl_distance;
         m_buy_group.virtualSL           = sl_price;

         m_state_changed = true;

         m_initialATR_buy   = atr;
         m_initialEntry_buy = current_bid - offset;
         m_lastEntry_buy    = current_bid - offset;

         LogTradeEvent("BUY",
                       "DCA_ENTRY",
                       "New BUY DCA grid created",
                       current_bid,
                       totalLots,
                       0.0,
                       0.0);

         if(!all_placed)
         {
            LogTradeEvent("BUY",
                          "DCA_ENTRY_PARTIAL",
                          "Not all BUY limit orders placed",
                          current_bid,
                          totalLots);
         }

         SaveIfChanged();
         return;
      }
      else if(buyFlipThisBar)
      {
         bool cond_targetOK     = !m_targetBalanceHit;
         bool cond_groupFlat    = !AnyBuyGroupActive();
         bool cond_noBuyPos     = !HasAnyBuyPosRaw();
         bool cond_dirOK        = (m_tradeDirection != TradeSellOnly);
         bool cond_hedgeOK      = (m_enableHedge || !HasAnySellPosRaw());
         bool cond_cooldownOK   = (TimeCurrent() >= m_buyCooldownEndTime);
         int  pendingBuy        = GetPendingCount(m_buy_magic, ORDER_TYPE_BUY_LIMIT);
         bool cond_noPendings   = (pendingBuy == 0);
         bool cond_attemptOK    = (TimeCurrent() - m_last_buy_attempt >= 60);

         string reason = StringFormat(
            "BUY flip arrow but entry blocked: targetOK=%s, groupFlat=%s, noBuyPos=%s, dirOK=%s, hedgeOK=%s, cooldownOK=%s, noPendings=%s, attemptCooldownOK=%s, pendings=%d",
            (cond_targetOK    ? "true" : "false"),
            (cond_groupFlat   ? "true" : "false"),
            (cond_noBuyPos    ? "true" : "false"),
            (cond_dirOK       ? "true" : "false"),
            (cond_hedgeOK     ? "true" : "false"),
            (cond_cooldownOK  ? "true" : "false"),
            (cond_noPendings  ? "true" : "false"),
            (cond_attemptOK   ? "true" : "false"),
            pendingBuy
         );

         double current_bid_log = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         LogTradeEvent("BUY",
                       "ENTRY_SKIP_BUY_GATES",
                       reason,
                       current_bid_log,
                       0.0,
                       0.0,
                       0.0);
      }

      // SCALE-IN MANAGEMENT
      ManageBuyScaleIn();
      ManageSellScaleIn();

      SaveIfChanged();
   }
};
//+------------------------------------------------------------------+















