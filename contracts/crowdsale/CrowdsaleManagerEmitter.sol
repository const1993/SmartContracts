pragma solidity ^0.4.11;

import "../core/event/MultiEventsHistoryAdapter.sol";

contract CrowdsaleManagerEmitter is MultiEventsHistoryAdapter {
    event CrowdsaleCreated(address indexed self, address indexed creator, bytes32 symbol, address crowdsale);
    event CrowdsaleDeleted(address indexed self, address crowdsale);
    event Error(address indexed self, uint errorCode);

    function emitCrowdsaleCreated(address creator, bytes32 symbol, address crowdsale) public {
        CrowdsaleCreated(_self(), creator, symbol, crowdsale);
    }

    function emitCrowdsaleDeleted(address crowdsale) public {
        CrowdsaleDeleted(_self(), crowdsale);
    }

    function emitError(uint errorCode) public {
        Error(_self(), errorCode);
    }
}
