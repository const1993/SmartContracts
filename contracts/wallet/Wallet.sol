//sol Wallet
// Multi-sig, daily-limited account proxy/wallet.
// @authors:
// Gav Wood <g@ethdev.com>
// inheritable "property" contract that enables methods to be protected by requiring the acquiescence of either a
// single, or, crucially, each of a number of, designated owners.
// usage:
// use modifiers onlyowner (just own owned) or onlymanyowners(hash), whereby the same hash must be provided by
// some number (specified in constructor) of the set of owners (specified in the constructor, modifiable) before the
// interior is executed.

pragma solidity ^0.4.11;

import "../core/erc20/ERC20Manager.sol";
import {ContractsManagerInterface as ContractsManager} from "../core/contracts/ContractsManagerInterface.sol";
import "../core/erc20/ERC20Interface.sol";
import "./WalletEmitter.sol";

contract WalletsManagerInterface {
    function removeWallet() returns (uint);
    function getOracleAddress() constant returns (address);
    function getOraclePrice() constant returns (uint);
}

contract multiowned is WalletEmitter {
    uint constant OK = 1;
    uint constant WALLET_INVALID_INVOCATION = 14010;
    uint constant WALLET_OWNER_ALREADY_EXISTS = 14013;
    uint constant WALLET_CONFIRMATION_NEEDED = 14014;
    uint constant WALLET_UNKNOWN_OPERATION = 14015;
    uint constant WALLET_OWNERS_LIMIT_EXIDED = 14016;
    uint constant WALLET_UNKNOWN_TOKEN_TRANSFER = 14017;
    uint constant WALLET_OPERATION_ALREADY_REGISTERED = 14018;
    uint constant WALLET_INSUFFICIENT_BALANCE = 14019;
    uint constant WALLET_RELEASE_TIME_ERROR = 14020;

    // struct for the status of a pending operation.
    struct PendingState {
        uint yetNeeded;
        uint ownersDone;
        uint index;
    }

    // Execute only if Two-factor authentication (2FA) is disabled
    modifier only2FADisabled() {
        if(use2FA) {
            uint errorCode = WALLET_INVALID_INVOCATION;
            assembly {
                mstore(0, errorCode)
                return(0, 32)
            }
        }
        assert(!use2FA);

        _;
    }

    // Allowed only for owner
    modifier onlyowner {
        require(isOwner(msg.sender) || msg.sender == address(this));
        _;
    }

    // Multisig operation
    modifier onlymanyowners() {
        if (isOwner(msg.sender)) {
            if (use2FA) {
              // send some eth to oracle
              address walletsManager = lookupManager("WalletsManager");
              if(msg.value < WalletsManagerInterface(walletsManager).getOraclePrice()) {
                  revert();
              }

              if(!WalletsManagerInterface(walletsManager).getOracleAddress().send(msg.value)) {
                  revert();
              }
            }

            uint errorCode = registerTx(msg.value, msg.data);

            assembly {
                mstore(0, errorCode)
                return(0, 32)
            }
        } else if (msg.sender == address(this)) {
            _;
        } else {
            revert();
        }
    }

    // Constructor is given number of sigs required to do protected "onlymanyowners" transactions
    // as well as the selection of addresses capable of confirming them.
    //
    // Note, msg.sender will not be added to owners by default.
    function multiowned(address[] _owners, uint _required) {
        require(_owners.length != 0);
        require(_owners.length >= _required);

        for (uint i = 0; i < _owners.length; i++) {
            m_owners[1 + i] = uint(_owners[i]);
            m_ownerIndex[uint(_owners[i])] = 1 + i;
            m_numOwners++;
        }

        m_required = _required;
    }

    // Revokes a prior confirmation of the given operation
    function revoke(bytes32 _operation)
    external
    onlyowner
    returns (uint)
    {
        uint ownerIndex = m_ownerIndex[uint(msg.sender)];
        assert(ownerIndex != 0);

        uint ownerIndexBit = 2**ownerIndex;
        var pending = m_pending[_operation];

        // TODO
        if (pending.ownersDone & ownerIndexBit == 0) {
            return _emitError(WALLET_INVALID_INVOCATION);
        }

        pending.yetNeeded++;
        pending.ownersDone -= ownerIndexBit;

        _emitRevoke(msg.sender, _operation);
        return OK;
    }

    // Replaces an owner `_from` with another `_to`.
    // Multisig operation.
    function changeOwner(address _from, address _to)
    external
    only2FADisabled
    onlymanyowners()
    returns (uint resultCode)
    {
        uint ownerIndex = m_ownerIndex[uint(_from)];
        assert (ownerIndex != 0);

        if (isOwner(_to)) {
            return _emitError(WALLET_OWNER_ALREADY_EXISTS);
        }

        clearPending();

        m_owners[ownerIndex] = uint(_to);
        m_ownerIndex[uint(_from)] = 0;
        m_ownerIndex[uint(_to)] = ownerIndex;

        _emitOwnerChanged(_from, _to);
        return OK;
    }

    // Add the a `_owner` to the wallet's owners
    // Multisig operation.
    function addOwner(address _owner)
    external
    only2FADisabled
    onlymanyowners()
    returns (uint errorCode)
    {
        if (isOwner(_owner)) {
            return _emitError(WALLET_OWNER_ALREADY_EXISTS);
        }

        clearPending();

        if (m_numOwners >= c_maxOwners) {
            reorganizeOwners();
        }

        if (m_numOwners >= c_maxOwners) {
            return WALLET_OWNERS_LIMIT_EXIDED;
        }

        m_numOwners++;
        m_owners[m_numOwners] = uint(_owner);
        m_ownerIndex[uint(_owner)] = m_numOwners;

        _emitOwnerAdded(_owner);
        return OK;
    }

    // Remove owner. Multisig operation.
    // Multisig operation.
    function removeOwner(address _owner)
    external
    only2FADisabled
    onlymanyowners()
    returns (uint errorCode)
    {
        uint ownerIndex = m_ownerIndex[uint(_owner)];
        assert(ownerIndex != 0);

        if (m_required > m_numOwners - 1) {
            return _emitError(WALLET_INVALID_INVOCATION);
        }

        m_owners[ownerIndex] = 0;
        m_ownerIndex[uint(_owner)] = 0;
        clearPending();
        reorganizeOwners();

        _emitOwnerRemoved(_owner);
        return OK;
    }

    // Changes the number of owners that must confirm the same operation
    // before it is run.
    //
    // `_newRequired` must be greater than the current number of owners.
    //
    // Multisig operation.
    function changeRequirement(uint _newRequired)
    external
    only2FADisabled
    onlymanyowners()
    returns (uint errorCode)
    {
        if (_newRequired > m_numOwners) {
            return _emitError(WALLET_INVALID_INVOCATION);
        }

        m_required = _newRequired;
        clearPending();

        _emitRequirementChanged(_newRequired);
        return OK;
    }

    //
    //  Toogles Two-factor authentication (2FA) mode.
    //
    // TODO: multisig?
    function toggle2FA() external onlyowner returns (uint) {
        assert (m_ownerIndex[uint(msg.sender)] != 0);

        address walletsManager = lookupManager("WalletsManager");
        address oracleAddress = WalletsManagerInterface(walletsManager).getOracleAddress();

        if(oracleAddress == address(0)) {
            return _emitError(WALLET_INVALID_INVOCATION);
        }

        if(!use2FA && m_required == 1) {
            use2FA = true;
            m_required = 2;
            clearPending();
            m_numOwners++;
            m_owners[m_numOwners] = uint(oracleAddress);
            m_ownerIndex[uint(oracleAddress)] = m_numOwners;

            _emit2FAChanged(use2FA);
            return OK;
        } else {
            if(use2FA && m_required == 2 && m_ownerIndex[uint(oracleAddress)] == 1) {
                use2FA = false;
                m_required = 1;
                uint ownerIndex = m_ownerIndex[uint(oracleAddress)];
                m_owners[ownerIndex] = 0;
                m_ownerIndex[uint(oracleAddress)] = 0;
                clearPending();
                reorganizeOwners();

                _emit2FAChanged(use2FA);
                return OK;
            }
        }

        return _emitError(WALLET_INVALID_INVOCATION);
    }

    // Gets an owner by 0-indexed position (using numOwners as the count)
    function getOwner(uint ownerIndex) public view returns (address) {
        return address(m_owners[ownerIndex + 1]);
    }

    // Tells whether the given `_address` is owner of this wallet or not.
    function isOwner(address _address) public view returns (bool) {
        return m_ownerIndex[uint(_address)] > 0;
    }

    // Tells whether the passed `_operation` is alredy confirmed by `_owner`.
    function hasConfirmed(bytes32 _operation, address _owner)
    public
    view
    returns (bool)
    {
        var pending = m_pending[_operation];
        uint ownerIndex = m_ownerIndex[uint(_owner)];

        // make sure they're an owner
        if (ownerIndex == 0) return false;

        // determine the bit to set for this owner.
        uint ownerIndexBit = 2**ownerIndex;
        return !(pending.ownersDone & ownerIndexBit == 0);
    }

    // Confirms operation
    function confirmAndCheck(bytes32 _operation) internal returns (uint) {
        // determine what index the present sender is:
        uint ownerIndex = m_ownerIndex[uint(msg.sender)];
        // make sure they're an owner
        assert(ownerIndex != 0);

        var pending = m_pending[_operation];
        // if we're not yet working on this operation, switch over and reset the confirmation status.
        if (pending.yetNeeded == 0) {
            // reset count of confirmations needed.
            pending.yetNeeded = m_required;
            // reset which owners have confirmed (none) - set our bitmap to 0.
            pending.ownersDone = 0;
            pending.index = m_pendingIndex.length++;
            m_pendingIndex[pending.index] = _operation;
        }
        // determine the bit to set for this owner.
        uint ownerIndexBit = 2**ownerIndex;
        // make sure we (the message sender) haven't confirmed this operation previously.
        if (pending.ownersDone & ownerIndexBit != 0) {
            return WALLET_INVALID_INVOCATION;
        }

        _emitConfirmation(msg.sender, _operation);

        // ok - check if count is enough to go ahead.
        if (pending.yetNeeded <= 1) {
          // enough confirmations: reset and run interior.
            delete m_pendingIndex[m_pending[_operation].index];
            delete m_pending[_operation];

            return OK;
        } else {
            // not enough: record that this owner in particular confirmed.
            pending.yetNeeded--;
            pending.ownersDone |= ownerIndexBit;

            return WALLET_CONFIRMATION_NEEDED;
        }
    }

    // Make sure m_numOwner is equal to the number of owners
    // and always points to the optimal free slot.
    function reorganizeOwners() private {
        uint free = 1;
        while (free < m_numOwners)
        {
            while (free < m_numOwners && m_owners[free] != 0) free++;
            while (m_numOwners > 1 && m_owners[m_numOwners] == 0) m_numOwners--;
            if (free < m_numOwners && m_owners[m_numOwners] != 0 && m_owners[free] == 0)
            {
                m_owners[free] = m_owners[m_numOwners];
                m_ownerIndex[m_owners[free]] = free;
                m_owners[m_numOwners] = 0;
            }
        }
    }

    function clearPending() internal {
        uint length = m_pendingIndex.length;
        for (uint i = 0; i < length; ++i) {
            if (m_pendingIndex[i] != 0) {
                delete m_pending[m_pendingIndex[i]];
            }
        }

        delete m_pendingIndex;
    }

    // Virtual function.
    function registerTx(uint _value, bytes _data) internal returns (uint resultCode);

    // Returns service by the given `type`
    function lookupManager(bytes32 _identifier) internal view returns (address manager) {
        manager = ContractsManager(contractsManager).getContractAddressByType(_identifier);
        require(manager != 0x0);
    }

    // Returns events history contract
    function getEventsHistory() public view returns (address) {
        return eventsEmmiter;
    }

    function _emitError(uint errorCode) internal returns (uint) {
        Wallet(getEventsHistory()).emitError(errorCode);
        return errorCode;
    }

    function _emitDeposit(address from, uint value) internal {
        Wallet(getEventsHistory()).emitDeposit(from, value);
    }

    function _emitSingleTransact(address owner, uint value, address to, bytes32 symbol) internal {
        Wallet(getEventsHistory()).emitSingleTransact(owner, value, to, symbol);
    }

    function _emitMultiTransact(address owner, bytes32 operation, uint value, address to, bytes data) internal {
        Wallet(getEventsHistory()).emitMultiTransact(owner, operation, value, to, data);
    }

    function _emitConfirmationNeeded(bytes32 operation, address initiator, uint value, address to, bytes data) internal {
        Wallet(getEventsHistory()).emitConfirmationNeeded(operation, initiator, value, to, data);
    }

    function _emitConfirmation(address owner, bytes32 operation) internal {
        Wallet(getEventsHistory()).emitConfirmation(owner, operation);
    }

    function _emitRevoke(address owner, bytes32 operation) internal {
        Wallet(getEventsHistory()).emitRevoke(owner, operation);
    }

    function _emitOwnerChanged(address oldOwner, address newOwner) internal {
        Wallet(getEventsHistory()).emitOwnerChanged(oldOwner, newOwner);
    }

    function _emitOwnerAdded(address newOwner) internal {
        Wallet(getEventsHistory()).emitOwnerAdded(newOwner);
    }

    function _emitOwnerRemoved(address oldOwner) internal {
        Wallet(getEventsHistory()).emitOwnerRemoved(oldOwner);
    }

    function _emitRequirementChanged(uint newRequirement) internal {
        Wallet(getEventsHistory()).emitRequirementChanged(newRequirement);
    }

    function _emit2FAChanged(bool enabled) internal {
        Wallet(getEventsHistory()).emit2FAChanged(enabled);
    }

    // wallets use 2FA oracle
    bool public use2FA;
    // the number of owners that must confirm the same operation before it is run.
    uint public m_required;
    // pointer used to find a free slot in m_owners
    uint public m_numOwners;
    // version
    bytes32 public version = "1.0.0";
    // list of owners
    uint[256] m_owners;
    uint constant c_maxOwners = 250;
    // index on the list of owners to allow reverse lookup
    mapping(uint => uint) m_ownerIndex;
    // the ongoing operations.
    mapping(bytes32 => PendingState) m_pending;
    bytes32[] m_pendingIndex;
    // events proxy
    address eventsEmmiter;
    // service provider
    address contractsManager;
}

/**
* TODO
*/
contract Wallet is multiowned {
    // Transaction structure to remember details of transaction lest
    // it need be saved for a later call.
    struct Transaction {
        uint value;
        bytes data;
    }

    modifier ensureReleaseTime() {
      if(releaseTime > now) {
          uint errorCode = _emitError(WALLET_RELEASE_TIME_ERROR);
          assembly {
              mstore(0, errorCode)
              return(0, 32)
          }
      }

      assert(releaseTime <= now);
      _;
    }

    modifier ensureBalance(uint _value, bytes32 _symbol) {
      uint errorCode;
      if(_symbol == bytes32('ETH') || _symbol == bytes32(0)) {
          errorCode = this.balance < _value ? WALLET_INSUFFICIENT_BALANCE : OK;
      } else {
          ERC20Manager erc20Manager = ERC20Manager(lookupManager("ERC20Manager"));
          address token = erc20Manager.getTokenAddressBySymbol(_symbol);
          if(token == 0x0) {
              errorCode = WALLET_UNKNOWN_TOKEN_TRANSFER;
          } else {
              errorCode = ERC20Interface(token).balanceOf(this) < _value ? WALLET_INSUFFICIENT_BALANCE : OK;
          }
      }

      if (errorCode != OK) {
          _emitError(errorCode);
          assembly {
              mstore(0, errorCode)
              return(0, 32)
          }
      }

      assert(errorCode == OK);
      _;
    }

    // Constructor
    function Wallet(address[] _owners,
        uint _required,
        address _contractsManager,
        address _eventsHistory,
        bool _use2FA,
        uint _releaseTime)
    multiowned(_owners, _required)
    {
        require(_contractsManager != 0x0);
        require(_eventsHistory != 0x0);

        contractsManager = _contractsManager;
        eventsEmmiter = _eventsHistory;
        use2FA = _use2FA;
        releaseTime = _releaseTime;
    }

    // Returns pending operations
    function getPendings()
    external
    view
    returns (
      uint[] values,
      bytes32[] operations,
      bool[] isConfirmed)
    {
        values = new uint[](m_pendingIndex.length);
        operations = new bytes32[](m_pendingIndex.length);
        isConfirmed = new bool[](m_pendingIndex.length);
        for(uint i=0; i<m_pendingIndex.length; i++) {
            values[i] = m_txs[m_pendingIndex[i]].value;
            operations[i] = m_pendingIndex[i];
            isConfirmed[i] = hasConfirmed(m_pendingIndex[i], msg.sender);
        }
        return (values, operations, isConfirmed);
    }

    // Returns a data associated with given operation hash `_h`.
    //
    // @param _h operation hash
    // @return _data associated with _h
    function getData(bytes32 _h) public view returns (bytes) {
        return m_txs[_h].data;
    }

    // Kills the contract sending everything to `_to`.
    function kill(address _to)
    external
    onlymanyowners()
    returns (uint errorCode)
    {
        if(releaseTime > now) {
            return _emitError(WALLET_RELEASE_TIME_ERROR);
        }

        address erc20Manager = lookupManager("ERC20Manager");
        uint tokenCount = ERC20Manager(erc20Manager).tokensCount();

        // TODO: oog
        for(uint i = 0; i < tokenCount; i++) {
            address token = ERC20Manager(erc20Manager).getAddressById(i);
            uint balance = ERC20Interface(token).balanceOf(this);
            if(balance != 0) {
                require(ERC20Interface(token).transfer(_to,balance));
            }
        }

        address walletsManager = lookupManager("WalletsManager");
        if (WalletsManagerInterface(walletsManager).removeWallet() != OK) {
            revert();
        }

        selfdestruct(_to);
        return OK;
    }

    // Gets called when no other function matches
    function() payable {
        if (msg.value > 0) {
            _emitDeposit(msg.sender, msg.value);
        }
    }


    // Send _value amount of tokens/eth to address _to from this wallet
    function transfer(address _to, uint _value, bytes32 _symbol)
    ensureReleaseTime
    ensureBalance(_value, _symbol)
    onlymanyowners()
    payable
    returns (uint)
    {
        if(_symbol == bytes32('ETH') || _symbol == bytes32(0)) {
            require(_to.send(_value));
        } else {
            address token = ERC20Manager(lookupManager("ERC20Manager")).getTokenAddressBySymbol(_symbol);
            require(ERC20Interface(token).transfer(_to, _value));
        }

        return OK;
    }

    // Transact entry point. Goes into multisig process. Only for internal usage.
    function registerTx(uint _value, bytes _data)
    internal
    returns (uint resultCode)
    {
        bytes32 _r = keccak256(msg.data, block.number);

        if (m_txs[_r].data.length != 0) {
            return _emitError(WALLET_OPERATION_ALREADY_REGISTERED);
        }

        m_txs[_r].data = _data;
        m_txs[_r].value = _value;

        resultCode = confirm(_r);
        if (resultCode != OK) {
            if (resultCode != WALLET_CONFIRMATION_NEEDED) {
                return _emitError(resultCode);
            }
            _emitConfirmationNeeded(_r, msg.sender, _value, this, _data);
            return WALLET_CONFIRMATION_NEEDED;
        }
        return OK;
    }

    // Confirm a transaction through just the hash.
    // We use the previous transactions map, m_txs, in order
    // to determine the body of the transaction from the hash provided.
    //
    // @param _h operation which should be confirmed
    // @return errorCode indicates what happened
    function confirm(bytes32 _h) public onlyowner returns (uint errorCode) {
       if (m_txs[_h].data.length == 0) {
          return _emitError(WALLET_UNKNOWN_OPERATION);
       }

       errorCode = confirmAndCheck(_h);
       if (OK != errorCode) {
           return errorCode;
       }

       require(this.call(m_txs[_h].data));
       delete m_txs[_h];

       _emitMultiTransact(msg.sender, _h, m_txs[_h].value, this, m_txs[_h].data);
       return OK;
   }


    // Clears pending transactions.
    function clearPending() internal {
        uint length = m_pendingIndex.length;
        for (uint i = 0; i < length; ++i) {
            delete m_txs[m_pendingIndex[i]];
        }

        super.clearPending();
    }

    // pending transactions we have at present.
    mapping (bytes32 => Transaction) m_txs;
    // the time when ETH/ERC20 transfer will be allowed
    uint public releaseTime;
}
