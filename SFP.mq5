//+------------------------------------------------------------------+
//|                                                  SFP_EA.mq5      |
//|    Swing Failure Pattern EA based on support/resistance            |
//| Implements both BUY and SELL signals using breakout events tracked |
//| Valid signal triggers if price retraces before RetraceCandles        |
//|         © Your Name – Licensed under CC BY-NC-SA 4.0                |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//---- Pivot settings
input int      LeftBars         = 15;    // Bars to left for pivot detection
input int      RightBars        = 15;    // Bars to right for pivot detection
input int      RetraceCandles   = 3;     // Maximum bars allowed after breakout for a valid retrace

//---- Risk Management & Trade Settings (unchanged) ----
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
input int      MaxTradesPerDay    = 5;
input bool     AllowMultiplePos   = false;
input ulong    EA_MagicNumber     = 123456;

//---- ATR indicator handle ----
int ATR_Handle;

//---- Dynamic arrays for pivot levels (all detected levels are kept) ----
double ResistanceLevels[]; // All detected resistance levels
double SupportLevels[];    // All detected support levels

//---- Breakout event structure ----
struct BreakoutEvent
  {
   double level;       // The pivot level (resistance for sell, support for buy)
   int    barCount;    // Number of bars counted since breakout was detected
   datetime startTime; // Time when breakout was detected
  };

//---- Dynamic arrays for breakout events ----
BreakoutEvent BreakoutSellEvents[];
BreakoutEvent BreakoutBuyEvents[];

//---- Daily trade count and last bar time ----
int      TradesToday  = 0;
int      LastTradeDay = 0;
datetime LastBarTime  = 0;

//---- Trade management object ----
CTrade   Trade;

//+------------------------------------------------------------------+
//| Helper: Insert a breakout event at beginning of sell events array |
//+------------------------------------------------------------------+
void InsertBreakoutSellEvent(const BreakoutEvent &evt)
  {
   int size = ArraySize(BreakoutSellEvents);
   ArrayResize(BreakoutSellEvents, size + 1);
   for(int i = size; i > 0; i--)
      BreakoutSellEvents[i] = BreakoutSellEvents[i-1];
   BreakoutSellEvents[0] = evt;
  }
  
//+------------------------------------------------------------------+
//| Helper: Insert a breakout event at beginning of buy events array  |
//+------------------------------------------------------------------+
void InsertBreakoutBuyEvent(const BreakoutEvent &evt)
  {
   int size = ArraySize(BreakoutBuyEvents);
   ArrayResize(BreakoutBuyEvents, size + 1);
   for(int i = size; i > 0; i--)
      BreakoutBuyEvents[i] = BreakoutBuyEvents[i-1];
   BreakoutBuyEvents[0] = evt;
  }
  
//+------------------------------------------------------------------+
//| Check if bar at index idx is a confirmed pivot high              |
//+------------------------------------------------------------------+
bool IsPivotHigh(int idx)
  {
   if(idx < RightBars) return false; 
   double pivot = iHigh(_Symbol, _Period, idx);
   for(int i = idx - LeftBars; i <= idx + RightBars; i++)
     {
      if(i == idx) continue;
      if(i < 0 || i >= Bars(_Symbol, _Period)) continue;
      if(iHigh(_Symbol, _Period, i) > pivot) return false;
     }
   return true;
  }
  
//+------------------------------------------------------------------+
//| Check if bar at index idx is a confirmed pivot low               |
//+------------------------------------------------------------------+
bool IsPivotLow(int idx)
  {
   if(idx < RightBars) return false;
   double pivot = iLow(_Symbol, _Period, idx);
   for(int i = idx - LeftBars; i <= idx + RightBars; i++)
     {
      if(i == idx) continue;
      if(i < 0 || i >= Bars(_Symbol, _Period)) continue;
      if(iLow(_Symbol, _Period, i) < pivot) return false;
     }
   return true;
  }
  
//+------------------------------------------------------------------+
//| Update pivot levels arrays and plot all detected levels as       |
//| horizontal trendlines spanning (LeftBars+RightBars) candles      |
//+------------------------------------------------------------------+
void UpdatePivotLevels()
  {
   int idx = RightBars; // Use bar at index = RightBars for confirmed pivot
   int periodSeconds = Period() * 60;  // Convert chart period (minutes) to seconds
   datetime pivotTime = iTime(_Symbol, _Period, idx);
   // The trendline will span (LeftBars + RightBars) candles in time.
   datetime endTime = pivotTime + (LeftBars + RightBars) * periodSeconds;
   
   // For a resistance pivot:
   if(IsPivotHigh(idx))
     {
      double newRes = iHigh(_Symbol, _Period, idx);
      int pos = ArraySize(ResistanceLevels);
      ArrayResize(ResistanceLevels, pos + 1);
      ResistanceLevels[pos] = newRes;
      
      // Create a horizontal trendline by setting both endpoints to newRes.
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
  
//+------------------------------------------------------------------+
//| Update breakout events for SELL side                            |
//+------------------------------------------------------------------+
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
              { exists = true; break; }
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
  
//+------------------------------------------------------------------+
//| Update breakout events for BUY side                             |
//+------------------------------------------------------------------+
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
              { exists = true; break; }
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
  
//+------------------------------------------------------------------+
//| Check if any SELL breakout event meets the retrace condition     |
//| Valid if current close is below the breakout level before reaching |
//| RetraceCandles count; otherwise, event is discarded.             |
//+------------------------------------------------------------------+
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
               BreakoutSellEvents[k] = BreakoutSellEvents[k+1];
            ArrayResize(BreakoutSellEvents, ArraySize(BreakoutSellEvents) - 1);
           }
        }
      else
        {
         for(int k = j; k < ArraySize(BreakoutSellEvents) - 1; k++)
            BreakoutSellEvents[k] = BreakoutSellEvents[k+1];
         ArrayResize(BreakoutSellEvents, ArraySize(BreakoutSellEvents) - 1);
        }
     }
   return validSignal;
  }
  
//+------------------------------------------------------------------+
//| Check if any BUY breakout event meets the retrace condition      |
//| Valid if current close is above the breakout level before reaching |
//| RetraceCandles count; otherwise, event is discarded.             |
//+------------------------------------------------------------------+
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
               BreakoutBuyEvents[k] = BreakoutBuyEvents[k+1];
            ArrayResize(BreakoutBuyEvents, ArraySize(BreakoutBuyEvents) - 1);
           }
        }
      else
        {
         for(int k = j; k < ArraySize(BreakoutBuyEvents) - 1; k++)
            BreakoutBuyEvents[k] = BreakoutBuyEvents[k+1];
         ArrayResize(BreakoutBuyEvents, ArraySize(BreakoutBuyEvents) - 1);
        }
     }
   return validSignal;
  }
  
//+------------------------------------------------------------------+
//| Check if any trade is already open by this EA                    |
//+------------------------------------------------------------------+
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
  
//+------------------------------------------------------------------+
//| Check if current time is within allowed trading session          |
//+------------------------------------------------------------------+
bool IsWithinSession()
  {
   datetime srvTime = TimeCurrent();
   datetime gmtTime = srvTime - BrokerGMTOffset * 3600;
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   int startSec = SessionStartHour * 3600 + SessionStartMin * 60;
   int endSec   = SessionEndHour * 3600 + SessionEndMin * 60;
   int curSec   = dt.hour * 3600 + dt.min * 60;
   return (curSec >= startSec && curSec < endSec);
  }
  
//+------------------------------------------------------------------+
//| Open a new trade using ATR-based risk management                 |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
  {
   double atrVal[1];
   if(CopyBuffer(ATR_Handle, 0, 1, 1, atrVal) <= 0)
     {
      Print("Failed to retrieve ATR value.");
      return;
     }
   double atr = atrVal[0];
   double stopLossDist   = atr * ATR_SL_Multiplier;
   double takeProfitDist = stopLossDist * RiskRewardRatio;
   
   double entryPrice, slPrice, tpPrice;
   if(orderType == ORDER_TYPE_SELL)
     {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slPrice = entryPrice + stopLossDist;
      tpPrice = entryPrice - takeProfitDist;
     }
   else if(orderType == ORDER_TYPE_BUY)
     {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slPrice = entryPrice - stopLossDist;
      tpPrice = entryPrice + takeProfitDist;
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
  
//+------------------------------------------------------------------+
//| Manage trades: daily limits, session check, and trade signals      |
//+------------------------------------------------------------------+
void ManageTrades()
  {
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
   
   if(!AllowMultiplePos && IsAnyTradeOpen())
      return;
      
   if(!IsWithinSession())
      return;
      
   // Update breakout events for both SELL and BUY sides
   UpdateBreakoutSellEvents();
   UpdateBreakoutBuyEvents();
   
   bool signalSell = CheckSFPSellSignal();
   bool signalBuy  = CheckSFPBuySignal();
   
   if(signalSell && !IsAnyTradeOpen())
     {
      OpenTrade(ORDER_TYPE_SELL);
      TradesToday++;
     }
   else if(signalBuy && !IsAnyTradeOpen())
     {
      OpenTrade(ORDER_TYPE_BUY);
      TradesToday++;
     }
  }
  
//+------------------------------------------------------------------+
//| Main OnTick function                                             |
//+------------------------------------------------------------------+
void OnTick_SFP()
  {
   datetime currBarTime = iTime(_Symbol, _Period, 0);
   if(currBarTime != LastBarTime)
     {
      UpdatePivotLevels();
      ManageTrades();
      LastBarTime = currBarTime;
     }
  }
  
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ATR_Handle = iATR(_Symbol, _Period, ATR_Period);
   if(ATR_Handle == INVALID_HANDLE)
     {
      Print("Failed to initialize ATR indicator.");
      return(INIT_FAILED);
     }
   // Initialize pivot arrays as empty
   ArrayResize(ResistanceLevels, 0);
   ArrayResize(SupportLevels, 0);
   
   ArrayResize(BreakoutSellEvents, 0);
   ArrayResize(BreakoutBuyEvents, 0);
   
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   OnTick_SFP();
  }
//+------------------------------------------------------------------+
