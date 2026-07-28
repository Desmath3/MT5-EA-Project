//+------------------------------------------------------------------+
//| BB MartingaleEA.mq5 |
//| Copyright 2025, [Your Name] |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#define PIP_SIZE (_Point * 10)
// Input Parameters
input double InitialLotSize = 0.01;
input double LotMultiplier = 2.0;
input int MaxMartingaleSteps = 5;
input int MartingalePips = 10;
input int BaseTP_Pips = 20;
input bool UseDailyReset = true;
input double MaxDailyDrawdownPct = 1.0;
input double TargetProfitPct = 2.0; // In percent. If total profit reaches this %, close all. Set to 0 to disable.
input long EA_MagicNumber = 123456;
input int BasketThreshold = 3; // Steps above which to start new basket
input int MaxBaskets = 10; // Maximum number of baskets (backtestable parameter)
input int TimeToNewBasketDays = 2; // Days without new trade to start new basket
// Bollinger Bands (entry logic)
input int BB_Period = 100;
input double BB_Deviation = 2.0;
// Robustness Parameters
input double MaxGlobalDrawdownPct = 20.0;
input int Slippage = 3;
// Expanding Grid Parameter
input bool UseExpandingGrid = true; // If true, martingale add threshold expands with step (e.g., 10 pips for first, 20 for second, etc.)
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
   int m_bb;
   CTrade m_trade;
   // Global start equity
   double m_globalStartEq;
   // Cached indicator values
   double m_upper[3], m_middle[3], m_lower[3], m_close[3];
   datetime m_last_bar_time;
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
      if(m_trade.PositionOpen(_Symbol, orderType, volume, 0, 0, "BB Martingale"))
      {
         Print("Order opened: ", EnumToString(orderType), " volume: ", volume, " price: ", price, " magic:", magic);
         m_last_trade_time = TimeCurrent();
         return true;
      }
      else
      {
         Print("Failed to open order: ", m_trade.ResultRetcode(), ", ", m_trade.ResultRetcodeDescription());
         return false;
      }
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
         group.virtualTP = NormalizeDouble(newAvgEntry + dir * (m_tpPips + extra_pips) * PIP_SIZE, _Digits);
         if(group.initial_entry == 0.0)
         {
            group.initial_entry = newAvgEntry;
         }
         Print(EnumToString(posType), " group updated: New average entry = ", newAvgEntry, ", New TP = ", group.virtualTP, " (extra pips: ", extra_pips, ")");
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
         prefix = _Symbol + IntegerToString(m_magic) + "BBMart_EA_Buy" + IntegerToString(i) + "_";
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
         prefix = _Symbol + IntegerToString(m_magic) + "BBMart_EA_Sell" + IntegerToString(i) + "_";
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
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "BBMart_EA_LastTradeTime", (double)m_last_trade_time);
      GlobalVariableSet(_Symbol + IntegerToString(m_magic) + "BBMart_EA_TradeMode", (double)m_trade_mode);
   }
   void LoadState()
   {
      const int max_saved_magics = 32;
      string prefix;
      for(int i = 0; i < m_maxBaskets; i++)
      {
         prefix = _Symbol + IntegerToString(m_magic) + "BBMart_EA_Buy" + IntegerToString(i) + "_";
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
         prefix = _Symbol + IntegerToString(m_magic) + "BBMart_EA_Sell" + IntegerToString(i) + "_";
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
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "BBMart_EA_LastTradeTime"))
      {
         m_last_trade_time = (datetime)GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "BBMart_EA_LastTradeTime");
      }
      else
      {
         m_last_trade_time = 0;
      }
      if(GlobalVariableCheck(_Symbol + IntegerToString(m_magic) + "BBMart_EA_TradeMode"))
      {
         m_trade_mode = (int)GlobalVariableGet(_Symbol + IntegerToString(m_magic) + "BBMart_EA_TradeMode");
      }
      else
      {
         m_trade_mode = 0;
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
      m_day = 0;
      m_startEq = 0.0;
      m_halted = false;
      m_globalHalted = false;
      m_last_bar_time = 0;
      m_last_trade_time = 0;
      m_trade_mode = 0;
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
      int bars = Bars(_Symbol, _Period);
      if(bars < BB_Period + 3)
      {
         Print("Insufficient historical bars for indicators.");
         return(INIT_FAILED);
      }
      m_bb = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
      if(m_bb == INVALID_HANDLE)
      {
         Print("Failed to create Bollinger Bands indicator");
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
      return(INIT_SUCCEEDED);
   }
   void OnDeinit(const int reason)
   {
      if(m_bb != INVALID_HANDLE)
      {
         IndicatorRelease(m_bb);
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
            }
            else
            {
               Print("Buy basket ", i, " found. Re-activating for management.");
               m_buy_baskets[i].active = true;
               m_buy_baskets[i].virtualTP = 0.0;
               UpdateGroupState(m_buy_baskets[i], POSITION_TYPE_BUY);
            }
            if(!HasPosForGroup(m_sell_baskets[i], POSITION_TYPE_SELL))
            {
               m_sell_baskets[i].active = false;
            }
            else
            {
               Print("Sell basket ", i, " found. Re-activating for management.");
               m_sell_baskets[i].active = true;
               m_sell_baskets[i].virtualTP = 0.0;
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
      bool is_new_bar = false;
      datetime time[1];
      if(CopyTime(_Symbol, _Period, 0, 1, time) > 0 && time[0] != m_last_bar_time)
      {
         m_last_bar_time = time[0];
         is_new_bar = true;
      }
      if(is_new_bar)
      {
         if(CopyBuffer(m_bb, 1, 0, 3, m_upper) < 3 || CopyBuffer(m_bb, 0, 0, 3, m_middle) < 3 || CopyBuffer(m_bb, 2, 0, 3, m_lower) < 3)
         {
            Print("Failed to copy indicator buffers");
            return;
         }
         if(CopyClose(_Symbol, _Period, 0, 3, m_close) < 3)
         {
            Print("Failed to copy close prices");
            return;
         }
         if(m_close[1] > m_upper[1])
         {
            if(m_trade_mode != 1)
            {
               Print("Bar closed above Upper BB. Switching to BUYS ONLY mode.");
               m_trade_mode = 1;
            }
         }
         else if(m_close[1] < m_lower[1])
         {
            if(m_trade_mode != -1)
            {
               Print("Bar closed below Lower BB. Switching to SELLS ONLY mode.");
               m_trade_mode = -1;
            }
         }
         double dynLot = (m_riskPct > 0.0) ? CalcLotSize(m_riskPct, m_tpPips) : m_initLot;
         dynLot = NormalizeLot(dynLot);
         // --- SELL ENTRY LOGIC ---
         if(m_trade_mode == -1 && !AnySellBasketActive() && !HasAnySellPos())
         {
            if(OpenOrder(ORDER_TYPE_SELL, dynLot, m_sell_magics[0]))
            {
               ResetTradeGroup(m_sell_baskets[0], m_sell_magics[0]);
               m_sell_baskets[0].active = true;
               m_sell_baskets[0].step = 1;
               m_sell_baskets[0].baseLot = dynLot;
               m_sell_baskets[0].last_trade_time = TimeCurrent();
               Print("SELL signal: Current candle closed below lower band");
               return;
            }
         }
         // --- BUY ENTRY LOGIC ---
         if(m_trade_mode == 1 && !AnyBuyBasketActive() && !HasAnyBuyPos())
         {
            if(OpenOrder(ORDER_TYPE_BUY, dynLot, m_buy_magics[0]))
            {
               ResetTradeGroup(m_buy_baskets[0], m_buy_magics[0]);
               m_buy_baskets[0].active = true;
               m_buy_baskets[0].step = 1;
               m_buy_baskets[0].baseLot = dynLot;
               m_buy_baskets[0].last_trade_time = TimeCurrent();
               Print("BUY signal: Current candle closed above upper band");
               return;
            }
         }
      }
      ManageBuyBaskets();
      ManageSellBaskets();
      if(m_trade_mode == 1)
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
                     Print("Started new buy basket ", next);
                     added = true;
                     return;
                  }
               }
               if(m_buy_baskets[i].step < m_maxSteps)
               {
                  double vol = NormalizeLot(m_buy_baskets[i].baseLot * MathPow(m_lotMult, m_buy_baskets[i].step));
                  if(OpenOrder(ORDER_TYPE_BUY, vol, m_buy_magics[i]))
                  {
                     m_buy_baskets[i].step++;
                     m_buy_baskets[i].last_trade_time = TimeCurrent();
                     Print("BUY martingale step ", m_buy_baskets[i].step, " triggered for basket ", i, " at threshold ", threshold / PIP_SIZE, " pips");
                     added = true;
                     return;
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
            }
         }
      }
      if(m_trade_mode == -1)
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
                     Print("Started new sell basket ", next);
                     added = true;
                     return;
                  }
               }
               if(m_sell_baskets[i].step < m_maxSteps)
               {
                  double vol = NormalizeLot(m_sell_baskets[i].baseLot * MathPow(m_lotMult, m_sell_baskets[i].step));
                  if(OpenOrder(ORDER_TYPE_SELL, vol, m_sell_magics[i]))
                  {
                     m_sell_baskets[i].step++;
                     m_sell_baskets[i].last_trade_time = TimeCurrent();
                     Print("SELL martingale step ", m_sell_baskets[i].step, " triggered for basket ", i, " at threshold ", threshold / PIP_SIZE, " pips");
                     added = true;
                     return;
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
            if(preferred_type == ORDER_TYPE_BUY && m_trade_mode == 1)
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
                     Print("Time-based trigger: Started new buy basket ", next);
                     return;
                  }
               }
            }
            else if(preferred_type == ORDER_TYPE_SELL && m_trade_mode == -1)
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
                     Print("Time-based trigger: Started new sell basket ", next);
                     return;
                  }
               }
            }
         }
      }
      CheckBuyMerges();
      CheckSellMerges();
      SaveState();
   }
};
// --- EA Instance and Functions ---
CBBMartingaleEA ea;
int OnInit()
{
   return ea.OnInit();
}
void OnDeinit(const int reason)
{
   ea.OnDeinit(reason);
}
void OnTick()
{
   ea.OnTick();
}
//+------------------------------------------------------------------+