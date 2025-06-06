//+------------------------------------------------------------------+
//|                                                  SFP_EA.mq5      |
//| Swing Failure Pattern EA with Advanced Trade Management          |
//| (ATR risk, partial close, breakeven, reversal exit, BB Trend & MA   |
//|  Ribbon filters)                                                 |
//|         © Your Name – Licensed under CC BY-NC-SA 4.0             |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--------------------------------------------------------------------
// SFP Settings
//--------------------------------------------------------------------
input int      LeftBars         = 15;    // Bars to left for pivot detection
input int      RightBars        = 15;    // Bars to right for pivot detection
input int      RetraceCandles   = 3;     // Maximum bars allowed after breakout for valid retrace

//--------------------------------------------------------------------
// Basic Risk Management & Trade Settings
//--------------------------------------------------------------------
input int      ATR_Period         = 14;
input double   ATR_SL_Multiplier  = 2.0;
input double   RiskRewardRatio    = 10.0;
input double   FixedRiskPerTrade  = 50.0;
input bool     UsePercentRisk     = false;
input double   RiskPercentage     = 1.0;
input int      AllowedSlippage    = 3;
input int      SessionStartHour   = 8;
input int      SessionStartMin    = 0;
input int      SessionEndHour     = 17;
input int      SessionEndMin      = 0;
input int      BrokerGMTOffset    = 0;
input bool     UseDailyBias       = false;
input int      MaxTradesPerDay    = 2;     // For example, 2 trades per day
input bool     AllowMultiplePos   = false; // Not used: we ensure one trade at a time
input ulong    EA_MagicNumber     = 123456;

//--------------------------------------------------------------------
// Additional Trade Management Settings
//--------------------------------------------------------------------
input bool     EnableBreakeven    = true;
input double   BreakevenReward    = 1.0;
input double   PartialClosePct    = 50.0;
input double   PartialCloseReward = 5.0;
input int      LookbackHighLow    = 14;
input bool     EnableReversalExit = true;

//--------------------------------------------------------------------
// Additional Filters: BB Trend & MA Ribbon
//--------------------------------------------------------------------
input bool     EnableBBTrendFilter   = true;
input int      BB_Period             = 100;
input double   BB_Deviation          = 2.0;

input bool     EnableMARibbonFilter  = true;
input ENUM_MA_METHOD MA_Method         = MODE_EMA;
input int      MA_StartPeriod        = 100;
input int      MA_PeriodStep         = 20;
#define NUM_MA 6

//--------------------------------------------------------------------
// Global Variables for SFP
//--------------------------------------------------------------------
int ATR_Handle;
double ResistanceLevels[];  // Array of detected resistance levels
double SupportLevels[];     // Array of detected support levels

// Structure for breakout events
struct BreakoutEvent
  {
   double level;       // Pivot level at breakout
   int    barCount;    // Bars counted since breakout detection
   datetime startTime; // Time when breakout was detected
  };

BreakoutEvent BreakoutSellEvents[];
BreakoutEvent BreakoutBuyEvents[];

int TradesToday  = 0;
int LastTradeDay = 0;
datetime LastBarTime = 0;

CTrade Trade; // Trade management object

//--------------------------------------------------------------------
// Global Variables for Additional Filters
//--------------------------------------------------------------------
int BBHandle;         // Bollinger Bands indicator handle
int MAHandles[NUM_MA]; // Array for MA indicator handles
// Persistent BB trend: 0 = undefined, 1 = LONG, -1 = SHORT
int BBTrend = 0;

ulong PartialClosedTickets[]; // Track partially closed tickets

//--------------------------------------------------------------------
// Helper Functions: Breakout Event Insertion
//--------------------------------------------------------------------
void InsertBreakoutSellEvent(const BreakoutEvent &evt)
  {
   int size = ArraySize(BreakoutSellEvents);
   ArrayResize(BreakoutSellEvents, size + 1);
   for(int i = size; i > 0; i--)
      BreakoutSellEvents[i] = BreakoutSellEvents[i - 1];
   BreakoutSellEvents[0] = evt;
  }
  
void InsertBreakoutBuyEvent(const BreakoutEvent &evt)
  {
   int size = ArraySize(BreakoutBuyEvents);
   ArrayResize(BreakoutBuyEvents, size + 1);
   for(int i = size; i > 0; i--)
      BreakoutBuyEvents[i] = BreakoutBuyEvents[i - 1];
   BreakoutBuyEvents[0] = evt;
  }
  
//--------------------------------------------------------------------
// Pivot Detection Functions
//--------------------------------------------------------------------
bool IsPivotHigh(int idx)
  {
   if(idx < RightBars)
      return false;
   double pivot = iHigh(_Symbol, _Period, idx);
   for(int i = idx - LeftBars; i <= idx + RightBars; i++)
   {
      if(i == idx)
         continue;
      if(i < 0 || i >= Bars(_Symbol, _Period))
         continue;
      if(iHigh(_Symbol, _Period, i) > pivot)
         return false;
   }
   return true;
  }
  
bool IsPivotLow(int idx)
  {
   if(idx < RightBars)
      return false;
   double pivot = iLow(_Symbol, _Period, idx);
   for(int i = idx - LeftBars; i <= idx + RightBars; i++)
   {
      if(i == idx)
         continue;
      if(i < 0 || i >= Bars(_Symbol, _Period))
         continue;
      if(iLow(_Symbol, _Period, i) < pivot)
         return false;
   }
   return true;
  }
  
//--------------------------------------------------------------------
// Update Pivot Levels & Plot Horizontal Lines (fixed time span)
//--------------------------------------------------------------------
void UpdatePivotLevels()
  {
   int idx = RightBars; // Confirmed pivot at bar index = RightBars
   int periodSeconds = Period() * 60;  // Candle duration in seconds
   datetime pivotTime = iTime(_Symbol, _Period, idx);
   datetime endTime = pivotTime + (LeftBars + RightBars) * periodSeconds;
   
   // For a resistance pivot:
   if(IsPivotHigh(idx))
   {
      double newRes = iHigh(_Symbol, _Period, idx);
      int pos = ArraySize(ResistanceLevels);
      ArrayResize(ResistanceLevels, pos + 1);
      ResistanceLevels[pos] = newRes;
      
      string name = "Resistance_" + IntegerToString(pivotTime);
      if(!ObjectCreate(0, name, OBJ_TREND, 0, pivotTime, newRes, endTime, newRes))
         Print("Failed to create resistance trendline");
      else
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
   }
   
   // For a support pivot:
   if(IsPivotLow(idx))
   {
      double newSup = iLow(_Symbol, _Period, idx);
      int pos = ArraySize(SupportLevels);
      ArrayResize(SupportLevels, pos + 1);
      SupportLevels[pos] = newSup;
      
      string name = "Support_" + IntegerToString(pivotTime);
      if(!ObjectCreate(0, name, OBJ_TREND, 0, pivotTime, newSup, endTime, newSup))
         Print("Failed to create support trendline");
      else
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
   }
  }
  
//--------------------------------------------------------------------
// Update Breakout Events for SELL and BUY sides
//--------------------------------------------------------------------
void UpdateBreakoutSellEvents()
  {
   double closePrev = iClose(_Symbol, _Period, 1);
   int nRes = ArraySize(ResistanceLevels);
   for(int i = 0; i < nRes; i++)
   {
      double level = ResistanceLevels[i];
      if(level > 0 && closePrev > level)
      {
         bool exists = false;
         for(int j = 0; j < ArraySize(BreakoutSellEvents); j++)
         {
            if(MathAbs(BreakoutSellEvents[j].level - level) < 0.00001)
            {
               exists = true;
               break;
            }
         }
         if(!exists)
         {
            BreakoutEvent evt;
            evt.level = level;
            evt.barCount = 0;
            evt.startTime = iTime(_Symbol, _Period, 0);
            InsertBreakoutSellEvent(evt);
         }
      }
   }
   for(int j = 0; j < ArraySize(BreakoutSellEvents); j++)
      BreakoutSellEvents[j].barCount++;
  }
  
void UpdateBreakoutBuyEvents()
  {
   double closePrev = iClose(_Symbol, _Period, 1);
   int nSup = ArraySize(SupportLevels);
   for(int i = 0; i < nSup; i++)
   {
      double level = SupportLevels[i];
      if(level > 0 && closePrev < level)
      {
         bool exists = false;
         for(int j = 0; j < ArraySize(BreakoutBuyEvents); j++)
         {
            if(MathAbs(BreakoutBuyEvents[j].level - level) < 0.00001)
            {
               exists = true;
               break;
            }
         }
         if(!exists)
         {
            BreakoutEvent evt;
            evt.level = level;
            evt.barCount = 0;
            evt.startTime = iTime(_Symbol, _Period, 0);
            InsertBreakoutBuyEvent(evt);
         }
      }
   }
   for(int j = 0; j < ArraySize(BreakoutBuyEvents); j++)
      BreakoutBuyEvents[j].barCount++;
  }
  
//--------------------------------------------------------------------
// Check for valid SFP signals based on breakout events
//--------------------------------------------------------------------
bool CheckSFPSellSignal()
  {
   double closeCurr = iClose(_Symbol, _Period, 0);
   bool validSignal = false;
   for(int j = ArraySize(BreakoutSellEvents) - 1; j >= 0; j--)
   {
      if(BreakoutSellEvents[j].barCount < RetraceCandles)
      {
         if(closeCurr < BreakoutSellEvents[j].level)
         {
            Print("SELL retracement detected. Valid SFP SELL signal at resistance ", BreakoutSellEvents[j].level);
            validSignal = true;
            for(int k = j; k < ArraySize(BreakoutSellEvents) - 1; k++)
               BreakoutSellEvents[k] = BreakoutSellEvents[k + 1];
            ArrayResize(BreakoutSellEvents, ArraySize(BreakoutSellEvents) - 1);
         }
      }
      else
      {
         for(int k = j; k < ArraySize(BreakoutSellEvents) - 1; k++)
            BreakoutSellEvents[k] = BreakoutSellEvents[k + 1];
         ArrayResize(BreakoutSellEvents, ArraySize(BreakoutSellEvents) - 1);
      }
   }
   return validSignal;
  }
  
bool CheckSFPBuySignal()
  {
   double closeCurr = iClose(_Symbol, _Period, 0);
   bool validSignal = false;
   for(int j = ArraySize(BreakoutBuyEvents) - 1; j >= 0; j--)
   {
      if(BreakoutBuyEvents[j].barCount < RetraceCandles)
      {
         if(closeCurr > BreakoutBuyEvents[j].level)
         {
            Print("BUY retracement detected. Valid SFP BUY signal at support ", BreakoutBuyEvents[j].level);
            validSignal = true;
            for(int k = j; k < ArraySize(BreakoutBuyEvents) - 1; k++)
               BreakoutBuyEvents[k] = BreakoutBuyEvents[k + 1];
            ArrayResize(BreakoutBuyEvents, ArraySize(BreakoutBuyEvents) - 1);
         }
      }
      else
      {
         for(int k = j; k < ArraySize(BreakoutBuyEvents) - 1; k++)
            BreakoutBuyEvents[k] = BreakoutBuyEvents[k + 1];
         ArrayResize(BreakoutBuyEvents, ArraySize(BreakoutBuyEvents) - 1);
      }
   }
   return validSignal;
  }
  
//--------------------------------------------------------------------
// Additional Filters: BB Trend and MA Ribbon
//--------------------------------------------------------------------
bool AdditionalFiltersPassed(ENUM_ORDER_TYPE signal)
  {
   bool result = true;
   double lastClose = iClose(_Symbol, _Period, 1);
   
   // BB Trend Filter using MA_Ribbon logic:
   if(EnableBBTrendFilter)
   {
       double bbUpperArr[1], bbLowerArr[1];
       ArrayResize(bbUpperArr, 1);
       ArrayResize(bbLowerArr, 1);
       if(CopyBuffer(BBHandle, 1, 0, 1, bbUpperArr) <= 0 ||
          CopyBuffer(BBHandle, 2, 0, 1, bbLowerArr) <= 0)
          result = false;
       else
       {
          double bbUpper = bbUpperArr[0];
          double bbLower = bbLowerArr[0];
          if(BBTrend == 0)
          {
             if(lastClose > bbUpper)
                BBTrend = 1;
             else if(lastClose < bbLower)
                BBTrend = -1;
          }
          else if(BBTrend == 1)
          {
             if(lastClose < bbLower)
                BBTrend = -1;
          }
          else if(BBTrend == -1)
          {
             if(lastClose > bbUpper)
                BBTrend = 1;
          }
          if(signal == ORDER_TYPE_BUY && BBTrend != 1)
             result = false;
          if(signal == ORDER_TYPE_SELL && BBTrend != -1)
             result = false;
       }
   }
   
   // MA Ribbon Filter: For BUY, previous close must be below all MAs; for SELL, above all.
   if(EnableMARibbonFilter)
   {
       if(signal == ORDER_TYPE_BUY && !IsBelowAllMAs()) result = false;
       if(signal == ORDER_TYPE_SELL && !IsAboveAllMAs()) result = false;
   }
   return result;
  }
  
bool IsBelowAllMAs()
  {
   for(int i = 0; i < NUM_MA; i++)
   {
      double bufArr[1];
      ArrayResize(bufArr, 1);
      if(CopyBuffer(MAHandles[i], 0, 1, 1, bufArr) <= 0)
         return false;
      double buf = bufArr[0];
      if(iClose(_Symbol, _Period, 1) >= buf)
         return false;
   }
   return true;
  }
  
bool IsAboveAllMAs()
  {
   for(int i = 0; i < NUM_MA; i++)
   {
      double bufArr[1];
      ArrayResize(bufArr, 1);
      if(CopyBuffer(MAHandles[i], 0, 1, 1, bufArr) <= 0)
         return false;
      double buf = bufArr[0];
      if(iClose(_Symbol, _Period, 1) <= buf)
         return false;
   }
   return true;
  }
  
//--------------------------------------------------------------------
// Trade Management Logics: Reversal Exit
//--------------------------------------------------------------------
void CheckReversalExit()
  {
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackHighLow, 2));
   double lowestLow   = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackHighLow, 2));
   double currentClose = iClose(_Symbol, _Period, 1);
   bool closeBuy  = EnableReversalExit && (currentClose > highestHigh);
   bool closeSell = EnableReversalExit && (currentClose < lowestLow);
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber)
            continue;
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(closeBuy && posType == POSITION_TYPE_SELL)
         {
            Print("Closing SELL position due to reversal buy signal.");
            if(!Trade.PositionClose(ticket))
               Print("Error closing SELL position: ", GetLastError());
         }
         else if(closeSell && posType == POSITION_TYPE_BUY)
         {
            Print("Closing BUY position due to reversal sell signal.");
            if(!Trade.PositionClose(ticket))
               Print("Error closing BUY position: ", GetLastError());
         }
      }
   }
  }
  
//--------------------------------------------------------------------
// Trade Management Logics: Partial Close & Breakeven
//--------------------------------------------------------------------
void CheckAndExecutePartialClose()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber)
            continue;
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double slPrice = PositionGetDouble(POSITION_SL);
         double risk = MathAbs(openPrice - slPrice);
         double currPrice = iClose(_Symbol, _Period, 0);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double targetPrice, breakevenPrice;
         if(posType == POSITION_TYPE_BUY)
         {
            targetPrice = openPrice + risk * PartialCloseReward;
            breakevenPrice = openPrice + risk * BreakevenReward;
            if(currPrice >= targetPrice)
            {
               double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (PartialClosePct / 100.0), 2);
               if(Trade.PositionClosePartial(ticket, volumeToClose))
               {
                  Print("Partial close executed for ticket #", ticket);
                  if(EnableBreakeven)
                  {
                     if(!Trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
                        Print("Error setting new SL after partial close: ", GetLastError());
                  }
               }
               else
                  Print("Error in partial closing: ", GetLastError());
            }
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            targetPrice = openPrice - risk * PartialCloseReward;
            breakevenPrice = openPrice - risk * BreakevenReward;
            if(currPrice <= targetPrice)
            {
               double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (PartialClosePct / 100.0), 2);
               if(Trade.PositionClosePartial(ticket, volumeToClose))
               {
                  Print("Partial close executed for ticket #", ticket);
                  if(EnableBreakeven)
                  {
                     if(!Trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
                        Print("Error setting new SL after partial close: ", GetLastError());
                  }
               }
               else
                  Print("Error in partial closing: ", GetLastError());
            }
         }
      }
   }
  }
  
//--------------------------------------------------------------------
// Open Trade using ATR-based risk management
//--------------------------------------------------------------------
void OpenTrade(ENUM_ORDER_TYPE orderType)
  {
   double atrVal[1];
   if(CopyBuffer(ATR_Handle, 0, 0, 1, atrVal) <= 0)
   {
      Print("Failed to retrieve ATR value.");
      return;
   }
   double atr = atrVal[0];
   double stopLossDist = atr * ATR_SL_Multiplier;
   double takeProfitDist = stopLossDist * RiskRewardRatio;
   
   double entryPrice, slPrice, tpPrice;
   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slPrice = entryPrice - stopLossDist;
      tpPrice = entryPrice + takeProfitDist;
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slPrice = entryPrice + stopLossDist;
      tpPrice = entryPrice - takeProfitDist;
   }
   else return;
   
   double riskAmount = UsePercentRisk ? AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentage / 100.0 : FixedRiskPerTrade;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskPerLot = (stopLossDist / tickSize) * tickVal;
   if(riskPerLot <= 0)
   {
      Print("Invalid risk per lot calculation.");
      return;
   }
   double lotSize = riskAmount / riskPerLot;
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotSize < volMin)
      lotSize = volMin;
   else
      lotSize = MathFloor(lotSize / volStep) * volStep;
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
   
   if(!Trade.OrderSend(request, result))
      Print("OrderSend failed with error code: ", GetLastError());
   else
      Print((orderType == ORDER_TYPE_BUY) ? "SFP Buy Trade opened with ticket #: " : "SFP Sell Trade opened with ticket #: ", result.order);
  }
  
//--------------------------------------------------------------------
// Check if any trade is open by this EA
//--------------------------------------------------------------------
bool IsAnyTradeOpen()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
            return true;
      }
   }
   return false;
  }
  
//--------------------------------------------------------------------
// Check if current time is within allowed session
//--------------------------------------------------------------------
bool IsWithinSession()
  {
   datetime srvTime = TimeCurrent();
   datetime gmtTime = srvTime - BrokerGMTOffset * 3600;
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   int startSec = SessionStartHour * 3600 + SessionStartMin * 60;
   int endSec = SessionEndHour * 3600 + SessionEndMin * 60;
   int curSec = dt.hour * 3600 + dt.min * 60;
   return (curSec >= startSec && curSec < endSec);
  }
  
//--------------------------------------------------------------------
// Manage Trades: update breakout events, check signals, and execute trades
// (Note: breakout events update normally even if a trade is open; however, a valid trade is not executed if IsAnyTradeOpen() is true)
//--------------------------------------------------------------------
void ManageTrades()
  {
   // Update daily counter
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int currDay = tm.day;
   if(currDay != LastTradeDay)
   {
      TradesToday = 0;
      LastTradeDay = currDay;
   }
   if(TradesToday >= MaxTradesPerDay)
      return;
   
   // Update breakout events regardless of trade status
   UpdateBreakoutSellEvents();
   UpdateBreakoutBuyEvents();
   
   // If a trade is open, do not execute a new valid signal
   if(IsAnyTradeOpen())
      return;
   
   bool signalSell = CheckSFPSellSignal();
   bool signalBuy = CheckSFPBuySignal();
   
   // Only execute trade if additional filters pass
   if(signalSell && AdditionalFiltersPassed(ORDER_TYPE_SELL))
   {
      OpenTrade(ORDER_TYPE_SELL);
      TradesToday++;
   }
   else if(signalBuy && AdditionalFiltersPassed(ORDER_TYPE_BUY))
   {
      OpenTrade(ORDER_TYPE_BUY);
      TradesToday++;
   }
  }
  
//--------------------------------------------------------------------
// Main OnTick for SFP logic: update pivots, manage trades, and then
// apply extra trade management logics (partial close, reversal exit)
//--------------------------------------------------------------------
void OnTick_SFP()
  {
   datetime currBarTime = iTime(_Symbol, _Period, 0);
   if(currBarTime != LastBarTime)
   {
      UpdatePivotLevels();
      ManageTrades();
      LastBarTime = currBarTime;
   }
   CheckAndExecutePartialClose();
   CheckReversalExit();
  }
  
//--------------------------------------------------------------------
// Expert Initialization: set up indicators and arrays
//--------------------------------------------------------------------
int OnInit()
  {
   ATR_Handle = iATR(_Symbol, _Period, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
   {
      Print("Failed to initialize ATR indicator.");
      return(INIT_FAILED);
   }
   ArrayResize(ResistanceLevels, 0);
   ArrayResize(SupportLevels, 0);
   ArrayResize(BreakoutSellEvents, 0);
   ArrayResize(BreakoutBuyEvents, 0);
   ArrayResize(PartialClosedTickets, 0);
   
   // Initialize additional filters
   if(EnableBBTrendFilter)
   {
       BBHandle = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
       if(BBHandle == INVALID_HANDLE)
          Print("Failed to initialize Bollinger Bands indicator.");
       BBTrend = 0;
   }
   if(EnableMARibbonFilter)
   {
       for(int i = 0; i < NUM_MA; i++)
       {
          int period = MA_StartPeriod + i * MA_PeriodStep;
          MAHandles[i] = iMA(_Symbol, _Period, period, 0, MA_Method, PRICE_CLOSE);
          if(MAHandles[i] == INVALID_HANDLE)
             Print("Failed to initialize MA indicator for period ", period);
       }
   }
   
   return(INIT_SUCCEEDED);
  }
  
//--------------------------------------------------------------------
// Expert Tick
//--------------------------------------------------------------------
void OnTick()
  {
   OnTick_SFP();
  }
  
//+------------------------------------------------------------------+
