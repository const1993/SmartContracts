pragma solidity ^0.4.11;

import "./crowdsales/BlockLimitedCrowdsale.sol";
import "./crowdsales/TimeLimitedCrowdsale.sol";
import "../core/common/BaseManager.sol";

/**
*  @title CrowdsaleFactory
*
*  Is not designed for direct crowdsale creation via external calls from web application.
*  Only CrowdsaleManager is authorised to create and delete crowdsale.
*
*  See CrowdsaleManager.
*/
contract CrowdsaleFactory is BaseManager {
    StorageInterface.Address priceTicker;

    modifier onlyCrowdsaleManager {
        if (msg.sender == lookupManager("CrowdsaleManager")) {
            _;
        }
    }

    function CrowdsaleFactory(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        priceTicker.init("priceTicker");
    }

    function init(address _contractsManager, address _priceTicker) onlyContractOwner public returns (uint) {
        BaseManager.init(_contractsManager, store.crate);

        setPriceTicker(_priceTicker);
        return OK;
    }

    function setPriceTicker(address _priceTicker) onlyContractOwner public {
        require(_priceTicker != 0x0);

        store.set(priceTicker, _priceTicker);
    }

    function createCrowdsale(bytes32 _symbol) public returns (address);

    function getPriceTicker() public constant returns (address) {
        return store.get(priceTicker);
    }
}

/**
*  @title TimeLimitedCrowdsaleFactory
*
*  Instantiates a TimeLimitedCrowdsale contract.
*/
contract TimeLimitedCrowdsaleFactory is CrowdsaleFactory {
    function TimeLimitedCrowdsaleFactory(Storage _store, bytes32 _crate) CrowdsaleFactory(_store, _crate) public {
    }

    function createCrowdsale(bytes32 _symbol) onlyCrowdsaleManager public returns (address) {
        require(_symbol != 0x0);

        address crowdsale = new TimeLimitedCrowdsale(contractsManager, _symbol, getPriceTicker());
        BaseCrowdsale(crowdsale).changeContractOwnership(msg.sender);

        return crowdsale;
    }
}

/**
*  @title BlockLimitedCrowdsaleFactory
*
*  Instantiates a BlockLimitedCrowdsale contract.
*/
contract BlockLimitedCrowdsaleFactory is CrowdsaleFactory {
    function BlockLimitedCrowdsaleFactory(Storage _store, bytes32 _crate) CrowdsaleFactory(_store, _crate) public {
    }

    function createCrowdsale(bytes32 _symbol) onlyCrowdsaleManager public returns (address) {
        require(_symbol != 0x0);

        address crowdsale = new BlockLimitedCrowdsale(contractsManager, _symbol, getPriceTicker());
        BaseCrowdsale(crowdsale).changeContractOwnership(msg.sender);

        return crowdsale;
    }
}
