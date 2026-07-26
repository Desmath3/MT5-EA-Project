#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// Input Parameters
input bool TradeNewYork = true;        // Trade during New York session
input bool TradeLondon  = true;        // Trade during London session
input bool TradeTokyo   = false;       // Trade during Tokyo session
input bool TradeSydney  = false;       // Trade during Sydney session

input int  LeftBars     = 15;          // Bars to left for pivot detection
input int  RightBars    = 15;          // Bars to right for pivot detection

input int  ATR_Period   = 14;          // ATR period for stop loss
input double ATR_SL_Multiplier = 2.0;  // ATR multiplier for stop loss
input double RiskPercent = 1.0;        // Risk percentage per trade
input double RR_Ratio   = 2.0;         // Risk-reward ratio for take profit

input int  ADX_Period   = 14;          // ADX period
input double ADX_Threshold = 25.0;     // ADX threshold for trend strength

input bool EnableBreakeven = true;     // Enable breakeven adjustment
input double BreakevenTriggerReward = 1.0; // Reward multiplier to trigger breakeven
input double BreakevenReward = 0.1;    // Reward multiplier for new SL

input bool EnableReversalExit = true;  // Enable reversal exit
input int  LookbackHighLow = 5;        // Lookback period for reversal exit

input int  MaxTradesPerDay = 2;        // Max trades per day
input int  EA_MagicNumber = 12345;     // Magic number for trades

input int MinBarsForRetest = 5;        // Minimum bars after breakout for valid retest
input int MaxBarsForRetest = 20;       // Maximum bars after breakout for valid retest
input int MinCandlesAboveBelow = 3;    // Minimum candles to stay above/below after breakout

// Global Variables
int ATR_Handle;
int ADX_Handle;
double RecentSwingHigh = 0;
double RecentSwingLow = 0;
datetime SwingHighTime = 0;           // Time when swing high was set
datetime SwingLowTime = 0;            // Time when swing low was set
int TradesToday = 0;
int LastTradeDay = 0;
datetime LastBarTime = 0;
CTrade Trade;
CPositionInfo PositionInfo;

datetime BuyBreakoutTime = 0;
bool WaitingForBuyRetest = false;
int BuyConsecutiveAbove = 0;

datetime SellBreakoutTime = 0;
bool WaitingForSellRetest = false;
int SellConsecutiveBelow = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
   ATR_Handle = iATR(_Symbol, _Period, ATR_Period);
   if (ATR_Handle == INVALID_HANDLE) {
      Print("ATR initialization failed");
      return INIT_FAILED;
   }
   
   ADX_Handle = iADX(_Symbol, _Period, ADX_Period);
   if (ADX_Handle == INVALID_HANDLE) {
      Print("ADX initialization failed");
      return INIT_FAILED;
   }
   
   Trade.SetExpertMagicNumber(EA_MagicNumber);
   
   RecentSwingHigh = 0;
   RecentSwingLow = 0;
   SwingHighTime = 0;
   SwingLowTime = 0;
   LastBarTime = 0;
   BuyBreakoutTime = 0;
   WaitingForBuyRetest = false;
   BuyConsecutiveAbove = 0;
   SellBreakoutTime = 0;
   WaitingForSellRetest = false;
   SellConsecutiveBelow = 0;
   
   // Remove grid lines from the chart
   ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
   
   // Expiration date: July 17th, 2025 23:59:59 GMT
   datetime ExpirationDate = StringToTime("2025.08.17 23:59:59");
   if(TimeCurrent() > ExpirationDate)
   {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return(INIT_FAILED);
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {

   // Expiration date: July 17th, 2025 23:59:59 GMT
   datetime ExpirationDate = StringToTime("2025.08.17 23:59:59");
   if(TimeCurrent() > ExpirationDate)
   {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return;
   }
   
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if (currentBarTime != LastBarTime) {
      UpdateSwingLevels();
      ManageTrades();
      LastBarTime = currentBarTime;
   }
   
   CheckBreakeven();
   CheckReversalExit();
}

//+------------------------------------------------------------------+
//| Session filter function                                            |
//+------------------------------------------------------------------+
bool IsWithinSession() {
   datetime gm = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(gm, dt);
   int minutes = dt.hour * 60 + dt.min;
   bool ok = false;
   
   if (TradeNewYork && minutes >= 12 * 60 && minutes < 21 * 60) ok = true;
   if (TradeLondon  && minutes >=  7 * 60 && minutes < 12 * 60) ok = true;
   if (TradeTokyo   && minutes >=  0     && minutes <  7 * 60) ok = true;
   if (TradeSydney  && (minutes >= 22 * 60 || minutes < 0))    ok = true;
   
   return ok;
}

//+------------------------------------------------------------------+
//| Pivot high detection function                                      |
//+------------------------------------------------------------------+
bool IsPivotHigh(int idx) {
   if (idx < RightBars) return false;
   double value = iHigh(_Symbol, _Period, idx);
   for (int i = idx - RightBars; i <= idx + LeftBars; i++) {
      if (i == idx || i < 0 || i >= Bars(_Symbol, _Period)) continue;
      if (iHigh(_Symbol, _Period, i) >= value) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Pivot low detection function                                       |
//+------------------------------------------------------------------+
bool IsPivotLow(int idx) {
   if (idx < RightBars) return false;
   double value = iLow(_Symbol, _Period, idx);
   for (int i = idx - RightBars; i <= idx + LeftBars; i++) {
      if (i == idx || i < 0 || i >= Bars(_Symbol, _Period)) continue;
      if (iLow(_Symbol, _Period, i) <= value) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Update swing levels and invalidate old ones                        |
//+------------------------------------------------------------------+
void UpdateSwingLevels() {
   int idx = RightBars;
   datetime t0 = iTime(_Symbol, _Period, idx);
   datetime t1 = t0 + RightBars * PeriodSeconds(_Period);
   
   // Check if existing levels have expired
   if (SwingHighTime > 0) {
      int barsSinceSwingHigh = iBarShift(_Symbol, _Period, SwingHighTime);
      if (barsSinceSwingHigh > MaxBarsForRetest) {
         RecentSwingHigh = 0;
         SwingHighTime = 0;
         WaitingForBuyRetest = false;
         BuyConsecutiveAbove = 0;
      }
   }
   
   if (SwingLowTime > 0) {
      int barsSinceSwingLow = iBarShift(_Symbol, _Period, SwingLowTime);
      if (barsSinceSwingLow > MaxBarsForRetest) {
         RecentSwingLow = 0;
         SwingLowTime = 0;
         WaitingForSellRetest = false;
         SellConsecutiveBelow = 0;
      }
   }
   
   // Detect new swing highs
   if (IsPivotHigh(idx)) {
      RecentSwingHigh = iHigh(_Symbol, _Period, idx);
      SwingHighTime = t0;
      WaitingForBuyRetest = false;
      BuyConsecutiveAbove = 0;
      string name = "SwingHigh_" + TimeToString(t0);
      if (ObjectCreate(0, name, OBJ_TREND, 0, t0, RecentSwingHigh, t1, RecentSwingHigh)) {
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      }
   }
   
   // Detect new swing lows
   if (IsPivotLow(idx)) {
      RecentSwingLow = iLow(_Symbol, _Period, idx);
      SwingLowTime = t0;
      WaitingForSellRetest = false;
      SellConsecutiveBelow = 0;
      string name = "SwingLow_" + TimeToString(t0);
      if (ObjectCreate(0, name, OBJ_TREND, 0, t0, RecentSwingLow, t1, RecentSwingLow)) {
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      }
   }
}

//+------------------------------------------------------------------+
//| ADX filter function                                                |
//+------------------------------------------------------------------+
bool AdditionalFiltersPassed(ENUM_ORDER_TYPE signal) {
   double adxVal[];
   ArraySetAsSeries(adxVal, true);
   if (CopyBuffer(ADX_Handle, 0, 1, 1, adxVal) <= 0) return false;
   return adxVal[0] < ADX_Threshold;
}

//+------------------------------------------------------------------+
//| Open trade function with risk management                           |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType) {
   double atr[], bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ArraySetAsSeries(atr, true);
   if (CopyBuffer(ATR_Handle, 0, 1, 1, atr) <= 0) return;
   
   double slDistance = atr[0] * ATR_SL_Multiplier;
   double lotSize = CalculateLotSize(slDistance);
   if (lotSize <= 0) return;
   
   double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   double sl = (orderType == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;
   double tp = (orderType == ORDER_TYPE_BUY) ? price + slDistance * RR_Ratio : price - slDistance * RR_Ratio;
   
   if (orderType == ORDER_TYPE_BUY)
      Trade.Buy(lotSize, _Symbol, price, sl, tp, "Breakout Retest Buy");
   else
      Trade.Sell(lotSize, _Symbol, price, sl, tp, "Breakout Retest Sell");
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance) {
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);
   lotSize = NormalizeDouble(lotSize, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (lotSize < minLot) lotSize = minLot;
   if (lotSize > maxLot) lotSize = maxLot;
   return lotSize;
}

//+------------------------------------------------------------------+
//| Manage trades function with breakout and retest logic              |
//+------------------------------------------------------------------+
void ManageTrades() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if (dt.day != LastTradeDay) {
      TradesToday = 0;
      LastTradeDay = dt.day;
   }
   if (TradesToday >= MaxTradesPerDay || !IsWithinSession()) return;
   
   double c1 = iClose(_Symbol, _Period, 1);  // Previous bar close
   double low1 = iLow(_Symbol, _Period, 1);  // Previous bar low
   double high1 = iHigh(_Symbol, _Period, 1); // Previous bar high
   
   // Buy logic
   if (RecentSwingHigh > 0 && !WaitingForBuyRetest) {
      if (c1 > RecentSwingHigh) {
         BuyConsecutiveAbove++;
         if (BuyConsecutiveAbove >= MinCandlesAboveBelow) {
            WaitingForBuyRetest = true;
            BuyBreakoutTime = iTime(_Symbol, _Period, 1);
         }
      } else {
         BuyConsecutiveAbove = 0;
      }
   } else if (WaitingForBuyRetest) {
      int barsSinceBreakout = iBarShift(_Symbol, _Period, BuyBreakoutTime);
      if (barsSinceBreakout < MinBarsForRetest) {
         if (low1 <= RecentSwingHigh) {
            // Early retest: invalidate breakout, keep pivot level
            WaitingForBuyRetest = false;
            BuyConsecutiveAbove = 0;
         }
      } else if (barsSinceBreakout <= MaxBarsForRetest) {
         if (low1 <= RecentSwingHigh) {
            // Valid retest detected
            if (AdditionalFiltersPassed(ORDER_TYPE_BUY)) {
               bool buyOpen = false;
               for (int i = PositionsTotal() - 1; i >= 0; i--) {
                  ulong ticket = PositionGetTicket(i);
                  if (PositionSelectByTicket(ticket) && 
                      PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && 
                      PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                     buyOpen = true;
                     break;
                  }
               }
               if (!buyOpen) {
                  OpenTrade(ORDER_TYPE_BUY);
                  TradesToday++;
                  WaitingForBuyRetest = false;
               }
            }
         }
      } else {
         // Exceeded max bars, reset breakout (pivot level already invalidated in UpdateSwingLevels)
         WaitingForBuyRetest = false;
      }
   }
   
   // Sell logic
   if (RecentSwingLow > 0 && !WaitingForSellRetest) {
      if (c1 < RecentSwingLow) {
         SellConsecutiveBelow++;
         if (SellConsecutiveBelow >= MinCandlesAboveBelow) {
            WaitingForSellRetest = true;
            SellBreakoutTime = iTime(_Symbol, _Period, 1);
         }
      } else {
         SellConsecutiveBelow = 0;
      }
   } else if (WaitingForSellRetest) {
      int barsSinceBreakout = iBarShift(_Symbol, _Period, SellBreakoutTime);
      if (barsSinceBreakout < MinBarsForRetest) {
         if (high1 >= RecentSwingLow) {
            // Early retest: invalidate breakout, keep pivot level
            WaitingForSellRetest = false;
            SellConsecutiveBelow = 0;
         }
      } else if (barsSinceBreakout <= MaxBarsForRetest) {
         if (high1 >= RecentSwingLow) {
            // Valid retest detected
            if (AdditionalFiltersPassed(ORDER_TYPE_SELL)) {
               bool sellOpen = false;
               for (int i = PositionsTotal() - 1; i >= 0; i--) {
                  ulong ticket = PositionGetTicket(i);
                  if (PositionSelectByTicket(ticket) && 
                      PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && 
                      PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                     sellOpen = true;
                     break;
                  }
               }
               if (!sellOpen) {
                  OpenTrade(ORDER_TYPE_SELL);
                  TradesToday++;
                  WaitingForSellRetest = false;
               }
            }
         }
      } else {
         // Exceeded max bars, reset breakout (pivot level already invalidated in UpdateSwingLevels)
         WaitingForSellRetest = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Breakeven adjustment function                                      |
//+------------------------------------------------------------------+
void CheckBreakeven() {
   if (!EnableBreakeven) return;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double risk = MathAbs(openPrice - sl);
      double currentPrice = iClose(_Symbol, _Period, 0);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double triggerPrice = (posType == POSITION_TYPE_BUY) ? openPrice + risk * BreakevenTriggerReward : openPrice - risk * BreakevenTriggerReward;
      double newSL = (posType == POSITION_TYPE_BUY) ? openPrice + risk * BreakevenReward : openPrice - risk * BreakevenReward;
      if (posType == POSITION_TYPE_BUY && currentPrice >= triggerPrice && sl < newSL)
         Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      if (posType == POSITION_TYPE_SELL && currentPrice <= triggerPrice && sl > newSL)
         Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
   }
}

//+------------------------------------------------------------------+
//| Reversal exit function                                             |
//+------------------------------------------------------------------+
void CheckReversalExit() {
   if (!EnableReversalExit) return;
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, LookbackHighLow, 2);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW, LookbackHighLow, 2);
   double highestHigh = iHigh(_Symbol, _Period, hiIdx);
   double lowestLow = iLow(_Symbol, _Period, loIdx);
   double close1 = iClose(_Symbol, _Period, 1);
   bool revBuy = (close1 > highestHigh);
   bool revSell = (close1 < lowestLow);
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if (revBuy && posType == POSITION_TYPE_SELL) Trade.PositionClose(ticket);
      if (revSell && posType == POSITION_TYPE_BUY) Trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(ATR_Handle);
   IndicatorRelease(ADX_Handle);
}