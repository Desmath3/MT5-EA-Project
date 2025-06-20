//+------------------------------------------------------------------+
//|                                        Breakout EA v2.mq5        |
//| EA with ATR risk, dual-level breakeven trigger & reward,        |
//| BB Trend & MA Ribbon filters, session filtering, pivots, and     |
//| configurable support/resistance count. © Your Name – CC BY-NC-SA 4.0 |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--------------------------------------------------------------------
// Session Filter Inputs
//--------------------------------------------------------------------
input bool TradeNewYork      = true;   // Trade during New York session
input bool TradeLondon       = true;   // Trade during London session
input bool TradeTokyo        = false;  // Trade during Tokyo session
input bool TradeSydney       = false;  // Trade during Sydney session

//--------------------------------------------------------------------
// Breakout / Pivot Settings
//--------------------------------------------------------------------
input int  LeftBars          = 15;     // Bars to left for pivot detection
input int  RightBars         = 15;     // Bars to right for pivot detection
input int  PivotLevelsCount  = 3;      // Number of S/R levels to keep
input int  MaxTradesPerLevel = 2;      // Max trades per pivot level

//--------------------------------------------------------------------
// Risk Management & Trade Settings
//--------------------------------------------------------------------
input int      ATR_Period         = 14;     // ATR period for SL
input double   ATR_SL_Multiplier  = 2.0;    // ATR×multiplier = SL distance
input double   RiskRewardRatio    = 10.0;   // TP distance = SL×RR
input double   FixedRiskPerTrade  = 50.0;   // Fixed risk in account currency
input bool     UsePercentRisk     = false;  // Switch to % of balance risk
input double   RiskPercentage     = 1.0;    // % risk if enabled
input int      AllowedSlippage    = 3;      // Max slippage (points)
input int      MaxTradesPerDay    = 2;      // Daily entry cap
input ulong    EA_MagicNumber     = 123456; // Magic number for EA trades

//--------------------------------------------------------------------
// Breakeven Settings
//--------------------------------------------------------------------
input bool     EnableBreakeven            = true;   // Enable breakeven move
input double   BreakevenTriggerReward     = 1.0;    // R multiple to trigger SL move
input double   BreakevenReward            = 1.1;    // R multiple for new SL level

//--------------------------------------------------------------------
// Reversal Exit Settings
//--------------------------------------------------------------------
input bool     EnableReversalExit         = true;   // Enable reversal-based exit
input int      LookbackHighLow           = 14;     // Bars for reversal exit check

//--------------------------------------------------------------------
// Additional Filters: BB Trend & MA Ribbon
//--------------------------------------------------------------------
input bool     EnableBBTrendFilter        = true;       // Enable BB trend filter
input int      BB_Period                  = 100;        // Bollinger Bands period
input double   BB_Deviation               = 2.0;        // BB deviation

input bool     EnableMARibbonFilter       = true;       // Enable MA ribbon filter
input ENUM_MA_METHOD MA_Method            = MODE_EMA;   // MA type
input int      MA_StartPeriod             = 100;        // Starting MA period
input int      MA_PeriodStep              = 20;         // Increment per MA
#define NUM_MA 6                                        // Number of MAs in ribbon

//--------------------------------------------------------------------
// Global Variables
//--------------------------------------------------------------------
int      ATR_Handle;               // ATR indicator handle
int      BBHandle;                 // BB indicator handle
int      MAHandles[NUM_MA];        // MA handles
int      BBTrend = 0;              // BB trend state: 0=undef,1=long,-1=short

struct LevelInfo {                  
   double level;                   // Pivot price
   int    tradeCount;              // Trades used at this level
};
LevelInfo ResistanceLevels[];       // Resistance pivot levels
LevelInfo SupportLevels[];         // Support pivot levels

int      TradesToday    = 0;       // Count trades today
int      LastTradeDay   = 0;       // Date of last trade
datetime LastBarTime    = 0;       // Last processed bar time

CTrade   Trade;                    // Trade helper object

//--------------------------------------------------------------------
// Session Filter
//--------------------------------------------------------------------
bool IsWithinSession() {
   datetime gm = TimeGMT();
   MqlDateTime dt; TimeToStruct(gm,dt);
   int minutes = dt.hour*60 + dt.min;
   bool ok = false;
   if(TradeNewYork && minutes>=12*60 && minutes<21*60) ok=true;
   if(TradeLondon  && minutes>= 7*60 && minutes<12*60) ok=true;
   if(TradeTokyo   && minutes>= 0    && minutes< 7*60) ok=true;
   if(TradeSydney  && (minutes>=22*60 || minutes<0)) ok=true;
   return ok;
}

//--------------------------------------------------------------------
// Pivot Detection
//--------------------------------------------------------------------
bool IsPivotHigh(int idx) {
   if(idx<RightBars) return false;
   double v = iHigh(_Symbol,_Period,idx);
   for(int i=idx-RightBars;i<=idx+LeftBars;i++){
      if(i==idx||i<0||i>=Bars(_Symbol,_Period)) continue;
      if(iHigh(_Symbol,_Period,i)>v) return false;
   }
   return true;
}
bool IsPivotLow(int idx) {
   if(idx<RightBars) return false;
   double v = iLow(_Symbol,_Period,idx);
   for(int i=idx-RightBars;i<=idx+LeftBars;i++){
      if(i==idx||i<0||i>=Bars(_Symbol,_Period)) continue;
      if(iLow(_Symbol,_Period,i)<v) return false;
   }
   return true;
}

//--------------------------------------------------------------------
// Update Pivot Levels & Draw Lines
//--------------------------------------------------------------------
void UpdatePivotLevels(){
   int idx = RightBars;
   datetime t0 = iTime(_Symbol,_Period,idx);
   datetime t1 = t0 + RightBars*Period()*60;
   // High pivot
   if(IsPivotHigh(idx)){
      LevelInfo L={iHigh(_Symbol,_Period,idx),0};
      int n=ArraySize(ResistanceLevels);
      if(n>=PivotLevelsCount){ for(int i=n-1;i>0;i--) ResistanceLevels[i]=ResistanceLevels[i-1]; ResistanceLevels[0]=L; }
      else { ArrayResize(ResistanceLevels,n+1); ResistanceLevels[n]=L; }
      string name = "Resistance_"+IntegerToString(t0);
      if(ObjectCreate(0,name,OBJ_TREND,0,t0,L.level,t1,L.level)) ObjectSetInteger(0,name,OBJPROP_COLOR,clrRed);
   }
   // Low pivot
   if(IsPivotLow(idx)){
      LevelInfo L={iLow(_Symbol,_Period,idx),0};
      int n=ArraySize(SupportLevels);
      if(n>=PivotLevelsCount){ for(int i=n-1;i>0;i--) SupportLevels[i]=SupportLevels[i-1]; SupportLevels[0]=L; }
      else { ArrayResize(SupportLevels,n+1); SupportLevels[n]=L; }
      string name = "Support_"+IntegerToString(t0);
      if(ObjectCreate(0,name,OBJ_TREND,0,t0,L.level,t1,L.level)) ObjectSetInteger(0,name,OBJPROP_COLOR,clrBlue);
   }
}

//--------------------------------------------------------------------
// Additional Filters: BB Trend & MA Ribbon
//--------------------------------------------------------------------
bool AdditionalFiltersPassed(ENUM_ORDER_TYPE sig){
   double lastClose = iClose(_Symbol,_Period,1);
   // Bollinger Bands
   if(EnableBBTrendFilter){
      double arrU[],arrL[];
      ArrayResize(arrU,1); ArrayResize(arrL,1);
      if(CopyBuffer(BBHandle,1,0,1,arrU)<=0 || CopyBuffer(BBHandle,2,0,1,arrL)<=0) return false;
      double upper=arrU[0], lower=arrL[0];
      if(BBTrend==0){ if(lastClose>upper) BBTrend=1; else if(lastClose<lower) BBTrend=-1; }
      else if(BBTrend==1 && lastClose<lower) BBTrend=-1; else if(BBTrend==-1 && lastClose>upper) BBTrend=1;
      if((sig==ORDER_TYPE_BUY && BBTrend!=1) || (sig==ORDER_TYPE_SELL && BBTrend!=-1)) return false;
   }
   // MA Ribbon
   if(EnableMARibbonFilter){
      for(int i=0;i<NUM_MA;i++){
         double m[],ma; ArrayResize(m,1);
         if(CopyBuffer(MAHandles[i],0,1,1,m)<=0) return false;
         ma=m[0]; double close1=iClose(_Symbol,_Period,1);
         if((sig==ORDER_TYPE_BUY && close1>=ma) || (sig==ORDER_TYPE_SELL && close1<=ma)) return false;
      }
   }
   return true;
}

//--------------------------------------------------------------------
// Open Trade with ATR-Based Risk
//--------------------------------------------------------------------
void OpenTrade(ENUM_ORDER_TYPE type){
   double arrATR[]; ArrayResize(arrATR,1);
   if(CopyBuffer(ATR_Handle,0,0,1,arrATR)<=0){ Print("ATR error"); return; }
   double atr=arrATR[0], slDist=atr*ATR_SL_Multiplier, tpDist=slDist*RiskRewardRatio;
   double entry, sl, tp;
   if(type==ORDER_TYPE_BUY){ entry=SymbolInfoDouble(_Symbol,SYMBOL_ASK); sl=entry-slDist; tp=entry+tpDist; }
   else { entry=SymbolInfoDouble(_Symbol,SYMBOL_BID); sl=entry+slDist; tp=entry-tpDist; }
   double riskAmt = UsePercentRisk ? AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercentage/100.0 : FixedRiskPerTrade;
   double tv = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double riskPerLot=(slDist/ts)*tv; if(riskPerLot<=0){ Print("Risk/lots error"); return; }
   double lots=NormalizeDouble(riskAmt/riskPerLot,2), vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), vst=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(lots<vmin) lots=vmin; else lots=floor(lots/vst)*vst;
   MqlTradeRequest req={}; MqlTradeResult res={}; req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=lots;
   req.type=type; req.price=(type==ORDER_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   req.sl=sl; req.tp=tp; req.deviation=AllowedSlippage; req.magic=EA_MagicNumber; req.comment=(type==ORDER_TYPE_BUY?"Buy":"Sell");
   if(!Trade.OrderSend(req,res)) Print("OrderSend failed: ",GetLastError());
}

//--------------------------------------------------------------------
// Entry Logic & Daily Limit
//--------------------------------------------------------------------
void ManageTrades(){
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day!=LastTradeDay){ TradesToday=0; LastTradeDay=dt.day; }
   if(TradesToday>=MaxTradesPerDay || !IsWithinSession()) return;
   // BUY
   bool buyOpen=false;
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC)==EA_MagicNumber && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buyOpen=true; }
   if(!buyOpen){ double c2=iClose(_Symbol,_Period,2), c1=iClose(_Symbol,_Period,1);
      for(int i=0;i<ArraySize(ResistanceLevels);i++){ double L=ResistanceLevels[i].level;
         if(c2<=L && c1>L && ResistanceLevels[i].tradeCount<MaxTradesPerLevel && AdditionalFiltersPassed(ORDER_TYPE_BUY)){
            OpenTrade(ORDER_TYPE_BUY); ResistanceLevels[i].tradeCount++; TradesToday++; break; }
      }
   }
   // SELL
   bool sellOpen=false;
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC)==EA_MagicNumber && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL) sellOpen=true; }
   if(!sellOpen){ double c2=iClose(_Symbol,_Period,2), c1=iClose(_Symbol,_Period,1);
      for(int i=0;i<ArraySize(SupportLevels);i++){ double L=SupportLevels[i].level;
         if(c2>=L && c1<L && SupportLevels[i].tradeCount<MaxTradesPerLevel && AdditionalFiltersPassed(ORDER_TYPE_SELL)){
            OpenTrade(ORDER_TYPE_SELL); SupportLevels[i].tradeCount++; TradesToday++; break; }
      }
   }
}

//--------------------------------------------------------------------
// Breakeven Trigger & Reward
//--------------------------------------------------------------------
void CheckBreakeven(){
   if(!EnableBreakeven) return;
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t) || PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN), sl=PositionGetDouble(POSITION_SL);
      double risk=MathAbs(open - sl), curr=iClose(_Symbol,_Period,0);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      // Calculate trigger and new SL levels
      double trg = (pt==POSITION_TYPE_BUY)
                   ? open + risk * BreakevenTriggerReward
                   : open - risk * BreakevenTriggerReward;
      double newSL = (pt==POSITION_TYPE_BUY)
                     ? open + risk * BreakevenReward
                     : open - risk * BreakevenReward;
      if(pt==POSITION_TYPE_BUY && curr>=trg && sl<newSL)
         Trade.PositionModify(t,newSL,PositionGetDouble(POSITION_TP));
      if(pt==POSITION_TYPE_SELL && curr<=trg && sl>newSL)
         Trade.PositionModify(t,newSL,PositionGetDouble(POSITION_TP));
   }
}

//--------------------------------------------------------------------
// Reversal Exit
//--------------------------------------------------------------------
void CheckReversalExit(){
   if(!EnableReversalExit) return;
   int hiIdx=iHighest(_Symbol,_Period,MODE_HIGH,LookbackHighLow,2);
   int loIdx=iLowest(_Symbol,_Period,MODE_LOW,LookbackHighLow,2);
   double highestHigh=iHigh(_Symbol,_Period,hiIdx), lowestLow=iLow(_Symbol,_Period,loIdx);
   double close1=iClose(_Symbol,_Period,1);
   bool revBuy=(close1>highestHigh), revSell=(close1<lowestLow);
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t) || PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(revBuy && pt==POSITION_TYPE_SELL) Trade.PositionClose(t);
      if(revSell&& pt==POSITION_TYPE_BUY ) Trade.PositionClose(t);
   }
}

//--------------------------------------------------------------------
// Main Tick
//--------------------------------------------------------------------
void OnTick(){
   datetime tm=iTime(_Symbol,_Period,0);
   if(tm!=LastBarTime){ UpdatePivotLevels(); ManageTrades(); LastBarTime=tm; }
   CheckBreakeven();
   CheckReversalExit();
}

//--------------------------------------------------------------------
// Initialization
//--------------------------------------------------------------------
int OnInit(){
   ATR_Handle=iATR(_Symbol,_Period,ATR_Period);
   if(ATR_Handle==INVALID_HANDLE){ Print("ATR init failed"); return INIT_FAILED; }
   ArrayResize(ResistanceLevels,0);
   ArrayResize(SupportLevels,0);
   if(EnableBBTrendFilter){ BBHandle=iBands(_Symbol,_Period,BB_Period,0,BB_Deviation,PRICE_CLOSE);
      if(BBHandle==INVALID_HANDLE) Print("BB init failed"); BBTrend=0; }
   if(EnableMARibbonFilter){ for(int i=0;i<NUM_MA;i++){ int p=MA_StartPeriod + i*MA_PeriodStep;
         MAHandles[i]=iMA(_Symbol,_Period,p,0,MA_Method,PRICE_CLOSE);
         if(MAHandles[i]==INVALID_HANDLE) Print("MA init failed for period ",p);
      }
   }
   return INIT_SUCCEEDED;
}
