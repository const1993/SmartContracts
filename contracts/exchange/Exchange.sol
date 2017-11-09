pragma solidity ^0.4.11;

import "../core/common/Object.sol";
import "../core/lib/SafeMath.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";
import "../core/contracts/ContractsManager.sol";

contract ExchangeEmitter {
    function emitError(uint errorCode) public returns (uint);
    function emitFeeUpdated(address rewards, uint feePercent, address by) public;
    function emitPricesUpdated(uint buyPrice, uint sellPrice, address by) public;
    function emitActiveChanged(bool isActive, address by) public;
    function emitBuy(address who, uint token, uint eth) public;
    function emitSell(address who, uint token, uint eth) public;
    function emitWithdrawEther(address recipient, uint amount, address by) public;
    function emitWithdrawTokens(address recipient, uint amount, address by) public;
    function emitReceivedEther(address sender, uint amount) public;
}

contract IExchangeManager {
    function removeExchange() public returns (uint errorCode);
}

/**
 * @title ERC20-Ether exchange contract.
 *
 * Users are able to buy/sell assigned ERC20 token for ether, as long as there is available
 * supply. Contract owner maintains sufficient token and ether supply, and sets buy/sell prices.
 *
 * In order to be able to sell tokens, user needs to create allowance for this contract, using
 * standard ERC20 approve() function, so that exchange can take tokens from the user, when user
 * orders a sell.
 *
 * Note: all the non constant functions return false instead of throwing in case if state change
 * didn't happen yet.
 */
contract Exchange is Object {
    using SafeMath for uint;
    uint constant ERROR_EXCHANGE_INVALID_INVOCATION = 6001;
    uint constant ERROR_EXCHANGE_MAINTENANCE_MODE = 6001;
    uint constant ERROR_EXCHANGE_TOO_HIGH_PRICE = 6002;
    uint constant ERROR_EXCHANGE_TOO_LOW_PRICE = 6003;
    uint constant ERROR_EXCHANGE_INSUFFICIENT_BALANCE = 6004;
    uint constant ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY = 6005;
    uint constant ERROR_EXCHANGE_PAYMENT_FAILED = 6006;
    uint constant ERROR_EXCHANGE_TRANSFER_FAILED = 6007;

    // Assigned ERC20 token.
    Asset public asset;
    address public rewards;
    //Switch for turn on and off the exchange operations
    bool public isActive;
    // Price in wei at which exchange buys tokens.
    uint public buyPrice;
    // Price in wei at which exchange sells tokens.
    uint public sellPrice;
    // Fee value for operations 10000 is 0.01.
    uint public feePercent;
    // Authorized price managers
    mapping (address => bool) authorized;

    // User sold tokens and received wei.
    event ExchangeSell(address indexed exchange, address indexed who, uint token, uint eth);
    // User bought tokens and payed wei.
    event ExchangeBuy(address indexed exchange, address indexed who, uint token, uint eth);
    // On received ethers
    event ExchangeReceivedEther(address indexed exchange, address indexed sender, uint256 indexed amount);

    event ExchangeWithdrawTokens(address indexed exchange, address indexed recipient, uint amount, address indexed by);
    event ExchangeWithdrawEther(address indexed exchange, address indexed recipient, uint amount, address indexed by);
    event ExchangeFeeUpdated(address indexed exchange, address rewards, uint feeValue, address indexed by);
    event ExchangePricesUpdated(address indexed exchange, uint buyPrice, uint sellPrice, address indexed by);
    event ExchangeActiveChanged(address indexed exchange, bool isActive, address indexed by);
    event Error(address indexed exchange, uint errorCode);

    // Should use interface of the emitter, but address of events history.
    ExchangeEmitter public eventsHistory;
    address contractsManager;

    modifier onlyAuthorized() {
        if (msg.sender == contractOwner || authorized[msg.sender]) {
            _;
        }
    }
    /**
     * Assigns ERC20 token for exchange.
     *
     * Can be set only once, and only by contract owner.
     *
     * @param _asset ERC20 token address.
     *
     * @return success.
     */
    function init(
        address _contractsManager,
        address _asset,
        address _rewards,
        uint _fee)
    public
    onlyContractOwner
    returns (uint errorCode)
    {
        require(_contractsManager != 0x0);
        require(_asset != 0x0);
        require(address(asset) == 0x0);

        asset = Asset(_asset);

        contractsManager = _contractsManager;

        errorCode = setFee(_rewards, _fee);
        if (errorCode != OK) {
            return errorCode;
        }

        return OK;
    }

    /**
     * Sets EventsHstory contract address.
     *
     * Can be set only once, and only by contract owner.
     *
     * @param _eventsHistory MultiEventsHistory contract address.
     *
     * @return success.
     */
    function setupEventsHistory(address _eventsHistory)
    public
    onlyContractOwner
    returns (uint)
    {
        eventsHistory = ExchangeEmitter(_eventsHistory);
        return OK;
    }

    function grantAuthorized(address _authorized)
    public
    onlyContractOwner
    returns (uint) {
        authorized[_authorized] = true;
        return OK;
    }

    function revokeAuthorized(address _authorized)
    public
    onlyContractOwner
    returns (uint) {
        delete authorized[_authorized];
        return OK;
    }

    function isAuthorized(address _authorized) public constant returns (bool) {
        return authorized[_authorized];
    }
    /**
     * Set exchange operation prices.
     * Sell price cannot be less than buy price.
     *
     * Can be set only by contract owner.
     *
     * @param _buyPrice price in wei at which exchange buys tokens.
     * @param _sellPrice price in wei at which exchange sells tokens.
     *
     * @return success.
     */
    function setPrices(uint _buyPrice, uint _sellPrice)
    public
    onlyAuthorized
    returns (uint)
    {
        require(_buyPrice > _sellPrice);

        buyPrice = _buyPrice;
        sellPrice = _sellPrice;

        _emitPricesUpdated(_buyPrice, _sellPrice, msg.sender);
        return OK;
    }

    function setActive(bool _active)
    public
    onlyContractOwner
    returns (uint)
    {
        isActive = _active;

        _emitActiveChanged(_active, msg.sender);
        return OK;
    }

    function etherBalance() public constant returns (uint) {
        return this.balance;
    }

    function assetBalance() public constant returns (uint) {
        return _balanceOf(this);
    }

    /**
     * Returns assigned token address balance.
     *
     * @param _address address to get balance.
     *
     * @return token balance.
     */
    function _balanceOf(address _address) constant internal returns (uint) {
        return asset.balanceOf(_address);
    }

    /**
     * Sell tokens for ether at specified price. Tokens are taken from caller
     * though an allowance logic.
     * Amount should be less than or equal to current allowance value.
     * Price should be less than or equal to current exchange buyPrice.
     *
     * @param _amount amount of tokens to sell.
     * @param _price price in wei at which sell will happen.
     *
     * @return success.
     */
    function sell(uint _amount, uint _price) public returns (uint) {
        if (!isActive) {
            return _emitError(ERROR_EXCHANGE_MAINTENANCE_MODE);
        }

        if (_price > buyPrice) {
            return _emitError(ERROR_EXCHANGE_TOO_HIGH_PRICE);
        }

        if (_balanceOf(msg.sender) < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint total = _amount.mul(_price);
        if (this.balance < total) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        if (!asset.transferFrom(msg.sender, this, _amount)) {
            return _emitError(ERROR_EXCHANGE_PAYMENT_FAILED);
        }

        if (!msg.sender.send(total)) {
            revert();
        }

        _emitSell(msg.sender, _amount, total);
        return OK;
    }

    /**
     * Buy tokens for ether at specified price. Payment needs to be sent along
     * with the call, and should equal amount * price.
     * Price should be greater than or equal to current exchange sellPrice.
     *
     * @param _amount amount of tokens to buy.
     * @param _price price in wei at which buy will happen.
     *
     * @return success.
     */
    function buy(uint _amount, uint _price) payable public returns (uint) {
        if (!isActive) {
            return _emitError(ERROR_EXCHANGE_MAINTENANCE_MODE);
        }

        if (_price < sellPrice) {
            return _emitError(ERROR_EXCHANGE_TOO_LOW_PRICE);
        }

        if (_balanceOf(this) < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint total = _amount.mul(_price);
        if (msg.value != total) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        if (!asset.transfer(msg.sender, _amount)) {
            revert();
        }

        _emitBuy(msg.sender, _amount, total);
        return OK;
    }

    /**
     * Transfer specified amount of tokens from exchange to specified address.
     *
     * Can be called only by contract owner.
     *
     * @param _recipient address to transfer tokens to.
     * @param _amount amount of tokens to transfer.
     *
     * @return success.
     */
    function withdrawTokens(address _recipient, uint _amount) onlyContractOwner public returns (uint) {
        if (_balanceOf(this) < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint amount = (_amount * 10000) / (10000 + feePercent);
        if (!asset.transfer(_recipient, amount)) {
            return _emitError(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        if (!asset.transfer(rewards, _amount.sub(amount))) {
            revert();
        }

        _emitWithdrawTokens(_recipient, amount, msg.sender);
        return OK;
    }

    /**
     * Transfer all tokens from exchange to specified address.
     *
     * Can be called only by contract owner.
     *
     * @param _recipient address to transfer tokens to.
     *
     * @return success.
     */
    function withdrawAllTokens(address _recipient) onlyContractOwner public returns (uint) {
        return withdrawTokens(_recipient, _balanceOf(this));
    }

    /**
     * Transfer specified amount of wei from exchange to specified address.
     *
     * Can be called only by contract owner.
     *
     * @param _recipient address to transfer wei to.
     * @param _amount amount of wei to transfer.
     *
     * @return success.
     */
    function withdrawEth(address _recipient, uint _amount) onlyContractOwner public returns (uint) {
        if (this.balance < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        uint amount = (_amount * 10000) / (10000 + feePercent);

        if (!_recipient.send(amount)) {
            return _emitError(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        if (!rewards.send(_amount.sub(amount))) {
            revert();
        }

        _emitWithdrawEther(_recipient, amount, msg.sender);
        return OK;
    }

    /**
     * Transfer all wei from exchange to specified address.
     *
     * Can be called only by contract owner.
     *
     * @param _recipient address to transfer wei to.
     *
     * @return success.
     */
    function withdrawAllEth(address _recipient) onlyContractOwner public returns (uint) {
        return withdrawEth(_recipient, this.balance);
    }

    /**
     * Transfer all tokens and wei from exchange to specified address.
     *
     * Can be called only by contract owner.
     *
     * @param _recipient address to transfer tokens and wei to.
     *
     * @return success.
     */
    function withdrawAll(address _recipient) onlyContractOwner public returns (uint) {
        uint withdrawAllTokensResult = withdrawAllTokens(_recipient);
        if (withdrawAllTokensResult != OK) {
            return withdrawAllTokensResult;
        }

        uint withdrawAllEthResult = withdrawAllEth(_recipient);
        if (withdrawAllEthResult != OK) {
            return withdrawAllEthResult;
        }

        return OK;
    }

    function destroy() onlyContractOwner {
        //revert();
    }

    function kill() onlyContractOwner returns (uint errorCode) {
        if (this.balance > 0) {
            return _emitError(ERROR_EXCHANGE_INVALID_INVOCATION);
        }

        if (asset.balanceOf(this) > 0) {
            return _emitError(ERROR_EXCHANGE_INVALID_INVOCATION);
        }

        address exchangeManager = ContractsManager(contractsManager).getContractAddressByType("ExchangeManager");
        errorCode = IExchangeManager(exchangeManager).removeExchange();
        if (errorCode != OK) {
            return _emitError(errorCode);
        }

        Owned.destroy();
    }

    function setFee(address _rewards, uint _feePercent)
    internal
    returns (uint)
    {
        require(_rewards != 0x0);
        require(/*_feePercent > 1 && */ _feePercent < 10000);

        rewards = _rewards;
        feePercent = _feePercent;

        _emitFeeUpdated(_rewards, _feePercent, msg.sender);
        return OK;
    }

    function _emitError(uint errorCode) public returns (uint) {
        eventsHistory.emitError(errorCode);
        return errorCode;
    }

    function _emitFeeUpdated(address rewards, uint feePercent, address by) public {
        eventsHistory.emitFeeUpdated(rewards, feePercent, by);
    }

    function _emitPricesUpdated(uint buyPrice, uint sellPrice, address by) public {
        eventsHistory.emitPricesUpdated(buyPrice, sellPrice, by);
    }

    function _emitActiveChanged(bool isActive, address by) public {
        eventsHistory.emitActiveChanged(isActive, by);
    }

    function _emitBuy(address who, uint token, uint eth) public {
        eventsHistory.emitBuy(who, token, eth);
    }

    function _emitSell(address who, uint token, uint eth) public {
        eventsHistory.emitSell(who, token, eth);
    }

    function _emitWithdrawEther(address recipient, uint amount, address by) public {
        eventsHistory.emitWithdrawEther(recipient, amount, by);
    }

    function _emitWithdrawTokens(address recipient, uint amount, address by) public {
        eventsHistory.emitWithdrawTokens(recipient, amount, by);
    }

    function _emitReceivedEther(address sender, uint amount) public {
        eventsHistory.emitReceivedEther(sender, amount);
    }

    // emit* methods are designed to be called only via EventsHistory

    function emitError(uint errorCode) public returns (uint) {
        Error(msg.sender, errorCode);
        return errorCode;
    }

    function emitFeeUpdated(address rewards, uint feePercent, address by) public {
        ExchangeFeeUpdated(msg.sender, rewards, feePercent, by);
    }

    function emitPricesUpdated(uint buyPrice, uint sellPrice, address by) public {
        ExchangePricesUpdated(msg.sender, buyPrice, sellPrice, by);
    }

    function emitActiveChanged(bool isActive, address by) public {
        ExchangeActiveChanged(msg.sender, isActive, by);
    }

    function emitBuy(address who, uint token, uint eth) public {
        ExchangeBuy(msg.sender, who, token, eth);
    }

    function emitSell(address who, uint token, uint eth) public {
        ExchangeSell(msg.sender, who, token, eth);
    }

    function emitWithdrawEther(address recipient, uint amount, address by) public {
        ExchangeWithdrawEther(msg.sender, recipient, amount, by);
    }

    function emitWithdrawTokens(address recipient, uint amount, address by) public {
        ExchangeWithdrawTokens(msg.sender, recipient, amount, by);
    }

    function emitReceivedEther(address sender, uint amount) public {
        ExchangeReceivedEther(msg.sender, sender, amount);
    }

    /**
     * Accept all ether to maintain exchange supply.
     */
    function() payable public {
        if (msg.value != 0) {
            _emitReceivedEther(msg.sender, msg.value); // TODO
        } else {
            revert();
        }
    }
}
