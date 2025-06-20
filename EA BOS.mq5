//+------------------------------------------------------------------+
//|                                     EA BOS_NoCandleConfirm.mq5   |
//|   Break-of-Structure EA with Fib Retracement as Region,          |
//|   ATR Risk, Partial Close, Breakeven, Reversal Exit,             |
//|   Pivot S/R Plotting                                             |
//|   © Your Name – Licensed under CC BY-NC-SA 4.0                   |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--------------------------------------------------------------------
// Input Parameters
//--------------------------------------------------------------------
input bool   TradeNewYork       = true;
input bool   TradeLondon        = true;
input bool   TradeTokyo         = false;
input bool   TradeSydney        = false;

input int    LeftBars           = 15;
input int    RightBars          = 15;
input int    PivotLevelsCount   = 3;

input int    BreakCandles       = 10;
input double FibLevel           = 0.5;
input int    FibLookback        = 40;

input int    ATR_Period         = 14;
input double ATR_SL_Mult        = 2.0;
input double RiskRewardRatio    = 3.0;
input double FixedRiskUSD       = 50.0;
input bool   UsePercentRisk     = false;
input double RiskPercent        = 1.0;
input int    AllowedSlippage    = 3;
input ulong  EA_MagicNumber     = 123456;
input int    MaxTradesPerDay    = 2;

input bool   EnableBreakeven    = true;
input double BreakevenReward    = 1.0;
input double PartialClosePct    = 50.0;
input double PartialCloseRR     = 2.0;

input int    LookbackHighLow    = 14;
input bool   EnableReversalExit = true;

//--------------------------------------------------------------------
// Global Variables
//--------------------------------------------------------------------
CTrade      Trade;
int         ATR_Handle;

struct LevelInfo { double level; int tradeCount; };
LevelInfo   ResistanceLevels[];
LevelInfo   SupportLevels[];

int         TradesToday    = 0;
int         LastTradeDay   = 0;
datetime    LastBarTime    = 0;

bool        TrendShort       = false;
bool        TrendLong        = false;
bool        WaitingRetrace   = false;
bool        RetraceReached   = false;
int         BreakCountShort  = 0;
int         BreakCountLong   = 0;

ulong       PartialClosedTickets[];

//--------------------------------------------------------------------
// Utility: Print debug header
//--------------------------------------------------------------------
void DebugPrint(const string msg) { Print(__FILE__," - ",msg); }

//--------------------------------------------------------------------
// Session Filter
//--------------------------------------------------------------------
bool IsWithinSession()
{
   datetime g = TimeGMT(); MqlDateTime dt; TimeToStruct(g, dt);
   int m = dt.hour*60 + dt.min;
   bool inSess = (TradeNewYork && m>=12*60 && m<21*60) ||
                 (TradeLondon  && m>= 7*60 && m<12*60) ||
                 (TradeTokyo   && m>= 0    && m< 7*60 ) ||
                 (TradeSydney  && (m>=22*60||m<0    ));
   DebugPrint(StringFormat("Session check: %s (m=%d)", inSess?"IN":"OUT", m));
   return inSess;
}

//--------------------------------------------------------------------
// Pivot Detection & Plot
//--------------------------------------------------------------------
bool IsPivotHigh(int idx)
{
   if(idx < RightBars) return false;
   double pv = iHigh(_Symbol,_Period,idx);
   for(int i=idx-RightBars; i<=idx+LeftBars; i++)
      if(i!=idx && i>=0 && i<Bars(_Symbol,_Period) && iHigh(_Symbol,_Period,i) > pv)
         return false;
   return true;
}
bool IsPivotLow(int idx)
{
   if(idx < RightBars) return false;
   double pv = iLow(_Symbol,_Period,idx);
   for(int i=idx-RightBars; i<=idx+LeftBars; i++)
      if(i!=idx && i>=0 && i<Bars(_Symbol,_Period) && iLow(_Symbol,_Period,i) < pv)
         return false;
   return true;
}

void UpdatePivotLevels()
{
   int idx = RightBars;
   datetime t = iTime(_Symbol,_Period,idx);
   datetime t2 = t + Period()*60*RightBars;
   LevelInfo lvlinfo; double lvl;

   if(IsPivotHigh(idx))
   {
      lvl = iHigh(_Symbol,_Period,idx);
      lvlinfo.level= lvl; lvlinfo.tradeCount=0;
      string name = "Res_"+IntegerToString(t);
      if(ObjectCreate(0,name,OBJ_TREND,0,t,lvl,t2,lvl))
         DebugPrint("Plot resistance at " + DoubleToString(lvl));
      int n=ArraySize(ResistanceLevels);
      if(n>=PivotLevelsCount) {
         for(int i=n-1;i>0;i--) ResistanceLevels[i]=ResistanceLevels[i-1];
         ResistanceLevels[0]=lvlinfo;
      } else {
         ArrayResize(ResistanceLevels,n+1);
         ResistanceLevels[n]=lvlinfo;
      }
   }
   if(IsPivotLow(idx))
   {
      lvl = iLow(_Symbol,_Period,idx);
      lvlinfo.level= lvl; lvlinfo.tradeCount=0;
      string name = "Sup_"+IntegerToString(t);
      if(ObjectCreate(0,name,OBJ_TREND,0,t,lvl,t2,lvl))
         DebugPrint("Plot support at " + DoubleToString(lvl));
      int n=ArraySize(SupportLevels);
      if(n>=PivotLevelsCount) {
         for(int i=n-1;i>0;i--) SupportLevels[i]=SupportLevels[i-1];
         SupportLevels[0]=lvlinfo;
      } else {
         ArrayResize(SupportLevels,n+1);
         SupportLevels[n]=lvlinfo;
      }
   }
}

//--------------------------------------------------------------------
// Break-of-Structure & Fib Region
//--------------------------------------------------------------------
void CheckBreakAndRetrace()
{
   double c1 = iClose(_Symbol,_Period,1);
   if(ArraySize(SupportLevels)>0)
   {
      if(c1 < SupportLevels[0].level)
      {
         BreakCountShort++; DebugPrint("BreakCountShort="+IntegerToString(BreakCountShort));
         if(BreakCountShort>=BreakCandles && !TrendShort)
         {
            TrendShort=true; TrendLong=false;
            WaitingRetrace=true; RetraceReached=false;
            DebugPrint("Break-of-Structure SHORT set");
         }
      }
      else BreakCountShort=0;
   }
   if(ArraySize(ResistanceLevels)>0)
   {
      if(c1 > ResistanceLevels[0].level)
      {
         BreakCountLong++; DebugPrint("BreakCountLong="+IntegerToString(BreakCountLong));
         if(BreakCountLong>=BreakCandles && !TrendLong)
         {
            TrendLong=true; TrendShort=false;
            WaitingRetrace=true; RetraceReached=false;
            DebugPrint("Break-of-Structure LONG set");
         }
      }
      else BreakCountLong=0;
   }
   if(WaitingRetrace)
   {
      int hi = iHighest(_Symbol,_Period,MODE_HIGH,FibLookback,1);
      int lo = iLowest (_Symbol,_Period,MODE_LOW, FibLookback,1);
      double hh=iHigh(_Symbol,_Period,hi), ll=iLow(_Symbol,_Period,lo);
      double pivot=(TrendShort?SupportLevels[0].level:ResistanceLevels[0].level);
      double fibPt=ll+(hh-ll)*(TrendShort?(1-FibLevel):FibLevel);
      double lowR=MathMin(pivot,fibPt), highR=MathMax(pivot,fibPt);
      DebugPrint(StringFormat("Fib region [%.5f,%.5f]", lowR, highR));
      double h1=iHigh(_Symbol,_Period,1), l1=iLow(_Symbol,_Period,1);
      if(h1>=lowR && l1<=highR)
      {
         RetraceReached=true; DebugPrint("Retrace into region detected");
      }
   }
}

//--------------------------------------------------------------------
// Entry Execution
//--------------------------------------------------------------------
void OpenEntry(bool isBuy)
{
   DebugPrint(isBuy?"Attempting BUY":"Attempting SELL");
   double atrArr[]; ArrayResize(atrArr,1);
   if(CopyBuffer(ATR_Handle,0,0,1,atrArr)<=0)
   {
      DebugPrint("ATR copy failed"); return;
   }
   double atr=atrArr[0]; DebugPrint("ATR="+DoubleToString(atr));
   double slDist=atr*ATR_SL_Mult;
   double tpDist=slDist*RiskRewardRatio;
   double price=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   DebugPrint(StringFormat("Entry price=%.5f SL dist=%.5f TP dist=%.5f", price, slDist, tpDist));
   double riskAmt=UsePercentRisk?AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercent/100.0:FixedRiskUSD;
   double perLot=(slDist/SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE))*SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double vol=MathFloor((riskAmt/perLot)/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = vol;
   req.type      = isBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   req.price     = price;
   req.sl        = isBuy?price-slDist:price+slDist;
   req.tp        = isBuy?price+tpDist:price-tpDist;
   req.deviation = AllowedSlippage;
   req.magic     = EA_MagicNumber;
   if(Trade.OrderSend(req,res))
      DebugPrint("OrderSend success, ticket="+IntegerToString(res.order));
   else
      DebugPrint("OrderSend failed, retcode="+IntegerToString(res.retcode));
}

//--------------------------------------------------------------------
// Partial Close & Breakeven
//--------------------------------------------------------------------
bool IsTicketPartiallyClosed(ulong t)
{
   for(int i=0;i<ArraySize(PartialClosedTickets);i++)
      if(PartialClosedTickets[i]==t) return true;
   return false;
}

void AddTicketToPartialClosed(ulong t)
{
   int n=ArraySize(PartialClosedTickets);
   ArrayResize(PartialClosedTickets, n+1);
   PartialClosedTickets[n] = t;
}

void CheckAndExecutePartialClose()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tic = PositionGetTicket(i);
      if(!PositionSelectByTicket(tic)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      if(IsTicketPartiallyClosed(tic)) continue;
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double slP   = PositionGetDouble(POSITION_SL);
      double risk  = MathAbs(openP-slP);
      double curr  = iClose(_Symbol,_Period,0);
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double tgt = (pt==POSITION_TYPE_BUY)? openP+risk*PartialCloseRR : openP-risk*PartialCloseRR;
      if((pt==POSITION_TYPE_BUY && curr>=tgt) || (pt==POSITION_TYPE_SELL && curr<=tgt))
      {
         double vol = NormalizeDouble(PositionGetDouble(POSITION_VOLUME)*(PartialClosePct/100.0),2);
         if(Trade.PositionClosePartial(tic,vol))
         {
            AddTicketToPartialClosed(tic);
            DebugPrint("Partial close executed, ticket="+IntegerToString(tic));
            if(EnableBreakeven)
            {
               double be = (pt==POSITION_TYPE_BUY)? openP+risk*BreakevenReward : openP-risk*BreakevenReward;
               Trade.PositionModify(tic, be, PositionGetDouble(POSITION_TP));
               DebugPrint("Breakeven set, ticket="+IntegerToString(tic));
            }
         }
      }
   }
}

//--------------------------------------------------------------------
// Reversal Exit
//--------------------------------------------------------------------
void CheckReversalExit()
{
   if(!EnableReversalExit) return;
   double hh = iHigh(_Symbol,_Period, iHighest(_Symbol,_Period,MODE_HIGH, LookbackHighLow,2));
   double ll = iLow (_Symbol,_Period, iLowest (_Symbol,_Period,MODE_LOW,  LookbackHighLow,2));
   double c  = iClose(_Symbol,_Period,1);
   bool exitBuy  = (c>hh);
   bool exitSell = (c<ll);
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tic = PositionGetTicket(i);
      if(!PositionSelectByTicket(tic)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=EA_MagicNumber) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(exitBuy && pt==POSITION_TYPE_SELL) { Trade.PositionClose(tic); DebugPrint("Reversal exit SELL, ticket="+IntegerToString(tic)); }
      if(exitSell && pt==POSITION_TYPE_BUY)  { Trade.PositionClose(tic); DebugPrint("Reversal exit BUY, ticket="+IntegerToString(tic));  }
   }
}

//--------------------------------------------------------------------
// Initialization & Tick
//--------------------------------------------------------------------
int OnInit()
{
   DebugPrint("Initializing EA");
   ATR_Handle = iATR(_Symbol, _Period, ATR_Period);
   if(ATR_Handle==INVALID_HANDLE) { DebugPrint("ATR init failed"); return INIT_FAILED; }
   ArrayResize(ResistanceLevels,0);
   ArrayResize(SupportLevels,0);
   ArrayResize(PartialClosedTickets,0);
   LastBarTime = 0;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime t = iTime(_Symbol,_Period,0);
   if(t==LastBarTime) return;
   LastBarTime = t;
   DebugPrint("New bar at " + TimeToString(t));

   UpdatePivotLevels();

   if(!IsWithinSession()) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day!=LastTradeDay) { TradesToday=0; LastTradeDay=dt.day; DebugPrint("New day reset"); }
   if(TradesToday>=MaxTradesPerDay) { DebugPrint("Max trades reached"); return; }
   if(PositionsTotal()>0) { DebugPrint("Position already open"); return; }

   CheckBreakAndRetrace();

   // Entry: remove candlestick confirmation, enter on retrace
   if(WaitingRetrace && RetraceReached)
   {
      DebugPrint("Ready to enter trade");
      if(TrendShort)
      {
         OpenEntry(false);
         TradesToday++;
         WaitingRetrace = false;
      }
      else if(TrendLong)
      {
         OpenEntry(true);
         TradesToday++;
         WaitingRetrace = false;
      }
   }

   CheckAndExecutePartialClose();
   CheckReversalExit();
}


