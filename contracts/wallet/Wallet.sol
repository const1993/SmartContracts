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

pragma solidity ^0.4.10;

import {ERC20ManagerInterface as ERC20Manager} from "../core/erc20/ERC20ManagerInterface.sol";
import {ContractsManagerInterface as ContractsManager} from "../core/contracts/ContractsManagerInterface.sol";
import "../core/erc20/ERC20Interface.sol";

contract WalletsManagerInterface {
    function removeWallet() returns (uint);
}

contract multiowned {

	// TYPES

    uint constant WALLET_INVALID_INVOCATION = 0;
    uint constant OK = 1;
    uint constant WALLET_UNKNOWN_OWNER = 2;
    uint constant WALLET_OWNER_ALREADY_EXISTS = 3;
    uint constant WALLET_CONFIRMATION_NEEDED = 4;
    uint constant WALLET_UNKNOWN_OPERATION = 5;
    uint constant WALLET_OWNERS_LIMIT_EXIDED = 6;
    uint constant WALLET_UNKNOWN_TOKEN_TRANSFER = 7;
    uint constant WALLET_TRANSFER_ALREADY_REGISTERED = 8;
    uint constant WALLET_INSUFFICIENT_BALANCE = 9;

    // struct for the status of a pending operation.
    struct PendingState {
        uint yetNeeded;
        uint ownersDone;
        uint index;
    }

	// EVENTS

    // this contract only has six types of events: it can accept a confirmation, in which case
    // we record owner and operation (hash) alongside it.
    event Confirmation(address owner, bytes32 operation);
    event Revoke(address owner, bytes32 operation);
    // some others are in the case of an owner changing.
    event OwnerChanged(address oldOwner, address newOwner);
    event OwnerAdded(address newOwner);
    event OwnerRemoved(address oldOwner);
    // the last one is emitted if the required signatures change
    event RequirementChanged(uint newRequirement);

    event Error(uint errorCode);

    function _emitError(uint error) internal returns (uint) {
        Error(error);
        return error;
    }

	// METHODS

    // constructor is given number of sigs required to do protected "onlymanyowners" transactions
    // as well as the selection of addresses capable of confirming them.
    function multiowned(address[] _owners, uint _required) {
        m_numOwners = _owners.length + 1;
        m_owners[1] = uint(msg.sender);
        m_ownerIndex[uint(msg.sender)] = 1;
        for (uint i = 0; i < _owners.length; ++i)
        {
            m_owners[2 + i] = uint(_owners[i]);
            m_ownerIndex[uint(_owners[i])] = 2 + i;
        }
        m_required = _required;
    }

    // Revokes a prior confirmation of the given operation
    function revoke(bytes32 _operation) external returns (uint) {
        uint ownerIndex = m_ownerIndex[uint(msg.sender)];
        // make sure they're an owner
        if (ownerIndex == 0) return _emitError(WALLET_UNKNOWN_OWNER);
        uint ownerIndexBit = 2**ownerIndex;
        var pending = m_pending[_operation];
        if (pending.ownersDone & ownerIndexBit > 0) {
            pending.yetNeeded++;
            pending.ownersDone -= ownerIndexBit;
            Revoke(msg.sender, _operation);
            return OK;
        }
        return _emitError(WALLET_UNKNOWN_OPERATION);
    }

    // Replaces an owner `_from` with another `_to`.
    function changeOwner(address _from, address _to) external returns (uint) {
        uint e = confirmAndCheck(sha3(msg.data));
        if(OK != e) {
            return _emitError(e);
        }
        if (isOwner(_to)) return _emitError(WALLET_OWNER_ALREADY_EXISTS);
        uint ownerIndex = m_ownerIndex[uint(_from)];
        if (ownerIndex == 0) return _emitError(WALLET_UNKNOWN_OWNER);
        clearPending();
        m_owners[ownerIndex] = uint(_to);
        m_ownerIndex[uint(_from)] = 0;
        m_ownerIndex[uint(_to)] = ownerIndex;
        OwnerChanged(_from, _to);
        return OK;
    }

    function addOwner(address _owner) external returns (uint) {
        uint e = confirmAndCheck(sha3(msg.data));
        if(OK != e) {
            return _emitError(e);
        }
        if (isOwner(_owner)) return _emitError(WALLET_OWNER_ALREADY_EXISTS);

        clearPending();
        if (m_numOwners >= c_maxOwners)
            reorganizeOwners();
        if (m_numOwners >= c_maxOwners)
            return WALLET_OWNERS_LIMIT_EXIDED;
        m_numOwners++;
        m_owners[m_numOwners] = uint(_owner);
        m_ownerIndex[uint(_owner)] = m_numOwners;
        OwnerAdded(_owner);
        return OK;
    }

    function removeOwner(address _owner) external returns (uint) {
        uint e = confirmAndCheck(sha3(msg.data));
        if(OK != e) {
            return _emitError(e);
        }
        uint ownerIndex = m_ownerIndex[uint(_owner)];
        if (ownerIndex == 0) return _emitError(WALLET_UNKNOWN_OWNER);
        if (m_required > m_numOwners - 1) return _emitError(WALLET_INVALID_INVOCATION);

        m_owners[ownerIndex] = 0;
        m_ownerIndex[uint(_owner)] = 0;
        clearPending();
        reorganizeOwners(); //make sure m_numOwner is equal to the number of owners and always points to the optimal free slot
        OwnerRemoved(_owner);
        return OK;
    }

    function changeRequirement(uint _newRequired) external returns (uint) {
        uint e = confirmAndCheck(sha3(msg.data));
        if(OK != e) {
            return _emitError(e);
        }
        if (_newRequired > m_numOwners) return;
        m_required = _newRequired;
        clearPending();
        RequirementChanged(_newRequired);
        return OK;
    }

    // Gets an owner by 0-indexed position (using numOwners as the count)
    function getOwner(uint ownerIndex) external constant returns (address) {
        return address(m_owners[ownerIndex + 1]);
    }

    function isOwner(address _addr) constant returns (bool) {
        return m_ownerIndex[uint(_addr)] > 0;
    }

    function hasConfirmed(bytes32 _operation, address _owner) constant returns (bool) {
        var pending = m_pending[_operation];
        uint ownerIndex = m_ownerIndex[uint(_owner)];

        // make sure they're an owner
        if (ownerIndex == 0) return false;

        // determine the bit to set for this owner.
        uint ownerIndexBit = 2**ownerIndex;
        return !(pending.ownersDone & ownerIndexBit == 0);
    }

    // INTERNAL METHODS

    function confirmAndCheck(bytes32 _operation) internal returns (uint) {
        // determine what index the present sender is:
        uint ownerIndex = m_ownerIndex[uint(msg.sender)];
        // make sure they're an owner
        if (ownerIndex == 0) return _emitError(WALLET_UNKNOWN_OWNER);

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
        if (pending.ownersDone & ownerIndexBit == 0) {
            Confirmation(msg.sender, _operation);
            // ok - check if count is enough to go ahead.
            if (pending.yetNeeded <= 1) {
                // enough confirmations: reset and run interior.
                delete m_pendingIndex[m_pending[_operation].index];
                delete m_pending[_operation];
                return OK;
            }
            else
            {
                // not enough: record that this owner in particular confirmed.
                pending.yetNeeded--;
                pending.ownersDone |= ownerIndexBit;
                return WALLET_CONFIRMATION_NEEDED;
            }
        }
    }

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
        for (uint i = 0; i < length; ++i)
            if (m_pendingIndex[i] != 0)
                delete m_pending[m_pendingIndex[i]];
        delete m_pendingIndex;
    }

   	// FIELDS

    // the number of owners that must confirm the same operation before it is run.
    uint public m_required;
    // pointer used to find a free slot in m_owners
    uint public m_numOwners;

    // list of owners
    uint[256] m_owners;
    uint constant c_maxOwners = 250;
    uint constant c_maxPending = 20;
    // index on the list of owners to allow reverse lookup
    mapping(uint => uint) m_ownerIndex;
    // the ongoing operations.
    mapping(bytes32 => PendingState) m_pending;
    bytes32[] m_pendingIndex;
}

// usage:
// bytes32 h = Wallet(w).from(oneOwner).execute(to, value, data);
// Wallet(w).from(anotherOwner).confirm(h);
contract Wallet is multiowned {

    // EVENTS

    // logged events:
    // Funds has arrived into the wallet (record how much).
    event Deposit(address _from, uint value);
    // Single transaction going out of the wallet (record who signed for it, how much, and to whom it's going).
    event SingleTransact(address owner, uint value, address to, bytes data);
    // Multi-sig transaction going out of the wallet (record who signed for it last, the operation hash, how much, and to whom it's going).
    event MultiTransact(address owner, bytes32 operation, uint value, address to, bytes32 symbol);
    // Confirmation still needed for a transaction.
    event ConfirmationNeeded(bytes32 operation, address initiator, uint value, address to, bytes32 symbol);
	// TYPES

    // Transaction structure to remember details of transaction lest it need be saved for a later call.
    struct Transaction {
        address to;
        uint value;
        bytes32 symbol;
    }

    address contractsManager;

    // METHODS

    // constructor - just pass on the owner array to the multiowned and
    // the limit to daylimit
    function Wallet(address[] _owners, uint _required, address _contractsManager, bytes32 _name) multiowned(_owners, _required)  {
        contractsManager = _contractsManager;
        name = _name;
    }

    function getTokenAddresses() constant returns (address[] result) {
        address erc20Manager = ContractsManager(contractsManager).getContractAddressByType(bytes32("ERC20Manager"));
        uint counter = ERC20Manager(erc20Manager).tokensCount();
        result = new address[](counter);
        for(uint i=0;i<counter;i++) {
            result[i] = ERC20Manager(erc20Manager).getAddressById(i);
        }
        return result;
    }

    // kills the contract sending everything to `_to`.
    function kill(address _to) external returns (uint) {
        uint e = confirmAndCheck(sha3(msg.data));
        if(OK != e) {
            return _emitError(e);
        }
        address[] memory tokens = getTokenAddresses();
        for(uint i=0;i<tokens.length;i++) {
            address token = tokens[i];
            uint balance = ERC20Interface(token).balanceOf(this);
            if(balance != 0)
                ERC20Interface(token).transfer(_to,balance);
        }
        selfdestruct(_to);
        address walletsManager = ContractsManager(contractsManager).getContractAddressByType(bytes32("WalletsManager"));
        return WalletsManagerInterface(walletsManager).removeWallet();
    }

    function setName(bytes32 _name) returns (uint) {
        // determine what index the present sender is and make sure they're an owner
        if (m_ownerIndex[uint(msg.sender)] == 0) {
            return _emitError(WALLET_UNKNOWN_OWNER);
        }

        name = _name;

        return OK;
    }

    // gets called when no other function matches
    function() payable {
        // just being sent some cash?
        if (msg.value > 0)
            Deposit(msg.sender, msg.value);
    }

    // Outside-visible transact entry point. Executes transaction immediately if below daily spend limit.
    // If not, goes into multisig process. We provide a hash on return to allow the sender to provide
    // shortcuts for the other confirmations (allowing them to avoid replicating the _to, _value
    // and _data arguments). They still get the option of using them if they want, anyways.
    function transfer(address _to, uint _value, bytes32 _symbol) external returns (uint) {
        if(!isOwner(msg.sender)) {
            return _emitError(WALLET_UNKNOWN_OWNER);
        }
        address erc20Manager = ContractsManager(contractsManager).getContractAddressByType(bytes32("ERC20Manager"));
        if(_symbol != bytes32('ETH') && ERC20Manager(erc20Manager).getTokenAddressBySymbol(_symbol) == 0)
            return _emitError(WALLET_UNKNOWN_TOKEN_TRANSFER);
        if(_symbol == bytes32('ETH')) {
            if(this.balance < _value) {
                return _emitError(WALLET_INSUFFICIENT_BALANCE);
            }
        }
        else {
            address token = ERC20Manager(erc20Manager).getTokenAddressBySymbol(_symbol);
            if(ERC20Interface(token).balanceOf(this) < _value)
                return _emitError(WALLET_INSUFFICIENT_BALANCE);
        }
        // determine our operation hash.
        bytes32 _r = sha3(msg.data, block.number);
        uint status = confirm(_r);
        if (!(status == OK) && (m_txs[_r].to == 0)) {
            m_txs[_r].to = _to;
            m_txs[_r].value = _value;
            m_txs[_r].symbol = _symbol;
            ConfirmationNeeded(_r, msg.sender, _value, _to, _symbol);
            return status;
        }
        return _emitError(WALLET_TRANSFER_ALREADY_REGISTERED);
    }

    // confirm a transaction through just the hash. we use the previous transactions map, m_txs, in order
    // to determine the body of the transaction from the hash provided.
    function confirm(bytes32 _h) returns (uint) {
        uint e = confirmAndCheck(_h);
        if(OK != e) {
            return e;
        }
        if (m_txs[_h].to != 0) {
            if(m_txs[_h].symbol == bytes32('ETH')) {
                require(m_txs[_h].to.send(m_txs[_h].value));
            }
            else {
                address erc20Manager = ContractsManager(contractsManager).getContractAddressByType(bytes32("ERC20Manager"));
                address token = ERC20Manager(erc20Manager).getTokenAddressBySymbol(m_txs[_h].symbol);
                ERC20Interface(token).transfer(m_txs[_h].to,m_txs[_h].value);
            }
            MultiTransact(msg.sender, _h, m_txs[_h].value, m_txs[_h].to, m_txs[_h].symbol);
            delete m_txs[_h];
            return OK;
        }
    }

    // INTERNAL METHODS

    function clearPending() internal {
        uint length = m_pendingIndex.length;
        for (uint i = 0; i < length; ++i)
            delete m_txs[m_pendingIndex[i]];
        super.clearPending();
    }

	// FIELDS

    // pending transactions we have at present.
    mapping (bytes32 => Transaction) m_txs;
    bytes32 public name;
}
