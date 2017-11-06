pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract ExchangeManagerEmitter is MultiEventsHistoryAdapter {
    event ExchangeRemoved(address indexed self, address exchange);
    event ExchangeAdded(address indexed self, address indexed user, address exchange);
    event ExchangeEdited(address indexed self, address indexed user, address oldExchange, address newExchange);
    event ExchangeCreated(address indexed self, address indexed user, address exchange);
    event ExchangeOwnerAdded(address indexed self, address indexed user, address owner, address exchange);
    event ExchangeOwnerRemoved(address indexed self, address indexed user, address owner, address exchange);
    event Error(address indexed self, uint errorCode);

    function emitExchangeRemoved(address exchange) {
        ExchangeRemoved(_self(), exchange);
    }

    function emitExchangeAdded(address user, address exchange) {
        ExchangeAdded(_self(), user, exchange);
    }

    function emitExchangeEdited(address user, address oldExchange, address newExchange) {
        ExchangeEdited(_self(), user, oldExchange, newExchange);
    }

    function emitExchangeCreated(address user, address exchange) {
        ExchangeCreated(_self(), user, exchange);
    }

    function emitExchangeOwnerAdded(address user, address owner, address exchange) {
        ExchangeOwnerAdded(_self(), user, owner, exchange);
    }

    function emitExchangeOwnerRemoved(address user, address owner, address exchange) {
        ExchangeOwnerRemoved(_self(), user, owner, exchange);
    }

    function emitError(uint errorCode) {
        Error(_self(),errorCode);
    }
}
