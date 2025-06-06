//+------------------------------------------------------------------+
//|                                             Fib_Retracement_EA.mq5 |
//| Fib Retracement EA                                               |
//| Immediately places a pending limit order at a Fibonacci retracement|
//| level when support/resistance (pivot) is detected. The entry price  |
//| is calculated using the highest high and lowest low of the candles |
//| that formed the level.                                             |
//|         © Your Name – Licensed under CC BY-NC-SA 4.0               |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--------------------------------------------------------------------
// Session Filter Inputs
//--------------------------------------------------------------------
input bool TradeNewYork = true;
input bool TradeLondon  = true;
input bool TradeTokyo   = false;
input bool TradeSydney  = false;

//--------------------------------------------------------------------
// Pivot Detection Settings
//--------------------------------------------------------------------
input int      LeftBars         = 15;    // Bars to left for pivot detection
input int      RightBars        = 15;    // Bars to right for pivot detection
input int      PivotLevelsCount = 3;     // Number of support/resistance levels to keep

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
input int      BrokerGMTOffset    = 0;
input bool     UseDailyBias       = false;
input int      MaxTradesPerDay    = 2;     // e.g., 2 trades per day
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
// Fibonacci Retracement Input
//--------------------------------------------------------------------
input double   FibRetracementLevel = 0.618;  // e.g., 0.618

//--------------------------------------------------------------------
// Global Variables for Pivot Detection
//--------------------------------------------------------------------
double ResistanceLevels[];  // Detected resistance levels
double SupportLevels[];     // Detected support levels

//--------------------------------------------------------------------
// Trade Management Objects & Global Counters
//--------------------------------------------------------------------
CTrade Trade;
int TradesToday  = 0;
int LastTradeDay = -1;  // Initialized to an invalid day to force a reset on first tick
datetime LastBarTime = 0;

//--------------------------------------------------------------------
// Global Variables for Additional Filters
//--------------------------------------------------------------------
int BBHandle;         // Bollinger Bands indicator handle
int MAHandles[NUM_MA]; // Array for MA indicator handles
int BBTrend = 0;      // 0 = undefined, 1 = LONG, -1 = SHORT
ulong PartialClosedTickets[]; // To track partially closed tickets

//--------------------------------------------------------------------
// Session Filter Function
//--------------------------------------------------------------------
bool IsWithinSessionNew()
  {
   datetime currentTime = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   int curTimeInMinutes = dt.hour * 60 + dt.min;
   bool inSession = false;
   if(TradeNewYork && curTimeInMinutes >= 13 * 60 && curTimeInMinutes < 22 * 60)
      inSession = true;
   if(TradeLondon && curTimeInMinutes >= 8 * 60 && curTimeInMinutes < 17 * 60)
      inSession = true;
   if(TradeTokyo && curTimeInMinutes >= 0 && curTimeInMinutes < 9 * 60)
      inSession = true;
   if(TradeSydney && (curTimeInMinutes >= 22 * 60 || curTimeInMinutes < 7 * 60))
      inSession = true;
   return inSession;
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
// Update Daily Trade Counter
//--------------------------------------------------------------------
void UpdateDailyCounter()
  {
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   if(tm.day != LastTradeDay)
     {
      TradesToday = 0;
      LastTradeDay = tm.day;
     }
  }
  
//--------------------------------------------------------------------
// Update Pivot Levels & Immediately Place Pending Order
//--------------------------------------------------------------------
void UpdatePivotLevels()
  {
   UpdateDailyCounter(); // Reset daily counter if a new day has started.
   int idx = RightBars; // Confirmed pivot index
   int periodSeconds = Period() * 60;
   datetime pivotTime = iTime(_Symbol, _Period, idx);
   datetime endTime = pivotTime + (LeftBars + RightBars) * periodSeconds;
   
   // For a resistance pivot:
   if(IsPivotHigh(idx))
     {
      double newRes = iHigh(_Symbol, _Period, idx);
      int n = ArraySize(ResistanceLevels);
      if(n >= PivotLevelsCount)
        {
         for(int i = n - 1; i > 0; i--)
            ResistanceLevels[i] = ResistanceLevels[i-1];
         ResistanceLevels[0] = newRes;
        }
      else
        {
         ArrayResize(ResistanceLevels, n + 1);
         ResistanceLevels[n] = newRes;
        }
      
      string name = "Resistance_" + IntegerToString(pivotTime);
      if(!ObjectCreate(0, name, OBJ_TREND, 0, pivotTime, newRes, endTime, newRes))
         Print("Failed to create resistance trendline");
      else
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      
      // Immediately place a SELL pending order.
      if(IsWithinSessionNew() && TradesToday < MaxTradesPerDay)
        {
         int startIdx = idx - LeftBars;
         int endIdxPivot = idx + RightBars;
         double highestHigh = iHigh(_Symbol, _Period, startIdx);
         double lowestLow = iLow(_Symbol, _Period, startIdx);
         for(int i = startIdx; i <= endIdxPivot; i++)
         {
            double hi = iHigh(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);
            if(hi > highestHigh) highestHigh = hi;
            if(lo < lowestLow) lowestLow = lo;
         }
         // For resistance: pending SELL order.
         // Entry price = lowestLow + FibRetracementLevel * (highestHigh - lowestLow)
         double entryPrice = lowestLow + FibRetracementLevel * (highestHigh - lowestLow);
         PlaceFibOrder(ORDER_TYPE_SELL, entryPrice, highestHigh, lowestLow);
         TradesToday++;
        }
     }
     
   // For a support pivot:
   if(IsPivotLow(idx))
     {
      double newSup = iLow(_Symbol, _Period, idx);
      int n = ArraySize(SupportLevels);
      if(n >= PivotLevelsCount)
        {
         for(int i = n - 1; i > 0; i--)
            SupportLevels[i] = SupportLevels[i-1];
         SupportLevels[0] = newSup;
        }
      else
        {
         ArrayResize(SupportLevels, n + 1);
         SupportLevels[n] = newSup;
        }
      
      string name = "Support_" + IntegerToString(pivotTime);
      if(!ObjectCreate(0, name, OBJ_TREND, 0, pivotTime, newSup, endTime, newSup))
         Print("Failed to create support trendline");
      else
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
      
      // Immediately place a BUY pending order.
      if(IsWithinSessionNew() && TradesToday < MaxTradesPerDay)
        {
         int startIdx = idx - LeftBars;
         int endIdxPivot = idx + RightBars;
         double highestHigh = iHigh(_Symbol, _Period, startIdx);
         double lowestLow = iLow(_Symbol, _Period, startIdx);
         for(int i = startIdx; i <= endIdxPivot; i++)
         {
            double hi = iHigh(_Symbol, _Period, i);
            double lo = iLow(_Symbol, _Period, i);
            if(hi > highestHigh) highestHigh = hi;
            if(lo < lowestLow) lowestLow = lo;
         }
         // For support: pending BUY order.
         // Entry price = highestHigh - FibRetracementLevel * (highestHigh - lowestLow)
         double entryPrice = highestHigh - FibRetracementLevel * (highestHigh - lowestLow);
         PlaceFibOrder(ORDER_TYPE_BUY, entryPrice, highestHigh, lowestLow);
         TradesToday++;
        }
     }
  }
  
//--------------------------------------------------------------------
// PlaceFibOrder: Calculate risk parameters and send pending limit order
//--------------------------------------------------------------------
void PlaceFibOrder(ENUM_ORDER_TYPE orderType, double entryPrice, double highestHigh, double lowestLow)
  {
   double atrVal[];
   ArrayResize(atrVal, 1);
   int atrHandle = iATR(_Symbol, _Period, ATR_Period);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrVal) <= 0)
     {
      Print("Failed to retrieve ATR value.");
      return;
     }
   double atr = atrVal[0];
   double stopLossDist = atr * ATR_SL_Multiplier;
   double takeProfitDist = stopLossDist * RiskRewardRatio;
   
   double slPrice, tpPrice;
   if(orderType == ORDER_TYPE_BUY)
     {
      slPrice = entryPrice - stopLossDist;
      tpPrice = entryPrice + takeProfitDist;
      orderType = ORDER_TYPE_BUY_LIMIT;
     }
   else if(orderType == ORDER_TYPE_SELL)
     {
      slPrice = entryPrice + stopLossDist;
      tpPrice = entryPrice - takeProfitDist;
      orderType = ORDER_TYPE_SELL_LIMIT;
     }
   else
      return;
      
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
   request.action    = TRADE_ACTION_PENDING;
   request.symbol    = _Symbol;
   request.volume    = lotSize;
   request.type      = orderType;
   request.price     = entryPrice;
   request.sl        = slPrice;
   request.tp        = tpPrice;
   request.deviation = AllowedSlippage;
   request.magic     = EA_MagicNumber;
   request.comment   = (orderType == ORDER_TYPE_BUY_LIMIT) ? "Fib Retracement BUY Pending" : "Fib Retracement SELL Pending";
   
   if(!Trade.OrderSend(request, result))
      Print("OrderSend failed with error code: ", GetLastError());
   else
      Print((orderType == ORDER_TYPE_BUY_LIMIT) ? "Fib Retracement BUY Pending Order placed with ticket #: " : "Fib Retracement SELL Pending Order placed with ticket #: ", result.order);
  }
  
//--------------------------------------------------------------------
// Trade Management Logics: Partial Close & Breakeven (unchanged)
//--------------------------------------------------------------------
void CheckAndExecutePartialClose()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(IsTicketPartiallyClosed(ticket))
            continue;
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
                  AddTicketToPartialClosed(ticket);
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
                  AddTicketToPartialClosed(ticket);
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
  
bool IsTicketPartiallyClosed(ulong ticket)
  {
   for(int i = 0; i < ArraySize(PartialClosedTickets); i++)
      if(PartialClosedTickets[i] == ticket)
         return true;
   return false;
  }
  
void AddTicketToPartialClosed(ulong ticket)
  {
   int size = ArraySize(PartialClosedTickets);
   ArrayResize(PartialClosedTickets, size + 1);
   PartialClosedTickets[size] = ticket;
  }
  

//--------------------------------------------------------------------
// Trade Management Logics: Reversal Exit (unchanged)
//--------------------------------------------------------------------
void CheckReversalExit()
  {
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackHighLow, 2));
   double lowestLow   = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackHighLow, 2));
   double currentClose = iClose(_Symbol, _Period, 1);
   bool closeBuy  = EnableReversalExit && (currentClose > highestHigh);
   bool closeSell = EnableReversalExit && (currentClose < lowestLow);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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
// Expert Initialization
//--------------------------------------------------------------------
int OnInit()
  {
   int atrHandle = iATR(_Symbol, _Period, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("Failed to initialize ATR indicator.");
      return(INIT_FAILED);
     }
   ArrayResize(ResistanceLevels, 0);
   ArrayResize(SupportLevels, 0);
   ArrayResize(PartialClosedTickets, 0);
   
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
   datetime currBarTime = iTime(_Symbol, _Period, 0);
   if(currBarTime != LastBarTime)
     {
      UpdatePivotLevels();
      LastBarTime = currBarTime;
     }
   CheckAndExecutePartialClose();
   CheckReversalExit();
  }
  
//+------------------------------------------------------------------+
