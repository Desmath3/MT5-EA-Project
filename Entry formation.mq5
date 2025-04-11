#property copyright "Your Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Forward declarations
bool IsAlreadyBought();
bool IsAlreadySold();
void ManageOpenPositions();
double CalculatePositionSize(double entryPrice, double stopLoss);
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice);
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss);

// Enums
enum ENUM_RISK_TYPE {
    RISK_PERCENT = 0,  // Percentage of Balance
    RISK_FIXED   = 1   // Fixed USD Amount
};

enum TradeDirection {
    LONG = 1,
    NONE = 0,
    SHORT = -1
};

// Risk Management Parameters
input group "Risk Management"
input ENUM_RISK_TYPE RiskType       = RISK_PERCENT; // Risk Type
input double RiskValue              = 1.0;          // Risk Value (% or USD)
input double MinLotSize             = 0.01;         // Minimum Lot Size
input double MaxLotSize             = 10.0;         // Maximum Lot Size
input bool UseFixedLotSize          = false;        // Use Fixed Lot Size
input double FixedLotSize           = 0.1;          // Fixed Lot Size Value

// Trade Parameters
input group "Trade Parameters"
input double FixedTakeProfit        = 50.0;         // Fixed take profit in pips
input double FixedStopLoss          = 30.0;         // Fixed stop loss in pips
input double PartialCloseProfitPips = 30.0;         // Profit in pips to initiate partial close
input double PartialClosePercentage = 50.0;         // Percentage of position to close
input double BreakevenPips          = 50.0;         // Distance in pips to set breakeven
input bool UseFixedSLTP             = true;         // Use fixed SL and TP
input int Slippage                  = 3;            // Slippage in points
input ulong MagicNumber             = 123456;       // EA identifier

// Time Parameters
input group "Trading Session"
input int StartHour                 = 8;            // Session start hour (GMT)
input int StartMinute              = 0;            // Session start minute
input int EndHour                  = 17;           // Session end hour (GMT)
input int EndMinute                = 0;            // Session end minute
input int BrokerGMTOffset          = 0;            // Broker GMT Offset

// Strategy Parameters
input group "Strategy Settings"
input int LookbackPeriod           = 14;           // Lookback period
input int LookbackCandles          = 5;            // Candles for high/low
input bool UsePartialClose         = true;         // Enable partial close
input bool UseBreakeven            = true;         // Enable breakeven
input bool UseDailyBias            = true;         // Enable daily bias
input double RiskRewardRatio       = 2.0;          // Risk:Reward ratio
input int StopLossPips             = 10;           // Stop loss pips
input double BreakevenReward       = 2.0;          // Reward multiple for breakeven
input double PartialCloseReward    = 1.0;          // Reward multiple for partial close

// Visual Parameters
input group "Visual Settings"
input color BuyColor               = clrGreen;      // Buy signal color
input color SellColor              = clrRed;        // Sell signal color

// Global Variables
CTrade trade;                        // Trade object
CPositionInfo positionInfo;         // Position info object
datetime lastBarTime = 0;           // Last bar time
TradeDirection tradeDirection = NONE;
bool buySignal = false;
bool sellSignal = false;

//+------------------------------------------------------------------+
//| Calculate position size based on risk                              |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLoss) {
    if(UseFixedLotSize) {
        return NormalizeDouble(MathMin(MaxLotSize, MathMax(MinLotSize, FixedLotSize)), 2);
    }
    
    double riskAmount = (RiskType == RISK_PERCENT) ? 
                       AccountInfoDouble(ACCOUNT_BALANCE) * (RiskValue / 100.0) : 
                       RiskValue;
    
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / tickSize;
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    if(stopDistance == 0) return MinLotSize;
    
    double lotSize = riskAmount / (stopDistance * pointValue);
    lotSize = MathMin(MaxLotSize, MathMax(MinLotSize, lotSize));
    
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    return NormalizeDouble(MathFloor(lotSize / lotStep) * lotStep, 2);
}

//+------------------------------------------------------------------+
//| Calculate stop loss level                                          |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice) {
    if(UseFixedSLTP) {
        return (orderType == ORDER_TYPE_BUY_LIMIT) ? 
               entryPrice - (FixedStopLoss * _Point) : 
               entryPrice + (FixedStopLoss * _Point);
    }
    
    if(orderType == ORDER_TYPE_BUY_LIMIT) {
        double lowestLow = iLow(_Symbol, PERIOD_CURRENT, 0);
        for(int i = 1; i <= LookbackCandles; i++) {
            lowestLow = MathMin(lowestLow, iLow(_Symbol, PERIOD_CURRENT, i));
        }
        return lowestLow - (StopLossPips * _Point);
    } else {
        double highestHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
        for(int i = 1; i <= LookbackCandles; i++) {
            highestHigh = MathMax(highestHigh, iHigh(_Symbol, PERIOD_CURRENT, i));
        }
        return highestHigh + (StopLossPips * _Point);
    }
}

//+------------------------------------------------------------------+
//| Calculate take profit level                                        |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss) {
    if(UseFixedSLTP) {
        return (orderType == ORDER_TYPE_BUY_LIMIT) ? 
               entryPrice + (FixedTakeProfit * _Point) : 
               entryPrice - (FixedTakeProfit * _Point);
    }
    
    double riskDistance = MathAbs(entryPrice - stopLoss);
    return (orderType == ORDER_TYPE_BUY_LIMIT) ? 
           entryPrice + (riskDistance * RiskRewardRatio) : 
           entryPrice - (riskDistance * RiskRewardRatio);
}

//+------------------------------------------------------------------+
//| Check if position is already bought                                |
//+------------------------------------------------------------------+
bool IsAlreadyBought() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) == _Symbol && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if position is already sold                                  |
//+------------------------------------------------------------------+
bool IsAlreadySold() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) == _Symbol && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Open new trade                                                     |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType, double price) {
    double stopLoss = CalculateStopLoss(orderType, price);
    double takeProfit = CalculateTakeProfit(orderType, price, stopLoss);
    double lotSize = CalculatePositionSize(price, stopLoss);
    
    trade.PositionOpen(_Symbol, orderType, lotSize, price, stopLoss, takeProfit, "Entry Formation EA");
}

//+------------------------------------------------------------------+
//| Manage open positions                                              |
//+------------------------------------------------------------------+
void ManageOpenPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol || 
           PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
           
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        double takeProfit = PositionGetDouble(POSITION_TP);
        
        // Handle breakeven
        if(UseBreakeven) {
            double profitPips = MathAbs(currentPrice - openPrice) / _Point;
            if(profitPips >= BreakevenPips) {
                double newSL = openPrice;
                if(MathAbs(stopLoss - newSL) > _Point) {
                    trade.PositionModify(PositionGetTicket(i), newSL, takeProfit);
                }
            }
        }
    }
}
