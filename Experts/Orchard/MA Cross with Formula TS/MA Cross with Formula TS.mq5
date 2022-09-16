/*

   MA Cross with Formula TS.mq5
   Copyright 2022, Orchard Forex
   https://www.orchardforex.com

*/

#property copyright "Copyright 2022, Orchard Forex"
#property link "https://www.orchardforex.com"
#property version "1.00"
#property strict

#include "MA Cross with Formula TS.mqh"

// Bring in the trade class to make trading easier
#include <Trade/Trade.mqh>
CTrade        Trade;
CPositionInfo Position;

// Handles and buffers for the moving averages
int           FastHandle;
double        FastBuffer[];
int           SlowHandle;
double        SlowBuffer[];
int           ATRHandle;
double        ATRBuffer[];

;
//
//	Initialisation
//
int OnInit() {

   TakeProfit = PipsToDouble( InpTakeProfitPips );
   StopLoss   = PipsToDouble( InpStopLossPips );
   ATRValue   = 0;

   Trade.SetExpertMagicNumber( InpMagic );

   FastHandle = iMA( Symbol(), Period(), InpFastMABars, 0, InpFastMAMethod, InpFastMAAppliedPrice );
   ArraySetAsSeries( FastBuffer, true );

   //	I could use the shift here but I won't
   SlowHandle = iMA( Symbol(), Period(), InpSlowMABars, 0, InpSlowMAMethod, InpSlowMAAppliedPrice );
   ArraySetAsSeries( SlowBuffer, true );

   ATRHandle = iATR( Symbol(), Period(), InpATRBars );
   ArraySetAsSeries( ATRBuffer, true );

   if ( FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE ) {
      Print( "Error creating handles to moving averages and ATR" );
      return INIT_FAILED;
   }

   // In case of starting the expert mid bar block the new bar result
   //	https://youtu.be/XHJPpvI2h50
   IsNewBar( true );

   return ( INIT_SUCCEEDED );
}

void OnDeinit( const int reason ) {
   IndicatorRelease( FastHandle );
   IndicatorRelease( SlowHandle );
   IndicatorRelease( ATRHandle );
}

void OnTick() {

   // This expert looks for a cross of fast ma over slow ma
   //	That can happen mid bar but if you check mid bar then
   //		the price often reverses and goes back and forth many times
   //	I prefer to wait for the bar to close
   //	That means I only need to run once per bar and I am looking
   //		at values from bar 1, not 0

   // Quick check if trading is possible
   if ( !IsTradeAllowed() ) return;
   // Also exit if the market may be closed
   //	https://youtu.be/GejPt5odJow
   if ( !IsMarketOpen() ) return;

   // I want to apply the trailing stop to every tick
   // so it goes here before the new bar test
   if ( ATRValue > 0 ) ApplyTrailingStop();

   //	Next exit if this is not a new bar
   //	https://youtu.be/XHJPpvI2h50
   if ( !IsNewBar( true ) ) return;

   // I also want to only get the ATR value on a new bar
   if ( CopyBuffer( ATRHandle, 0, 0, 2, ATRBuffer ) < 2 ) {
      Print( "Insufficient results from ATR" );
      ATRValue = 0;
   }
   else {
      ATRValue = ATRBuffer[1] * InpATRFactor;
   }

   // Get the fast and slow ma values for bar 1 and bar 2
   if ( CopyBuffer( FastHandle, 0, 0, 3, FastBuffer ) < 3 ) {
      Print( "Insufficient results from fast MA" );
      return;
   }
   // This is where I apply the shift
   if ( CopyBuffer( SlowHandle, 0, InpSlowMAShift, 3, SlowBuffer ) < 3 ) {
      Print( "Insufficient results from slow MA" );
      return;
   }

   // Compare, if Fast 1 is above Slow 1 and Fast 2 is not above Slow 2 then
   // there is a cross up
   if ( ( FastBuffer[1] > SlowBuffer[1] ) && !( FastBuffer[2] > SlowBuffer[2] ) ) {
      OpenTrade( ORDER_TYPE_BUY );
   }
   else if ( ( FastBuffer[1] < SlowBuffer[1] ) && !( FastBuffer[2] < SlowBuffer[2] ) ) {
      OpenTrade( ORDER_TYPE_SELL );
   }

   //
}

void OpenTrade( ENUM_ORDER_TYPE type ) {

   double price;
   double sl;
   double tp;

   if ( type == ORDER_TYPE_BUY ) {
      price = SymbolInfoDouble( Symbol(), SYMBOL_ASK );
      sl    = price - StopLoss;
      tp    = price + TakeProfit;
   }
   else {
      price = SymbolInfoDouble( Symbol(), SYMBOL_BID );
      sl    = price + StopLoss;
      tp    = price - TakeProfit;
   }

   price = NormalizeDouble( price, Digits() );
   sl    = NormalizeDouble( sl, Digits() );
   tp    = NormalizeDouble( tp, Digits() );

   //-	8.	Allow tp and sl = 0
   if ( StopLoss == 0 ) sl = 0;
   if ( TakeProfit == 0 ) tp = 0;

   if ( !Trade.PositionOpen( Symbol(), type, InpOrderSize, price, sl, tp, InpTradeComment ) ) {
      Print( "Open failed for %s, %s, price=%f, sl=%f, tp=%f", Symbol(), EnumToString( type ), price, sl, tp );
   }
}

bool IsTradeAllowed() {

   return ( ( bool )MQLInfoInteger( MQL_TRADE_ALLOWED )              // Trading allowed in input dialog
            && ( bool )TerminalInfoInteger( TERMINAL_TRADE_ALLOWED ) // Trading allowed in terminal
            && ( bool )AccountInfoInteger( ACCOUNT_TRADE_ALLOWED )   // Is account able to trade, not locked out
            && ( bool )AccountInfoInteger( ACCOUNT_TRADE_EXPERT )    // Is account able to auto trade
   );
}

//-	9.	The trailing stop function
void ApplyTrailingStop() {

   double ask                   = SymbolInfoDouble( Symbol(), SYMBOL_ASK );
   double bid                   = SymbolInfoDouble( Symbol(), SYMBOL_BID );
   double buyTrailingStopPrice  = ask - ATRValue;
   double sellTrailingStopPrice = bid + ATRValue;
   int    err;

   //	https://youtu.be/u9qFvriLQnU
   // For hedging accounts, not netting
   for ( int i = PositionsTotal() - 1; i >= 0; i-- ) {
      ulong ticket = PositionGetTicket( i );
      if ( !PositionSelectByTicket( ticket ) ) continue;
      if ( Position.Symbol() != Symbol() || Position.Magic() != InpMagic ) continue;

      if ( Position.PositionType() == POSITION_TYPE_BUY && buyTrailingStopPrice > Position.PriceOpen() &&
           ( Position.StopLoss() == 0 || buyTrailingStopPrice > Position.StopLoss() ) ) {
         ResetLastError();
         if ( !Trade.PositionModify( ticket, buyTrailingStopPrice, Position.TakeProfit() ) ) {
            err = GetLastError();
            PrintFormat( "Failed to update ts on ticket %I64u to %f, err=%i", ticket, buyTrailingStopPrice, err );
         }
      }

      if ( Position.PositionType() == POSITION_TYPE_SELL && sellTrailingStopPrice < Position.PriceOpen() &&
           ( Position.StopLoss() == 0 || sellTrailingStopPrice < Position.StopLoss() ) ) {
         ResetLastError();
         if ( !Trade.PositionModify( ticket, sellTrailingStopPrice, Position.TakeProfit() ) ) {
            err = GetLastError();
            PrintFormat( "Failed to update ts on ticket %I64u to %f, err=%i", ticket, sellTrailingStopPrice, err );
         }
      }
   }
}
