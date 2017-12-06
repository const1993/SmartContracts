pragma solidity ^0.4.11;

import "../core/common/Object.sol";
import "../core/lib/SafeMath.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";
import "../core/contracts/ContractsManager.sol";

contract ExchangeEmitter {
    function emitError(uint errorCode) public returns (uint);
    function emitFeeUpdated(address rewards, uint feePercent, address by) public;
    function emitPricesUpdated(uint buyPrice, uint buyDecimals, uint sellPrice, uint sellDecimals, address by) public;
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

// @title ERC20-Ether exchange contract.
//
// @notice Users are able to buy/sell assigned ERC20 token for ether,
// as long as there is available supply. Contract owner maintains
// sufficient token and ether supply, and sets buy/sell prices.
//
// In order to be able to sell tokens, user needs to create allowance
// for this contract, using standard ERC20 approve() function,
// so that exchange can take tokens from the user, when user
// orders a sell.
//
// Note: all the non constant functions return false instead of
// throwing in case if state change didn't happen yet.
contract Exchange is Object {
    using SafeMath for uint;
    uint constant ERROR_EXCHANGE_INVALID_INVOCATION = 6000;
    uint constant ERROR_EXCHANGE_MAINTENANCE_MODE = 6001;
    uint constant ERROR_EXCHANGE_INVALID_PRICE = 6002;
    uint constant ERROR_EXCHANGE_INSUFFICIENT_BALANCE = 6004;
    uint constant ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY = 6005;
    uint constant ERROR_EXCHANGE_PAYMENT_FAILED = 6006;
    uint constant ERROR_EXCHANGE_TRANSFER_FAILED = 6007;

    // Price structure. Price representation: 1.1 == 11* 10^1 == Price(10, 1)
    struct Price {
        uint base;
        uint decimals;
    }
    // Assigned ERC20 token.
    Asset public asset;
    //Switch for turn on and off the exchange operations
    bool public isActive;
    // Price in wei at which exchange buys tokens.
    Price buyPrice;
    // Price in wei at which exchange sells tokens.
    Price sellPrice;
    // Fee wallet
    address public rewards;
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
    // On tokens withdraw
    event ExchangeWithdrawTokens(address indexed exchange, address indexed recipient, uint amount, address indexed by);
    // On eth withdraw
    event ExchangeWithdrawEther(address indexed exchange, address indexed recipient, uint amount, address indexed by);
    // On Fee updated
    event ExchangeFeeUpdated(address indexed exchange, address rewards, uint feeValue, address indexed by);
    // On prices updated
    event ExchangePricesUpdated(address indexed exchange, uint buyPrice, uint buyDecimals, uint sellPrice, uint sellDecimals, address indexed by);
    // On state changed
    event ExchangeActiveChanged(address indexed exchange, bool isActive, address indexed by);
    // On error
    event Error(address indexed exchange, uint errorCode);

    // Should use interface of the emitter, but address of events history.
    ExchangeEmitter eventsHistory;
    // service registry
    address contractsManager;

    // @notice only authorized account are permitted to call
    modifier onlyAuthorized() {
        if (msg.sender == contractOwner || authorized[msg.sender]) {
            _;
        }
    }

    // @notice Assigns ERC20 token for exchange.
    //
    // Can be set only once, and only by contract owner.
    //
    // @param _asset ERC20 token address.
    //
    // @return OK if success.
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

        if (OK != setFee(_rewards, _fee)) {
            revert();
        }

        return OK;
    }

    // @notice Sets EventsHstory contract address.
    // Can be set only once, and only by contract owner.
    //
    // @param _eventsHistory MultiEventsHistory contract address.
    //
    // @return OK if success.
    function setupEventsHistory(address _eventsHistory)
    public
    onlyContractOwner
    returns (uint)
    {
        require(_eventsHistory != 0x0);
        eventsHistory = ExchangeEmitter(_eventsHistory);
        return OK;
    }

    // @notice Authorizes given address to execute restricted methods.
    // @dev Can be called only by contract owner.
    //
    // @return OK if success.
    function grantAuthorized(address _authorized)
    public
    onlyContractOwner
    returns (uint) {
        authorized[_authorized] = true;
        return OK;
    }

    // @notice Revokes granted access rights.
    // @dev Can be called only by contract owner.
    //
    // @return OK if success.
    function revokeAuthorized(address _authorized)
    public
    onlyContractOwner
    returns (uint) {
        delete authorized[_authorized];
        return OK;
    }

    // @notice Tells whether given address is authorized or not
    //
    // @return `true` if given address is authorized to make secured changes.
    function isAuthorized(address _authorized) public constant returns (bool) {
        return authorized[_authorized];
    }

    // @notice Set exchange operation prices.
    // Sell price cannot be less than buy price.
    //
    // Can be set only by contract owner.
    //
    // @param _buyPrice price in wei at which exchange buys tokens.
    // @param _sellPrice price in wei at which exchange sells tokens.
    //
    // @return OK if success.
    function setPrices(uint _buyPrice, uint _buyDecimals, uint _sellPrice, uint _sellDecimals)
    public
    onlyAuthorized
    returns (uint)
    {
        // buy price <= sell price
        uint max_dec = 10**max(_buyDecimals, _sellDecimals);
        require(_buyPrice * max_dec / 10**_buyDecimals <= _sellPrice * max_dec / 10**_sellDecimals);

        buyPrice = Price(_buyPrice, _buyDecimals);
        sellPrice = Price(_sellPrice, _sellDecimals);

        _emitPricesUpdated(_buyPrice, _buyDecimals, _sellPrice, _sellDecimals, msg.sender);
        return OK;
    }

    // @notice Exchange must be activated before using.
    //
    // Note: An exchange is not activated `by default` after init().
    // Make sure that prices are valid before activation.
    //
    // @return OK if success.
    function setActive(bool _active)
    public
    onlyContractOwner
    returns (uint)
    {
        isActive = _active;

        _emitActiveChanged(_active, msg.sender);
        return OK;
    }

    // @notice Returns ERC20 balance of an exchange
    // @return balance.
    function assetBalance() public constant returns (uint) {
        return _balanceOf(this);
    }

    // @notice Returns assigned token address balance.
    //
    // @param _address address to get balance.
    //
    // @return token balance.
    function _balanceOf(address _address) constant internal returns (uint) {
        return asset.balanceOf(_address);
    }

    // @notice Returns sell price
    function getSellPrice() public view returns (uint base, uint decimals) {
        return (sellPrice.base, sellPrice.decimals);
    }

    // @notice Returns buy price
    function getBuyPrice() public view returns (uint base, uint decimals) {
        return (buyPrice.base, buyPrice.decimals);
    }

    // @notice Sell tokens for ether at specified price. Tokens are taken from caller
    // though an allowance logic.
    // Amount should be less than or equal to current allowance value.
    // Price should be less than or equal to current exchange buyPrice.
    //
    // @param _amount amount of tokens to sell.
    // @param _price price in wei at which sell will happen.
    //
    // @return OK if success.
    function sell(uint _amount, uint _price, uint _priceDecimals) public returns (uint) {
        if (!isActive) {
            return _emitError(ERROR_EXCHANGE_MAINTENANCE_MODE);
        }

        if (_price != buyPrice.base || _priceDecimals != buyPrice.decimals) {
            return _emitError(ERROR_EXCHANGE_INVALID_PRICE);
        }

        if (_balanceOf(msg.sender) < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint total = _amount.mul(buyPrice.base) / 10**buyPrice.decimals;
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

    // @notice Buy tokens for ether at specified price. Payment needs to be sent along
    // with the call, and should equal amount * price.
    // Price should be greater than or equal to current exchange sellPrice.
    //
    // @param _amount amount of tokens to buy.
    // @param _price price in wei at which buy will happen.
    //
    // @return OK if success.
    function buy(uint _amount, uint _price, uint _priceDecimals) payable public returns (uint) {
        if (!isActive) {
            return _emitError(ERROR_EXCHANGE_MAINTENANCE_MODE);
        }

        if (_price != sellPrice.base || _priceDecimals != sellPrice.decimals) {
            return _emitError(ERROR_EXCHANGE_INVALID_PRICE);
        }

        if (_balanceOf(this) < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint total = _amount.mul(sellPrice.base) / 10**sellPrice.decimals;
        if (msg.value != total) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        if (!asset.transfer(msg.sender, _amount)) {
            revert();
        }

        _emitBuy(msg.sender, _amount, total);
        return OK;
    }

    // @notice Transfer specified amount of tokens from exchange to specified address.
    //
    // Can be called only by contract owner.
    //
    // @param _recipient address to transfer tokens to.
    // @param _amount amount of tokens to transfer.
    //
    // @return OK if success.
    function withdrawTokens(address _recipient, uint _amount) public onlyContractOwner returns (uint) {
        if (_balanceOf(this) < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_BALANCE);
        }

        uint amount = (_amount * 10000) / (10000 + feePercent);
        if (!asset.transfer(_recipient, amount)) {
            return _emitError(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        if (feePercent > 0 && !asset.transfer(rewards, _amount.sub(amount))) {
            revert();
        }

        _emitWithdrawTokens(_recipient, amount, msg.sender);
        return OK;
    }

    // @notice Transfer all tokens from exchange to specified address.
    //
    // Can be called only by contract owner.
    //
    // @param _recipient address to transfer tokens to.
    //
    // @return OK if success.
    function withdrawAllTokens(address _recipient) public onlyContractOwner returns (uint) {
        return withdrawTokens(_recipient, _balanceOf(this));
    }

    // @notice Transfer specified amount of wei from exchange to specified address.
    //
    // Can be called only by contract owner.
    //
    // @param _recipient address to transfer wei to.
    // @param _amount amount of wei to transfer.
    //
    // @return OK if success.
    function withdrawEth(address _recipient, uint _amount) public onlyContractOwner returns (uint) {
        if (this.balance < _amount) {
            return _emitError(ERROR_EXCHANGE_INSUFFICIENT_ETHER_SUPPLY);
        }

        uint amount = (_amount * 10000) / (10000 + feePercent);

        if (!_recipient.send(amount)) {
            return _emitError(ERROR_EXCHANGE_TRANSFER_FAILED);
        }

        if (feePercent > 0 && !rewards.send(_amount.sub(amount))) {
            revert();
        }

        _emitWithdrawEther(_recipient, amount, msg.sender);
        return OK;
    }

    // @notice Transfer all wei from exchange to specified address.
    //
    // Can be called only by contract owner.
    //
    // @param _recipient address to transfer wei to.
    //
    // @return OK if success.
    function withdrawAllEth(address _recipient) public onlyContractOwner returns (uint) {
        return withdrawEth(_recipient, this.balance);
    }

    // @notice Transfer all tokens and wei from exchange to specified address.
    //
    // Can be called only by contract owner.
    //
    // @param _recipient address to transfer tokens and wei to.
    //
    // @return OK if success.
    function withdrawAll(address _recipient) public onlyContractOwner returns (uint result) {
        result = withdrawAllTokens(_recipient);
        if (result != OK) {
            return result;
        }

        result = withdrawAllEth(_recipient);
        if (result != OK) {
            return result;
        }

        return OK;
    }

    // @notice Use kill() instead of destroy() to prevent accidental ether/ERC20 loosing
    function destroy() public onlyContractOwner {
        revert();
    }

    // @notice Kills an exchnage contract.
    //
    // Checks balances of an exchange before destroying.
    // Destroys an exchange only if balances are empty.
    //
    // @return OK if success.
    function kill() public onlyContractOwner returns (uint errorCode) {
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

    /* Events helpers */

    function _emitError(uint _errorCode) internal returns (uint) {
        eventsHistory.emitError(_errorCode);
        return _errorCode;
    }

    function _emitFeeUpdated(address _rewards, uint _feePercent, address _by) internal {
        eventsHistory.emitFeeUpdated(_rewards, _feePercent, _by);
    }

    function _emitPricesUpdated(uint _buyPrice, uint _buyDecimals, uint _sellPrice, uint _sellDecimals, address _by) internal {
        eventsHistory.emitPricesUpdated(_buyPrice, _buyDecimals, _sellPrice, _sellDecimals, _by);
    }

    function _emitActiveChanged(bool _isActive, address _by) internal {
        eventsHistory.emitActiveChanged(_isActive, _by);
    }

    function _emitBuy(address _who, uint _token, uint _eth) internal {
        eventsHistory.emitBuy(_who, _token, _eth);
    }

    function _emitSell(address _who, uint _token, uint _eth) internal {
        eventsHistory.emitSell(_who, _token, _eth);
    }

    function _emitWithdrawEther(address _recipient, uint _amount, address _by) internal {
        eventsHistory.emitWithdrawEther(_recipient, _amount, _by);
    }

    function _emitWithdrawTokens(address _recipient, uint _amount, address _by) internal {
        eventsHistory.emitWithdrawTokens(_recipient, _amount, _by);
    }

    function _emitReceivedEther(address _sender, uint _amount) internal {
        eventsHistory.emitReceivedEther(_sender, _amount);
    }

    /* emit* methods are designed to be called only via EventsHistory */

    function emitError(uint _errorCode) public returns (uint) {
        Error(msg.sender, _errorCode);
        return _errorCode;
    }

    function emitFeeUpdated(address _rewards, uint _feePercent, address _by) public {
        ExchangeFeeUpdated(msg.sender, _rewards, _feePercent, _by);
    }

    function emitPricesUpdated(uint _buyPrice, uint _buyDecimals, uint _sellPrice, uint _sellDecimals, address _by) public {
        ExchangePricesUpdated(msg.sender, _buyPrice, _buyDecimals, _sellPrice, _sellDecimals, _by);
    }

    function emitActiveChanged(bool _isActive, address _by) public {
        ExchangeActiveChanged(msg.sender, _isActive, _by);
    }

    function emitBuy(address _who, uint _token, uint _eth) public {
        ExchangeBuy(msg.sender, _who, _token, _eth);
    }

    function emitSell(address _who, uint _token, uint _eth) public {
        ExchangeSell(msg.sender, _who, _token, _eth);
    }

    function emitWithdrawEther(address _recipient, uint _amount, address _by) public {
        ExchangeWithdrawEther(msg.sender, _recipient, _amount, _by);
    }

    function emitWithdrawTokens(address _recipient, uint _amount, address _by) public {
        ExchangeWithdrawTokens(msg.sender, _recipient, _amount, _by);
    }

    function emitReceivedEther(address _sender, uint _amount) public {
        ExchangeReceivedEther(msg.sender, _sender, _amount);
    }

    // @notice Accept all ether to maintain exchange supply.
    function() payable public {
        if (msg.value != 0) {
            _emitReceivedEther(msg.sender, msg.value);
        } else {
            revert();
        }
    }

    function max(uint a, uint b) private pure returns (uint256) {
        return a >= b ? a : b;
    }
}
