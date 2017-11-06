pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract ExchangeManagerEmitter is MultiEventsHistoryAdapter {
    event ExchangeCreated(address indexed self, address indexed user, address exchange);
    event ExchangeAdded(address indexed self, address indexed user, address exchange);
    event ExchangeRemoved(address indexed self, address exchange);
    event Error(address indexed self, uint errorCode);

    function emitExchangeCreated(address user, address exchange) {
        ExchangeCreated(_self(), user, exchange);
    }

    function emitExchangeRemoved(address exchange) {
        ExchangeRemoved(_self(), exchange);
    }

    function emitExchangeAdded(address user, address exchange) {
        ExchangeAdded(_self(), user, exchange);
    }

    function emitError(uint errorCode) {
        Error(_self(),errorCode);
    }
}
