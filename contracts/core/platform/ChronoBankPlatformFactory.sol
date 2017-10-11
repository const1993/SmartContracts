pragma solidity ^0.4.11;

import "./ChronoBankPlatform.sol";
import "../event/MultiEventsHistory.sol";

/**
* @dev TODO
*/
contract ChronoBankPlatformFactory {

    function createPlatform(address owner) returns(address) {
        MultiEventsHistory history = new MultiEventsHistory();
        ChronoBankPlatform platform = new ChronoBankPlatform();
        history.authorize(platform);
        platform.setupEventsHistory(history);
        platform.transferContractOwnership(msg.sender);
        history.transferContractOwnership(owner);
        return platform;
    }

    function() {
        throw;
    }
}
