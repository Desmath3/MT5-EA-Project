// File: VWAP Flip bot V2.mq5
#property strict
#property tester_file "VWAP_NewsCache.csv"
//+------------------------------------------------------------------+
//| VWAP Flip bot – DCA + Scale-in (Main) |
//+------------------------------------------------------------------+
// 1) Inputs live here
input group "General Settings"
input long EA_MagicNumber = 123456;
input int Slippage = 3;
input bool EnableHedge = true;
enum ENUM_TRADE_DIRECTION { TradeBoth, TradeBuyOnly, TradeSellOnly };
input ENUM_TRADE_DIRECTION TradeDirection = TradeBoth;
input group "Risk Management"
input double MaxTotalRiskPct = 10.0;
input int AtrPeriod = 14;
input double AtrSlMultiplier = 4.0;
input double MaxDailyDrawdownPct = 1.9;
input double MaxGlobalDrawdownPct = 20.0;
input double ProfitTargetRR = 20.0;
input int FlipFallback1HCandles = 60;
input double FlipFallbackReward = 5.0; // RR multiplier for fallback TP
input double MaxMarginUsagePct = 60.0; // Max % of equity allowed in margin for NEW orders
input group "Account Targets & Dynamic Risk"
input double StartBalance = 50000.0;
input double TargetBalance = 55000.0;
input bool EnableTargetBalance= true;
input bool EnableDynamicRisk = true;
input group "Partial Take Profit"
input bool EnablePartialTP = false;
input double PartialTP_RR = 2.0;
input double PartialTP_Percent = 50.0;
input group "Trade Management Filters"
input double SequenceBE_StartR = 2.0;
input double BreakevenOffsetR = 0.0; // offset in R (risk units) for breakeven SL
input int TradeExpiryCandles = 60; // bars after first fill before BE can be armed by time
input bool EnablePeakDrawdownExit = true;
input double PeakDrawdownStartR = 2.0;
input double PeakProfitDrawdownPercent= 30.0;
input group "No Trade Zone"
input int NoTradeStartHour = 23;
input int NoTradeStartMin = 30;
input int NoTradeEndHour = 0;
input int NoTradeEndMin = 30;
input int CooldownH1Candles= 1;
input group "Session Management"
input bool TradeNewYork = true;
input bool TradeLondon = true;
input bool TradeTokyo = true;
input bool TradeSydney = true;
input bool EnableDailyClose = false; // Close all EA trades 10 minutes before NY close
input group "News Filter"
input bool EnableNewsFilter = true;
input int NewsBlockBeforeMin = 10;
input int NewsBlockAfterMin = 10;
input group "DCA Settings"
input int DCAParts = 5;
input int PendingExpiryCandles= 30;
input double InitialDCAOffsetATR = 0.5;
input double LotSizeMultiple = 0.1;
input double DCA_SL_Percent = 70.0; // % of SL distance used for DCA grid
input group "Scaling Strategy"
// ScaleInMaxExposure semantics:
// 0 = SL moved such that maximum exposure + additional scale-in trade is net 0
// 1 = Trade can only ever end at a risk of the total maximum risk once scaling in
// 2 = Trade can only ever end at twice the total maximum risk once scaling in
enum ENUM_SCALE_IN_EXPOSURE { NoExtraExposure=0, OneTimesBaseRisk=1, TwoTimesBaseRisk=2 };
input ENUM_SCALE_IN_EXPOSURE ScaleInMaxExposure = NoExtraExposure;
input bool EnableScaleIn = false;
input double ScaleIn_MinATRFracToSL = 0.1;
input double ScaleIn_AddATRMultiplier = 0.2;
input int ScaleIn_MaxTopUps = 3;
input double ScaleInLotMultiplier = 1.0; // Multiplier for scale-in lots when DCA fully filled
input group "Swing Logic"
input int SwingPeriod = 50;
input group "Swing Anchored VWAP"
input int VwapAPTBase = 20;          // APT base length
input bool PlotSwingVWAP = true;     // Plot anchored VWAP
input color VwapUpColor = clrLime;   // VWAP up color
input color VwapDownColor = clrRed;  // VWAP down color
input int VwapLineWidth = 2;         // VWAP line width
// 2) Include engine (which in turn includes the strategy .mqh inside the class)
#include "VWAP Flip bot_Engine_Core.mqh"
// 3) EA instance and global event functions
CBBMartingaleEA ea;
int OnInit()
{
   datetime ExpirationDate = D'2026.05.31 23:59:59';
   if(TimeCurrent() > ExpirationDate)
   {
      Print("EA expired. Please contact developer.");
      return(INIT_FAILED);
   }
   return ea.OnInit();
}
void OnDeinit(const int reason)
{
   ea.OnDeinit(reason);
}
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   ea.OnTradeTransaction(trans, request, result);
}
void OnTick()
{
   ea.OnTick();
}






