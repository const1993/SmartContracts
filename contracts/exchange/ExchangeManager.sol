pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "./Exchange.sol";
import "../core/erc20/ERC20Manager.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";
import "./ExchangeManagerEmitter.sol";
import "../assets/AssetsManager.sol";
import "../core/event/MultiEventsHistory.sol";
import "./ExchangeFactory.sol";


contract ExchangeManager is ExchangeManagerEmitter, BaseManager {
    uint constant ERROR_EXCHANGE_STOCK_NOT_FOUND = 7000;
    uint constant ERROR_EXCHANGE_STOCK_UNABLE_CREATE_EXCHANGE = 7001;
    uint constant ERROR_EXCHANGE_STOCK_UNKNOWN_SYMBOL = 7002;
    uint constant ERROR_EXCHANGE_STOCK_EXISTS = 7003;

    StorageInterface.Address exchangeFactory;
    StorageInterface.Set exchanges; // (exchange [])
    StorageInterface.AddressesSetMapping owners; // (owner => exchange [])

    StorageInterface.UInt fee;

    modifier onlyExchangeContractOwner(address _exchange) {
        if (Exchange(_exchange).contractOwner() == msg.sender) {
            _;
        }
    }

    function ExchangeManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        exchanges.init("ex_m_exchanges");
        owners.init("ex_m_owners");
        exchangeFactory.init("ex_m_exchangeFactory");
        fee.init("ex_m_fee");
    }

    function init(address _contractsManager, address _exchangeFactory)
    public
    onlyContractOwner
    returns (uint)
    {
        BaseManager.init(_contractsManager, "ExchangeManager");
        store.set(exchangeFactory, _exchangeFactory);
        return OK;
    }

    function isExchangeExists(address exchange) public constant returns (bool) {
        return store.includes(exchanges, bytes32(exchange));
    }

    function getExchangesForOwner(address owner) public constant returns (address []) {
        return store.get(owners, bytes32(owner));
    }

    function getExchangesForOwnerCount(address owner) public constant returns (address []) {
        return store.get(owners, bytes32(owner));
    }

    function getExchanges(uint _fromIdx, uint _length) public constant returns (address [] result) {
        result = new address [] (_length);
        for (uint idx = 0; idx < _length; idx++) {
            result[idx] = address(store.get(exchanges, idx + _fromIdx));
        }
    }

    function getExchangesCount() public constant returns (uint) {
        return store.count(exchanges);
    }

    function getExchangeData(address [] _exchanges)
    external
    constant
    returns (address [] exchanges,
             bytes32 [] symbols,
             address [] owners,
             uint [] buyPrices,
             uint [] sellPrices,
             uint [] assetBalances,
             uint [] ethBalances)
    {
        exchanges = new address [] (_exchanges.length);
        symbols = new bytes32 [] (_exchanges.length);
        owners = new address [] (_exchanges.length);
        buyPrices = new uint [] (_exchanges.length);
        sellPrices = new uint [] (_exchanges.length);
        assetBalances = new uint [] (_exchanges.length);
        ethBalances = new uint [] (_exchanges.length);

        for (uint idx = 0; idx < _exchanges.length; idx++) {
            if (isExchangeExists(_exchanges[idx])) {
                Exchange exchange = Exchange(_exchanges[idx]);

                exchanges[idx] = address(exchange);
                symbols[idx] = getSymbol(address(exchange.asset()));
                owners[idx] = exchange.contractOwner();
                buyPrices[idx] = exchange.buyPrice();
                sellPrices[idx] = exchange.sellPrice();
                assetBalances[idx] = exchange.assetBalance();
                ethBalances[idx] = exchange.etherBalance();
            }
        }
    }

    function getExchangeFactory() public constant returns (ExchangeFactory) {
        return ExchangeFactory(store.get(exchangeFactory));
    }

    function getFee() public constant returns (uint) {
        return store.get(fee);
    }

    function setFee(uint _fee) public onlyAuthorized returns (uint) {
        require(_fee > 1 && _fee < 10000);
        store.set(fee, _fee);
        return OK;
    }

    function createExchange(
        bytes32 _symbol,
        bool _useTicker,
        uint _sellPrice,
        uint _buyPrice,
        address _authorizedManager,
        bool _isActive)
    public
    returns (uint errorCode)
    {
        address token = lookupERC20Manager().getTokenAddressBySymbol(_symbol);
        if (token == 0x0) {
            return _emitError(ERROR_EXCHANGE_STOCK_UNKNOWN_SYMBOL);
        }

        address rewards = lookupManager("Rewards");
        if (rewards == 0x0) {
            return _emitError(ERROR_EXCHANGE_STOCK_UNABLE_CREATE_EXCHANGE);
        }

        Exchange exchange = getExchangeFactory().createExchange();

        exchange.setupEventsHistory(getEventsHistory());

        if (!MultiEventsHistory(getEventsHistory()).authorize(exchange)) {
            revert();
        }

        exchange.init(contractsManager, Asset(token), rewards, getFee());

        if (_buyPrice > 0 && _sellPrice > 0) {
            if (exchange.setPrices(_buyPrice, _sellPrice) != OK) {
                revert();
            }
        }

        if (_authorizedManager != 0x0) {
            if (exchange.grantAuthorized(_authorizedManager) != OK) {
                revert();
            }
        }

        if (exchange.setActive(_isActive) != OK) {
            revert();
        }

        if (!exchange.transferContractOwnership(msg.sender)) {
            revert();
        }

        registerExchange(Exchange(exchange));

        _emitExchangeCreated(msg.sender, exchange, _symbol, rewards, getFee(), _buyPrice, _sellPrice);
        return OK;
    }

    /**
    *  Deletes msg.sender from an exchange list.
    *  Designed to be called by exchange contract.
    */
    function removeExchange()
    public
    returns (uint errorCode)
    {
        if (!isExchangeExists(msg.sender)) {
            return _emitError(ERROR_EXCHANGE_STOCK_NOT_FOUND);
        }

        unregisterExchange(Exchange(msg.sender));

        _emitExchangeRemoved(msg.sender);
        return OK;
    }

    function lookupAssetMananger() private constant returns (AssetsManager) {
        return AssetsManager(lookupManager("AssetsManager"));
    }

    function lookupERC20Manager() private constant returns (ERC20Manager) {
        return ERC20Manager(lookupManager("ERC20Manager"));
    }

    function registerExchange(Exchange exchange) private {
        store.add(exchanges, bytes32(address(exchange)));

        address owner = exchange.contractOwner();
        store.add(owners, bytes32(owner), address(exchange));
    }

    function unregisterExchange(Exchange exchange) private {
        store.remove(exchanges, bytes32(address(exchange)));

        address owner = exchange.contractOwner();
        store.remove(owners, bytes32(owner), address(exchange));
    }

    //bytes32 smb = getSymbol(address(exchange.asset()));
    function getSymbol(address token) internal constant returns (bytes32) {
        var (tokenAddress, name, symbol, url, decimals, ipfsHash, swarmHash)
                = lookupERC20Manager().getTokenMetaData(token);
        return symbol;
    }

    function _emitExchangeRemoved(address exchange) internal {
        Asset asset = Exchange(exchange).asset();
        ExchangeManager(getEventsHistory()).emitExchangeRemoved(exchange, getSymbol(address(asset)));
    }

    function _emitExchangeAdded(address user, address exchange) internal {
        Asset asset = Exchange(exchange).asset();
        ExchangeManager(getEventsHistory()).emitExchangeAdded(user, exchange, getSymbol(address(asset)));
    }

    function _emitExchangeCreated(
        address user,
        address exchange,
        bytes32 symbol,
        address rewards,
        uint fee,
        uint buyPrice,
        uint sellPrice)
    internal
    {
        ExchangeManager(getEventsHistory()).emitExchangeCreated(user, exchange, symbol, rewards, fee, buyPrice, sellPrice);
    }

    function _emitError(uint error) internal returns (uint) {
        ExchangeManager(getEventsHistory()).emitError(error);
        return error;
    }
}
