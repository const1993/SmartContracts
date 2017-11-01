pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "./Exchange.sol";
import {ERC20ManagerInterface as ERC20Manager} from "../core/erc20/ERC20ManagerInterface.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";
import "./ExchangeManagerEmitter.sol";
import "../assets/AssetsManager.sol";
import "../core/event/MultiEventsHistory.sol";


contract ExchangeManager is ExchangeManagerEmitter, BaseManager {
    uint constant ERROR_EXCHANGE_STOCK_NOT_FOUND = 7000;
    uint constant ERROR_EXCHANGE_STOCK_INVALID_PARAMETER = 7001;
    uint constant ERROR_EXCHANGE_STOCK_INVALID_INVOCATION = 7002;
    uint constant ERROR_EXCHANGE_STOCK_ADD_CONTRACT = 7003;
    uint constant ERROR_EXCHANGE_STOCK_UNABLE_CREATE_EXCHANGE = 7004;
    uint constant ERROR_EXCHANGE_STOCK_UNKNOWN_SYMBOL = 7005;
    uint constant ERROR_EXCHANGE_STOCK_EXISTS = 7006;
    uint constant ERROR_EXCHANGE_STOCK_HAS_ETH_BALANCE = 7008;
    uint constant ERROR_EXCHANGE_STOCK_HAS_ERC20_BALANCE = 7007;

    StorageInterface.AddressesSetMapping exchanges;
    StorageInterface.AddressesSetMapping owners;

    modifier onlyExchangeContractOwner(address _exchange) {
        if (Exchange(_exchange).contractOwner() == msg.sender) {
            _;
        }
    }

    function ExchangeManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        exchanges.init("ex_m_exchanges");
        owners.init("ex_m_owners");
    }

    function init(address _contractsManager) public onlyContractOwner returns (uint) {
        BaseManager.init(_contractsManager, "ExchangeManager");
        return OK;
    }

    function isExchangeExists(address exchange) public constant returns (bool) {
        return store.count(exchanges, bytes32(exchange)) > 0;
    }

    function getExchangeOwners(address exchange) public constant returns (address []) {
        return store.get(exchanges, bytes32(exchange));
    }

    function getExchangeForOwner(address owner) public constant returns (address []) {
        return store.get(owners, bytes32(owner));
    }

    function createExchange(bytes32 _symbol, bool _useTicker, bytes32 _tickerType)
    public
    returns (uint errorCode)
    {
        address _erc20Manager = lookupManager("ERC20Manager");
        address token = ERC20Manager(_erc20Manager).getTokenAddressBySymbol(_symbol);
        if (token == 0x0) {
            return _emitError(ERROR_EXCHANGE_STOCK_UNKNOWN_SYMBOL);
        }

        address rewards = lookupManager("Rewards");
        if (rewards == 0x0) {
            return _emitError(ERROR_EXCHANGE_STOCK_UNABLE_CREATE_EXCHANGE);
        }

        Exchange exchange = new Exchange();

        exchange.init(Asset(token), rewards, 0x0, 10);
        exchange.setupEventsHistory(getEventsHistory());

        if (!MultiEventsHistory(getEventsHistory()).authorize(exchange)) {
            revert();
        }

        if (!exchange.transferContractOwnership(msg.sender)) {
            revert();
        }

        if (_useTicker) {
            // TODO: not implemented yet
        }

        store.add(exchanges, bytes32(address(exchange)), msg.sender);
        store.add(owners, bytes32(msg.sender), exchange);

        _emitExchangeCreated(msg.sender, exchange);
        return OK;
    }

    function addExchange(address _exchange)
    public
    onlyExchangeContractOwner(_exchange)
    returns (uint errorCode)
    {
        // no additional checks needed if `onlyExchangeContractOwner` is passed

        if (isExchangeExists(_exchange)) {
            return _emitError(ERROR_EXCHANGE_STOCK_EXISTS);
        }

        // dirty `instance of` check
        Exchange(_exchange).buyPrice();
        Exchange(_exchange).sellPrice();

        store.add(exchanges, bytes32(_exchange), msg.sender);
        store.add(owners, bytes32(msg.sender), _exchange);

        _emitExchangeAdded(msg.sender, _exchange);
        return OK;
    }

    function removeExchange(address _exchange)
    public
    onlyExchangeContractOwner(_exchange)
    returns (uint errorCode)
    {
        // no additional checks needed if `onlyExchangeOwner` is passed

        address [] memory exchangeOwners = getExchangeOwners(_exchange);
        for (uint idx = 0; idx < exchangeOwners.length; idx++) {
            store.remove(exchanges, bytes32(_exchange), exchangeOwners[idx]);
            store.remove(owners, bytes32(exchangeOwners[idx]), _exchange);

            _emitExchangeRemoved(exchangeOwners[idx], _exchange);
        }

        return OK;
    }

    function destroyExchange(address _exchange)
    public
    onlyExchangeContractOwner(_exchange)
    returns (uint errorCode)
    {
        if (_exchange.balance > 0) {
            return _emitError(ERROR_EXCHANGE_STOCK_HAS_ETH_BALANCE);
        }

        Asset asset = Exchange(_exchange).asset();
        if (asset.balanceOf(msg.sender) > 0) {
            return _emitError(ERROR_EXCHANGE_STOCK_HAS_ERC20_BALANCE);
        }

        errorCode = removeExchange(_exchange);
        if (OK != errorCode) {
            return _emitError(errorCode);
        }

        // TODO: destroy

        return OK;
    }

    function _emitExchangeRemoved(address user, address exchange) internal {
        ExchangeManager(getEventsHistory()).emitExchangeRemoved(user, exchange);
    }

    function _emitExchangeAdded(address user, address exchange) internal {
        ExchangeManager(getEventsHistory()).emitExchangeAdded(user, exchange);
    }

    function _emitExchangeEdited(address user, address oldExchange, address newExchange) internal {
        ExchangeManager(getEventsHistory()).emitExchangeEdited(user, oldExchange, newExchange);
    }

    function _emitExchangeCreated(address user, address exchange) internal {
        ExchangeManager(getEventsHistory()).emitExchangeCreated(user, exchange);
    }

    function _emitExchangeOwnerAdded(address user, address owner, address exchange) internal {
        ExchangeManager(getEventsHistory()).emitExchangeOwnerAdded(user, owner, exchange);
    }

    function _emitExchangeOwnerRemoved(address user, address owner, address exchange) internal {
        ExchangeManager(getEventsHistory()).emitExchangeOwnerRemoved(user, owner, exchange);
    }

    function _emitError(uint error) internal returns (uint) {
        ExchangeManager(getEventsHistory()).emitError(error);
        return error;
    }

    function lookupAssetMananger() private constant returns (AssetsManager) {
        return AssetsManager(lookupManager("AssetsManager"));
    }
}
