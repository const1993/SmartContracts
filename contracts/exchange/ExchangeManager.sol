pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "../core/erc20/ERC20Manager.sol";
import "../core/event/MultiEventsHistory.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";

import "./Exchange.sol";
import "./ExchangeManagerEmitter.sol";
import "./ExchangeFactory.sol";

// @title ExchangeManager
//
// @notice ExchangeManager contract is the exchange registry which holds info
// about created exchanges and provides some util methods for managing it.
//
// The entry point for creating new exchanges.
//
// CBE users are permited to manage fee value against which an exchange will calculate fee.
contract ExchangeManager is ExchangeManagerEmitter, BaseManager {
    uint constant ERROR_EXCHANGE_STOCK_NOT_FOUND = 7000;
    uint constant ERROR_EXCHANGE_STOCK_INTERNAL = 7001;
    uint constant ERROR_EXCHANGE_STOCK_UNKNOWN_SYMBOL = 7002;

    StorageInterface.Address exchangeFactory;
    StorageInterface.Set exchanges; // (exchange [])
    StorageInterface.AddressesSetMapping owners; // (owner => exchange [])
    StorageInterface.UInt fee;

    modifier onlyExchangeContractOwner(address _exchange) {
        if (Exchange(_exchange).contractOwner() == msg.sender) {
            _;
        }
    }

    // Contructor
    function ExchangeManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        exchanges.init("ex_m_exchanges");
        owners.init("ex_m_owners");
        exchangeFactory.init("ex_m_exchangeFactory");
        fee.init("ex_m_fee");
    }

    // Initialises an exchange with the given params
    function init(address _contractsManager, address _exchangeFactory)
    public
    onlyContractOwner
    returns (uint)
    {
        BaseManager.init(_contractsManager, "ExchangeManager");
        if (setExchangeFactory(_exchangeFactory) != OK) {
            revert();
        }
        return OK;
    }

    // Sets fee value against which the exchange should calculate fee.
    //
    // Note, only CBE members are allowed to set this value.
    function setFee(uint _fee)
    public
    onlyAuthorized
    returns (uint)
    {
        require(_fee < 10000);
        store.set(fee, _fee);
        return OK;
    }

    // Sets the Exchange Factory address
    function setExchangeFactory(address _exchangeFactory)
    public
    onlyContractOwner
    returns (uint)
    {
        require(_exchangeFactory != 0x0);
        store.set(exchangeFactory, _exchangeFactory);
        return OK;
    }

    // Creates a new exchange with the given params.
    function createExchange(
        bytes32 _symbol,
        uint _buyPrice,
        uint _buyDecimals,
        uint _sellPrice,
        uint _sellDecimals,
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
            return _emitError(ERROR_EXCHANGE_STOCK_INTERNAL);
        }

        Exchange exchange = Exchange(getExchangeFactory().createExchange());

        exchange.setupEventsHistory(getEventsHistory());
        if (!MultiEventsHistory(getEventsHistory()).authorize(exchange)) {
            revert();
        }

        exchange.init(contractsManager, token, rewards, getFee());

        if (_buyPrice > 0 && _sellPrice > 0) {
            if (exchange.setPrices(_buyPrice, _buyDecimals, _sellPrice, _sellDecimals) != OK) {
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

        store.add(exchanges, bytes32(address(exchange)));
        store.add(owners, bytes32(msg.sender), address(exchange));

        assert(exchange.contractOwner() == msg.sender);
        assert(exchange.rewards() == rewards);
        assert(exchange.feePercent() == getFee());

        _emitExchangeCreated(msg.sender, exchange, _symbol, rewards, getFee(), _buyPrice, _sellPrice);
        return OK;
    }

    // Deletes msg.sender from the exchange list.
    // Note: Designed to be called only by exchange contract.
    function removeExchange()
    public
    returns (uint errorCode)
    {
        if (!isExchangeExists(msg.sender)) {
            return _emitError(ERROR_EXCHANGE_STOCK_NOT_FOUND);
        }

        store.remove(exchanges, bytes32(msg.sender));
        MultiEventsHistory(getEventsHistory()).reject(msg.sender);

        address owner = Exchange(msg.sender).contractOwner();
        store.remove(owners, bytes32(owner), msg.sender);

        _emitExchangeRemoved(msg.sender);
        return OK;
    }

    // Tells whether the given _exchange is in registry.
    function isExchangeExists(address _exchange) public view returns (bool) {
        return store.includes(exchanges, bytes32(_exchange));
    }

    // Returns the paginated array of excnhages, starting from _fromIdx and len _length.
    function getExchanges(uint _fromIdx, uint _length) public view returns (address [] result) {
        result = new address [] (_length);
        for (uint idx = 0; idx < _length; idx++) {
            result[idx] = address(store.get(exchanges, idx + _fromIdx));
        }
    }

    // Returns the count of the registered exchanges.
    function getExchangesCount() public view returns (uint) {
        return store.count(exchanges);
    }

    // Returns the exchanges which belongs to the given _owner
    function getExchangesForOwner(address _owner) public view returns (address []) {
        return store.get(owners, bytes32(_owner));
    }

    // Returns the number of exchanges which belongs to the given _owner
    function getExchangesForOwnerCount(address _owner) public view returns (uint) {
        return store.count(owners, bytes32(_owner));
    }

    // The fee value against which the exchange should calculate fee.
    function getFee() public view returns (uint) {
        return store.get(fee);
    }

    // Util method which returns agregated data for given _exchanges.
    function getExchangeData(address [] _exchanges)
    external
    view
    returns (bytes32 [] symbols,
             uint [] buyPrices,
             uint [] buyDecimals,
             uint [] sellPrices,
             uint [] sellDecimals,
             uint [] assetBalances,
             uint [] ethBalances)
    {
        symbols = new bytes32 [] (_exchanges.length);
        buyPrices = new uint [] (_exchanges.length);
        buyDecimals = new uint [] (_exchanges.length);
        sellPrices = new uint [] (_exchanges.length);
        sellDecimals = new uint [] (_exchanges.length);
        assetBalances = new uint [] (_exchanges.length);
        ethBalances = new uint [] (_exchanges.length);

        for (uint idx = 0; idx < _exchanges.length; idx++) {
            if (isExchangeExists(_exchanges[idx])) {
                Exchange exchange = Exchange(_exchanges[idx]);

                symbols[idx] = getSymbol(address(exchange.asset()));
                (buyPrices[idx], buyDecimals[idx]) = exchange.getBuyPrice();
                (sellPrices[idx], sellDecimals[idx]) = exchange.getSellPrice();
                assetBalances[idx] = exchange.assetBalance();
                ethBalances[idx] = exchange.balance;
            }
        }
    }

    // Returns the Exchange Factory address
    function getExchangeFactory() public view returns (ExchangeFactory) {
        return ExchangeFactory(store.get(exchangeFactory));
    }

    // Retturns ERC20Manager address
    function lookupERC20Manager() internal view returns (ERC20Manager) {
        return ERC20Manager(lookupManager("ERC20Manager"));
    }

    // Returns the symbol of the given token
    function getSymbol(address _token) internal view returns (bytes32) {
        var (,,symbol,,,,) = lookupERC20Manager().getTokenMetaData(_token);
        return symbol;
    }

    /* Events History util methods */
    
    function _emitExchangeRemoved(address _exchange) internal {
        Asset asset = Exchange(_exchange).asset();
        ExchangeManagerEmitter(getEventsHistory())
            .emitExchangeRemoved(_exchange, getSymbol(address(asset)));
    }

    function _emitExchangeAdded(address _user, address _exchange) internal {
        Asset asset = Exchange(_exchange).asset();
        ExchangeManagerEmitter(getEventsHistory())
            .emitExchangeAdded(_user, _exchange, getSymbol(address(asset)));
    }

    function _emitExchangeCreated(
        address _user,
        address _exchange,
        bytes32 _symbol,
        address _rewards,
        uint _fee,
        uint _buyPrice,
        uint _sellPrice)
    internal
    {
        ExchangeManagerEmitter(getEventsHistory())
            .emitExchangeCreated(_user, _exchange, _symbol, _rewards, _fee, _buyPrice, _sellPrice);
    }

    function _emitError(uint error) internal returns (uint) {
        ExchangeManagerEmitter(getEventsHistory()).emitError(error);
        return error;
    }
}
