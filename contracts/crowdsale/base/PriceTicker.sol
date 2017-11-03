pragma solidity ^0.4.11;

/**
*  PriceFetcher Interface. Defines how a price could be fetched
*/
contract PriceFetcher {
    uint constant OK = 1;

    event ExchangePriceUpdated(address initiator, bytes32 indexed fsym, bytes32 indexed tsym, uint indexed updateTime, uint exchangePrice, uint rateDecimals);

    /**
    *  Check if the price of a `fsym` currency against 'tsym' currency is availbale.
    *
    *  @dev Note:
    *      1. must return `true` for equivalent symbols;
    *      2. `Ether` and `ETH` are equivalent.
    *
    *  @param fsym From Symbol
    *  @param tsym To Symbol
    *
    *  @return true if the price is an available.
    */
    function isPriceAvailable(bytes32 fsym, bytes32 tsym) public constant returns (bool);

    /**
    *  Get the price of a `fsym` currency against 'tsym' currency.
    *  Will throw if price is an unavailable;
    *
    *  @dev Note:
    *        1. must return (1, 0) if `fsym` equivalent for `tsym`,
    *           since price is always availbale to the same currency symbols;
    *        2. `Ether` and `ETH` are equivalent.
    *
    *  @param fsym From Symbol
    *  @param tsym To Symbol
    *
    *  @return a price and its decimals
    */
    function price(bytes32 fsym, bytes32 tsym) public constant returns (uint, uint);
}


/**
*  PriceTicker Interface.
*/
contract PriceTicker is PriceFetcher {
    uint constant PRICE_TICKER_OK_UPDATING = 2;
    uint constant PRICE_TICKER_INSUFFICIENT_BALANCE = 3;
    uint constant PRICE_TICKER_INVALID_INVOCATION = 4;

    /**
    *  Request asynchronously the price of a `fsym` currency against 'tsym' currency.
    *
    *  Note:
    *      1. Caller must implement PriceTickerCallback.
    *      2. Result will be returned via callback `receivePrice`.
    *      3. ETH symbol is used for getting price for Ether.
    *
    *  Since price of equivalent symbols is always 1, do not use async method
    *  for getting price of equivalent symbols.
    *
    *  @param fsym From Symbol
    *  @param tsym To Symbol
    *
    *  @return oraclize query id
    */
    function requestPrice(bytes32 fsym, bytes32 tsym) public payable returns (bytes32, uint);
}
