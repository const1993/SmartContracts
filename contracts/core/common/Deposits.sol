pragma solidity ^0.4.11;

import "./BaseManager.sol";
import "../lib/SafeMath.sol";
import {ERC20Manager as ERC20Service} from "../erc20/ERC20Manager.sol";

/**
* @title TODO
*/
contract Deposits is BaseManager {

    using SafeMath for uint;

    StorageInterface.OrderedAddressesSet shareholders;
    StorageInterface.UIntOrderedSetMapping deposits;
    StorageInterface.UInt depositsIdCounter_old; // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
    StorageInterface.Bytes32UIntMapping depositsIdCounters;
    StorageInterface.Mapping amounts;
    StorageInterface.Mapping timestamps;
    StorageInterface.UInt totalSharesStorage_old; // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
    StorageInterface.Bytes32UIntMapping totalSharesStorage;
    StorageInterface.Address sharesContractStorage_old; // DEPRECATED. WILL BE REMOVED IN THE NEXT RELEASE
    StorageInterface.Set sharesContractsStorage;
    StorageInterface.Bytes32 defaultSharesSymbolStorage;

    function Deposits(Storage _store, bytes32 _crate) BaseManager(_store, _crate) {
        shareholders.init('shareholders');
        deposits.init('deposits');
        depositsIdCounters.init('depositsIdCounters');
        amounts.init('amounts');
        timestamps.init('timestamps');
        totalSharesStorage.init('totalSharesStorage_v2');
        sharesContractsStorage.init('sharesContractsStorage');
        defaultSharesSymbolStorage.init('defaultSharesSymbolStorage');

        depositsIdCounter_old.init('depositsIdCounter'); // DEPRECATED
        totalSharesStorage_old.init('totalSharesStorage'); // DEPRECATED
        sharesContractStorage_old.init('sharesContractStorage'); // DEPRECATED
    }

    /**
    * @dev TODO: consider a better way to update storage variables to the new appearance
    */
    function _migrateToVersion2() internal {
        bytes32 _defaultSymbol = store.get(defaultSharesSymbolStorage);
        require(_defaultSymbol != bytes32(0));

        if (store.get(depositsIdCounters, _defaultSymbol) == 0) {
            store.set(depositsIdCounters, _defaultSymbol, store.get(depositsIdCounter_old));
        }

        if (store.get(totalSharesStorage, _defaultSymbol) == 0) {
            store.set(totalSharesStorage, _defaultSymbol, store.get(totalSharesStorage_old));
        }

        // NOTE: ignore migrating sharesContractStorage_old cause defaultSymbol should mark the same token
    }

    /**
     * @dev Returns shares amount deposited by a particular shareholder for defaultSharesSymbolStorage.
     *
     * @param _address shareholder address.
     *
     * @return _balance shares amount.
     */
    function depositBalance(address _address) public constant returns (uint) {
        return depositBalanceForTokenSymbol(store.get(defaultSharesSymbolStorage), _address);
    }

    /**
     * @dev Returns shares amount deposited by a particular shareholder.
     *
     * @param _smbl token symbol.
     * @param _address shareholder address.
     *
     * @return _balance shares amount.
     */
    function depositBalanceForTokenSymbol(bytes32 _smbl, address _address) public constant returns (uint _balance) {
        bytes32 _key = getCompositeKey(_smbl, _address);
        StorageInterface.Iterator memory iterator = store.listIterator(deposits, _key);
        for (uint i = 0; store.canGetNextWithIterator(deposits, iterator); ++i) {
            uint _cur_amount = uint(store.get(amounts, _key, bytes32(store.getNextWithIterator(deposits, iterator))));
            _balance = _balance.add(_cur_amount);
        }
    }

    /**
    * @dev TODO
    */
    function getCompositeKey(bytes32 _smbl, address _address) internal constant returns (bytes32) {
        return keccak256(_smbl, _address);
    }

    function lookupERC20Service() internal constant returns (ERC20Service) {
        return ERC20Service(lookupManager("ERC20Manager"));
    }

    /**
    *   Returns token symbol by given address.
    */
    function getTokenSymbol(address _token) internal constant returns (bytes32) {
        var (,, symbol,,,,) = lookupERC20Service().getTokenMetaData(_token);
        return symbol;
    }
}
