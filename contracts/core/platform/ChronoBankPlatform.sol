pragma solidity ^0.4.11;

import "../common/Object.sol";
import "./ChronoBankPlatformEmitter.sol";
import "../lib/SafeMath.sol";

contract ProxyEventsEmitter {
    function emitTransfer(address _from, address _to, uint _value);
    function emitApprove(address _from, address _spender, uint _value);
}

/**
 * @title ChronoBank Platform.
 *
 * The official ChronoBank assets platform powering TIME and LHT tokens, and possibly
 * other unknown tokens needed later.
 * Platform uses MultiEventsHistory contract to keep events, so that in case it needs to be redeployed
 * at some point, all the events keep appearing at the same place.
 *
 * Every asset is meant to be used through a proxy contract. Only one proxy contract have access
 * rights for a particular asset.
 *
 * Features: transfers, allowances, supply adjustments, lost wallet access recovery.
 *
 * Note: all the non constant functions return false instead of throwing in case if state change
 * didn't happen yet.
 */
contract ChronoBankPlatform is Object, ChronoBankPlatformEmitter {
    using SafeMath for uint;

    uint constant CHRONOBANK_PLATFORM_SCOPE = 15000;
    uint constant CHRONOBANK_PLATFORM_PROXY_ALREADY_EXISTS = CHRONOBANK_PLATFORM_SCOPE + 0;
    uint constant CHRONOBANK_PLATFORM_CANNOT_APPLY_TO_ONESELF = CHRONOBANK_PLATFORM_SCOPE + 1;
    uint constant CHRONOBANK_PLATFORM_INVALID_VALUE = CHRONOBANK_PLATFORM_SCOPE + 2;
    uint constant CHRONOBANK_PLATFORM_INSUFFICIENT_BALANCE = CHRONOBANK_PLATFORM_SCOPE + 3;
    uint constant CHRONOBANK_PLATFORM_NOT_ENOUGH_ALLOWANCE = CHRONOBANK_PLATFORM_SCOPE + 4;
    uint constant CHRONOBANK_PLATFORM_ASSET_ALREADY_ISSUED = CHRONOBANK_PLATFORM_SCOPE + 5;
    uint constant CHRONOBANK_PLATFORM_CANNOT_ISSUE_FIXED_ASSET_WITH_INVALID_VALUE = CHRONOBANK_PLATFORM_SCOPE + 6;
    uint constant CHRONOBANK_PLATFORM_CANNOT_REISSUE_FIXED_ASSET = CHRONOBANK_PLATFORM_SCOPE + 7;
    uint constant CHRONOBANK_PLATFORM_SUPPLY_OVERFLOW = CHRONOBANK_PLATFORM_SCOPE + 8;
    uint constant CHRONOBANK_PLATFORM_NOT_ENOUGH_TOKENS = CHRONOBANK_PLATFORM_SCOPE + 9;
    uint constant CHRONOBANK_PLATFORM_INVALID_NEW_OWNER = CHRONOBANK_PLATFORM_SCOPE + 10;
    uint constant CHRONOBANK_PLATFORM_ALREADY_TRUSTED = CHRONOBANK_PLATFORM_SCOPE + 11;
    uint constant CHRONOBANK_PLATFORM_SHOULD_RECOVER_TO_NEW_ADDRESS = CHRONOBANK_PLATFORM_SCOPE + 12;
    uint constant CHRONOBANK_PLATFORM_ASSET_IS_NOT_ISSUED = CHRONOBANK_PLATFORM_SCOPE + 13;
    uint constant CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_OWNER = CHRONOBANK_PLATFORM_SCOPE + 14;
    uint constant CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_PROXY = CHRONOBANK_PLATFORM_SCOPE + 15;
    uint constant CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_TRUSTED = CHRONOBANK_PLATFORM_SCOPE + 16;
    uint constant CHRONOBANK_PLATFORM_INVALID_INVOCATION = CHRONOBANK_PLATFORM_SCOPE + 17;

    // Structure of a particular asset.
    struct Asset {
        uint owner;                       // Asset's owner id.
        uint totalSupply;                 // Asset's total supply.
        string name;                      // Asset's name, for information purposes.
        string description;               // Asset's description, for information purposes.
        bool isReissuable;                // Indicates if asset have dynamic or fixed supply.
        uint8 baseUnit;                   // Proposed number of decimals.
        mapping(uint => Wallet) wallets;  // Holders wallets.
        mapping(uint => bool) partowners; // Part-owners of an asset; have less access rights than owner
    }

    // Structure of an asset holder wallet for particular asset.
    struct Wallet {
        uint balance;
        mapping(uint => uint) allowance;
    }

    // Structure of an asset holder.
    struct Holder {
        address addr;                    // Current address of the holder.
        mapping(address => bool) trust;  // Addresses that are trusted with recovery proocedure.
    }

    // Iterable mapping pattern is used for holders.
    uint public holdersCount;
    mapping(uint => Holder) public holders;

    // This is an access address mapping. Many addresses may have access to a single holder.
    mapping(address => uint) holderIndex;

    // List of symbols that exist in a platform
    bytes32[] public symbols;

    // Asset symbol to asset mapping.
    mapping(bytes32 => Asset) public assets;

    // Asset symbol to asset proxy mapping.
    mapping(bytes32 => address) public proxies;

    /** Co-owners of a platform. Has less access rights than a root contract owner */
    mapping(address => bool) public partowners;

    // Should use interface of the emitter, but address of events history.
    address public eventsHistory;

    /**
     * Emits Error event with specified error message.
     *
     * Should only be used if no state changes happened.
     *
     * @param _errorCode code of an error
     * @param _message error message.
     */
    function _error(uint _errorCode, bytes32 _message) internal returns(uint) {
        ChronoBankPlatformEmitter(eventsHistory).emitError(_message);
        return _errorCode;
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
    function setupEventsHistory(address _eventsHistory) returns(uint errorCode) {
        errorCode = checkOnlyContractOwner();
        if (errorCode != OK) {
            return errorCode;
        }
        if (eventsHistory != 0x0 && eventsHistory != _eventsHistory) {
            return CHRONOBANK_PLATFORM_INVALID_INVOCATION;
        }
        eventsHistory = _eventsHistory;
        return OK;
    }

    /**
     * Emits Error if called not by asset owner.
     */
    modifier onlyOwner(bytes32 _symbol) {
        if (checkIsOnlyOwner(_symbol) == OK) {
            _;
        }
    }

    /**
     * Emits Error if called not by asset proxy.
     */
    modifier onlyProxy(bytes32 _symbol) {
        if (checkIsOnlyProxy(_symbol) == OK) {
            _;
        }
    }

    /**
     * Emits Error if _from doesn't trust _to.
     */
    modifier checkTrust(address _from, address _to) {
        if (shouldBeTrusted(_from, _to) == OK) {
            _;
        }
    }

    function checkIsOnlyOwner(bytes32 _symbol) internal constant returns(uint errorCode) {
        if (isOwner(msg.sender, _symbol)) {
            return OK;
        }
        return _error(CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_OWNER, "Only owner: access denied");
    }

    function checkIsOnlyOneOfOwners(bytes32 _symbol) internal constant returns (uint errorCode) {
        if (hasAssetRights(msg.sender, _symbol)) {
            return OK;
        }
        return _error(CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_OWNER, "Only owners: access denied");
    }

    function checkIsOnlyProxy(bytes32 _symbol) internal constant returns(uint errorCode) {
        if (proxies[_symbol] == msg.sender) {
            return OK;
        }
        return _error(CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_PROXY, "Only proxy: access denied");
    }

    function shouldBeTrusted(address _from, address _to) internal constant returns(uint errorCode) {
        if (isTrusted(_from, _to)) {
            return OK;
        }
        return _error(CHRONOBANK_PLATFORM_ACCESS_DENIED_ONLY_TRUSTED, "Only trusted: access denied");
    }

    function checkOnlyOneOfContractOwners() internal constant returns (uint errorCode) {
        errorCode = checkOnlyContractOwner();
        if (errorCode == OK || partowners[msg.sender]) {
            return OK;
        }
    }

    /**
    * Adds a co-owner of a contract. Might be more than one co-owner
    * @dev Allowed to only contract onwer
    *
    * @param _partowner a co-owner of a contract
    *
    * @return result code of an operation
    */
    function addPartOwner(address _partowner) onlyContractOwner returns (uint) {
        partowners[_partowner] = true;
        return OK;
    }

    /**
    * Removes a co-owner of a contract
    * @dev Should be performed only by root contract owner
    *
    * @param _partowner a co-owner of a contract
    *
    * @return result code of an operation
    */
    function removePartOwner(address _partowner) onlyContractOwner returns (uint) {
        delete partowners[_partowner];
        return OK;
    }

    /**
    * Provides a cheap way to get number of symbols registered in a platform
    *
    * @return number of symbols
    */
    function symbolsCount() public constant returns (uint) {
        return symbols.length;
    }

    /**
     * Check asset existance.
     *
     * @param _symbol asset symbol.
     *
     * @return asset existance.
     */
    function isCreated(bytes32 _symbol) constant returns(bool) {
        return assets[_symbol].owner != 0;
    }

    /**
     * Returns asset decimals.
     *
     * @param _symbol asset symbol.
     *
     * @return asset decimals.
     */
    function baseUnit(bytes32 _symbol) constant returns(uint8) {
        return assets[_symbol].baseUnit;
    }

    /**
     * Returns asset name.
     *
     * @param _symbol asset symbol.
     *
     * @return asset name.
     */
    function name(bytes32 _symbol) constant returns(string) {
        return assets[_symbol].name;
    }

    /**
     * Returns asset description.
     *
     * @param _symbol asset symbol.
     *
     * @return asset description.
     */
    function description(bytes32 _symbol) constant returns(string) {
        return assets[_symbol].description;
    }

    /**
     * Returns asset reissuability.
     *
     * @param _symbol asset symbol.
     *
     * @return asset reissuability.
     */
    function isReissuable(bytes32 _symbol) constant returns(bool) {
        return assets[_symbol].isReissuable;
    }

    /**
     * Returns asset owner address.
     *
     * @param _symbol asset symbol.
     *
     * @return asset owner address.
     */
    function owner(bytes32 _symbol) constant returns(address) {
        return holders[assets[_symbol].owner].addr;
    }

    /**
     * Check if specified address has asset owner rights.
     *
     * @param _owner address to check.
     * @param _symbol asset symbol.
     *
     * @return owner rights availability.
     */
    function isOwner(address _owner, bytes32 _symbol) constant returns(bool) {
        return isCreated(_symbol) && (assets[_symbol].owner == getHolderId(_owner));
    }

    /**
    * Checks if a specified address has asset owner or co-owner rights.
    *
    * @param _owner address to check.
    * @param _symbol asset symbol.
    *
    * @return owner rights availability.
    */
    function hasAssetRights(address _owner, bytes32 _symbol) constant returns (bool) {
        uint holderId = getHolderId(_owner);
        return isCreated(_symbol) && (assets[_symbol].owner == holderId || assets[_symbol].partowners[holderId]);
    }

    /**
     * Returns asset total supply.
     *
     * @param _symbol asset symbol.
     *
     * @return asset total supply.
     */
    function totalSupply(bytes32 _symbol) constant returns(uint) {
        return assets[_symbol].totalSupply;
    }

    /**
     * Returns asset balance for a particular holder.
     *
     * @param _holder holder address.
     * @param _symbol asset symbol.
     *
     * @return holder balance.
     */
    function balanceOf(address _holder, bytes32 _symbol) constant returns(uint) {
        return _balanceOf(getHolderId(_holder), _symbol);
    }

    /**
     * Returns asset balance for a particular holder id.
     *
     * @param _holderId holder id.
     * @param _symbol asset symbol.
     *
     * @return holder balance.
     */
    function _balanceOf(uint _holderId, bytes32 _symbol) constant returns(uint) {
        return assets[_symbol].wallets[_holderId].balance;
    }

    /**
     * Returns current address for a particular holder id.
     *
     * @param _holderId holder id.
     *
     * @return holder address.
     */
    function _address(uint _holderId) constant returns(address) {
        return holders[_holderId].addr;
    }

    /**
    * Adds a co-owner for an asset with provided symbol.
    * @dev Should be performed by a contract owner or its co-owners
    *
    * @param _symbol asset's symbol
    * @param _partowner a co-owner of an asset
    *
    * @return errorCode result code of an operation
    */
    function addAssetPartOwner(bytes32 _symbol, address _partowner) returns (uint errorCode) {
        errorCode = checkIsOnlyOneOfOwners(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }

        uint holderId = _createHolderId(_partowner);
        assets[_symbol].partowners[holderId] = true;
        return OK;
    }

    /**
    * Removes a co-owner for an asset with provided symbol.
    * @dev Should be performed by a contract owner or its co-owners
    *
    * @param _symbol asset's symbol
    * @param _partowner a co-owner of an asset
    *
    * @return errorCode result code of an operation
    */
    function removeAssetPartOwner(bytes32 _symbol, address _partowner) returns (uint errorCode) {
        errorCode = checkIsOnlyOneOfOwners(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }

        uint holderId = getHolderId(_partowner);
        delete assets[_symbol].partowners[holderId];
        return OK;
    }

    /**
     * Sets Proxy contract address for a particular asset.
     *
     * Can be set only once for each asset, and only by contract owner.
     *
     * @param _address Proxy contract address.
     * @param _symbol asset symbol.
     *
     * @return success.
     */
    function setProxy(address _address, bytes32 _symbol) returns(uint errorCode) {
        errorCode = checkOnlyOneOfContractOwners();
        if (errorCode != OK) {
            return errorCode;
        }

        if (proxies[_symbol] != 0x0) {
            return CHRONOBANK_PLATFORM_PROXY_ALREADY_EXISTS;
        }
        proxies[_symbol] = _address;
        return OK;
    }

    /**
     * Transfers asset balance between holders wallets.
     *
     * @param _fromId holder id to take from.
     * @param _toId holder id to give to.
     * @param _value amount to transfer.
     * @param _symbol asset symbol.
     */
    function _transferDirect(uint _fromId, uint _toId, uint _value, bytes32 _symbol) internal {
        assets[_symbol].wallets[_fromId].balance = assets[_symbol].wallets[_fromId].balance.sub(_value);
        assets[_symbol].wallets[_toId].balance = assets[_symbol].wallets[_toId].balance.add(_value);
    }

    /**
     * Transfers asset balance between holders wallets.
     *
     * Performs sanity checks and takes care of allowances adjustment.
     *
     * @param _fromId holder id to take from.
     * @param _toId holder id to give to.
     * @param _value amount to transfer.
     * @param _symbol asset symbol.
     * @param _reference transfer comment to be included in a Transfer event.
     * @param _senderId transfer initiator holder id.
     *
     * @return success.
     */
    function _transfer(uint _fromId, uint _toId, uint _value, bytes32 _symbol, string _reference, uint _senderId) internal returns(uint) {
        // Should not allow to send to oneself.
        if (_fromId == _toId) {
            return _error(CHRONOBANK_PLATFORM_CANNOT_APPLY_TO_ONESELF, "Cannot send to oneself");
        }
        // Should have positive value.
        if (_value == 0) {
            return _error(CHRONOBANK_PLATFORM_INVALID_VALUE, "Cannot send 0 value");
        }
        // Should have enough balance.
        if (_balanceOf(_fromId, _symbol) < _value) {
            return _error(CHRONOBANK_PLATFORM_INSUFFICIENT_BALANCE, "Insufficient balance");
        }
        // Should have enough allowance.
        if (_fromId != _senderId && _allowance(_fromId, _senderId, _symbol) < _value) {
            return _error(CHRONOBANK_PLATFORM_NOT_ENOUGH_ALLOWANCE, "Not enough allowance");
        }

        _transferDirect(_fromId, _toId, _value, _symbol);
        // Adjust allowance.
        if (_fromId != _senderId) {
            assets[_symbol].wallets[_fromId].allowance[_senderId] = assets[_symbol].wallets[_fromId].allowance[_senderId].sub(_value);
        }
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: n/a after HF 4;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitTransfer(_address(_fromId), _address(_toId), _symbol, _value, _reference);
        _proxyTransferEvent(_fromId, _toId, _value, _symbol);
        return OK;
    }

    /**
     * Transfers asset balance between holders wallets.
     *
     * Can only be called by asset proxy.
     *
     * @param _to holder address to give to.
     * @param _value amount to transfer.
     * @param _symbol asset symbol.
     * @param _reference transfer comment to be included in a Transfer event.
     * @param _sender transfer initiator address.
     *
     * @return success.
     */
    function proxyTransferWithReference(address _to, uint _value, bytes32 _symbol, string _reference, address _sender) returns(uint errorCode) {
        errorCode = checkIsOnlyProxy(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }

        return _transfer(getHolderId(_sender), _createHolderId(_to), _value, _symbol, _reference, getHolderId(_sender));
    }

    /**
     * Ask asset Proxy contract to emit ERC20 compliant Transfer event.
     *
     * @param _fromId holder id to take from.
     * @param _toId holder id to give to.
     * @param _value amount to transfer.
     * @param _symbol asset symbol.
     */
    function _proxyTransferEvent(uint _fromId, uint _toId, uint _value, bytes32 _symbol) internal {
        if (proxies[_symbol] != 0x0) {
            // Internal Out Of Gas/Throw: revert this transaction too;
            // Call Stack Depth Limit reached: n/a after HF 4;
            // Recursive Call: safe, all changes already made.
            ProxyEventsEmitter(proxies[_symbol]).emitTransfer(_address(_fromId), _address(_toId), _value);
        }
    }

    /**
     * Returns holder id for the specified address.
     *
     * @param _holder holder address.
     *
     * @return holder id.
     */
    function getHolderId(address _holder) constant returns(uint) {
        return holderIndex[_holder];
    }

    /**
     * Returns holder id for the specified address, creates it if needed.
     *
     * @param _holder holder address.
     *
     * @return holder id.
     */
    function _createHolderId(address _holder) internal returns(uint) {
        uint holderId = holderIndex[_holder];
        if (holderId == 0) {
            holderId = ++holdersCount;
            holders[holderId].addr = _holder;
            holderIndex[_holder] = holderId;
        }
        return holderId;
    }

    /**
     * Issues new asset token on the platform.
     *
     * Tokens issued with this call go straight to contract owner.
     * Each symbol can be issued only once, and only by contract owner.
     *
     * @param _symbol asset symbol.
     * @param _value amount of tokens to issue immediately.
     * @param _name name of the asset.
     * @param _description description for the asset.
     * @param _baseUnit number of decimals.
     * @param _isReissuable dynamic or fixed supply.
     *
     * @return success.
     */
    function issueAsset(bytes32 _symbol, uint _value, string _name, string _description, uint8 _baseUnit, bool _isReissuable) returns(uint errorCode) {
        errorCode = checkOnlyOneOfContractOwners();
        if (errorCode != OK) {
            return errorCode;
        }
        // Should have positive value if supply is going to be fixed.
        if (_value == 0 && !_isReissuable) {
            return _error(CHRONOBANK_PLATFORM_CANNOT_ISSUE_FIXED_ASSET_WITH_INVALID_VALUE, "Cannot issue 0 value fixed asset");
        }
        // Should not be issued yet.
        if (isCreated(_symbol)) {
            return _error(CHRONOBANK_PLATFORM_ASSET_ALREADY_ISSUED, "Asset already issued");
        }
        uint holderId = _createHolderId(msg.sender);

        symbols.push(_symbol);
        assets[_symbol] = Asset(holderId, _value, _name, _description, _isReissuable, _baseUnit);
        assets[_symbol].wallets[holderId].balance = _value;
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: n/a after HF 4;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitIssue(_symbol, _value, _address(holderId));
        return OK;
    }

    /**
     * Issues additional asset tokens if the asset have dynamic supply.
     *
     * Tokens issued with this call go straight to asset owner.
     * Can only be called by asset owner.
     *
     * @param _symbol asset symbol.
     * @param _value amount of additional tokens to issue.
     *
     * @return success.
     */
    function reissueAsset(bytes32 _symbol, uint _value) returns(uint errorCode) {
        errorCode = checkIsOnlyOneOfOwners(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }
        // Should have positive value.
        if (_value == 0) {
            return _error(CHRONOBANK_PLATFORM_INVALID_VALUE, "Cannot reissue 0 value");
        }
        Asset asset = assets[_symbol];
        // Should have dynamic supply.
        if (!asset.isReissuable) {
            return _error(CHRONOBANK_PLATFORM_CANNOT_REISSUE_FIXED_ASSET, "Cannot reissue fixed asset");
        }
        // Resulting total supply should not overflow.
        if (asset.totalSupply + _value < asset.totalSupply) {
            return _error(CHRONOBANK_PLATFORM_SUPPLY_OVERFLOW, "Total supply overflow");
        }
        uint holderId = getHolderId(msg.sender);
        asset.wallets[holderId].balance = asset.wallets[holderId].balance.add(_value);
        asset.totalSupply = asset.totalSupply.add(_value);
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: n/a after HF 4;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitIssue(_symbol, _value, _address(holderId));
        _proxyTransferEvent(0, holderId, _value, _symbol);
        return OK;
    }

    /**
     * Destroys specified amount of senders asset tokens.
     *
     * @param _symbol asset symbol.
     * @param _value amount of tokens to destroy.
     *
     * @return success.
     */
    function revokeAsset(bytes32 _symbol, uint _value) returns(uint) {
        // Should have positive value.
        if (_value == 0) {
            return _error(CHRONOBANK_PLATFORM_INVALID_VALUE, "Cannot revoke 0 value");
        }
        Asset asset = assets[_symbol];
        uint holderId = getHolderId(msg.sender);
        // Should have enough tokens.
        if (asset.wallets[holderId].balance < _value) {
            return _error(CHRONOBANK_PLATFORM_NOT_ENOUGH_TOKENS, "Not enough tokens to revoke");
        }
        asset.wallets[holderId].balance = asset.wallets[holderId].balance.sub(_value);
        asset.totalSupply = asset.totalSupply.sub(_value);
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: n/a after HF 4;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitRevoke(_symbol, _value, _address(holderId));
        _proxyTransferEvent(holderId, 0, _value, _symbol);
        return OK;
    }

    /**
     * Passes asset ownership to specified address.
     *
     * Only ownership is changed, balances are not touched.
     * Can only be called by asset owner.
     *
     * @param _symbol asset symbol.
     * @param _newOwner address to become a new owner.
     *
     * @return success.
     */
    function changeOwnership(bytes32 _symbol, address _newOwner) returns(uint errorCode) {
        errorCode = checkIsOnlyOwner(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }

        if (_newOwner == 0x0) {
            return _error(CHRONOBANK_PLATFORM_INVALID_NEW_OWNER, "Can't change ownership to 0x0");
        }

        Asset asset = assets[_symbol];
        uint newOwnerId = _createHolderId(_newOwner);
        // Should pass ownership to another holder.
        if (asset.owner == newOwnerId) {
            return _error(CHRONOBANK_PLATFORM_CANNOT_APPLY_TO_ONESELF, "Cannot pass ownership to oneself");
        }
        address oldOwner = _address(asset.owner);
        asset.owner = newOwnerId;
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: n/a after HF 4;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitOwnershipChange(oldOwner, _newOwner, _symbol);
        return OK;
    }

    /**
     * Check if specified holder trusts an address with recovery procedure.
     *
     * @param _from truster.
     * @param _to trustee.
     *
     * @return trust existance.
     */
    function isTrusted(address _from, address _to) constant returns(bool) {
        return holders[getHolderId(_from)].trust[_to];
    }

    /**
     * Trust an address to perform recovery procedure for the caller.
     *
     * @param _to trustee.
     *
     * @return success.
     */
    function trust(address _to) returns(uint) {
        uint fromId = _createHolderId(msg.sender);
        // Should trust to another address.
        if (fromId == getHolderId(_to)) {
            return _error(CHRONOBANK_PLATFORM_CANNOT_APPLY_TO_ONESELF, "Cannot trust to oneself");
        }
        // Should trust to yet untrusted.
        if (isTrusted(msg.sender, _to)) {
            return _error(CHRONOBANK_PLATFORM_ALREADY_TRUSTED, "Already trusted");
        }

        holders[fromId].trust[_to] = true;
        return OK;
    }

    /**
     * Revoke trust to perform recovery procedure from an address.
     *
     * @param _to trustee.
     *
     * @return success.
     */
    function distrust(address _to) returns(uint errorCode) {
        errorCode = shouldBeTrusted(msg.sender, _to);
        if (errorCode != OK) {
            return errorCode;
        }
        holders[getHolderId(msg.sender)].trust[_to] = false;
        return OK;
    }

    /**
     * Perform recovery procedure.
     *
     * This function logic is actually more of an addAccess(uint _holderId, address _to).
     * It grants another address access to recovery subject wallets.
     * Can only be called by trustee of recovery subject.
     *
     * @param _from holder address to recover from.
     * @param _to address to grant access to.
     *
     * @return success.
     */
    function recover(address _from, address _to) returns(uint errorCode) {
        errorCode = shouldBeTrusted(_from, msg.sender);
        if (errorCode != OK) {
            return errorCode;
        }
        // Should recover to previously unused address.
        if (getHolderId(_to) != 0) {
            return _error(CHRONOBANK_PLATFORM_SHOULD_RECOVER_TO_NEW_ADDRESS, "Should recover to new address");
        }
        // We take current holder address because it might not equal _from.
        // It is possible to recover from any old holder address, but event should have the current one.
        address from = holders[getHolderId(_from)].addr;
        holders[getHolderId(_from)].addr = _to;
        holderIndex[_to] = getHolderId(_from);
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: revert this transaction too;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitRecovery(from, _to, msg.sender);
        return OK;
    }

    /**
     * Sets asset spending allowance for a specified spender.
     *
     * Note: to revoke allowance, one needs to set allowance to 0.
     *
     * @param _spenderId holder id to set allowance for.
     * @param _value amount to allow.
     * @param _symbol asset symbol.
     * @param _senderId approve initiator holder id.
     *
     * @return success.
     */
    function _approve(uint _spenderId, uint _value, bytes32 _symbol, uint _senderId) internal returns(uint) {
        // Asset should exist.
        if (!isCreated(_symbol)) {
            return _error(CHRONOBANK_PLATFORM_ASSET_IS_NOT_ISSUED, "Asset is not issued");
        }
        // Should allow to another holder.
        if (_senderId == _spenderId) {
            return _error(CHRONOBANK_PLATFORM_CANNOT_APPLY_TO_ONESELF, "Cannot approve to oneself");
        }
        assets[_symbol].wallets[_senderId].allowance[_spenderId] = _value;
        // Internal Out Of Gas/Throw: revert this transaction too;
        // Call Stack Depth Limit reached: revert this transaction too;
        // Recursive Call: safe, all changes already made.
        ChronoBankPlatformEmitter(eventsHistory).emitApprove(_address(_senderId), _address(_spenderId), _symbol, _value);
        if (proxies[_symbol] != 0x0) {
            // Internal Out Of Gas/Throw: revert this transaction too;
            // Call Stack Depth Limit reached: n/a after HF 4;
            // Recursive Call: safe, all changes already made.
            ProxyEventsEmitter(proxies[_symbol]).emitApprove(_address(_senderId), _address(_spenderId), _value);
        }
        return OK;
    }

    /**
     * Sets asset spending allowance for a specified spender.
     *
     * Can only be called by asset proxy.
     *
     * @param _spender holder address to set allowance to.
     * @param _value amount to allow.
     * @param _symbol asset symbol.
     * @param _sender approve initiator address.
     *
     * @return success.
     */
    function proxyApprove(address _spender, uint _value, bytes32 _symbol, address _sender) returns(uint errorCode) {
        errorCode = checkIsOnlyProxy(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }
        return _approve(_createHolderId(_spender), _value, _symbol, _createHolderId(_sender));
    }

    /**
     * Returns asset allowance from one holder to another.
     *
     * @param _from holder that allowed spending.
     * @param _spender holder that is allowed to spend.
     * @param _symbol asset symbol.
     *
     * @return holder to spender allowance.
     */
    function allowance(address _from, address _spender, bytes32 _symbol) constant returns(uint) {
        return _allowance(getHolderId(_from), getHolderId(_spender), _symbol);
    }

    /**
     * Returns asset allowance from one holder to another.
     *
     * @param _fromId holder id that allowed spending.
     * @param _toId holder id that is allowed to spend.
     * @param _symbol asset symbol.
     *
     * @return holder to spender allowance.
     */
    function _allowance(uint _fromId, uint _toId, bytes32 _symbol) constant internal returns(uint) {
        return assets[_symbol].wallets[_fromId].allowance[_toId];
    }

    /**
     * Prforms allowance transfer of asset balance between holders wallets.
     *
     * Can only be called by asset proxy.
     *
     * @param _from holder address to take from.
     * @param _to holder address to give to.
     * @param _value amount to transfer.
     * @param _symbol asset symbol.
     * @param _reference transfer comment to be included in a Transfer event.
     * @param _sender allowance transfer initiator address.
     *
     * @return success.
     */
    function proxyTransferFromWithReference(address _from, address _to, uint _value, bytes32 _symbol, string _reference, address _sender) returns(uint errorCode) {
        errorCode = checkIsOnlyProxy(_symbol);
        if (errorCode != OK) {
            return errorCode;
        }
        return _transfer(getHolderId(_from), _createHolderId(_to), _value, _symbol, _reference, getHolderId(_sender));
    }
}
