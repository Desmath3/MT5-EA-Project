//+------------------------------------------------------------------+
//|                                                   MA_Ribbon.mq5  |
//|                        Copyright 2021, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// V2 just enables the option to enable or disable buyclose and sellclose i.e // Enable or disable reversal close logic
input ENUM_MA_METHOD MA_Method       = MODE_EMA; // Type of Moving Average
input bool EnableReversalClose = true; // Enable or disable reversal close logic
input double FixedTakeProfit         = 50.0;     // Fixed take profit in pips
input double FixedStopLoss           = 30.0;     // Fixed stop loss in pips
input double PartialCloseProfitPips = 30.0; // Profit in pips to initiate partial close
input double PartialClosePercentage = 50.0; // Percentage of the position to close
input bool SetBreakeven = true;        // Flag to enable/disable setting breakeven
input double BreakevenPips = 50.0;      // Distance in pips to set the breakeven stop loss
input bool UseFixedSLTP              = true;     // Use fixed SL and TP
input double MaxPipsFromMA = 10.0; // Maximum allowed distance in pips from the MA to open trades
input double LotSize                 = 0.1;      // Trading lot size
input int Slippage                   = 3;        // Slippage in points
input ulong MagicNumber              = 123456;   // Unique identifier for EA's orders
input int LookbackPeriod = 14; // Lookback period for high and low
input int StartHour                  = 8;        // Start hour of the trading session (GMT)
input int StartMinute                = 0;        // Start minute of the trading session (GMT)
input int EndHour                    = 17;       // End hour of the trading session (GMT)
input int EndMinute                  = 0;        // End minute of the trading session (GMT)
input int BrokerGMTOffset            = 0;        // Broker GMT Offset
input int MAPeriod1                  = 5;        // First MA period
input int MAPeriod2                  = 10;       // Second MA period
input int MAPeriod3                  = 15;       // Third MA period
input int MAPeriod4                  = 20;       // Fourth MA period
input int MAPeriod5                  = 25;       // Fifth MA period
input int MAPeriod6                  = 30;       // Sixth MA period
input int BollingerPeriod = 20; // Bollinger Bands period
input double BollingerDeviation = 2.0; // Bollinger Bands deviation

enum TradeDirection {
    LONG = 1,
    NONE = 0,
    SHORT = -1
};
TradeDirection tradeDirection = NONE;
bool buySignal = false;
bool sellSignal = false;

// Function declarations
//bool IsWithinMaxPipsFromAllMAs(string symbol, ENUM_TIMEFRAMES period, int &maHandles[], double MaxPipsFromMA);
//double CalculateDistanceFromMA(int handle, string symbol, ENUM_TIMEFRAMES period);
//double FindMAWithHighestDistance(string symbol, ENUM_TIMEFRAMES period, int &maHandles[], int &indexOfMaxDistance);

int maHandles[6];                    // Array to store handles of the MAs
int BandHandle;
double upperBand[1] ;
double lowerBand[1] ; 
CTrade trade;                        // Trade object for order management
datetime lastBarTime = 0;            // Track the last bar time
  // Check for Buy or Sell signals


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize MA handles
    for(int i = 0; i < ArraySize(maHandles); i++)
    {
        maHandles[i] = iMA(_Symbol, _Period, MAPeriod1 + i * 5, 0, MA_Method, PRICE_CLOSE);
        if(maHandles[i] == INVALID_HANDLE)
        {
            Print("Failed to get handle for MA with period ", MAPeriod1 + i * 5);
            return(INIT_FAILED);
        }
    }
    BandHandle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDeviation, PRICE_CLOSE);
    return(INIT_SUCCEEDED); // This return statement should be inside OnInit()
}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if(currentBarTime != lastBarTime) {
        // New bar logic here
        ManageTrades();
        lastBarTime = currentBarTime; // Update the last bar time after processing
    }
    // Call to check for partial close on every tick
    CheckAndExecutePartialClose();
}


//+------------------------------------------------------------------+
//| Manage trades based on signals                                   |
//+------------------------------------------------------------------+
void ManageTrades() 
{
    
    
    double lastClose = iClose(_Symbol, _Period, 1);
    {
             CopyBuffer(BandHandle, 1, 0, 1, upperBand);
             CopyBuffer(BandHandle, 2, 0, 1, lowerBand);
         }
            if(lastClose > upperBand[0])
            {
                tradeDirection = LONG;
                
            }
            else if(lastClose < lowerBand[0])
            {
                tradeDirection = SHORT;
                
            }
    // Get the highest high and the lowest low of the lookback period
    double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackPeriod, 2));
    
    double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackPeriod, 2));
    
  
    
    double currentClose = iClose(_Symbol, _Period, 1);
    // Define buy and sell close conditions based on the new trade logic
    bool buyClose = EnableReversalClose && (currentClose > highestHigh);
    bool sellClose = EnableReversalClose && (currentClose < lowestLow);
    //bool buySignal = false;
    //bool sellSignal = false;
   // Check for Buy or Sell signals with the additional filter for maximum pip distance from all MAs
    if (tradeDirection == LONG && IsAboveAllMovingAverages()) {
        buySignal = true;
        sellSignal = false;
           } else if (tradeDirection == SHORT && IsBelowAllMovingAverages() ) {
        sellSignal = true;
        buySignal = false;
        
    }
   
    // Check for existing positions and manage them based on the signals
    ulong ticket;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
            // Check if the position is for the current symbol and the MagicNumber matches
            if(positionSymbol != _Symbol || positionMagic != MagicNumber)
                continue; // Skip this position if it's not for the current symbol or not opened by this EA

            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            // Check for opposite positions and close them if needed
            if((buyClose) && posType == POSITION_TYPE_SELL)
            {
                Print("Closing SELL position due to a BUY signal.");
                if(!trade.PositionClose(ticket))
                    Print("Error closing SELL position: ", GetLastError());
            }
            else if((sellClose) && posType == POSITION_TYPE_BUY)
            {
                Print("Closing BUY position due to a SELL signal.");
                if(!trade.PositionClose(ticket))
                    Print("Error closing BUY position: ", GetLastError());
	    }
		
        }

    }
    	// After managing existing trades, check if we need to open new trades
   // Before deciding to open a trade, check if the current price is within MaxPipsFromMA from all MAs
    int indexOfMaxDistance = -1; // Declare variable to hold the index of MA with the highest distance
    double maxDistance = FindMAWithHighestDistance(_Symbol, _Period, indexOfMaxDistance); // Corrected function call

    if(maxDistance < MaxPipsFromMA) {
        // The current price is within MaxPipsFromMA from all MAs
        // Check for Buy or Sell signals with the additional filter for maximum pip distance from all MAs
        if (buySignal && IsWithinSession() && !IsAlreadyBought() && IsAboveAllMovingAverages() ) {
            OpenTrade(ORDER_TYPE_BUY);
        } else if (sellSignal && IsWithinSession() && !IsAlreadySold() && IsBelowAllMovingAverages()) {
            OpenTrade(ORDER_TYPE_SELL);
        }
    }
  
}
bool IsAlreadyBought() {
    // Check for existing BUY positions with the same magic number
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
                PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
                PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                return true;
            }
        }
    }
    return false;
}

bool IsAlreadySold() {
    // Check for existing SELL positions with the same magic number
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
                PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
                PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if the current close price is above all moving averages    |
//+------------------------------------------------------------------+
bool IsAboveAllMovingAverages() {
    double maBuffer[1]; // Buffer to hold the MA value
    for(int i = 0; i < ArraySize(maHandles); i++) {
        if(CopyBuffer(maHandles[i], 0, 1, 1, maBuffer) > 0) {
            if(iClose(_Symbol, _Period, 1) <= maBuffer[0]) {
                return false; // If the close price is less than or equal to any MA, it's not above all
            }
        } else {
            Print("Failed to copy data for MA handle: ", maHandles[i]);
            return false; // In case of an error, default to false
        }
    }
    return true; // The close price is above all MAs
}

//+------------------------------------------------------------------+
//| Check if the current close price is below all moving averages    |
//+------------------------------------------------------------------+
bool IsBelowAllMovingAverages() {
    double maBuffer[1]; // Buffer to hold the MA value
    for(int i = 0; i < ArraySize(maHandles); i++) {
        if(CopyBuffer(maHandles[i], 0, 1, 1, maBuffer) > 0) {
            if(iClose(_Symbol, _Period, 1) >= maBuffer[0]) {
                return false; // If the close price is greater than or equal to any MA, it's not below all
            }
        } else {
            Print("Failed to copy data for MA handle: ", maHandles[i]);
            return false; // In case of an error, default to false
        }
    }
    return true; // The close price is below all MAs
}
//+------------------------------------------------------------------+
//| Check if we are within the trading session                       |
//+------------------------------------------------------------------+
bool IsWithinSession() {
    Print("IsWithinSession called"); // This will confirm the function is being triggered

    datetime serverTime = TimeCurrent();
    datetime gmtTime = serverTime - BrokerGMTOffset * 3600;
    MqlDateTime gmtDateTime;
    TimeToStruct(gmtTime, gmtDateTime);

    int sessionStart = StartHour * 3600 + StartMinute * 60;
    int sessionEnd = EndHour * 3600 + EndMinute * 60;
    int currentTime = gmtDateTime.hour * 3600 + gmtDateTime.min * 60;

    Print("Server Time: ", TimeToString(serverTime));
    Print("GMT Time: ", TimeToString(gmtTime));
    Print("Session Start: ", sessionStart);
    Print("Session End: ", sessionEnd);
    Print("Current Time: ", currentTime);

    if (currentTime >= sessionStart && currentTime < sessionEnd) {
        Print("We are within the trading session.");
        return true;
    } else {
        Print("We are outside the trading session.");
        return false;
    }
}

double CalculateDistanceFromMA(int maHandle, string symbol, ENUM_TIMEFRAMES period) {
    double maBuffer[1]; // Buffer to hold the MA value
    // Copy the latest value of the MA into the buffer
    if(CopyBuffer(maHandle, 0, 0, 1, maBuffer) <= 0) {
        Print("Failed to copy data for MA handle: ", maHandle);
        return -1; // Return -1 to indicate failure
    }
    // Get the current close price
    double currentPrice = iClose(symbol, period, 0);
    // Calculate and return the absolute distance
    return MathAbs(currentPrice - maBuffer[0]);
}

double PositionGetProfitPips(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return 0;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double profitPips = (currentPrice - openPrice) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? profitPips : -profitPips;
}


//+------------------------------------------------------------------+
//| Check and execute partial close                                  |
//+------------------------------------------------------------------+
void CheckAndExecutePartialClose() 
{
    // Loop through all positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            // Ensure the position is for the current symbol and opened by this EA
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
            if(positionSymbol != _Symbol || positionMagic != MagicNumber)
                continue;

            // Calculate profit in pips
            double profitPips = PositionGetProfitPips(ticket);
            if(profitPips >= PartialCloseProfitPips)
            {
                // Calculate the volume to close
                double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (PartialClosePercentage / 100.0), 2);

                // Execute a market order to partially close the position
                if(trade.PositionClosePartial(ticket, volumeToClose))
                {
                    Print("Partial close executed for ticket #", ticket);
                    
                    // Check if breakeven feature is enabled
                    if(SetBreakeven)
                    {
                        // Calculate new stop loss level
                        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                        double newStopLoss = 0.0;
                        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                            newStopLoss = openPrice + BreakevenPips * _Point;
                        else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                            newStopLoss = openPrice - BreakevenPips * _Point;

                        // Modify the stop loss
                        if(!trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
                            Print("Error setting new SL after partial close: ", GetLastError());
                    }
                }
                else
                {
                    Print("Error in partial closing: ", GetLastError());
                }
            }
        }
    }
}


// Function to find the MA with the highest distance from the current price
double FindMAWithHighestDistance(string symbol, ENUM_TIMEFRAMES period, int &indexOfMaxDistance) {
    indexOfMaxDistance = -1;
    double maxDistance = 0;
    double distance;

    // Iterate through all MAs
    for(int i = 0; i < ArraySize(maHandles); i++) {
        // Calculate the distance from the current price to the current MA
        distance = CalculateDistanceFromMA(maHandles[i], symbol, period);
        if(distance == -1) continue; // Skip if the distance calculation failed

        // Convert the distance to pips based on the number of digits of the symbol
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        if (digits == 5 || digits == 3) { // For 5 digit forex pairs or 3 digit JPY pairs
            distance /= 0.0001; // 1 pip is 0.0001 for non-JPY pairs
        } else if (digits == 4 || digits == 2) { // For 4 digit forex pairs or 2 digit JPY pairs
            distance /= 0.01; // 1 pip is 0.01 for JPY pairs
        }

        // Check if the calculated distance is larger than the maximum found so far
        if (distance > maxDistance) {
            maxDistance = distance;
            indexOfMaxDistance = i;
        }
    }
      Print("maxDistance: ", maxDistance, "MaxPipsFromMA: ", MaxPipsFromMA );
    return maxDistance;
}

//+------------------------------------------------------------------+
//| Open a new trade                                                 |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
    // Define the request structure and result structure
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
 
    // Set the request parameters
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = orderType;
    request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = (orderType == ORDER_TYPE_BUY) ? request.price - (FixedStopLoss * _Point) : request.price + (FixedStopLoss * _Point);
    request.tp = (orderType == ORDER_TYPE_BUY) ? request.price + (FixedTakeProfit * _Point) : request.price - (FixedTakeProfit * _Point);
    request.deviation = Slippage;
    request.magic = MagicNumber;
    request.comment = "MA Ribbon Trade";
 
    // Send the trade request
    if(!trade.OrderSend(request, result))
    {
        Print("OrderSend failed with error code: ", GetLastError());
    }
    else
    {
        Print("Trade opened with ticket #: ", result.order);
    }
}
//+------------------------------------------------------------------+


