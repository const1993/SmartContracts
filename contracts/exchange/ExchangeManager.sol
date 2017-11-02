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
    uint constant ERROR_EXCHANGE_STOCK_INVALID_PARAMETER = 7001;
    uint constant ERROR_EXCHANGE_STOCK_INVALID_INVOCATION = 7002;
    uint constant ERROR_EXCHANGE_STOCK_ADD_CONTRACT = 7003;
    uint constant ERROR_EXCHANGE_STOCK_UNABLE_CREATE_EXCHANGE = 7004;
    uint constant ERROR_EXCHANGE_STOCK_UNKNOWN_SYMBOL = 7005;
    uint constant ERROR_EXCHANGE_STOCK_EXISTS = 7006;
    uint constant ERROR_EXCHANGE_STOCK_HAS_ETH_BALANCE = 7008;
    uint constant ERROR_EXCHANGE_STOCK_HAS_ERC20_BALANCE = 7007;

    StorageInterface.Address exchangeFactory;
    StorageInterface.OrderedAddressesSet exchanges; // (exchange [])
    StorageInterface.AddressesSetMapping owners; // (owner => exchange [])
    StorageInterface.AddressesSetMapping symbols; // (symbol => exchange [])
    StorageInterface.Set assetSymbols; // (symbol [])

    modifier onlyExchangeContractOwner(address _exchange) {
        if (Exchange(_exchange).contractOwner() == msg.sender) {
            _;
        }
    }

    function ExchangeManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        exchanges.init("ex_m_exchanges");
        owners.init("ex_m_owners");
        symbols.init("ex_m_symbols");
        assetSymbols.init("ex_m_assetSymbols");
        exchangeFactory.init("ex_m_exchangeFactory");
    }

    function init(address _contractsManager, address _exchangeFactory) public onlyContractOwner returns (uint) {
        BaseManager.init(_contractsManager, "ExchangeManager");
        store.set(exchangeFactory, _exchangeFactory);
        return OK;
    }

    function isExchangeExists(address exchange) public constant returns (bool) {
        return store.includes(exchanges, exchange);
    }

    function getExchangesForOwner(address owner) public constant returns (address []) {
        return store.get(owners, bytes32(owner));
    }

    function getAssetSymbols() public constant returns (bytes32 []) {
        return store.get(assetSymbols);
    }

    function getExchangesForSymbol(bytes32 _symbol) public constant returns (address []) {
        return store.get(symbols, _symbol);
    }

    function getExchangeData(address [] _exchanges)
    external
    constant
    returns (address [] exchanges,
             address [] owners,
             uint [] buyPrices,
             uint [] sellPrices,
             uint [] assetBalances,
             uint [] ethBalances)
    {
        exchanges = new address [] (_exchanges.length);
        owners = new address [] (_exchanges.length);
        buyPrices = new uint [] (_exchanges.length);
        sellPrices = new uint [] (_exchanges.length);
        assetBalances = new uint [] (_exchanges.length);
        ethBalances = new uint [] (_exchanges.length);

        for (uint idx = 0; idx < _exchanges.length; idx++) {
            if (isExchangeExists(_exchanges[idx])) {
                Exchange exchange = Exchange(_exchanges[idx]);

                exchanges[idx] = address(exchange);
                owners[idx] = exchange.contractOwner();
                buyPrices[idx] = exchange.buyPrice();
                sellPrices[idx] = exchange.sellPrice();
                assetBalances[idx] = exchange.assetBalance();
                ethBalances[idx] = exchange.ethBalance();
            }
        }
    }

    function getExchangeFactory() public constant returns (ExchangeFactory) {
        return ExchangeFactory(store.get(exchangeFactory));
    }

    function createExchange(bytes32 _symbol, bool _useTicker)
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

        registerExchange(Exchange(exchange));

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

        registerExchange(Exchange(_exchange));

        _emitExchangeAdded(msg.sender, _exchange);
        return OK;
    }

    function removeExchange(address _exchange)
    public
    onlyExchangeContractOwner(_exchange)
    returns (uint errorCode)
    {
        // no additional checks needed if `onlyExchangeOwner` is passed
        unregisterExchange(Exchange(_exchange));

        _emitExchangeRemoved(msg.sender, _exchange);
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

    function lookupERC20Manager() private constant returns (ERC20Manager) {
        return ERC20Manager(lookupManager("ERC20Manager"));
    }

    function registerExchange(Exchange exchange) private {
        address owner = exchange.contractOwner();

        store.add(exchanges, address(exchange));
        store.add(owners, bytes32(owner), address(exchange));

        bytes32 smb = getSymbol(address(exchange.asset()));
        store.add(symbols, smb, address(exchange));
        store.add(assetSymbols, smb);
    }

    function unregisterExchange(Exchange exchange) private {
        address owner = exchange.contractOwner();
        store.remove(exchanges, exchange);
        store.remove(owners, bytes32(owner), exchange);

        bytes32 symbol = getSymbol(address(exchange.asset()));

        if (store.count(assetSymbols) == 1) {
            store.remove(assetSymbols, symbol);
        }
        store.remove(symbols, symbol, address(exchange));
    }

    function getSymbol(address token) internal constant returns (bytes32) {
        var (tokenAddress, name, symbol, url, decimals, ipfsHash, swarmHash)
                = lookupERC20Manager().getTokenMetaData(token);
        return symbol;
    }
}
