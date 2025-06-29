//+------------------------------------------------------------------+
//|                                              RSI_ReversalEA.mq5  |
//|                        Copyright 2025, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//------------------ Session Filter Inputs --------------------------
input bool TradeNewYork           = true;
input bool TradeLondon            = true;
input bool TradeTokyo             = false;
input bool TradeSydney            = false;

//------------------ RSI Settings -----------------------------------
input int  RSIPeriod              = 14;
input int  RSI_UpperLevel         = 80;
input int  RSI_LowerLevel         = 20;

//------------------ Basic Risk Management & Trade Settings ---------
input int    ATR_Period           = 14;
input double ATR_SL_Multiplier    = 2.0;
input double RiskRewardRatio      = 10.0;
input double FixedRiskPerTrade    = 50.0;
input bool   UsePercentRisk       = false;
input double RiskPercentage       = 1.0;
input int    AllowedSlippage      = 3;
input bool   UseDailyBias         = false;
input int    MaxTradesPerDay      = 5;
input ulong  EA_MagicNumber       = 123456;

//------------------ Additional Trade Management Settings ----------
input bool   EnableBreakeven      = true;
input double BreakevenReward      = 1.0;
input double PartialClosePct      = 50.0;
input double PartialCloseReward   = 5.0;
input int    LookbackHighLow      = 14;
input bool   EnableReversalExit   = true;

//------------------ Additional Filters: BB Trend & MA Ribbon -------
input bool   EnableBBTrendFilter  = true;
input int    BB_Period            = 100;
input double BB_Deviation         = 2.0;
input bool   EnableMARibbonFilter = true;
input ENUM_MA_METHOD MA_Method    = MODE_EMA;
input int    MA_StartPeriod       = 100;
input int    MA_PeriodStep        = 20;
#define NUM_MA 6

//+------------------------------------------------------------------+
class CRSIReversalEA
  {
private:
   // inputs
   bool          m_TradeNewYork,m_TradeLondon,m_TradeTokyo,m_TradeSydney;
   int           m_RSIPeriod,m_RSIUpper,m_RSILower;
   int           m_ATRPeriod;
   double        m_ATRSLMultiplier,m_RiskRewardRatio;
   double        m_RiskPerTrade;
   bool          m_UsePercentRisk;
   double        m_RiskPercentage;
   int           m_Slippage;
   bool          m_UseDailyBias;
   int           m_MaxTradesPerDay;
   ulong         m_Magic;
   bool          m_EnableBreakeven;
   double        m_BreakevenReward,m_PartialCloseReward;
   double        m_PartialClosePct;
   int           m_Lookback;
   bool          m_EnableReversalExit;
   bool          m_EnableBB;
   int           m_BBPeriod;
   double        m_BBDev;
   bool          m_EnableMA;
   ENUM_MA_METHOD m_MAMethod;
   int           m_MAStart,m_MAPeriod;

   // state
   enum RSIState{RSI_NONE,RSI_WAIT_BUY,RSI_WAIT_SELL}m_state;
   int           m_tradesToday,m_lastDay;
   datetime      m_lastBar;
   ulong         m_partialTickets[];

   // handles
   int           m_RSIHandle,m_ATRHandle,m_BBHandle;
   int           m_MAHandles[NUM_MA];
   int           m_BBTrend;

   CTrade        m_trade;

   // helper: check if ticket in array
   bool IsTicketClosed(ulong ticket)
     {
      for(int i=0;i<ArraySize(m_partialTickets);i++)
         if(m_partialTickets[i]==ticket) return true;
      return false;
     }

public:
   CRSIReversalEA()
     {
      m_TradeNewYork      =TradeNewYork;
      m_TradeLondon       =TradeLondon;
      m_TradeTokyo        =TradeTokyo;
      m_TradeSydney       =TradeSydney;
      m_RSIPeriod         =RSIPeriod;
      m_RSIUpper          =RSI_UpperLevel;
      m_RSILower          =RSI_LowerLevel;
      m_ATRPeriod         =ATR_Period;
      m_ATRSLMultiplier   =ATR_SL_Multiplier;
      m_RiskRewardRatio   =RiskRewardRatio;
      m_RiskPerTrade      =FixedRiskPerTrade;
      m_UsePercentRisk    =UsePercentRisk;
      m_RiskPercentage    =RiskPercentage;
      m_Slippage          =AllowedSlippage;
      m_UseDailyBias      =UseDailyBias;
      m_MaxTradesPerDay   =MaxTradesPerDay;
      m_Magic             =EA_MagicNumber;
      m_EnableBreakeven   =EnableBreakeven;
      m_BreakevenReward   =BreakevenReward;
      m_PartialCloseReward=PartialCloseReward;
      m_PartialClosePct   =PartialClosePct;
      m_Lookback          =LookbackHighLow;
      m_EnableReversalExit=EnableReversalExit;
      m_EnableBB          =EnableBBTrendFilter;
      m_BBPeriod          =BB_Period;
      m_BBDev             =BB_Deviation;
      m_EnableMA          =EnableMARibbonFilter;
      m_MAMethod          =MA_Method;
      m_MAStart           =MA_StartPeriod;
      m_MAPeriod          =MA_PeriodStep;

      m_state             =RSI_NONE;
      m_tradesToday       =0;
      m_lastDay           =0;
      m_lastBar           =0;
      ArrayResize(m_partialTickets,0);
     }

   int OnInit()
     {
      m_RSIHandle = iRSI(_Symbol,_Period,m_RSIPeriod,PRICE_CLOSE);
      m_ATRHandle = iATR(_Symbol,_Period,m_ATRPeriod);
      if(m_EnableBB)
         m_BBHandle = iBands(_Symbol,_Period,m_BBPeriod,0,m_BBDev,PRICE_CLOSE);
      if(m_EnableMA)
        for(int i=0;i<NUM_MA;i++)
           m_MAHandles[i] = iMA(_Symbol,_Period,m_MAStart + i*m_MAPeriod,0,m_MAMethod,PRICE_CLOSE);
      return INIT_SUCCEEDED;
     }

   void UpdateState()
     {
      double arr[1]; CopyBuffer(m_RSIHandle,0,1,1,arr);
      double val=arr[0];
      if(m_state==RSI_NONE)
        {
         if(val>m_RSIUpper) m_state=RSI_WAIT_SELL;
         else if(val<m_RSILower) m_state=RSI_WAIT_BUY;
        }
     }

   ENUM_ORDER_TYPE GetSignal()
     {
      double arr[1]; CopyBuffer(m_RSIHandle,0,1,1,arr);
      double val=arr[0];
      if(m_state==RSI_WAIT_SELL && val<m_RSIUpper) {m_state=RSI_NONE; return ORDER_TYPE_SELL;}
      if(m_state==RSI_WAIT_BUY  && val>m_RSILower) {m_state=RSI_NONE; return ORDER_TYPE_BUY;}
      return (ENUM_ORDER_TYPE)-1;
     }

   bool SessionOK()
     {
      datetime t=TimeGMT(); MqlDateTime dt; TimeToStruct(t,dt);
      int m=dt.hour*60+dt.min;
      if(m_TradeTokyo && m<7*60) return true;
      if(m_TradeLondon&&m>=7*60&&m<12*60) return true;
      if(m_TradeNewYork&&m>=12*60&&m<21*60) return true;
      if(m_TradeSydney&&m>=21*60) return true;
      return false;
     }

   void ManageTrades()
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
      if(dt.day!=m_lastDay){m_tradesToday=0; m_lastDay=dt.day;}
      if(m_tradesToday>=m_MaxTradesPerDay) return;

      ENUM_ORDER_TYPE sig = GetSignal();
      if(sig == (ENUM_ORDER_TYPE)-1) return;

      // BB filter
      if(m_EnableBB)
        {
         double ub[1], lb[1];
         CopyBuffer(m_BBHandle,1,0,1,ub);
         CopyBuffer(m_BBHandle,2,0,1,lb);
         double lastClose = iClose(_Symbol,_Period,1);
         if(m_BBTrend==0)
            m_BBTrend = (lastClose>ub[0]?1:(lastClose<lb[0]?-1:0));
         else if(m_BBTrend==1 && lastClose<lb[0]) m_BBTrend=-1;
         else if(m_BBTrend==-1&& lastClose>ub[0]) m_BBTrend=1;
         if((sig==ORDER_TYPE_BUY&&m_BBTrend!=1)||(sig==ORDER_TYPE_SELL&&m_BBTrend!=-1)) return;
        }

      // MA ribbon
      if(m_EnableMA)
        {
         double price=iClose(_Symbol,_Period,1);
         for(int i=0;i<NUM_MA;i++)
           {
            double ma[1]; CopyBuffer(m_MAHandles[i],0,1,1,ma);
            if((sig==ORDER_TYPE_BUY  && price<=ma[0]) ||
               (sig==ORDER_TYPE_SELL && price>=ma[0]))
               return;
           }
        }

      // daily bias
      if(m_UseDailyBias)
        {
         int bias=(iClose(_Symbol,PERIOD_D1,1)>iOpen(_Symbol,PERIOD_D1,1)?1:-1);
         if((sig==ORDER_TYPE_BUY && bias!=1)||(sig==ORDER_TYPE_SELL && bias!=-1)) return;
        }

      if(!SessionOK()) return;

      // single trade per direction
      if(sig==ORDER_TYPE_BUY  && !IsPosition(POSITION_TYPE_BUY))  Open(sig);
      if(sig==ORDER_TYPE_SELL && !IsPosition(POSITION_TYPE_SELL)) Open(sig);
     }

   bool IsPosition(ENUM_POSITION_TYPE type)
     {
      for(int i=0;i<PositionsTotal();i++)
        {
         ulong tk=PositionGetTicket(i);
         if(PositionSelectByTicket(tk) &&
            PositionGetInteger(POSITION_MAGIC)==m_Magic &&
            PositionGetInteger(POSITION_TYPE)==type)
            return true;
        }
      return false;
     }

   void Open(ENUM_ORDER_TYPE t)
     {
      double atr[1]; CopyBuffer(m_ATRHandle,0,1,1,atr);
      double dist = atr[0]*m_ATRSLMultiplier;
      double price = (t==ORDER_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
      double sl = (t==ORDER_TYPE_BUY?price-dist:price+dist);
      double tp = (t==ORDER_TYPE_BUY?price+dist*m_RiskRewardRatio:price-dist*m_RiskRewardRatio);
      double riskAmt = m_UsePercentRisk?AccountInfoDouble(ACCOUNT_BALANCE)*m_RiskPercentage/100.0:m_RiskPerTrade;
      double tickVal  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double lotRisk = (dist/tickSize)*tickVal;
      double lots = NormalizeDouble(riskAmt/lotRisk,2);

      MqlTradeRequest req={}; MqlTradeResult res={};
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = lots;
      req.type      = t;
      req.price     = price;
      req.sl        = sl;
      req.tp        = tp;
      req.deviation = m_Slippage;
      req.magic     = m_Magic;
      m_trade.OrderSend(req,res);
      m_tradesToday++;
     }

   void CheckAndExecutePartialClose()
     {
      for(int i=0;i<PositionsTotal();i++)
        {
         ulong tk=PositionGetTicket(i);
         if(!PositionSelectByTicket(tk) || PositionGetInteger(POSITION_MAGIC)!=m_Magic) continue;
         if(IsTicketClosed(tk)) continue;

         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         double risk = MathAbs(open-sl);
         double cur  = iClose(_Symbol,_Period,0);
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double target = (pt==POSITION_TYPE_BUY?open+risk*m_PartialCloseReward:open-risk*m_PartialCloseReward);

         if((pt==POSITION_TYPE_BUY && cur>=target) || (pt==POSITION_TYPE_SELL && cur<=target))
           {
            double vol = NormalizeDouble(PositionGetDouble(POSITION_VOLUME)*(m_PartialClosePct/100.0),2);
            if(m_trade.PositionClosePartial(tk,vol))
              {
               ArrayResize(m_partialTickets,ArraySize(m_partialTickets)+1);
               m_partialTickets[ArraySize(m_partialTickets)-1]=tk;
               if(m_EnableBreakeven)
                  m_trade.PositionModify(tk,
                     (pt==POSITION_TYPE_BUY?open+risk*m_BreakevenReward:open-risk*m_BreakevenReward),
                     PositionGetDouble(POSITION_TP));
              }
           }
        }
     }

   void CheckReversalExit()
     {
      double hh = iHigh(_Symbol,_Period,iHighest(_Symbol,_Period,MODE_HIGH,m_Lookback,2));
      double ll = iLow(_Symbol,_Period,iLowest(_Symbol,_Period,MODE_LOW,m_Lookback,2));
      double cur= iClose(_Symbol,_Period,1);
      for(int i=0;i<PositionsTotal();i++)
        {
         ulong tk=PositionGetTicket(i);
         if(!PositionSelectByTicket(tk) || PositionGetInteger(POSITION_MAGIC)!=m_Magic) continue;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(!m_EnableReversalExit) continue;
         if(pt==POSITION_TYPE_SELL && cur>hh) m_trade.PositionClose(tk);
         if(pt==POSITION_TYPE_BUY  && cur<ll) m_trade.PositionClose(tk);
        }
     }

   void OnTick()
     {
      datetime bt=iTime(_Symbol,_Period,0);
      if(bt!=m_lastBar)
        {
         UpdateState();
         ManageTrades();
         m_lastBar=bt;
        }
      CheckAndExecutePartialClose();
      CheckReversalExit();
     }
  };

CRSIReversalEA ea;

int OnInit(){return ea.OnInit();}
void OnTick(){ea.OnTick();}
//+------------------------------------------------------------------+
