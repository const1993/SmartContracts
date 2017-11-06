pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract ExchangeManagerEmitter is MultiEventsHistoryAdapter {
    event ExchangeCreated(
        address indexed self,
        address indexed user,
        address exchange,
        bytes32 symbol,
        address rewards,
        uint fee,
        uint buyPrice,
        uint sellPrice);
    event ExchangeAdded(address indexed self, address indexed user, address exchange, bytes32 symbol);
    event ExchangeRemoved(address indexed self, address exchange, bytes32 symbol);
    event Error(address indexed self, uint errorCode);

    function emitExchangeCreated(
        address user,
        address exchange,
        bytes32 symbol,
        address rewards,
        uint fee,
        uint buyPrice,
        uint sellPrice)
    {
        ExchangeCreated(_self(), user, exchange, symbol, rewards, fee, buyPrice, sellPrice);
    }

    function emitExchangeRemoved(address exchange, bytes32 symbol) {
        ExchangeRemoved(_self(), exchange, symbol);
    }

    function emitExchangeAdded(address user, address exchange, bytes32 symbol) {
        ExchangeAdded(_self(), user, exchange, symbol);
    }

    function emitError(uint errorCode) {
        Error(_self(),errorCode);
    }
}
