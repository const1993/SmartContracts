pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "../assets/AssetsManagerInterface.sol";
import "./base/BaseCrowdsale.sol";
import "./CrowdsaleFactory.sol";
import "./CrowdsaleManagerEmitter.sol";

/**
 *  @title CrowdsaleManager
 *
 *  Is not designed for direct crowdsale management via external calls
 *  from web application.
 *
 *  Only AssetsManager is authorised to execute CrowdsaleManager's methods.
 */
contract CrowdsaleManager is CrowdsaleManagerEmitter, BaseManager {
    uint constant ERROR_CROWDFUNDING_INVALID_INVOCATION = 3000;
    uint constant ERROR_CROWDFUNDING_ADD_CONTRACT = 3001;
    uint constant ERROR_CROWDFUNDING_NOT_ASSET_OWNER = 3002;
    uint constant ERROR_CROWDFUNDING_DOES_NOT_EXIST = 3003;

    StorageInterface.AddressesSet campaigns;

    modifier onlyAssetAuthorizedContract {
        if (TokenExtensionRegistry(lookupManager("AssetsManager")).containsTokenExtension(msg.sender)) {
            _;
        }
    }

    /**
    *  Constructor
    */
    function CrowdsaleManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        campaigns.init('campaigns');
    }

    /**
    *  Initialize
    */
    function init(address _contractsManager) onlyContractOwner public returns (uint) {
        return BaseManager.init(_contractsManager, "CrowdsaleManager");
    }

    /**
    *  Creates Crowdsale with a type produced by CrowdsaleFactory with given _factoryName.
    */
    function createCrowdsale(address _creator, bytes32 _symbol, bytes32 _factoryName)
    onlyAssetAuthorizedContract
    public returns (address, uint) {
        if (!lookupAssetsManager().isAssetOwner(_symbol, _creator)) {
            return (0x0, _emitError(ERROR_CROWDFUNDING_NOT_ASSET_OWNER));
        }

        address crowdsale = getCrowdsaleFactory(_factoryName).createCrowdsale(_symbol);

        if (!BaseCrowdsale(crowdsale).claimContractOwnership()) {
            return (0x0, _emitError(ERROR_CROWDFUNDING_INVALID_INVOCATION));
        }

        store.add(campaigns, crowdsale);
        _emitCrowdsaleCreated(_creator, _symbol, crowdsale);

        return (crowdsale, OK);
    }

    /**
    *  Deletes Crowdsale if It is allowed.
    */
    function deleteCrowdsale(address crowdsale) onlyAssetAuthorizedContract public returns (uint) {
        if (!lookupAssetsManager().isAssetOwner(BaseCrowdsale(crowdsale).getSymbol(), crowdsale)) {
            return _emitError(ERROR_CROWDFUNDING_NOT_ASSET_OWNER);
        }

        if (!store.includes(campaigns, crowdsale)) {
            return _emitError(ERROR_CROWDFUNDING_DOES_NOT_EXIST);
        }

        if (!BaseCrowdsale(crowdsale).hasEnded()) {
            return _emitError(ERROR_CROWDFUNDING_INVALID_INVOCATION);
        }

        store.remove(campaigns, crowdsale);

        BaseCrowdsale(crowdsale).destroy(); // TODO: @ahiatsevich refund to CrowdsaleManager??

        _emitCrowdsaleDeleted(crowdsale);
        return OK;
    }

    /**
    *  Returns CrowdsaleFactory by given _factoryName.
    */
    function getCrowdsaleFactory(bytes32 _factoryName) public constant returns (CrowdsaleFactory) {
        return CrowdsaleFactory(lookupManager(_factoryName));
    }

    /**
    *  Returns user's tokens placed on crowdsale
    */
    function getTokensOnCrowdsale(address _user) public constant returns (address[] _tokens) {
        AssetsManagerInterface assetsManager = lookupAssetsManager();
        AssetsManagerStatisticsInterface assetsStatisticsManager = AssetsManagerStatisticsInterface(address(assetsManager));
        _tokens = new address[](assetsStatisticsManager.getSystemAssetsForOwnerCount(_user));
        uint _crowdsaleCount = store.count(campaigns);
        uint _tokenPointer;
        bytes32 _symbol;
        for (uint _crowdsaleIdx = 0; _crowdsaleIdx < _crowdsaleCount && _tokenPointer < _tokens.length; ++_crowdsaleIdx) {
            _symbol = BaseCrowdsale(store.get(campaigns, _crowdsaleIdx)).getSymbol();
            if (assetsManager.isAssetOwner(_symbol, _user)) {
                _tokens[_tokenPointer++] = assetsManager.getAssetBySymbol(_symbol);
            }
        }
    }

    /**
    *  Returns AssetsManager.
    */
    function lookupAssetsManager() internal constant returns (AssetsManagerInterface) {
        return AssetsManagerInterface(lookupManager("AssetsManager"));
    }

    function _emitCrowdsaleCreated(address creator, bytes32 symbol, address crowdsale) internal {
        CrowdsaleManagerEmitter(getEventsHistory()).emitCrowdsaleCreated(creator, symbol, crowdsale);
    }

    function _emitCrowdsaleDeleted(address crowdsale) internal {
        CrowdsaleManagerEmitter(getEventsHistory()).emitCrowdsaleDeleted(crowdsale);
    }

    function _emitError(uint error) internal returns (uint) {
        CrowdsaleManagerEmitter(getEventsHistory()).emitError(error);
        return error;
    }
}
