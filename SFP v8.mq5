//+------------------------------------------------------------------+
//|                                                  SFP_EA.mq5      |
//| Swing Failure Pattern EA with Advanced Trade Management          |
//| (ATR risk, breakeven, reversal exit, BB Trend & MA Ribbon        |
//|  filters, session filtering, and configurable support/resistance |
//|  count)                                                          |
//|         © Your Name – Licensed under CC BY-NC-SA 4.0             |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--------------------------------------------------------------------
// Session Filter Inputs
//--------------------------------------------------------------------
input bool TradeNewYork = true;     // Trade during New York session
input bool TradeLondon  = true;     // Trade during London session
input bool TradeTokyo   = false;    // Trade during Tokyo session
input bool TradeSydney  = false;    // Trade during Sydney session

//--------------------------------------------------------------------
// SFP Settings
//--------------------------------------------------------------------
input int LeftBars         = 15;    // Bars to left for pivot detection
input int RightBars        = 15;    // Bars to right for pivot detection
input int RetraceCandles   = 3;     // Max bars after breakout for retrace
input int PivotLevelsCount = 3;     // Number of support/resistance levels
input int MaxTradesPerLevel = 2;    // Max trades per level

//--------------------------------------------------------------------
// Basic Risk Management & Trade Settings
//--------------------------------------------------------------------
input int      ATR_Period         = 14;     // ATR period for stop loss
input double   ATR_SL_Multiplier  = 2.0;    // ATR multiplier for stop loss
input double   RiskRewardRatio    = 10.0;   // Risk-reward ratio for TP
input double   FixedRiskPerTrade  = 50.0;   // Fixed risk amount per trade
input bool     UsePercentRisk     = false;  // Use percentage risk instead
input double   RiskPercentage     = 1.0;    // Risk percentage if enabled
input int      AllowedSlippage    = 3;      // Slippage allowance in points
input int      BrokerGMTOffset    = 0;      // Broker's GMT offset
input bool     UseDailyBias       = false;  // Use daily bias (not implemented)
input int      MaxTradesPerDay    = 2;      // Max trades per day
input ulong    EA_MagicNumber     = 123456; // EA magic number

//--------------------------------------------------------------------
// Additional Trade Management Settings
//--------------------------------------------------------------------
input bool     EnableBreakeven    = true;   // Enable breakeven adjustment
input double   BreakevenReward    = 1.0;    // Reward ratio for breakeven
input double   BreakevenTriggerReward = 2.0;    // Reward ratio to trigger breakeven
input int      LookbackHighLow    = 14;     // Bars for reversal exit check
input bool     EnableReversalExit = true;   // Enable reversal exit

//--------------------------------------------------------------------
// Additional Filters: BB Trend & MA Ribbon
//--------------------------------------------------------------------
input bool     EnableBBTrendFilter  = true;         // Enable BB trend filter
input int      BB_Period            = 100;          // BB period
input double   BB_Deviation         = 2.0;          // BB deviation

input bool     EnableMARibbonFilter = true;         // Enable MA ribbon filter
input ENUM_MA_METHOD MA_Method      = MODE_EMA;     // MA method
input int      MA_StartPeriod       = 100;          // Starting MA period
input int      MA_PeriodStep        = 20;           // MA period increment
#define NUM_MA 6                                    // Number of MAs in ribbon

//--------------------------------------------------------------------
// Global Variables for SFP
//--------------------------------------------------------------------
int ATR_Handle; // Handle for ATR indicator

// Structure to hold level price and trade count
struct LevelInfo {
   double level;      // Price level
   int    tradeCount; // Number of trades from this level
};
LevelInfo ResistanceLevels[]; // Array of resistance levels
LevelInfo SupportLevels[];    // Array of support levels

// Structure for breakout events
struct BreakoutEvent {
   double   level;       // Pivot level at breakout
   int      barCount;    // Bars since breakout
   datetime startTime;   // Time of breakout
};
BreakoutEvent BreakoutSellEvents[]; // Sell breakout events
BreakoutEvent BreakoutBuyEvents[];  // Buy breakout events

int      TradesToday    = 0;        // Trades opened today
int      LastTradeDay   = 0;        // Last trading day
datetime LastBarTime    = 0;        // Time of last processed bar

CTrade Trade; // Trade management object

//--------------------------------------------------------------------
// Global Variables for Additional Filters
//--------------------------------------------------------------------
int BBHandle;          // Bollinger Bands indicator handle
int MAHandles[NUM_MA]; // MA indicator handles
int BBTrend = 0;       // BB trend: 0=undefined, 1=long, -1=short

ulong BreakevenAdjustedTickets[]; // Tickets that have had breakeven adjusted

//--------------------------------------------------------------------
// Session Filter Function
//--------------------------------------------------------------------
bool IsWithinSessionNew() {
   // Get current GMT time
   datetime currentTime = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   int curTimeInMinutes = dt.hour * 60 + dt.min;
   
   bool inSession = false;
   // New York: 12:00 - 21:00 GMT
   if (TradeNewYork && curTimeInMinutes >= 12 * 60 && curTimeInMinutes < 21 * 60)
      inSession = true;
   // London: 07:00 - 12:00 GMT
   if (TradeLondon && curTimeInMinutes >= 7 * 60 && curTimeInMinutes < 12 * 60)
      inSession = true;
   // Tokyo: 00:00 - 07:00 GMT
   if (TradeTokyo && curTimeInMinutes >= 0 && curTimeInMinutes < 7 * 60)
      inSession = true;
   // Sydney: 22:00 - 00:00 GMT (spans midnight)
   if (TradeSydney && (curTimeInMinutes >= 22 * 60 || curTimeInMinutes < 0))
      inSession = true;
   
   return inSession;
}

//--------------------------------------------------------------------
// Helper Functions: Insert Breakout Events
//--------------------------------------------------------------------
void InsertBreakoutSellEvent(const BreakoutEvent &evt) {
   int size = ArraySize(BreakoutSellEvents);
   ArrayResize(BreakoutSellEvents, size + 1);
   for (int i = size; i > 0; i--)
      BreakoutSellEvents[i] = BreakoutSellEvents[i - 1];
   BreakoutSellEvents[0] = evt;
}

void InsertBreakoutBuyEvent(const BreakoutEvent &evt) {
   int size = ArraySize(BreakoutBuyEvents);
   ArrayResize(BreakoutBuyEvents, size + 1);
   for (int i = size; i > 0; i--)
      BreakoutBuyEvents[i] = BreakoutBuyEvents[i - 1];
   BreakoutBuyEvents[0] = evt;
}

//--------------------------------------------------------------------
// Pivot Detection Functions
//--------------------------------------------------------------------
bool IsPivotHigh(int idx) {
   if (idx < RightBars)
      return false;
   double pivot = iHigh(_Symbol, _Period, idx);
   // Look right (smaller indices) and left (larger indices)
   for (int i = idx + LeftBars; i >= idx - RightBars; i--) {
      if (i == idx)
         continue;
      if (i < 0 || i >= Bars(_Symbol, _Period))
         continue;
      if (iHigh(_Symbol, _Period, i) > pivot)
         return false;
   }
   return true;
}

bool IsPivotLow(int idx) {
   if (idx < RightBars)
      return false;
   double pivot = iLow(_Symbol, _Period, idx);
   // Check bars to the right (more recent bars - smaller indices)
   for (int i = idx - RightBars; i < idx; i++) {
      if (i < 0 || i >= Bars(_Symbol, _Period))
         continue;
      if (iLow(_Symbol, _Period, i) < pivot)
         return false;
   }
   // Check bars to the left (older bars - larger indices)
   for (int i = idx + 1; i <= idx + LeftBars; i++) {
      if (i < 0 || i >= Bars(_Symbol, _Period))
         continue;
      if (iLow(_Symbol, _Period, i) < pivot)
         return false;
   }
   return true;
}

//--------------------------------------------------------------------
// Update Pivot Levels & Plot Lines
//--------------------------------------------------------------------
void UpdatePivotLevels() {
   int idx = RightBars; // Pivot confirmed at this bar
   int periodSeconds = Period() * 60;
   datetime pivotTime = iTime(_Symbol, _Period, idx);
   datetime endTime = pivotTime + (RightBars) * periodSeconds;

   if (IsPivotHigh(idx)) {
      LevelInfo newLevel;
      newLevel.level = iHigh(_Symbol, _Period, idx);
      newLevel.tradeCount = 0;
      int n = ArraySize(ResistanceLevels);
      if (n >= PivotLevelsCount) {
         for (int i = n - 1; i > 0; i--)
            ResistanceLevels[i] = ResistanceLevels[i - 1];
         ResistanceLevels[0] = newLevel;
      } else {
         ArrayResize(ResistanceLevels, n + 1);
         ResistanceLevels[n] = newLevel;
      }
      string name = "Resistance_" + IntegerToString(pivotTime);
      if (!ObjectCreate(0, name, OBJ_TREND, 0, pivotTime, newLevel.level, endTime, newLevel.level))
         Print("Failed to create resistance trendline");
      else
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
   }

   if (IsPivotLow(idx)) {
      LevelInfo newLevel;
      newLevel.level = iLow(_Symbol, _Period, idx);
      newLevel.tradeCount = 0;
      int n = ArraySize(SupportLevels);
      if (n >= PivotLevelsCount) {
         for (int i = n - 1; i > 0; i--)
            SupportLevels[i] = SupportLevels[i - 1];
         SupportLevels[0] = newLevel;
      } else {
         ArrayResize(SupportLevels, n + 1);
         SupportLevels[n] = newLevel;
      }
      string name = "Support_" + IntegerToString(pivotTime);
      if (!ObjectCreate(0, name, OBJ_TREND, 0, pivotTime, newLevel.level, endTime, newLevel.level))
         Print("Failed to create support trendline");
      else
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
   }
}

//--------------------------------------------------------------------
// Update Breakout Events
//--------------------------------------------------------------------
void UpdateBreakoutSellEvents() {
   double closePrev = iClose(_Symbol, _Period, 1);
   int nRes = ArraySize(ResistanceLevels);
   for (int i = 0; i < nRes; i++) {
      double level = ResistanceLevels[i].level;
      if (level > 0 && closePrev > level) {
         bool exists = false;
         for (int j = 0; j < ArraySize(BreakoutSellEvents); j++) {
            if (MathAbs(BreakoutSellEvents[j].level - level) < 0.00001) {
               exists = true;
               break;
            }
         }
         if (!exists) {
            BreakoutEvent evt;
            evt.level = level;
            evt.barCount = 0;
            evt.startTime = iTime(_Symbol, _Period, 0);
            InsertBreakoutSellEvent(evt);
         }
      }
   }
   // Update bar counts and expire levels if needed
   for (int j = ArraySize(BreakoutSellEvents) - 1; j >= 0; j--) {
      BreakoutSellEvents[j].barCount++;
      if (BreakoutSellEvents[j].barCount >= RetraceCandles) {
         // Expire the level
         for (int k = 0; k < ArraySize(ResistanceLevels); k++) {
            if (MathAbs(ResistanceLevels[k].level - BreakoutSellEvents[j].level) < 0.00001) {
               for (int m = k; m < ArraySize(ResistanceLevels) - 1; m++)
                  ResistanceLevels[m] = ResistanceLevels[m + 1];
               ArrayResize(ResistanceLevels, ArraySize(ResistanceLevels) - 1);
               break;
            }
         }
         // Remove the event
         for (int m = j; m < ArraySize(BreakoutSellEvents) - 1; m++)
            BreakoutSellEvents[m] = BreakoutSellEvents[m + 1];
         ArrayResize(BreakoutSellEvents, ArraySize(BreakoutSellEvents) - 1);
      }
   }
}

void UpdateBreakoutBuyEvents() {
   double closePrev = iClose(_Symbol, _Period, 1);
   int nSup = ArraySize(SupportLevels);
   for (int i = 0; i < nSup; i++) {
      double level = SupportLevels[i].level;
      if (level > 0 && closePrev < level) {
         bool exists = false;
         for (int j = 0; j < ArraySize(BreakoutBuyEvents); j++) {
            if (MathAbs(BreakoutBuyEvents[j].level - level) < 0.00001) {
               exists = true;
               break;
            }
         }
         if (!exists) {
            BreakoutEvent evt;
            evt.level = level;
            evt.barCount = 0;
            evt.startTime = iTime(_Symbol, _Period, 0);
            InsertBreakoutBuyEvent(evt);
         }
      }
   }
   // Update bar counts and expire levels if needed
   for (int j = ArraySize(BreakoutBuyEvents) - 1; j >= 0; j--) {
      BreakoutBuyEvents[j].barCount++;
      if (BreakoutBuyEvents[j].barCount >= RetraceCandles) {
         // Expire the level
         for (int k = 0; k < ArraySize(SupportLevels); k++) {
            if (MathAbs(SupportLevels[k].level - BreakoutBuyEvents[j].level) < 0.00001) {
               for (int m = k; m < ArraySize(SupportLevels) - 1; m++)
                  SupportLevels[m] = SupportLevels[m + 1];
               ArrayResize(SupportLevels, ArraySize(SupportLevels) - 1);
               break;
            }
         }
         // Remove the event
         for (int m = j; m < ArraySize(BreakoutBuyEvents) - 1; m++)
            BreakoutBuyEvents[m] = BreakoutBuyEvents[m + 1];
         ArrayResize(BreakoutBuyEvents, ArraySize(BreakoutBuyEvents) - 1);
      }
   }
}

//--------------------------------------------------------------------
// Check SFP Signals
//--------------------------------------------------------------------
double CheckSFPSellSignal() {
   double closeCurr = iClose(_Symbol, _Period, 0);
   for (int j = ArraySize(BreakoutSellEvents) - 1; j >= 0; j--) {
      if (BreakoutSellEvents[j].barCount < RetraceCandles) {
         if (closeCurr < BreakoutSellEvents[j].level) {
            for (int k = 0; k < ArraySize(ResistanceLevels); k++) {
               if (MathAbs(ResistanceLevels[k].level - BreakoutSellEvents[j].level) < 0.00001) {
                  if (ResistanceLevels[k].tradeCount < MaxTradesPerLevel) {
                     double triggerLevel = BreakoutSellEvents[j].level;
                     Print("SELL retracement detected. Valid SFP SELL signal at resistance ", triggerLevel);
                     // Remove the event after signal
                     for (int m = j; m < ArraySize(BreakoutSellEvents) - 1; m++)
                        BreakoutSellEvents[m] = BreakoutSellEvents[m + 1];
                     ArrayResize(BreakoutSellEvents, ArraySize(BreakoutSellEvents) - 1);
                     return triggerLevel;
                  }
                  break;
               }
            }
         }
      }
   }
   return 0; // No signal
}

double CheckSFPBuySignal() {
   double closeCurr = iClose(_Symbol, _Period, 0);
   for (int j = ArraySize(BreakoutBuyEvents) - 1; j >= 0; j--) {
      if (BreakoutBuyEvents[j].barCount < RetraceCandles) {
         if (closeCurr > BreakoutBuyEvents[j].level) {
            for (int k = 0; k < ArraySize(SupportLevels); k++) {
               if (MathAbs(SupportLevels[k].level - BreakoutBuyEvents[j].level) < 0.00001) {
                  if (SupportLevels[k].tradeCount < MaxTradesPerLevel) {
                     double triggerLevel = BreakoutBuyEvents[j].level;
                     Print("BUY retracement detected. Valid SFP BUY signal at support ", triggerLevel);
                     // Remove the event after signal
                     for (int m = j; m < ArraySize(BreakoutBuyEvents) - 1; m++)
                        BreakoutBuyEvents[m] = BreakoutBuyEvents[m + 1];
                     ArrayResize(BreakoutBuyEvents, ArraySize(BreakoutBuyEvents) - 1);
                     return triggerLevel;
                  }
                  break;
               }
            }
         }
      }
   }
   return 0; // No signal
}

//--------------------------------------------------------------------
// Additional Filters: BB Trend & MA Ribbon
//--------------------------------------------------------------------
bool AdditionalFiltersPassed(ENUM_ORDER_TYPE signal) {
   bool result = true;
   double lastClose = iClose(_Symbol, _Period, 1);

   if (EnableBBTrendFilter) {
      double bbUpperArr[], bbLowerArr[];
      ArrayResize(bbUpperArr, 1);
      ArrayResize(bbLowerArr, 1);
      if (CopyBuffer(BBHandle, 1, 0, 1, bbUpperArr) <= 0 || CopyBuffer(BBHandle, 2, 0, 1, bbLowerArr) <= 0)
         result = false;
      else {
         double bbUpper = bbUpperArr[0];
         double bbLower = bbLowerArr[0];
         if (BBTrend == 0) {
            if (lastClose > bbUpper) BBTrend = 1;
            else if (lastClose < bbLower) BBTrend = -1;
         } else if (BBTrend == 1) {
            if (lastClose < bbLower) BBTrend = -1;
         } else if (BBTrend == -1) {
            if (lastClose > bbUpper) BBTrend = 1;
         }
         if (signal == ORDER_TYPE_BUY && BBTrend != 1) result = false;
         if (signal == ORDER_TYPE_SELL && BBTrend != -1) result = false;
      }
   }

   if (EnableMARibbonFilter) {
      for (int i = 0; i < NUM_MA; i++) {
         double bufArr[];
         ArrayResize(bufArr, 1);
         if (CopyBuffer(MAHandles[i], 0, 1, 1, bufArr) <= 0) return false;
         double buf = bufArr[0];
         if (signal == ORDER_TYPE_BUY && iClose(_Symbol, _Period, 1) >= buf) return false;
         if (signal == ORDER_TYPE_SELL && iClose(_Symbol, _Period, 1) <= buf) return false;
      }
   }
   return result;
}

//--------------------------------------------------------------------
// Trade Management: Reversal Exit
//--------------------------------------------------------------------
void CheckReversalExit() {
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackHighLow, 2));
   double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackHighLow, 2));
   double currentClose = iClose(_Symbol, _Period, 1);
   bool closeBuy = EnableReversalExit && (currentClose > highestHigh);
   bool closeSell = EnableReversalExit && (currentClose < lowestLow);

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber)
            continue;
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if (closeBuy && posType == POSITION_TYPE_SELL) {
            Print("Closing SELL position due to reversal buy signal.");
            if (!Trade.PositionClose(ticket)) Print("Error closing SELL position: ", GetLastError());
         } else if (closeSell && posType == POSITION_TYPE_BUY) {
            Print("Closing BUY position due to reversal sell signal.");
            if (!Trade.PositionClose(ticket)) Print("Error closing BUY position: ", GetLastError());
         }
      }
   }
}

//--------------------------------------------------------------------
// Trade Management: Breakeven Adjustment
//--------------------------------------------------------------------
void CheckAndExecuteBreakeven() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (IsTicketBreakevenAdjusted(ticket)) continue;
         if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber)
            continue;
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double slPrice = PositionGetDouble(POSITION_SL);
         double risk = MathAbs(openPrice - slPrice);
         double currPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double triggerPrice, newSL;
         if (posType == POSITION_TYPE_BUY) {
            triggerPrice = openPrice + risk * BreakevenTriggerReward;
            newSL = openPrice + risk * BreakevenReward;
            if (currPrice >= triggerPrice && EnableBreakeven) {
               if (newSL > slPrice) { // Ensure new SL is better than current SL
                  if (Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
                     Print("Breakeven SL adjusted for ticket #", ticket);
                     AddTicketToBreakevenAdjusted(ticket);
                  } else {
                     Print("Error adjusting SL for breakeven: ", GetLastError());
                  }
               }
            }
         } else if (posType == POSITION_TYPE_SELL) {
            triggerPrice = openPrice - risk * BreakevenTriggerReward;
            newSL = openPrice - risk * BreakevenReward;
            if (currPrice <= triggerPrice && EnableBreakeven) {
               if (newSL < slPrice) { // Ensure new SL is better than current SL
                  if (Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
                     Print("Breakeven SL adjusted for ticket #", ticket);
                     AddTicketToBreakevenAdjusted(ticket);
                  } else {
                     Print("Error adjusting SL for breakeven: ", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//--------------------------------------------------------------------
// Helper: Check Breakeven Adjustment Status
//--------------------------------------------------------------------
bool IsTicketBreakevenAdjusted(ulong ticket) {
   for (int i = 0; i < ArraySize(BreakevenAdjustedTickets); i++) {
      if (BreakevenAdjustedTickets[i] == ticket) return true;
   }
   return false;
}

void AddTicketToBreakevenAdjusted(ulong ticket) {
   int size = ArraySize(BreakevenAdjustedTickets);
   ArrayResize(BreakevenAdjustedTickets, size + 1);
   BreakevenAdjustedTickets[size] = ticket;
}

//--------------------------------------------------------------------
// Open Trade with ATR-Based Risk Management
//--------------------------------------------------------------------
void OpenTrade(ENUM_ORDER_TYPE orderType) {
   double atrVal[];
   ArrayResize(atrVal, 1);
   if (CopyBuffer(ATR_Handle, 0, 0, 1, atrVal) <= 0) {
      Print("Failed to retrieve ATR value.");
      return;
   }
   double atr = atrVal[0];
   double stopLossDist = atr * ATR_SL_Multiplier;
   double takeProfitDist = stopLossDist * RiskRewardRatio;

   double entryPrice, slPrice, tpPrice;
   if (orderType == ORDER_TYPE_BUY) {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slPrice = entryPrice - stopLossDist;
      tpPrice = entryPrice + takeProfitDist;
   } else if (orderType == ORDER_TYPE_SELL) {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slPrice = entryPrice + stopLossDist;
      tpPrice = entryPrice - takeProfitDist;
   } else return;

   double riskAmount = UsePercentRisk ? AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentage / 100.0 : FixedRiskPerTrade;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskPerLot = (stopLossDist / tickSize) * tickVal;
   if (riskPerLot <= 0) {
      Print("Invalid risk per lot calculation.");
      return;
   }
   double lotSize = riskAmount / riskPerLot;
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (lotSize < volMin) lotSize = volMin;
   else lotSize = MathFloor(lotSize / volStep) * volStep;
   lotSize = NormalizeDouble(lotSize, 2);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lotSize;
   request.type      = orderType;
   request.price     = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = slPrice;
   request.tp        = tpPrice;
   request.deviation = AllowedSlippage;
   request.magic     = EA_MagicNumber;
   request.comment   = (orderType == ORDER_TYPE_BUY) ? "SFP Buy Trade" : "SFP Sell Trade";

   if (!Trade.OrderSend(request, result))
      Print("OrderSend failed with error code: ", GetLastError());
   else
      Print((orderType == ORDER_TYPE_BUY) ? "SFP Buy Trade opened with ticket #: " : "SFP Sell Trade opened with ticket #: ", result.order);
}

//--------------------------------------------------------------------
// Check Open Positions
//--------------------------------------------------------------------
bool IsBuyPositionOpen() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber &&
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            return true;
      }
   }
   return false;
}

bool IsSellPositionOpen() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber &&
             PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            return true;
      }
   }
   return false;
}

bool IsAnyPositionOpen() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
             PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber) {
            return true;
         }
      }
   }
   return false;
}

//--------------------------------------------------------------------
// Manage Trades
//--------------------------------------------------------------------
void ManageTrades() {
   // Update daily trade counter
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int currDay = tm.day;
   if (currDay != LastTradeDay) {
      TradesToday = 0;
      LastTradeDay = currDay;
   }
   if (TradesToday >= MaxTradesPerDay) return;

   // Update breakout events
   UpdateBreakoutSellEvents();
   UpdateBreakoutBuyEvents();

   // Check session
   if (!IsWithinSessionNew()) return;

   // Check if any position is open; if so, exit the function
   if (IsAnyPositionOpen()) return;

   // Check for buy signal
   double buyLevel = CheckSFPBuySignal();
   if (buyLevel != 0 && AdditionalFiltersPassed(ORDER_TYPE_BUY)) {
      OpenTrade(ORDER_TYPE_BUY);
      // Increment trade count for the level
      for (int k = 0; k < ArraySize(SupportLevels); k++) {
         if (MathAbs(SupportLevels[k].level - buyLevel) < 0.00001) {
            SupportLevels[k].tradeCount++;
            break;
         }
      }
      TradesToday++;
   } else {
      // If no buy signal, check for sell signal
      double sellLevel = CheckSFPSellSignal();
      if (sellLevel != 0 && AdditionalFiltersPassed(ORDER_TYPE_SELL)) {
         OpenTrade(ORDER_TYPE_SELL);
         // Increment trade count for the level
         for (int k = 0; k < ArraySize(ResistanceLevels); k++) {
            if (MathAbs(ResistanceLevels[k].level - sellLevel) < 0.00001) {
               ResistanceLevels[k].tradeCount++;
               break;
            }
         }
         TradesToday++;
      }
   }
}

//--------------------------------------------------------------------
// Main OnTick Function
//--------------------------------------------------------------------
void OnTick_SFP() {
   datetime currBarTime = iTime(_Symbol, _Period, 0);
   if (currBarTime != LastBarTime) {
      UpdatePivotLevels();
      ManageTrades();
      LastBarTime = currBarTime;
   }
   CheckAndExecuteBreakeven();
   CheckReversalExit();
}

//--------------------------------------------------------------------
// Initialization
//--------------------------------------------------------------------
int OnInit() {
   ATR_Handle = iATR(_Symbol, _Period, ATR_Period);
   if (ATR_Handle == INVALID_HANDLE) {
      Print("Failed to initialize ATR indicator.");
      return(INIT_FAILED);
   }
   ArrayResize(ResistanceLevels, 0);
   ArrayResize(SupportLevels, 0);
   ArrayResize(BreakoutSellEvents, 0);
   ArrayResize(BreakoutBuyEvents, 0);
   ArrayResize(BreakevenAdjustedTickets, 0);

   if (EnableBBTrendFilter) {
      BBHandle = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
      if (BBHandle == INVALID_HANDLE) Print("Failed to initialize Bollinger Bands indicator.");
      BBTrend = 0;
   }
   if (EnableMARibbonFilter) {
      for (int i = 0; i < NUM_MA; i++) {
         int period = MA_StartPeriod + i * MA_PeriodStep;
         MAHandles[i] = iMA(_Symbol, _Period, period, 0, MA_Method, PRICE_CLOSE);
         if (MAHandles[i] == INVALID_HANDLE)
            Print("Failed to initialize MA indicator for period ", period);
      }
   }
   return(INIT_SUCCEEDED);
}

//--------------------------------------------------------------------
// Tick Handler
//--------------------------------------------------------------------
void OnTick() {
   OnTick_SFP();
}

//+------------------------------------------------------------------+