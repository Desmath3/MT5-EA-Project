//+------------------------------------------------------------------+
//|                                               MA_Touch_Modified.mq5  |
//|                        Copyright 2021, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//====================================================================
// Input Parameters - Strategy, Filters, and Risk Management
//====================================================================
// --- Moving Average Settings ---
input ENUM_MA_METHOD   MA_Method          = MODE_EMA;
input int              MA_StartPeriod     = 100;
input int              MA_PeriodStep      = 20;
#define NUM_MA 6

// --- Trade Entry Filters ---
input bool             EnableReversalExit = true;
input int              LookbackHighLow    = 14;

// --- Partial Close & Breakeven Settings ---
input double           PartialClosePct    = 50.0;
input double           PartialCloseReward = 5.0;
input bool             EnableBreakeven    = true;
input double           BreakevenReward    = 1.0;

// --- Session Filter Inputs ---
input bool             TradeNewYork       = true;
input bool             TradeLondon        = true;
input bool             TradeTokyo         = false;
input bool             TradeSydney        = false;

// --- Daily Filters ---
input bool             UseDailyBias       = false;
input int              MaxTradesPerDay    = 5;
input bool             AllowMultiplePos   = true;

// --- ATR-Based Risk Management ---
input int              ATR_Period         = 14;
input double           ATR_SL_Multiplier  = 2.0;
input double           RiskRewardRatio    = 10.0;
input double           FixedRiskPerTrade  = 50.0;
input bool             UsePercentRisk     = false;
input double           RiskPercentage     = 1.0;

// --- Other Trade Settings ---
input int              AllowedSlippage    = 3;
input ulong            EA_MagicNumber     = 123456;

// --- Bollinger Bands Settings ---
input int              BB_Period          = 100;
input double           BB_Deviation       = 2.0;

//====================================================================
// Class Definition: CMaRibbonEA
//====================================================================
class CMaRibbonEA
  {
private:
   ENUM_MA_METHOD  m_MAMethod;
   int             m_MAStartPeriod;
   int             m_MAPeriodStep;
   int             m_NumMAs;
   bool            m_EnableReversalExit;
   int             m_LookbackHL;
   double          m_PartialClosePct;
   double          m_PartialCloseReward;
   bool            m_EnableBreakeven;
   double          m_BreakevenReward;
   bool            m_UseDailyBias;
   int             m_MaxTradesPerDay;
   bool            m_AllowMultiplePos;
   int             m_ATRPeriod;
   double          m_ATRSLMultiplier;
   double          m_RiskRewardRatio;
   double          m_FixedRiskPerTrade;
   bool            m_UsePercentRisk;
   double          m_RiskPercentage;
   int             m_AllowedSlippage;
   ulong           m_EAMagicNumber;
   int             m_BBPeriod;
   double          m_BBDeviation;
   bool            m_TradeNewYork;
   bool            m_TradeLondon;
   bool            m_TradeTokyo;
   bool            m_TradeSydney;
   int             m_MAHandles[NUM_MA];
   int             m_BBHandle;
   double          m_BBUpper[1], m_BBLower[1];
   int             m_ATRHandle;
   enum TradeDir { LONG=1, NONE=0, SHORT=-1 };
   TradeDir        m_TrendDir;
   int             m_TradesToday;
   int             m_LastTradeDay;
   datetime        m_LastBarTime;
   CTrade          m_Trade;

   double CalculateMADistance(int maHandle)
     {
      double arr[1];
      if(CopyBuffer(maHandle,0,0,1,arr)<=0) return(-1);
      double price=iClose(_Symbol,_Period,0);
      double dist=MathAbs(price-arr[0]);
      int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      if(digits==5||digits==3) dist/=0.0001; else dist/=0.01;
      return(dist);
     }

   bool IsMATouched()
     {
      double maVal[1], high=iHigh(_Symbol,_Period,1), low=iLow(_Symbol,_Period,1);
      for(int i=0;i<m_NumMAs;i++)
        if(CopyBuffer(m_MAHandles[i],0,1,1,maVal)>0)
          if(low<=maVal[0]&&maVal[0]<=high) return(true);
      return(false);
     }

   bool IsWithinSessionNew()
     {
      MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
      int cur=dt.hour*60+dt.min;
      bool ok=false;
      if(m_TradeNewYork && cur>=13*60 && cur<22*60) ok=true;
      if(m_TradeLondon  && cur>=8*60  && cur<17*60) ok=true;
      if(m_TradeTokyo   && cur>=0     && cur<9*60 ) ok=true;
      if(m_TradeSydney  && (cur>=22*60||cur<7*60)) ok=true;
      return(ok);
     }

   void UpdateTrendDirection()
     {
      double last=iClose(_Symbol,_Period,1);
      CopyBuffer(m_BBHandle,1,0,1,m_BBUpper);
      CopyBuffer(m_BBHandle,2,0,1,m_BBLower);
      if(m_TrendDir==NONE)
        { if(last>m_BBUpper[0]) m_TrendDir=LONG; else if(last<m_BBLower[0]) m_TrendDir=SHORT; }
      else if(m_TrendDir==LONG && last<m_BBLower[0]) m_TrendDir=SHORT;
      else if(m_TrendDir==SHORT && last>m_BBUpper[0]) m_TrendDir=LONG;
     }

   ENUM_ORDER_TYPE GetTradeSignal()
     {
      if(!IsMATouched()) return((ENUM_ORDER_TYPE)-1);
      if(m_TrendDir==LONG)  return ORDER_TYPE_BUY;
      if(m_TrendDir==SHORT) return ORDER_TYPE_SELL;
      return((ENUM_ORDER_TYPE)-1);
     }

   bool IsAlreadyBought()
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        if(PositionSelectByTicket(PositionGetTicket(i))
           &&PositionGetString(POSITION_SYMBOL)==_Symbol
           &&PositionGetInteger(POSITION_MAGIC)==m_EAMagicNumber
           &&PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
           return(true);
      return(false);
     }

   bool IsAlreadySold()
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        if(PositionSelectByTicket(PositionGetTicket(i))
           &&PositionGetString(POSITION_SYMBOL)==_Symbol
           &&PositionGetInteger(POSITION_MAGIC)==m_EAMagicNumber
           &&PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
           return(true);
      return(false);
     }

   void ManageTrades()
     {
      MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
      if(tm.day!=m_LastTradeDay) { m_TradesToday=0; m_LastTradeDay=tm.day; }
      if(m_TradesToday>=m_MaxTradesPerDay) return;
      if(!IsWithinSessionNew()) return;
      ENUM_ORDER_TYPE sig=GetTradeSignal();
      if(sig==ORDER_TYPE_BUY && !IsAlreadyBought()) { OpenTrade(sig); m_TradesToday++; }
      if(sig==ORDER_TYPE_SELL&& !IsAlreadySold()) { OpenTrade(sig); m_TradesToday++; }
     }

   void CheckAndExecutePartialClose(){}
   void CheckReversalExit(){}

   void OpenTrade(ENUM_ORDER_TYPE type)
     {
      double atr[1]; CopyBuffer(m_ATRHandle,0,1,1,atr);
      double slDist=atr[0]*m_ATRSLMultiplier;
      double tpDist=slDist*m_RiskRewardRatio;
      double price=(type==ORDER_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
      double sl=(type==ORDER_TYPE_BUY?price-slDist:price+slDist);
      double tp=(type==ORDER_TYPE_BUY?price+tpDist:price-tpDist);
      double risk=m_UsePercentRisk?AccountInfoDouble(ACCOUNT_BALANCE)*m_RiskPercentage/100:m_FixedRiskPerTrade;
      double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double lot=risk/((slDist/tickSize)*tickVal);
      lot=NormalizeDouble(MathFloor(lot/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),2);
      MqlTradeRequest req={}; MqlTradeResult res={};
      req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=lot; req.type=type;
      req.price=price; req.sl=sl; req.tp=tp; req.deviation=m_AllowedSlippage;
      req.magic=m_EAMagicNumber; req.comment="MA Touch Modified";
      m_Trade.OrderSend(req,res);
     }

public:
   CMaRibbonEA():m_TrendDir(NONE),m_TradesToday(0),m_LastTradeDay(0),m_LastBarTime(0){}
   void InitializeIndicators()
     {
      m_MAMethod=MA_Method; m_MAStartPeriod=MA_StartPeriod; m_MAPeriodStep=MA_PeriodStep; m_NumMAs=NUM_MA;
      m_EnableReversalExit=EnableReversalExit; m_LookbackHL=LookbackHighLow;
      m_PartialClosePct=PartialClosePct; m_PartialCloseReward=PartialCloseReward;
      m_EnableBreakeven=EnableBreakeven; m_BreakevenReward=BreakevenReward;
      m_UseDailyBias=UseDailyBias; m_MaxTradesPerDay=MaxTradesPerDay; m_AllowMultiplePos=AllowMultiplePos;
      m_ATRPeriod=ATR_Period; m_ATRSLMultiplier=ATR_SL_Multiplier; m_RiskRewardRatio=RiskRewardRatio;
      m_FixedRiskPerTrade=FixedRiskPerTrade; m_UsePercentRisk=UsePercentRisk; m_RiskPercentage=RiskPercentage;
      m_AllowedSlippage=AllowedSlippage; m_EAMagicNumber=EA_MagicNumber;
      m_BBPeriod=BB_Period; m_BBDeviation=BB_Deviation;
      m_TradeNewYork=TradeNewYork; m_TradeLondon=TradeLondon;
      m_TradeTokyo=TradeTokyo; m_TradeSydney=TradeSydney;
      for(int i=0;i<m_NumMAs;i++) m_MAHandles[i]=iMA(_Symbol,_Period,m_MAStartPeriod+i*m_MAPeriodStep,0,m_MAMethod,PRICE_CLOSE);
      m_BBHandle=iBands(_Symbol,_Period,m_BBPeriod,0,m_BBDeviation,PRICE_CLOSE);
      m_ATRHandle=iATR(_Symbol,_Period,m_ATRPeriod);
     }

   void OnTick()
     {
      datetime t=iTime(_Symbol,_Period,0);
      if(t!=m_LastBarTime)
        { UpdateTrendDirection(); ManageTrades(); m_LastBarTime=t; }
     }
  };

CMaRibbonEA maRibbonInstance;

int OnInit() { maRibbonInstance.InitializeIndicators(); return(INIT_SUCCEEDED); }
void OnTick() { maRibbonInstance.OnTick(); }

