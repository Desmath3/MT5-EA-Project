//+------------------------------------------------------------------+
//|                                        Breakout EA v2 MACD_MA    |
//| EA with ATR risk, dual-level breakeven, reward, MA ribbon & MACD  |
//| plus floating-profit-based close-all feature. © Your Name         |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--------------------------------------------------------------------
// User Inputs
//--------------------------------------------------------------------
input bool     TradeNewYork             = true;    // Trade during New York session
input bool     TradeLondon              = true;    // Trade during London session
input bool     TradeTokyo               = false;   // Trade during Tokyo session
input bool     TradeSydney              = false;   // Trade during Sydney session

input int      ATR_Period               = 14;      // ATR period for SL
input double   ATR_SL_Multiplier        = 2.0;     // ATR×multiplier = SL distance
input double   RiskRewardRatio          = 10.0;    // TP distance = SL×RR
input double   FixedRiskPerTrade        = 50.0;    // Fixed risk in account currency
input bool     UsePercentRisk           = false;   // Switch to % of balance risk
input double   RiskPercentage           = 1.0;     // % risk if enabled
input int      AllowedSlippage          = 3;       // Max slippage (points)
input int      MaxTradesPerDay          = 2;       // Daily entry cap
input ulong    EA_MagicNumber           = 123456;  // Magic number for EA trades

input bool     EnableBreakeven          = true;    // Enable breakeven move
input double   BreakevenTriggerReward   = 1.0;     // R multiple to trigger SL move
input double   BreakevenReward          = 1.1;     // R multiple for new SL

input bool     EnableReversalExit       = true;    // Enable reversal-based exit
input int      LookbackHighLow         = 14;       // Bars for reversal exit check

// MA Ribbon Inputs
input bool     EnableMARibbonFilter     = true;    // (kept for potential future use)
input ENUM_MA_METHOD MA_Method          = MODE_EMA;
input int      MA_StartPeriod           = 100;
input int      MA_PeriodStep            = 20;
#define NUM_MA 6                              // Number of MAs in ribbon

// MACD inputs
input int      MACD_FastEMAPeriod       = 12;
input int      MACD_SlowEMAPeriod       = 26;
input int      MACD_SignalPeriod        = 9;

// Close-all on floating profit
input double   CloseAllFloatingPercent  = 5.0;     // % of account balance to trigger mass-close

//--------------------------------------------------------------------
// Global Variables
//--------------------------------------------------------------------
int      ATR_Handle;
int      MAHandles[NUM_MA];
int      MACD_Handle;

int      TradesToday    = 0;
int      LastTradeDay   = 0;
datetime LastBarTime    = 0;

CTrade   Trade;

//--------------------------------------------------------------------
// Session Filter
//--------------------------------------------------------------------
bool IsWithinSession(){
   datetime gm = TimeGMT(); MqlDateTime dt; TimeToStruct(gm,dt);
   int minutes = dt.hour*60 + dt.min;
   bool ok = false;
   if(TradeNewYork && minutes>=12*60 && minutes<21*60) ok=true;
   if(TradeLondon  && minutes>= 7*60 && minutes<12*60) ok=true;
   if(TradeTokyo   && minutes>= 0    && minutes< 7*60) ok=true;
   if(TradeSydney  && (minutes>=22*60 || minutes<0)) ok=true;
   return ok;
}

//--------------------------------------------------------------------
// Open Trade with ATR-Based Risk
//--------------------------------------------------------------------
void OpenTrade(ENUM_ORDER_TYPE type){
   double arrATR[1]; if(CopyBuffer(ATR_Handle,0,0,1,arrATR)<=0) return;
   double atr = arrATR[0];
   double slDist = atr * ATR_SL_Multiplier;
   double tpDist = slDist * RiskRewardRatio;

   double entry = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = (type==ORDER_TYPE_BUY) ? entry - slDist : entry + slDist;
   double tp = (type==ORDER_TYPE_BUY) ? entry + tpDist : entry - tpDist;

   double riskAmt = UsePercentRisk ? AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercentage/100.0 : FixedRiskPerTrade;
   double tv = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double riskPerLot = (slDist/ts)*tv;
   if(riskPerLot<=0) return;

   double lots = NormalizeDouble(riskAmt/riskPerLot,2);
   double vmin = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vst  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(lots<vmin) lots=vmin; else lots = MathFloor(lots/vst)*vst;

   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lots;
   req.type      = type;
   req.price     = entry;
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = AllowedSlippage;
   req.magic     = EA_MagicNumber;
   req.comment   = (type==ORDER_TYPE_BUY?"Buy":"Sell");
   Trade.OrderSend(req,res);
}

//--------------------------------------------------------------------
// Manage Trades: Entry Logic
//--------------------------------------------------------------------
void ManageTrades(){
   // Daily reset
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day != LastTradeDay){ TradesToday=0; LastTradeDay=dt.day; }
   if(TradesToday>=MaxTradesPerDay || !IsWithinSession()) return;

   // Get MACD values
   double macdVals[2];
   if(CopyBuffer(MACD_Handle,0,1,2,macdVals)<=1) return;
   double macdCurr = macdVals[0], macdPrev = macdVals[1];

   // Get MA values
   double maVals[NUM_MA];
   for(int i=0;i<NUM_MA;i++){
      double tmp[1]; CopyBuffer(MAHandles[i],0,1,1,tmp);
      maVals[i] = tmp[0];
   }

   double close1 = iClose(_Symbol,_Period,1);
   double low1   = iLow(_Symbol,_Period,1);
   double high1  = iHigh(_Symbol,_Period,1);

   bool aboveAll = true, belowAll = true;
   for(int i=0;i<NUM_MA;i++){
      if(close1 <= maVals[i]) aboveAll = false;
      if(close1 >= maVals[i]) belowAll = false;
   }

   // BUY Conditions
   if(macdPrev <= 0 && macdCurr > 0 && aboveAll){ OpenTrade(ORDER_TYPE_BUY); TradesToday++; }
   if(macdCurr > 0 && aboveAll){
      for(int i=0;i<NUM_MA;i++){
         if(low1 <= maVals[i]){ OpenTrade(ORDER_TYPE_BUY); TradesToday++; break; }
      }
   }

   // SELL Conditions
   if(macdPrev >= 0 && macdCurr < 0 && belowAll){ OpenTrade(ORDER_TYPE_SELL); TradesToday++; }
   if(macdCurr < 0 && belowAll){
      for(int i=0;i<NUM_MA;i++){
         if(high1 >= maVals[i]){ OpenTrade(ORDER_TYPE_SELL); TradesToday++; break; }
      }
   }
}

//--------------------------------------------------------------------
// Breakeven Trigger & Reward
//--------------------------------------------------------------------
void CheckBreakeven(){
   if(!EnableBreakeven) return;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t) || PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double risk = MathAbs(open - sl);
      double curr = iClose(_Symbol,_Period,0);
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double trg   = (pt==POSITION_TYPE_BUY)? open + risk*BreakevenTriggerReward : open - risk*BreakevenTriggerReward;
      double newSL = (pt==POSITION_TYPE_BUY)? open + risk*BreakevenReward      : open - risk*BreakevenReward;
      if(pt==POSITION_TYPE_BUY && curr>=trg && sl<newSL) Trade.PositionModify(t,newSL,PositionGetDouble(POSITION_TP));
      if(pt==POSITION_TYPE_SELL&& curr<=trg && sl>newSL) Trade.PositionModify(t,newSL,PositionGetDouble(POSITION_TP));
   }
}

//--------------------------------------------------------------------
// Reversal Exit
//--------------------------------------------------------------------
void CheckReversalExit(){
   if(!EnableReversalExit) return;
   int hiIdx = iHighest(_Symbol,_Period,MODE_HIGH,LookbackHighLow,2);
   int loIdx = iLowest(_Symbol,_Period,MODE_LOW, LookbackHighLow,2);
   double highestHigh = iHigh(_Symbol,_Period,hiIdx);
   double lowestLow   = iLow(_Symbol,_Period,loIdx);
   double close1 = iClose(_Symbol,_Period,1);
   bool revBuy  = (close1 > highestHigh);
   bool revSell = (close1 < lowestLow);
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t) || PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(revBuy  && pt==POSITION_TYPE_SELL) Trade.PositionClose(t);
      if(revSell && pt==POSITION_TYPE_BUY ) Trade.PositionClose(t);
   }
}

//--------------------------------------------------------------------
// Close All on Floating Profit Threshold
//--------------------------------------------------------------------
void CheckCloseOnFloatingProfit(){
   double totalProfit = 0;
   for(int i=PositionsTotal()-1;i>=0; i--){
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t) || PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   double threshold = AccountInfoDouble(ACCOUNT_BALANCE) * (CloseAllFloatingPercent/100.0);
   if(totalProfit >= threshold){
      for(int i=PositionsTotal()-1;i>=0;i--){
         ulong t = PositionGetTicket(i);
         if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC)==EA_MagicNumber)
            Trade.PositionClose(t);
      }
   }
}

//--------------------------------------------------------------------
// Main Tick
//--------------------------------------------------------------------
void OnTick(){
   datetime tm = iTime(_Symbol,_Period,0);
   if(tm != LastBarTime){ ManageTrades(); LastBarTime = tm; }
   CheckBreakeven();
   CheckReversalExit();
   CheckCloseOnFloatingProfit();
}

//--------------------------------------------------------------------
// Initialization
//--------------------------------------------------------------------
int OnInit(){
   ATR_Handle = iATR(_Symbol,_Period,ATR_Period);
   if(ATR_Handle==INVALID_HANDLE) return INIT_FAILED;

   for(int i=0;i<NUM_MA;i++){
      int p = MA_StartPeriod + i*MA_PeriodStep;
      MAHandles[i] = iMA(_Symbol,_Period,p,0,MA_Method,PRICE_CLOSE);
      if(MAHandles[i]==INVALID_HANDLE) return INIT_FAILED;
   }

   MACD_Handle = iMACD(_Symbol,_Period,MACD_FastEMAPeriod,MACD_SlowEMAPeriod,MACD_SignalPeriod,PRICE_CLOSE);
   if(MACD_Handle==INVALID_HANDLE) return INIT_FAILED;

   return INIT_SUCCEEDED;
}
