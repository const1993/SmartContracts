pragma solidity ^0.4.11;

import "./ChronoBankPlatform.sol";
import "../event/MultiEventsHistory.sol";

/**
* @dev TODO
*/
contract ChronoBankPlatformFactory {
    function createPlatform(address owner, MultiEventsHistory eventsHistory, address eventsHistoryAdmin) returns(address) {
        ChronoBankPlatform platform = new ChronoBankPlatform();
        platform.setupEventsHistoryAdmin(eventsHistoryAdmin);
        eventsHistory.authorize(platform);
        platform.setupEventsHistory(eventsHistory);

        platform.transferContractOwnership(msg.sender);
        return platform;
    }
}
