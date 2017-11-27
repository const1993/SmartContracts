pragma solidity ^0.4.11;

import "./TimeHolderEmitter.sol";
import "../core/common/BaseManager.sol";
import "../core/common/ListenerInterface.sol";
import "../core/common/Deposits.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";
import "./DepositWalletInterface.sol";


/**
* @title Contract allows to block some amount of shares' balance to unlock
* functionality inside a system.
*/
contract TimeHolder is Deposits, TimeHolderEmitter {

    /** Error codes */

    uint constant ERROR_TIMEHOLDER_ALREADY_ADDED = 12000;
    uint constant ERROR_TIMEHOLDER_INVALID_INVOCATION = 12001;
    uint constant ERROR_TIMEHOLDER_INVALID_STATE = 12002;
    uint constant ERROR_TIMEHOLDER_TRANSFER_FAILED = 12003;
    uint constant ERROR_TIMEHOLDER_WITHDRAWN_FAILED = 12004;
    uint constant ERROR_TIMEHOLDER_DEPOSIT_FAILED = 12005;
    uint constant ERROR_TIMEHOLDER_INSUFFICIENT_BALANCE = 12006;
    uint constant ERROR_TIMEHOLDER_LIMIT_EXCEEDED = 12007;
    uint constant ERROR_TIMEHOLDER_SHARES_IS_NOT_ALLOWED = 12008;


    /** Listener interface versions */

    uint constant TIMEHOLDER_LISTENER_VERSION_V1 = 1;
    uint constant TIMEHOLDER_LISTENER_VERSION_V2 = 2;


    /** Storage keys */

    StorageInterface.OrderedAddressesSet listeners_old; // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
    StorageInterface.AddressOrderedSetMapping listeners;
    StorageInterface.Address walletStorage;
    StorageInterface.Address feeWalletStorage;
    StorageInterface.Bytes32UIntMapping limitAmountsStorage;
    StorageInterface.AddressUIntMapping listenersSupportStorage;


    /** @dev Guards invokations only for FeatureManager */
    modifier onlyFeatureFeeManager {
        if (msg.sender == lookupManager("FeatureFeeManager")) {
            _;
        }
    }

    function TimeHolder(Storage _store, bytes32 _crate) Deposits(_store, _crate) public {
        listeners_old.init('listeners'); // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
        listeners.init('listeners_v2');
        feeWalletStorage.init("timeHolderFeeWalletStorage");
        walletStorage.init("timeHolderWalletStorage");
        limitAmountsStorage.init('limitAmountsStorage');
        listenersSupportStorage.init('listenersSupportStorage');
    }

    /**
     * @dev Init TimeHolder contract.
     *
     * @param _contractsManager address.
     * @param _defaultSharesTokenSymbol default ERC20 token symbol to act as shares.
     *
     * @return result code of an operation
     */
    function init(address _contractsManager, bytes32 _defaultSharesTokenSymbol, address _wallet, address _feeWallet) onlyContractOwner public returns (uint) {
        require(_wallet != 0x0);
        require(_feeWallet != 0x0);

        BaseManager.init(_contractsManager, "TimeHolder");

        if (_defaultSharesTokenSymbol != bytes32(0) && lookupERC20Service().getTokenAddressBySymbol(_defaultSharesTokenSymbol) != 0x0) {
            store.set(defaultSharesSymbolStorage, _defaultSharesTokenSymbol);
            store.add(sharesContractsStorage, _defaultSharesTokenSymbol);
            store.set(limitAmountsStorage, _defaultSharesTokenSymbol, 2**255);
        }

        _migrateToVersion2();

        store.set(walletStorage, _wallet);
        store.set(feeWalletStorage, _feeWallet);

        return OK;
    }

    /**
    * @dev Performs migrations to an updated version (v2) of contract.
    * @notice Will be removed after the next release together with _migrateToVersion2
    */
    function _migrateToVersion2() internal {
        super._migrateToVersion2();

        address _listener;
        StorageInterface.Iterator memory iterator = store.listIterator(listeners_old);
        while (store.canGetNextWithIterator(listeners_old, iterator)) {
            store.remove(listeners_old, _listener);
            _listener = store.getNextWithIterator(listeners_old, iterator);
            addListener(_listener);
        }
        store.remove(listeners_old, _listener);
    }

    /**
    * @dev Destroys contract and send all ether to a sender.
    * @notice Can be invoked only by contract owner.
    */
    function destroy() onlyContractOwner public {
        selfdestruct(msg.sender);
    }

    /**
    * @dev Adds ERC20-compatible token symbols and put them in the whitelist to be used then as
    * shares for other contracts and allow users to deposit for this share.
    * @notice Allowed only for CBEs
    *
    * @param _whiteList list of token symbols that will be allowed to be deposited in TimeHolder
    */
    function addERC20Shares(bytes32[] _whiteList) onlyAuthorized public {
        ERC20Service erc20Service = lookupERC20Service();
        for (uint _idx = 0; _idx < _whiteList.length; ++_idx) {
            address _token = erc20Service.getTokenAddressBySymbol(_whiteList[_idx]);
            if (!(_token == 0x0 || store.includes(sharesContractsStorage, _whiteList[_idx]))) {
                store.add(sharesContractsStorage, _whiteList[_idx]);
                store.set(limitAmountsStorage, _whiteList[_idx], 2**255);
                _emitSharesWhiteListAdded(_whiteList[_idx]);
            }
        }
    }

    /**
    * @dev Removes ERC20-compatible token symbols from TimeHolder so they will be removed
    * from the whitelist and will not be accessible to be used as shares. All deposited amounts
    * still will be available to withdraw.
    * @notice Allowed only for CBEs
    *
    * @param _blackList list of token symbols that will be removed from TimeHolder
    */
    function removeERC20Shares(bytes32[] _blackList) onlyAuthorized public {
        ERC20Service erc20Service = lookupERC20Service();
        for (uint _idx = 0; _idx < _blackList.length; ++_idx) {
            address _token = erc20Service.getTokenAddressBySymbol(_blackList[_idx]);
            if (_token != 0x0) {
                store.remove(sharesContractsStorage, _blackList[_idx]);
                _emitSharesWhiteListRemoved(_blackList[_idx]);
            }
        }
    }

    /**
    * @dev DEPRECATED. Adds a listener to observe default share changes.
    * Should not be used by newly created contracts, left only for backward compatibility.
    * Use `addHolderListener` function to specify exact token symbol you are interested in.
    * @notice Allowed only for CBEs
    *
    * @param _listener address of a listener to add
    */
    function addListener(address _listener) onlyAuthorized public returns (uint) {
        ListenerInterface(_listener).deposit(this, 0, 0);
        ListenerInterface(_listener).withdrawn(this, 0, 0);

        return _addListener(store.get(defaultSharesSymbolStorage), _listener, TIMEHOLDER_LISTENER_VERSION_V1);
    }

    /**
    * @dev DEPRECATED. Removes a listener from watching default share changes.
    * Should not be used by newly created contracts, left only for backward compatibility.
    * Use `removeHolderListener` function to specify exact token symbol you are interested in.
    *
    * @param _listener address of a listener to remove
    */
    function removeListener(address _listener) onlyAuthorized public {
        removeHolderListener(store.get(defaultSharesSymbolStorage), _listener);
    }

    /**
    * @dev Adds provided listener to observe changes of passed symbol when some amount will be deposited/withdrawn.
    * Checks passed listener for HolderListenerInterface compatibility.
    * @notice Allowed only for CBEs
    *
    * @param _smbl token symbol to watch deposits and withdrawals
    * @param _listener address of a listener to add
    */
    function addHolderListener(bytes32 _smbl, address _listener) onlyAuthorized public returns (uint) {
        HolderListenerInterface(_listener).depositHolder(_smbl, this, 0, 0);
        HolderListenerInterface(_listener).withdrawnHolder(_smbl, this, 0, 0);

        return _addListener(_smbl, _listener, TIMEHOLDER_LISTENER_VERSION_V2);
    }

    /**
    * @dev Removes provided listener from observing changes of passed symbol.
    * @notice Allowed only for CBEs
    *
    * @param _smbl token symbol to stop watching by a listener
    * @param _listener address of a listener to remove
    */
    function removeHolderListener(bytes32 _smbl, address _listener) onlyAuthorized public {
        require(_smbl != bytes32(0));

        if (store.includes(listeners, _smbl, _listener)) {
            store.remove(listeners, _smbl, _listener);
            store.set(listenersSupportStorage, _listener, 0);
            _emitListenerRemoved(_listener, _smbl);
        }
    }

    /**
    * @dev PRIVATE. Basic implementation of adding a listener for the timeHolder. Provides a way
    * to specify a version of listener to separate different interface compatibility.
    */
    function _addListener(bytes32 _smbl, address _listener, uint _listenerVersion) private returns (uint) {
        require(_smbl != bytes32(0));
        require(store.includes(sharesContractsStorage, _smbl));

        if (store.includes(listeners, _smbl, _listener)) {
            return _emitError(ERROR_TIMEHOLDER_ALREADY_ADDED);
        }

        store.add(listeners, _smbl, _listener);
        store.set(listenersSupportStorage, _listener, _listenerVersion);

        _emitListenerAdded(_listener, _smbl);
    }

    /**
    * @dev Sets fee wallet address.
    */
    function setFeeWallet(address _feeWallet) onlyContractOwner public {
        require(_feeWallet != 0x0);
        store.set(feeWalletStorage, _feeWallet);
    }

    /**
    * @dev Gets an associated wallet for the time holder
    */
    function wallet() public constant returns (address) {
        return store.get(walletStorage);
    }

    /**
    * @dev Gets an associated fee wallet for the time holder
    */
    function feeWallet() public constant returns (address) {
        return store.get(feeWalletStorage);
    }

    /**
    * @dev Total amount of shares of default token
    *
    * @return total amount of shares
    */
    function totalShares() public constant returns (uint) {
        return totalShares(store.get(defaultSharesSymbolStorage));
    }

    /**
    * @dev Total amount of shares for provided symbol
    *
    * @param _smbl token symbol to check total shares amout
    *
    * @return total amount of shares
    */
    function totalShares(bytes32 _smbl) public constant returns (uint) {
        require(_smbl != bytes32(0));

        return store.get(totalSharesStorage, _smbl);
    }

    /**
    * @dev Contract address of default shares
    *
    * @return address of shares contract
    */
    function sharesContract() public constant returns (address) {
        return sharesContract(store.get(defaultSharesSymbolStorage));
    }

    /**
    * @dev Contract address of provided symbol
    */
    function sharesContract(bytes32 _smbl) internal constant returns (address) {
        return ERC20Service(lookupERC20Service()).getTokenAddressBySymbol(_smbl);
    }

    /**
    * @dev Number of shareholders
    *
    * @return number of shareholders
    */
    function shareholdersCount() public constant returns (uint) {
        return store.count(shareholders);
    }

    /**
    * @dev Returns deposit/withdraw limit for default shares
    *
    * @return limit
    */
    function getLimit() public constant returns (uint) {
        return getLimitForTokenSymbol(store.get(defaultSharesSymbolStorage));
    }

    /**
    * @dev Returns deposit/withdraw limit for shares with provided symbol
    *
    * @param _smbl token symbol to get limit
    *
    * @return limit number for specified shares
    */
    function getLimitForTokenSymbol(bytes32 _smbl) public constant returns (uint) {
        require(_smbl != bytes32(0));

        return store.get(limitAmountsStorage, _smbl);
    }

    /**
    * @dev Setter deposit/withdraw limit
    *
    * @param _limitAmount limit
    */
    function setLimit(uint _limitAmount) onlyContractOwner public {
        setLimitForTokenSymbol(store.get(defaultSharesSymbolStorage), _limitAmount);
    }

    /**
    * @dev Setter deposit/withdraw limit
    *
    * @param _smbl token symbol
    * @param _limitAmount limit
    */
    function setLimitForTokenSymbol(bytes32 _smbl, uint _limitAmount) onlyContractOwner public {
        require(_smbl != bytes32(0));

        store.set(limitAmountsStorage, _smbl, _limitAmount);
    }

    /**
     * @dev Deposit shares and prove possession.
     * Amount should be less than or equal to current allowance value.
     *
     * Proof should be repeated for each active period. To prove possesion without
     * depositing more shares, specify 0 amount.
     *
     * @param _amount amount of shares to deposit, or 0 to just prove.
     *
     * @return result code of an operation.
     */
    function deposit(uint _amount) public returns (uint) {
        return depositForTokenSymbol(store.get(defaultSharesSymbolStorage), msg.sender, _amount);
    }

    /**
    * @dev Deposits shares with provided symbol and prove possesion. See `deposit` for more details.
    *
    * @param _smbl token symbol for shares
    * @param _amount amount of shares to deposit, or 0 to just prove.
    *
    * @return result code of an operation.
    */
    function depositTokenSymbol(bytes32 _smbl, uint _amount) public returns (uint) {
        return depositForTokenSymbol(_smbl, msg.sender, _amount);
    }

    /**
     * @dev Deposit own shares and prove possession for arbitrary shareholder.
     * Amount should be less than or equal to caller current allowance value.
     *
     * Proof should be repeated for each active period. To prove possesion without
     * depositing more shares, specify 0 amount.
     *
     * This function meant to be used by some backend application to prove shares possesion
     * of arbitrary shareholders.
     *
     * @param _address to deposit and prove for.
     * @param _amount amount of shares to deposit, or 0 to just prove.
     *
     * @return result code of an operation.
     */
    function depositFor(address _address, uint _amount) public returns (uint) {
        bytes32 _symbol = store.get(defaultSharesSymbolStorage);

        require(_symbol != bytes32(0));

        return depositForTokenSymbol(_symbol, _address, _amount);
    }

    /**
    * @dev Deposit own shares and prove possession for arbitrary shareholder. See `depositFor` for more details.
    *
    * @param _smbl token symbol for shares
    * @param _address to deposit and prove for.
    * @param _amount amount of shares to deposit, or 0 to just prove.
    *
    * @return result code of an operation.
    */
    function depositForTokenSymbol(bytes32 _smbl, address _address, uint _amount) public returns (uint) {
        require(_smbl != bytes32(0));
        require(store.includes(sharesContractsStorage, _smbl));

        if (_amount > getLimitForTokenSymbol(_smbl)) {
            return _emitError(ERROR_TIMEHOLDER_LIMIT_EXCEEDED);
        }

        if (!(_amount == 0 || DepositWalletInterface(wallet()).deposit(sharesContract(_smbl), msg.sender, _amount))) {
            return _emitError(ERROR_TIMEHOLDER_TRANSFER_FAILED);
        }

        store.add(shareholders, _address);

        bytes32 _key = getCompositeKey(_smbl, _address);

        uint _id = store.get(depositsIdCounters, _key) + 1;
        store.set(depositsIdCounters, _key, _id);
        store.add(deposits, _key, _id);
        store.set(amounts, _key, bytes32(_id), bytes32(_amount));
        store.set(timestamps, _key, bytes32(_id), bytes32(now));

        _goThroughListeners(_smbl, _address, _amount, _notifyDepositListener);

        _emitDeposit(_smbl, _address, _amount);

        uint prevAmount = store.get(totalSharesStorage, _smbl);
        _amount = _amount.add(prevAmount);
        store.set(totalSharesStorage, _smbl, _amount);

        return OK;
    }

    /**
    * @dev Withdraw shares from the contract, updating the possesion proof in active period.
    *
    * @param _amount amount of shares to withdraw.
    *
    * @return result code of an operation.
    */
    function withdrawShares(uint _amount) public returns (uint) {
        return withdrawShares(store.get(defaultSharesSymbolStorage), _amount);
    }

    /**
    * @dev Withdraw shares from the contract, updating the possesion proof in active period.
    *
    * @param _smbl token symbol to withdraw from.
    * @param _amount amount of shares to withdraw.
    *
    * @return resultCode result code of an operation.
    */
    function withdrawShares(bytes32 _smbl, uint _amount) public returns (uint resultCode) {
        require(_smbl != bytes32(0));

        resultCode = _withdrawShares(_smbl, msg.sender, msg.sender, _amount);
        if (resultCode != OK) {
            return _emitError(resultCode);
        }

        _emitWithdrawShares(_smbl, msg.sender, _amount);
    }

    /**
    * @dev Provides a way to support getting additional fee for using features of the system.
    *
    * @param _account holder of deposits, will pay for using a features
    * @param _amount size of a fee
    *
    * @return resultCode result code of the operation
    */
    function takeFeatureFee(address _account, uint _amount) onlyFeatureFeeManager public returns (uint resultCode) {
        require(_account != 0x0);

        assert(feeWallet() != 0x0);

        bytes32 _smbl = store.get(defaultSharesSymbolStorage);

        assert(_smbl != bytes32(0));

        resultCode = _withdrawShares(_smbl, _account, feeWallet(), _amount);
        if (resultCode != OK) {
            return _emitError(resultCode);
        }

        _emitFeatureFeeTaken(_account, feeWallet(), _amount);
    }

    /**
    * @dev Withdraws deposited amount of tokens from account to a receiver address.
    * Emits its own errorCodes if some will be encountered.
    *
    * @param _account an address that have deposited tokens
    * @param _receiver an address that will receive tokens from _account
    * @param _amount amount of tokens to withdraw to the _receiver
    *
    * @return result code of the operation
    */
    function _withdrawShares(bytes32 _smbl, address _account, address _receiver, uint _amount) internal returns (uint) {
        if (_amount > getLimitForTokenSymbol(_smbl)) {
            return _emitError(ERROR_TIMEHOLDER_LIMIT_EXCEEDED);
        }

        uint _depositBalance = depositBalanceForTokenSymbol(_smbl, _account);

        if (_amount > _depositBalance) {
            return _emitError(ERROR_TIMEHOLDER_INSUFFICIENT_BALANCE);
        }

        if (!DepositWalletInterface(wallet()).withdraw(sharesContract(_smbl), _receiver, _amount)) {
            return _emitError(ERROR_TIMEHOLDER_TRANSFER_FAILED);
        }

        _withdrawSharesFromDeposits(_depositBalance, _smbl, _account, _amount);
        _goThroughListeners(_smbl, _account, _amount, _notifyWithdrawListener);

        store.set(totalSharesStorage, _smbl, store.get(totalSharesStorage, _smbl).sub(_amount));

        return OK;
    }

    /**
    * @dev Withdraws shares from one of made deposits.
    *
    * @param _key composite key from keccak256(symbol, user)
    * @param _id deposit key
    * @param _amount deposit amount to withdraw
    * @param _depositsLeft number of deposits left
    *
    * @return {
    *   updated deposits left,
    *   updated amount left,
    * }
    */
    function _withdrawSharesFromDeposit(bytes32 _key, uint _id, uint _amount, uint _depositsLeft) private returns (uint, uint) {
        uint _cur_amount = uint(store.get(amounts, _key, bytes32(_id)));
        if (_amount < _cur_amount) {
            store.set(amounts, _key, bytes32(_id), bytes32(_cur_amount.sub(_amount)));
            return (_depositsLeft, _amount);
        }
        if (_amount == _cur_amount) {
            store.remove(deposits, _key, _id);
            return (_depositsLeft.sub(1), _amount);
        }
        if (_amount > _cur_amount) {
            store.remove(deposits, _key, _id);
            return (_depositsLeft.sub(1), _amount.sub(_cur_amount));
        }
    }

    /**
    * @dev Withdraws shares with symbol back to provided account
    *
    * @param _totalDepositBalance total balance of shares
    * @param _smbl token symbol of shares
    * @param _account token recepient
    * @param _amount number of tokens to withdraw
    */
    function _withdrawSharesFromDeposits(uint _totalDepositBalance, bytes32 _smbl, address _account, uint _amount) private {
        if (_totalDepositBalance == 0) {
            return;
        }

        bytes32 _key = getCompositeKey(_smbl, _account);
        StorageInterface.Iterator memory iterator = store.listIterator(deposits, _key);
        uint _deposits_count_left = iterator.count();
        for (uint i = 0; store.canGetNextWithIterator(deposits, iterator); ++i) {
            uint _id = store.getNextWithIterator(deposits, iterator);
            (_deposits_count_left, _amount) = _withdrawSharesFromDeposit(_key, _id, _amount, _deposits_count_left);
        }

        if (_deposits_count_left == 0) {
            store.remove(shareholders, _account);
        }
    }

    /**
    * @dev Notifies listener about depositing token with symbol
    */
    function _notifyDepositListener(uint _listenerVersion, address _listener, bytes32 _defaultSmbl, bytes32 _smbl, address _address, uint _amount, uint _balance) private returns (uint _errorCode) {
        _errorCode = OK;
        if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V1 && _smbl == _defaultSmbl) { // DEPRECATED. LEFT ONLY FOR BACKWARD COMPATIBILITY. WILL BE REMOVED SOON
            _errorCode = ListenerInterface(_listener).deposit(_address, _amount, _balance);
        } else if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V2) {
            _errorCode = HolderListenerInterface(_listener).depositHolder(_smbl, _address, _amount, _balance);
        }
    }

    /**
    * @dev Notifies listener about withdrawing token with symbol
    */
    function _notifyWithdrawListener(uint _listenerVersion, address _listener, bytes32 _defaultSmbl, bytes32 _smbl, address _address, uint _amount, uint _balance) private returns (uint _errorCode) {
        _errorCode = OK;
        if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V1 && _smbl == _defaultSmbl) { // DEPRECATED. LEFT ONLY FOR BACKWARD COMPATIBILITY. WILL BE REMOVED SOON
            _errorCode = ListenerInterface(_listener).withdrawn(_address, _amount, _balance);
        } else if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V2) {
            _errorCode = HolderListenerInterface(_listener).withdrawnHolder(_smbl, _address, _amount, _balance);
        }
    }

    /**
    * @dev Iterates through listeners of provided symbol and notifies by calling notification function
    */
    function _goThroughListeners(bytes32 _smbl, address _address, uint _amount, function (uint, address, bytes32, bytes32, address, uint, uint) returns (uint) _notification) private {
        uint _depositBalance = depositBalanceForTokenSymbol(_smbl, _address);
        uint _errorCode;
        bytes32 _defaultSmbl = store.get(defaultSharesSymbolStorage);
        StorageInterface.Iterator memory iterator = store.listIterator(listeners, _smbl);
        for (uint i = 0; store.canGetNextWithIterator(listeners, iterator); ++i) {
            address _listener = store.getNextWithIterator(listeners, iterator);
            uint _listenerVersion = store.get(listenersSupportStorage, _listener);
            _errorCode = _notification(_listenerVersion, _listener, _defaultSmbl, _smbl, _address, _amount, _depositBalance);

            if (_errorCode != OK) {
                _emitError(_errorCode);
            }
        }
    }

    function() public {
        revert();
    }


    /** Event emitting */

    function _emitDeposit(bytes32 symbol, address who, uint amount) private {
        TimeHolderEmitter(getEventsHistory()).emitDeposit(symbol, who, amount);
    }

    function _emitWithdrawShares(bytes32 symbol, address who, uint amount) private {
        TimeHolderEmitter(getEventsHistory()).emitWithdrawShares(symbol, who, amount);
    }

    function _emitListenerAdded(address listener, bytes32 symbol) private {
        TimeHolderEmitter(getEventsHistory()).emitListenerAdded(listener, symbol);
    }

    function _emitListenerRemoved(address listener, bytes32 symbol) private {
        TimeHolderEmitter(getEventsHistory()).emitListenerRemoved(listener, symbol);
    }

    function _emitFeatureFeeTaken(address _from, address _to, uint _amount) private {
        TimeHolderEmitter(getEventsHistory()).emitFeatureFeeTaken(_from, _to, _amount);
    }

    function _emitSharesWhiteListAdded(bytes32 symbol) private {
        TimeHolderEmitter(getEventsHistory()).emitSharesWhiteListChanged(symbol, true);
    }

    function _emitSharesWhiteListRemoved(bytes32 symbol) private {
        TimeHolderEmitter(getEventsHistory()).emitSharesWhiteListChanged(symbol, false);
    }

    function _emitError(uint e) private returns (uint) {
        TimeHolderEmitter(getEventsHistory()).emitError(e);
        return e;
    }
}
