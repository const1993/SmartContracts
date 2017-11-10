pragma solidity ^0.4.11;

import '../../core/event/MultiEventsHistoryAdapter.sol';

/**
* @title Emitter with support of events history for TokenExtensionRouter
*/
contract PlatformTokenExtensionGatewayManagerEmitter is MultiEventsHistoryAdapter {

    /** @dev Event for errors */
    event Error(address indexed self, uint errorCode);

    /** @dev Event for creating an asset */
    event AssetCreated(address indexed self, address platform, bytes32 symbol, address token, address indexed by);

    /** @dev Event for starting token's crowdsale */
    event CrowdsaleCampaignCreated(address indexed self, address platform, bytes32 symbol, address campaign, address indexed by);

    /** @dev Event for removing token's crowdsale */
    event CrowdsaleCampaignRemoved(address indexed self, address platform, bytes32 symbol, address campaign, address indexed by);


    function emitError(uint _errorCode) {
        Error(_self(), _errorCode);
    }

    function emitAssetCreated(address _platform, bytes32 _symbol, address _token, address _by) {
        AssetCreated(_self(), _platform, _symbol, _token, _by);
    }

    function emitCrowdsaleCampaignCreated(address _platform, bytes32 _symbol, address _campaign, address _by) {
        CrowdsaleCampaignCreated(_self(), _platform, _symbol, _campaign, _by);
    }

    function emitCrowdsaleCampaignRemoved(address _platform, bytes32 _symbol, address _campaign, address _by) {
        CrowdsaleCampaignRemoved(_self(), _platform, _symbol, _campaign, _by);
    }
}
