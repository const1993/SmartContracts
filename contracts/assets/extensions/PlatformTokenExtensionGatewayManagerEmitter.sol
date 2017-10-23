pragma solidity ^0.4.11;

import '../../core/event/MultiEventsHistoryAdapter.sol';

/**
* Emitter with support of events history for PlatformTokenExtensionGatewayManager
*/
contract PlatformTokenExtensionGatewayManagerEmitter is MultiEventsHistoryAdapter {

    /** TODO */
    event Error(address indexed self, uint errorCode);

    /** TODO */
    event AssetCreated(address indexed self, address platform, bytes32 symbol, address token);

    /** TODO */
    event CrowdsaleCampaignCreated(address indexed self, address platform, bytes32 symbol, address campaign);

    /** TODO */
    event CrowdsaleCampaignRemoved(address indexed self, address platform, bytes32 symbol, address campaign);


    function emitError(uint _errorCode) {
        Error(_self(), _errorCode);
    }

    function emitAssetCreated(address _platform, bytes32 _symbol, address _token) {
        AssetCreated(_self(), _platform, _symbol, _token);
    }

    function emitCrowdsaleCampaignCreated(address _platform, bytes32 _symbol, address _campaign) {
        CrowdsaleCampaignCreated(_self(), _platform, _symbol, _campaign);
    }

    function emitCrowdsaleCampaignRemoved(address _platform, bytes32 _symbol, address _campaign) {
        CrowdsaleCampaignRemoved(_self(), _platform, _symbol, _campaign);
    }
}
