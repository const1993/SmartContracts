pragma solidity ^0.4.11;

import "../core/common/Object.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";

contract ExchangeEmitter {
    function emitError(uint errorCode);
    function emitFeeUpdated(uint feeValue);
    function emitPricesUpdated(uint buyPrice, uint sellPrice);
    function emitActiveChanged(bool isActive);
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

    uint constant ERROR_EXCHANGE_INVALID_PARAMETER = 6000;
    uint constant ERROR_EXCHANGE_INVALID_INVOCATION = 6001;
    uint constant ERROR_EXCHANGE_INVALID_FEE_PERCENT = 6002;
    uint constant ERROR_EXCHANGE_INVALID_PRICE = 6003;
    uint constant ERROR_EXCHANGE_MAINTENANCE_MODE = 6004;
    uint constant ERROR_EXCHANGE_TOO_HIGH_PRICE = 6005;
    uint constant ERROR_EXCHANGE_TOO_LOW_PRICE = 6006;
    uint constant ERROR_EXCHANGE_INSUFFICIENT_BALANCE = 6007;
    uint constant ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY = 6008;
    uint constant ERROR_EXCHANGE_PAYMENT_FAILED = 6009;
    uint constant ERROR_EXCHANGE_TRANSFER_FAILED = 6010;
    uint constant ERROR_EXCHANGE_FEE_TRANSFER_FAILED = 6011;

    // Assigned ERC20 token.
    Asset public asset;
    address rewards;
    address delegate;
    //Switch for turn on and off the exchange operations
    bool public isActive;
    // Price in wei at which exchange buys tokens.
    uint public buyPrice = 1;
    // Price in wei at which exchange sells tokens.
    uint public sellPrice = 2;
    uint public minAmount;
    uint public maxAmount;
    // Fee value for operations 10000 is 0.01.
    uint public feePercent = 10000;
    // User sold tokens and received wei.
    event Sell(address indexed who, uint token, uint eth);
    // User bought tokens and payed wei.
    event Buy(address indexed who, uint token, uint eth);
    event WithdrawTokens(address indexed recipient, uint amount);
    event WithdrawEth(address indexed recipient, uint amount);
    event FeeUpdated(address indexed self, uint feeValue);
    event PricesUpdated(address indexed self, uint buyPrice, uint sellPrice);
    event ActiveChanged(address indexed self, bool isActive);
    event Error(uint errorCode);

    /**
     * @dev On received ethers
     * @param sender Ether sender
     * @param amount Ether value
     */
    event ReceivedEther(address indexed sender, uint256 indexed amount);

    // Should use interface of the emitter, but address of events history.
    ExchangeEmitter public eventsHistory;

    /**
     * Emits Error event with specified error message.
     *
     * Should only be used if no state changes happened.
     *
     * @param error error from Errors library.
     */
    function _error(uint error) internal returns (uint) {
        getEventsHistory().emitError(error);
        return error;
    }

    function _emitFeeUpdated(uint _feePercent) internal {
        getEventsHistory().emitFeeUpdated(_feePercent);
    }

    function _emitPricesUpdated(uint _buyPrice, uint _sellPrice) internal {
        getEventsHistory().emitPricesUpdated(_buyPrice, _sellPrice);
    }

    function _emitActiveChanged(bool _isActive) internal {
        getEventsHistory().emitActiveChanged(_isActive);
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
    function setupEventsHistory(address _eventsHistory) onlyContractOwner public returns (uint) {
        if (address(eventsHistory) != 0x0) {
            return _error(ERROR_EXCHANGE_INVALID_INVOCATION);
        }

        eventsHistory = ExchangeEmitter(_eventsHistory);
        return OK;
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
    function init(Asset _asset, address _rewards, address _delegate, uint _fee) onlyContractOwner public returns (uint errorCode) {
        if (address(asset) != 0x0 || rewards != 0x0) {
            return _error(ERROR_EXCHANGE_INVALID_INVOCATION);
        }

        asset = _asset;
        rewards = _rewards;
        delegate = _delegate;
        uint feeResult = setFee(_fee);
        errorCode = feeResult;
        if (feeResult == OK) {
            isActive = true;
        }
    }

    function setFee(uint _feePercent) internal returns (uint) {
        if (feePercent < 1 || feePercent > 10000) {
            return _error(ERROR_EXCHANGE_INVALID_FEE_PERCENT);
        }

        feePercent = _feePercent;
        _emitFeeUpdated(feePercent);
        return OK;
    }

    function setActive(bool _active) onlyContractOwner public returns (uint) {
        if (isActive != _active) {
            _emitActiveChanged(_active);
        }

        isActive = _active;
        return OK;
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
    function setPrices(uint _buyPrice, uint _sellPrice) onlyContractOwner public returns (uint) {
        if (_sellPrice < _buyPrice) {
            return _error(ERROR_EXCHANGE_INVALID_PRICE);
        }

        buyPrice = _buyPrice;
        sellPrice = _sellPrice;
        _emitPricesUpdated(_buyPrice, _sellPrice);

        return OK;
    }

    function ethBalance() public constant returns (uint) {
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
            return _error(ERROR_EXCHANGE_MAINTENANCE_MODE);
        }

        if (_price > buyPrice) {
            return _error(ERROR_EXCHANGE_TOO_HIGH_PRICE);
        }

        if (_balanceOf(msg.sender) < _amount) {
            return _error(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint total = _mul(_amount, _price);
        if (this.balance < total) {
            return _error(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        if (!asset.transferFrom(msg.sender, this, _amount)) {
            return _error(ERROR_EXCHANGE_PAYMENT_FAILED);
        }

        if (!msg.sender.send(total)) {
            revert();
        }

        Sell(msg.sender, _amount, total);

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
            return _error(ERROR_EXCHANGE_MAINTENANCE_MODE);
        }

        if (_price < sellPrice) {
            return _error(ERROR_EXCHANGE_TOO_LOW_PRICE);
        }

        if (_balanceOf(this) < _amount) {
            return _error(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint total = _mul(_amount, _price);
        if (msg.value != total) {
            return _error(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        if (!asset.transfer(msg.sender, _amount)) {
            return _error(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        Buy(msg.sender, _amount, total);

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
            return _error(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint amount = (_amount * 10000) / (10000 + feePercent);
        if (!asset.transfer(_recipient, amount)) {
            return _error(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        WithdrawTokens(_recipient, amount);

        if (!asset.transfer(rewards, _amount - amount)) {
            _error(ERROR_EXCHANGE_FEE_TRANSFER_FAILED);
        }

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
            return _error(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        uint amount = (_amount * 10000) / (10000 + feePercent);

        if (!_recipient.send(amount)) {
            return _error(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        WithdrawEth(_recipient, amount);

        if (!rewards.send(_amount - amount)) {
            return _error(ERROR_EXCHANGE_FEE_TRANSFER_FAILED);
        }

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

    function emitError(uint errorCode) {
        Error(errorCode);
    }

    function emitFeeUpdated(uint _feePercent) public {
        FeeUpdated(msg.sender, _feePercent);
    }

    function emitPricesUpdated(uint _buyPrice, uint _sellPrice) public {
        PricesUpdated(msg.sender, _buyPrice, _sellPrice);
    }

    function emitActiveChanged(bool _isActive) public {
        ActiveChanged(msg.sender, _isActive);
    }

    function getEventsHistory() public constant returns (ExchangeEmitter) {
        return address(eventsHistory) != 0x0 ? eventsHistory : ExchangeEmitter(this);
    }
    /**
     * Overflow-safe multiplication.
     *
     * Throws in case of value overflow.
     *
     * @param _a first operand.
     * @param _b second operand.
     *
     * @return multiplication result.
     */
    function _mul(uint _a, uint _b) internal constant returns (uint) {
        uint result = _a * _b;
        if (_a != 0 && result / _a != _b) {
            revert();
        }
        return result;
    }

    /**
     * Accept all ether to maintain exchange supply.
     */
    function() payable public {
        if (msg.value != 0) {
            ReceivedEther(msg.sender, msg.value);
        } else {
            revert();
        }
    }
}
