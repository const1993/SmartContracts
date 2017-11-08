pragma solidity ^0.4.11;

import "../../core/common/Once.sol";
import "./BaseCrowdsale.sol";
import "./PriceTicker.sol";

/**
*  @title GenericCrowdsale
*
*  Funds collected are not forwarded to a wallet as they arrive. Instead,
*  this crowdasale contract is used for storing funds while a crowdsale is in progress.
*
*  Holds information about campaign contributors.
*
*  It features Smart Agent compatibility. The Sale Agent is a new type of contract
*  (or just an address) that can authorise the minting of tokens on behalf
*  of the traditional ERC20 token contract. This allows to distribute ICO tokens
*  through multiple Sale Agents. Once a new Sale Agent contract is written,
*  it can be permitted to sell tokens.
*/
contract GenericCrowdsale is BaseCrowdsale, Once {
    /* Data structure to hold information about campaign contributors
    `what is donated` => (`who donated` => `how much is donated`) */
    mapping (bytes32 => mapping(address => uint)) public donations;
    /* How many crypto of funding we have raised */
    mapping (bytes32 => uint) public raised;
    /* Contract addresses that are authorised to mint tokens */
    mapping (bytes32 => address) public salesAgents;
    /* Contract addresse that provides exchange rates */
    PriceFetcher private priceTicker;

    /* For example, USD, from 10k to 30k, 50000 wei / 1 Token */
    struct Goal {
        bytes32 currencyCode;
        uint minValue;
        uint maxValue;
        uint exchangeRate;
        uint exchangeRateDecimals;
    }

    Goal private goal;
    uint private goalRaised;

    event SaleAgentRegistered(address indexed sender, address saleAgent, bytes32 symbol);
    event SaleAgentDeleted(address indexed sender, address saleAgent, bytes32 symbol);

    event NewSaleDone(address indexed sender, address investor, uint value, bytes32 currencyCode);
    event NewRefund(address indexed sender, address investor, uint value, bytes32 currencyCode);
    event SaleCurrencyNoPriceFound(address indexed sender, address investor, uint value, bytes32 fsym, bytes32 tsym);

    /* Permitted only for sale agent */
    modifier onlySaleAgent(bytes32 currencyId) {
        if (salesAgents[currencyId] != msg.sender) revert();
        _;
    }

    /**
    *  Constructor
    */
    function GenericCrowdsale(address _serviceProvider, bytes32 _symbol, address _priceTicker)
        BaseCrowdsale(_serviceProvider, _symbol)
        public
    {
        require(_priceTicker != 0x0);
        priceTicker = PriceFetcher(_priceTicker);
    }

    /**
    *  Inits crowdsale. Sets a goal.
    *
    *  If the funding goal is not reached, investors may withdraw their funds.
    *  PriceFetcher should support given currency.
    */
    function init(
        bytes32 _currencyCode,
        uint _minValue,
        uint _maxValue,
        uint _exchangeRate,
        uint _exchangeRateDecimals
    ) onlyAuthorised onlyOnce internal {
        require(_currencyCode != 0x0);
        require(_minValue != 0);
        require(_maxValue != 0);
        require(_exchangeRate > 0);

        goal.currencyCode = _currencyCode;
        goal.minValue = _minValue;
        goal.maxValue = _maxValue;
        goal.exchangeRate = _exchangeRate;
        goal.exchangeRateDecimals = _exchangeRateDecimals;
    }

    /**
    *  This function mints the tokens and moves the crowdsale needle.
    *
    *  Amount of minted tokens is calculated according to a price
    *  provided by PriceFetcher, and an exchangeRate given during initialization.
    *
    *  This function is permited only for Sale Agent and can be executed only
    *  when crawdsale is running.
    */
    function sale(address _investor, uint _value, bytes32 _currencyCode) onlySaleAgent(_currencyCode) onlyRunning public {
        require(_investor != 0x0);
        require(_currencyCode != 0x0);

        donations[_currencyCode][_investor] = donations[_currencyCode][_investor].add(_value);
        raised[_currencyCode] = raised[_currencyCode].add(_value);

        if (priceTicker.isPriceAvailable(_currencyCode, goal.currencyCode)) {
            var (price, priceDecimals) = priceTicker.price(_currencyCode, goal.currencyCode);
            mint(_investor, _value, price, priceDecimals);

            NewSaleDone(msg.sender, _investor, _value, _currencyCode);
        } else {
            SaleCurrencyNoPriceFound(msg.sender, _investor, _value, _currencyCode, goal.currencyCode);
        }
    }

    /**
    *  Refunds donated fund.
    */
    function refund(address _investor, bytes32 _currencyCode) onlySaleAgent(_currencyCode) onlyFailure public returns (uint) {
        uint donation = donations[_currencyCode][_investor];
        forceRefund(_investor, _currencyCode, donation);
        return donation;
    }

    /**
    *  Setter for PriceFetcher
    */
    function setPriceTicker(address _priceTicker) onlyAuthorised public {
        require(_priceTicker != 0x0);
        priceTicker = PriceFetcher(_priceTicker);
    }

    /**
    *  Allow SaleAgent to sale tokens.
    */
    function addSalesAgent(address _salesAgent, bytes32 _currencyCode) onlyAuthorised public {
        registerSalesAgent(_salesAgent, _currencyCode);
    }

    /**
    *  Deny SaleAgent to sale tokens.
    */
    function removeSalesAgent(address _salesAgent, bytes32 _currencyCode) onlyAuthorised public {
        unregisterSalesAgent(_salesAgent, _currencyCode);
    }

    /**
    *  Returns priceTicker address.
    */
    function getPriceTicker() public constant returns (address) {
        return address(priceTicker);
    }

    /**
    *  Returns salesAgent by given `_symbol`.
    */
    function getSalesAgent(bytes32 _symbol) public constant returns (address) {
        return salesAgents[_symbol];
    }

    /**
    *  Returns Crowdsale goal.
    */
    function getGoal() public constant returns (bytes32, uint, uint, uint, uint) {
        return (goal.currencyCode, goal.minValue, goal.maxValue, goal.exchangeRate, goal.exchangeRateDecimals);
    }

    /**
    *  See BaseCrowdsale
    */
    function isRunning() public constant returns (bool) {
        return goalRaised < goal.maxValue;
    }

    /**
    *  See BaseCrowdsale
    */
    function isSuccessed() public constant returns (bool) {
        return goalRaised > goal.minValue;
    }

    function registerSalesAgent(address _salesAgent, bytes32 _currencyCode) internal {
        require(_salesAgent != 0x0);
        require(_currencyCode != 0x0);

        salesAgents[_currencyCode] = _salesAgent;

        SaleAgentRegistered(msg.sender, _salesAgent, _currencyCode);
    }

    function unregisterSalesAgent(address _salesAgent, bytes32 _currencyCode) internal {
        require(_salesAgent != 0x0);
        require(_currencyCode != 0);

        delete salesAgents[_currencyCode];

        SaleAgentDeleted(msg.sender, _salesAgent, _currencyCode);
    }

    function mint(address _investor, uint _value, uint _price, uint _priceDecimanl) private {
        uint goalValue = _value.mul(_price) / (10 ** _priceDecimanl);

        goalRaised = goalRaised.add(goalValue);

        uint tokensAmount = goalValue.mul(goal.exchangeRate) / (10 ** goal.exchangeRateDecimals);
        mintTokensTo(_investor, tokensAmount);
    }

    function forceRefund(address _investor, bytes32 _currencyCode, uint _value) private {
        require(_investor != 0x0);
        require(_currencyCode != 0x0);

        uint donation = donations[_currencyCode][_investor];
        require(_value <= donation);

        donations[_currencyCode][_investor] = donations[_currencyCode][_investor].sub(_value);
        raised[_currencyCode] = raised[_currencyCode].sub(_value);

        withdrawTokensFrom(_investor);

        NewRefund(msg.sender, _investor, _value, _currencyCode);
    }
}
