pragma solidity ^0.4.11;

import "./TimeHolderEmitter.sol";
import "../core/common/BaseManager.sol";
import "../core/common/ListenerInterface.sol";
import "../core/common/Deposits.sol";
import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";
import "./DepositWalletInterface.sol";


/**
* @title TODO
*/
contract TimeHolder is Deposits, TimeHolderEmitter {

    uint constant ERROR_TIMEHOLDER_ALREADY_ADDED = 12000;
    uint constant ERROR_TIMEHOLDER_INVALID_INVOCATION = 12001;
    uint constant ERROR_TIMEHOLDER_INVALID_STATE = 12002;
    uint constant ERROR_TIMEHOLDER_TRANSFER_FAILED = 12003;
    uint constant ERROR_TIMEHOLDER_WITHDRAWN_FAILED = 12004;
    uint constant ERROR_TIMEHOLDER_DEPOSIT_FAILED = 12005;
    uint constant ERROR_TIMEHOLDER_INSUFFICIENT_BALANCE = 12006;
    uint constant ERROR_TIMEHOLDER_LIMIT_EXCEEDED = 12007;

    uint constant TIMEHOLDER_LISTENER_VERSION_V1 = 1;
    uint constant TIMEHOLDER_LISTENER_VERSION_V2 = 2;

    StorageInterface.OrderedAddressesSet listeners;
    StorageInterface.AddressOrderedSetMapping listeners_v2;
    StorageInterface.Address walletStorage;
    StorageInterface.Address feeWalletStorage;
    StorageInterface.UInt limitAmount_old; // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
    StorageInterface.Bytes32UIntMapping limitAmountsStorage;
    StorageInterface.AddressUIntMapping listenersSupportStorage;


    modifier onlyFeatureFeeManager {
        if (msg.sender == lookupManager("FeatureFeeManager")) {
            _;
        }
    }

    function TimeHolder(Storage _store, bytes32 _crate) Deposits(_store, _crate) public {
        listeners.init('listeners');
        listeners_v2.init('listeners_v2');
        limitAmount_old.init('limitAmount'); // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
        feeWalletStorage.init("timeHolderFeeWalletStorage");
        walletStorage.init("timeHolderWalletStorage");
        limitAmountsStorage.init('limitAmountsStorage');
        listenersSupportStorage.init('listenersSupportStorage');
    }

    /**
     * Init TimeHolder contract.
     *
     *
     * @param _contractsManager address.
     * @param _defaultSharesTokenSymbol default ERC20 token symbol to act as shares.
     *
     * @return success.
     */
    function init(address _contractsManager, bytes32 _defaultSharesTokenSymbol, address _wallet, address _feeWallet) onlyContractOwner public returns (uint) {
        require(_wallet != 0x0);
        require(_feeWallet != 0x0);

        BaseManager.init(_contractsManager, "TimeHolder");

        _migrateToVersion2(_defaultSharesTokenSymbol);

        store.set(limitAmountsStorage, _defaultSharesTokenSymbol, 2**255);

        store.set(walletStorage, _wallet);
        store.set(feeWalletStorage, _feeWallet);

        return OK;
    }

    function _migrateToVersion2(bytes32 _defaultSharesTokenSymbol) private {
        if (_defaultSharesTokenSymbol != bytes32(0)) {
            store.set(defaultSharesSymbolStorage, _defaultSharesTokenSymbol);
        }

        _migrateToVersion2();

        if (_defaultSharesTokenSymbol != bytes32(0)) {
            store.add(sharesContractsStorage, _defaultSharesTokenSymbol);
        }

        address _listener;
        StorageInterface.Iterator memory iterator = store.listIterator(listeners);
        while (store.canGetNextWithIterator(listeners, iterator)) {
            store.remove(listeners, _listener);
            _listener = store.getNextWithIterator(listeners, iterator);
            addListener(_listener);
        }
        store.remove(listeners, _listener);
    }

    function destroy() onlyContractOwner public {
        selfdestruct(msg.sender);
    }

    /**
    * @dev TODO
    */
    function addERC20Shares(bytes32[] _whiteList) onlyAuthorized public returns (uint) {
        ERC20Service erc20Service = lookupERC20Service();
        for (uint _idx = 0; _idx < _whiteList.length; ++_idx) {
            address _token = erc20Service.getTokenAddressBySymbol(_whiteList[_idx]);
            if (!(_token == 0x0 || store.includes(sharesContractsStorage, _whiteList[_idx]))) {
                store.add(sharesContractsStorage, _whiteList[_idx]);
                store.set(limitAmountsStorage, _whiteList[_idx], 2**255);
                // TODO: emit event
            }
        }
    }

    /**
    * @dev TODO
    */
    function removeERC20Shares(bytes32[] _blackList) onlyAuthorized public returns (uint) {
        ERC20Service erc20Service = lookupERC20Service();
        for (uint _idx = 0; _idx < _blackList.length; ++_idx) {
            address _token = erc20Service.getTokenAddressBySymbol(_blackList[_idx]);
            if (_token != 0x0) {
                store.remove(sharesContractsStorage, _blackList[_idx]);
                store.set(limitAmountsStorage, _blackList[_idx], 0);
                // TODO: emit event
            }
        }
    }

    /**
    * @dev TODO
    */
    function addListener(address _listener) onlyAuthorized public returns (uint) {
        ListenerInterface(_listener).deposit(this, 0, 0);
        ListenerInterface(_listener).withdrawn(this, 0, 0);

        return _addListener(store.get(defaultSharesSymbolStorage), _listener, TIMEHOLDER_LISTENER_VERSION_V1);
    }

    /**
    * @dev TODO
    */
    function removeListener(address _listener) onlyAuthorized public {
        removeHolderListener(store.get(defaultSharesSymbolStorage), _listener);
    }

    /**
    * @dev TODO
    */
    function addHolderListener(bytes32 _smbl, address _listener) onlyAuthorized public returns (uint) {
        HolderListenerInterface(_listener).depositHolder(_smbl, this, 0, 0);
        HolderListenerInterface(_listener).withdrawnHolder(_smbl, this, 0, 0);

        return _addListener(_smbl, _listener, TIMEHOLDER_LISTENER_VERSION_V2);
    }

    /**
    * @dev TODO
    */
    function removeHolderListener(bytes32 _smbl, address _listener) onlyAuthorized public {
        require(_smbl != bytes32(0));

        if (store.includes(listeners_v2, _smbl, _listener)) {
            store.remove(listeners_v2, _smbl, _listener);
            store.set(listenersSupportStorage, _listener, 0);
            _emitListenerRemoved(_listener); // TODO: update event args
        }
    }

    /**
    * @dev TODO
    */
    function _addListener(bytes32 _smbl, address _listener, uint _listenerVersion) private returns (uint) {
        require(_smbl != bytes32(0));

        if (store.includes(listeners_v2, _smbl, _listener)) {
            return _emitError(ERROR_TIMEHOLDER_ALREADY_ADDED);
        }

        store.add(listeners_v2, _smbl, _listener);
        store.set(listenersSupportStorage, _listener, _listenerVersion);

        _emitListenerAdded(_listener); // TODO: update event args
    }

    /**
    *  Sets fee wallet address.
    */
    function setFeeWallet(address _feeWallet) onlyContractOwner public {
        require(_feeWallet != 0x0);
        store.set(feeWalletStorage, _feeWallet);
    }

    /**
    * Gets an associated wallet for the time holder
    */
    function wallet() public constant returns (address) {
        return store.get(walletStorage);
    }

    /**
    * Gets an associated fee wallet for the time holder
    */
    function feeWallet() public constant returns (address) {
        return store.get(feeWalletStorage);
    }

    /**
    * Total amount of shares
    *
    * @return total amount of shares
    */
    function totalShares() public constant returns (uint) {
        return totalShares(store.get(defaultSharesSymbolStorage));
    }

    /**
    * Total amount of shares
    *
    * @return total amount of shares
    */
    function totalShares(bytes32 _smbl) public constant returns (uint) {
        require(_smbl != bytes32(0));

        return store.get(totalSharesStorage, _smbl);
    }

    /**
    * @dev TODO
    */
    function totalSupply() public constant returns (uint) {
        return totalSupply(store.get(defaultSharesSymbolStorage));
    }

    /**
    * @dev TODO
    */
    function totalSupply(bytes32 _smbl) public constant returns (uint) {
        require(_smbl != bytes32(0));

        address _asset = ERC20Service(lookupERC20Service()).getTokenAddressBySymbol(_smbl);

        require(_asset != 0x0);

        return Asset(_asset).totalSupply();
    }

    /**
    * Contract address of shares
    *
    * @return address of shares contract
    */
    function sharesContract() public constant returns (address) {
        return sharesContract(store.get(defaultSharesSymbolStorage));
    }

    /**
    * @dev TODO
    */
    function sharesContract(bytes32 _smbl) internal constant returns (address) {
        require(_smbl != bytes32(0));

        address _asset = ERC20Service(lookupERC20Service()).getTokenAddressBySymbol(_smbl);

        require(_asset != 0x0);

        return _asset;
    }

    /**
    * Number of shareholders
    *
    * @return number of shareholders
    */
    function shareholdersCount() public constant returns (uint) {
        return store.count(shareholders);
    }

    /**
    * Returns deposit/withdraw limit
    *
    * @return limit
    */
    function getLimit() public constant returns (uint) {
        return getLimitForTokenSymbol(store.get(defaultSharesSymbolStorage));
    }

    /**
    * @dev TODO
    */
    function getLimitForTokenSymbol(bytes32 _smbl) public constant returns (uint) {
        require(_smbl != bytes32(0));

        return store.get(limitAmountsStorage, _smbl);
    }

    /**
    * Setter deposit/withdraw limit
    *
    * @param _limitAmount is limit
    */
    function setLimit(uint _limitAmount) onlyContractOwner public {
        setLimitForTokenSymbol(store.get(defaultSharesSymbolStorage), _limitAmount);
    }

    /**
    * @dev TODO
    */
    function setLimitForTokenSymbol(bytes32 _smbl, uint _limitAmount) onlyContractOwner internal {
        require(_smbl != bytes32(0));

        store.set(limitAmountsStorage, _smbl, _limitAmount);
    }

    /**
     * Deposit shares and prove possession.
     * Amount should be less than or equal to current allowance value.
     *
     * Proof should be repeated for each active period. To prove possesion without
     * depositing more shares, specify 0 amount.
     *
     * @param _amount amount of shares to deposit, or 0 to just prove.
     *
     * @return success.
     */
    function deposit(uint _amount) public returns (uint) {
        return depositForTokenSymbol(store.get(defaultSharesSymbolStorage), msg.sender, _amount);
    }

    /**
    * @dev TODO
    */
    function depositTokenSymbol(bytes32 _smbl, uint _amount) public returns (uint) {
        return depositForTokenSymbol(_smbl, msg.sender, _amount);
    }

    /**
     * Deposit own shares and prove possession for arbitrary shareholder.
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
     * @return success.
     */
    function depositFor(address _address, uint _amount) public returns (uint) {
        bytes32 _symbol = store.get(defaultSharesSymbolStorage);

        require(_symbol != bytes32(0));

        return depositForTokenSymbol(_symbol, _address, _amount);
    }

    /**
    * @dev TODO
    */
    function depositForTokenSymbol(bytes32 _smbl, address _address, uint _amount) public returns (uint) {
        require(_smbl != bytes32(0));

        if (_amount > getLimitForTokenSymbol(_smbl)) {
            return _emitError(ERROR_TIMEHOLDER_LIMIT_EXCEEDED);
        }

        if (!(_amount == 0 || DepositWalletInterface(wallet()).deposit(sharesContract(_smbl), msg.sender, _amount))) {
            return _emitError(ERROR_TIMEHOLDER_TRANSFER_FAILED);
        }

        if (!store.includes(shareholders, _address)) {
            store.add(shareholders, _address);
        }

        bytes32 _key = getCompositeKey(_smbl, _address);

        uint _id = store.get(depositsIdCounters, _key) + 1;
        store.set(depositsIdCounters, _key, _id);
        store.add(deposits, _key, _id);
        store.set(amounts, _key, bytes32(_id), bytes32(_amount));
        store.set(timestamps, _key, bytes32(_id), bytes32(now));

        _notifyListenersDeposit(_smbl, _address, _amount);

        _emitDeposit(_address, _amount);

        uint prevAmount = store.get(totalSharesStorage, _smbl);
        _amount = _amount.add(prevAmount);
        store.set(totalSharesStorage, _smbl, _amount);

        return OK;
    }

    /**
    * Withdraw shares from the contract, updating the possesion proof in active period.
    *
    * @param _amount amount of shares to withdraw.
    *
    * @return success.
    */
    function withdrawShares(uint _amount) public returns (uint) {
        return withdrawShares(store.get(defaultSharesSymbolStorage), _amount);
    }

    /**
    * @dev TODO
    */
    function withdrawShares(bytes32 _smbl, uint _amount) public returns (uint resultCode) {
        require(_smbl != bytes32(0));

        resultCode = _withdrawShares(_smbl, msg.sender, msg.sender, _amount);
        if (resultCode != OK) {
            return _emitError(resultCode);
        }

        _emitWithdrawShares(msg.sender, _amount);
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
        _notifyListenersWithdraw(_smbl, _account, _amount);

        store.set(totalSharesStorage, _smbl, store.get(totalSharesStorage, _smbl).sub(_amount));

        return OK;
    }

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

    function _withdrawSharesFromDeposits(uint _totalDepositBalance, bytes32 _smbl, address _account, uint _amount) private {
        if (_totalDepositBalance == 0) {
            return;
        }

        bytes32 _key = getCompositeKey(_smbl, _account);
        StorageInterface.Iterator memory iterator = store.listIterator(deposits, _key);
        uint _deposits_count_left = iterator.count();

        if (_deposits_count_left != 0) {
            for (uint i = 0; store.canGetNextWithIterator(deposits, iterator); ++i) {
                uint _id = store.getNextWithIterator(deposits, iterator);
                (_deposits_count_left, _amount) = _withdrawSharesFromDeposit(_key, _id, _amount, _deposits_count_left);
            }
        }

        if (_deposits_count_left == 0) {
            store.remove(shareholders, _account);
        }
    }

    function _notifyListenersWithdraw(bytes32 _smbl, address _account, uint _amount) private {
        uint _depositBalance = depositBalanceForTokenSymbol(_smbl, _account);
        uint _errorCode;
        bytes32 _defaultSmbl = store.get(defaultSharesSymbolStorage);
        StorageInterface.Iterator memory iterator = store.listIterator(listeners_v2, _smbl);
        for (uint i = 0; store.canGetNextWithIterator(listeners_v2, iterator); ++i) {
            address _listener = store.getNextWithIterator(listeners_v2, iterator);
            uint _listenerVersion = store.get(listenersSupportStorage, _listener);
            _errorCode = OK;

            if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V1 && _smbl == _defaultSmbl) { // DEPRECATED. LEFT ONLY FOR BACKWARD COMPATIBILITY. WILL BE REMOVED SOON
                _errorCode = ListenerInterface(_listener).withdrawn(_account, _amount, _depositBalance);
            } else if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V2) {
                _errorCode = HolderListenerInterface(_listener).withdrawnHolder(_smbl, _account, _amount, _depositBalance);
            }

            if (_errorCode != OK) {
                _emitError(_errorCode);
            }
        }
    }

    function _notifyListenersDeposit(bytes32 _smbl, address _address, uint _amount) private {
        uint _depositBalance = depositBalanceForTokenSymbol(_smbl, _address);
        uint _errorCode;
        bytes32 _defaultSmbl = store.get(defaultSharesSymbolStorage);
        StorageInterface.Iterator memory iterator = store.listIterator(listeners_v2, _smbl);
        for (uint i = 0; store.canGetNextWithIterator(listeners_v2, iterator); ++i) {
            address _listener = store.getNextWithIterator(listeners_v2, iterator);
            uint _listenerVersion = store.get(listenersSupportStorage, _listener);
            _errorCode = OK;

            if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V1 && _smbl == _defaultSmbl) { // DEPRECATED. LEFT ONLY FOR BACKWARD COMPATIBILITY. WILL BE REMOVED SOON
                _errorCode = ListenerInterface(_listener).deposit(_address, _amount, _depositBalance);
            } else if (_listenerVersion == TIMEHOLDER_LISTENER_VERSION_V2) {
                _errorCode = HolderListenerInterface(_listener).depositHolder(_smbl, _address, _amount, _depositBalance);
            }

            if (_errorCode != OK) {
                _emitError(_errorCode);
            }
        }
    }

    function() public {
        revert();
    }

    function _emitDeposit(address who, uint amount) private {
        TimeHolderEmitter(getEventsHistory()).emitDeposit(who, amount);
    }

    function _emitWithdrawShares(address who, uint amount) private {
        TimeHolderEmitter(getEventsHistory()).emitWithdrawShares(who, amount);
    }

    function _emitListenerAdded(address listener) private {
        TimeHolderEmitter(getEventsHistory()).emitListenerAdded(listener);
    }

    function _emitListenerRemoved(address listener) private {
        TimeHolderEmitter(getEventsHistory()).emitListenerRemoved(listener);
    }

    function _emitFeatureFeeTaken(address _from, address _to, uint _amount) private {
        TimeHolderEmitter(getEventsHistory()).emitFeatureFeeTaken(_from, _to, _amount);
    }

    function _emitError(uint e) private returns (uint) {
        TimeHolderEmitter(getEventsHistory()).emitError(e);
        return e;
    }
}
