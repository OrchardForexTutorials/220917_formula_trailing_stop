/*

   MA Cross with Formula TS.mq4
   Copyright 2022, Orchard Forex
   https://www.orchardforex.com

*/

#property copyright "Copyright 2022, Orchard Forex"
#property link "https://www.orchardforex.com"
#property version "1.00"
#property strict

#include "MA Cross with Formula TS.mqh"

;
//
//	Initialisation
//
int OnInit() {

   TakeProfit = PipsToDouble( InpTakeProfitPips );
   StopLoss   = PipsToDouble( InpStopLossPips );
   ATRValue   = 0;

   // In case of starting the expert mid bar block the new bar result
   //	https://youtu.be/XHJPpvI2h50
   IsNewBar( true );

   return ( INIT_SUCCEEDED );
}

void OnDeinit( const int reason ) {}

void OnTick() {

   // This expert looks for a cross of fast ma over slow ma
   //	That can happen mid bar but if you check mid bar then
   //		the price often reverses and goes back and forth many times
   //	I prefer to wait for the bar to close
   //	That means I only need to run once per bar and I am looking
   //		at values from bar 1, not 0

   // Quick check if trading is possible
   if ( !IsTradeAllowed() ) return;
   // This to check also if the market is open
   //	https://youtu.be/GejPt5odJow
   if ( !IsTradeAllowed( Symbol(), TimeCurrent() ) ) return;

   // I want to apply the trailing stop to every tick
   // so it goes here before the new bar test
   if ( ATRValue > 0 ) ApplyTrailingStop();

   //	Next exit if this is not a new bar
   //	https://youtu.be/XHJPpvI2h50
   if ( !IsNewBar( true ) ) return;

   // Get the ATR value
   ATRValue     = iATR( Symbol(), Period(), InpATRBars, 1 ) * InpATRFactor;

   // Get the fast and slow ma values for bar 1 and bar 2
   // Add the shift to slow, but I do it in the index
   double fast1 = iMA( Symbol(), Period(), InpFastMABars, 0, InpFastMAMethod, InpFastMAAppliedPrice, 1 );
   double fast2 = iMA( Symbol(), Period(), InpFastMABars, 0, InpFastMAMethod, InpFastMAAppliedPrice, 2 );
   double slow1 = iMA( Symbol(), Period(), InpSlowMABars, 0, InpSlowMAMethod, InpSlowMAAppliedPrice, 1 + InpSlowMAShift );
   double slow2 = iMA( Symbol(), Period(), InpSlowMABars, 0, InpSlowMAMethod, InpSlowMAAppliedPrice, 2 + InpSlowMAShift );

   // Compare, if Fast 1 is above Slow 1 and Fast 2 is not above Slow 2 then
   // there is a cross up
   if ( ( fast1 > slow1 ) && !( fast2 > slow2 ) ) {
      OpenTrade( ORDER_TYPE_BUY );
   }
   else if ( ( fast1 < slow1 ) && !( fast2 < slow2 ) ) {
      OpenTrade( ORDER_TYPE_SELL );
   }

   //
}

void OpenTrade( ENUM_ORDER_TYPE type ) {

   double price;
   double sl;
   double tp;

   if ( type == ORDER_TYPE_BUY ) {
      price = Ask;
      sl    = price - StopLoss;
      tp    = price + TakeProfit;
   }
   else {
      price = Bid;
      sl    = price + StopLoss;
      tp    = price - TakeProfit;
   }

   price = NormalizeDouble( price, Digits );
   sl    = NormalizeDouble( sl, Digits );
   tp    = NormalizeDouble( tp, Digits );

   if ( StopLoss == 0 ) sl = 0;
   if ( TakeProfit == 0 ) tp = 0;

   if ( !OrderSend( Symbol(), type, InpOrderSize, price, 0, sl, tp, InpTradeComment, InpMagic ) ) {
      Print( "Open failed for %s, %s, price=%f, sl=%f, tp=%f", Symbol(), EnumToString( type ), price, sl, tp );
   }
}

void ApplyTrailingStop() {

   double buyTrailingStopPrice  = Ask - ATRValue;
   double sellTrailingStopPrice = Bid + ATRValue;
   int    err;

   //	https://youtu.be/u9qFvriLQnU
   for ( int i = OrdersTotal() - 1; i >= 0; i-- ) {
      if ( !OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) ) continue;
      if ( OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic ) continue;

      if ( OrderType() == ORDER_TYPE_BUY && buyTrailingStopPrice > OrderOpenPrice() && ( OrderStopLoss() == 0 || buyTrailingStopPrice > OrderStopLoss() ) ) {
         ResetLastError();
         if ( !OrderModify( OrderTicket(), OrderOpenPrice(), buyTrailingStopPrice, OrderTakeProfit(), OrderExpiration() ) ) {
            err = GetLastError();
            PrintFormat( "Failed to update ts on ticket %i to %f, err=%i", OrderTicket(), buyTrailingStopPrice, err );
         }
      }

      if ( OrderType() == ORDER_TYPE_SELL && sellTrailingStopPrice < OrderOpenPrice() && ( OrderStopLoss() == 0 || sellTrailingStopPrice < OrderStopLoss() ) ) {
         ResetLastError();
         if ( !OrderModify( OrderTicket(), OrderOpenPrice(), sellTrailingStopPrice, OrderTakeProfit(), OrderExpiration() ) ) {
            err = GetLastError();
            PrintFormat( "Failed to update ts on ticket %i to %f, err=%i", OrderTicket(), sellTrailingStopPrice, err );
         }
      }
   }
}
