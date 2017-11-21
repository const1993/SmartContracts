pragma solidity ^0.4.11;

import "../../core/contracts/ContractsManagerInterface.sol";
import "../../core/user/UserManagerInterface.sol";
import "../../timeholder/TimeHolderInterface.sol";
import "../../pending/MultiSigSupporter.sol";
import "../../core/lib/SafeMath.sol";
import "../../core/lib/ArrayLib.sol";
import "./VotingManagerInterface.sol";
import "./PollEntityEmitter.sol";

/**
* @title Backend contract is created to reduce size of poll contract and transfer all logic
* and operations (where it's possible) on a shoulders of this contract. This contract could
* be updatable through by publishing new poll factory.

* It is not supposed to be registered in ContractsManager.
*/
contract PollEntityBackend is MultiSigSupporter {

    using SafeMath for uint;


    /** Constants */

    uint8 constant OPTIONS_POLLS_MAX = 16;
    uint8 constant IPFS_HASH_POLLS_MAX = 5;


    /** Error codes */

    uint constant UNAUTHORIZED = 0;
    uint constant REINITIALIZED = 6;
    uint constant ERROR_POLL_BACKEND_INVALID_INVOCATION = 26001;
    uint constant ERROR_POLL_BACKEND_NO_SHARES = 26002;
    uint constant ERROR_POLL_BACKEND_INVALID_PARAMETER = 26003;


    /**
    * Storage variables. Duplicates @see PollEntityRouter storage layout so
    * DO NOT CHANGE VARIABLES' LAYOUT UNDER ANY CIRCUMSTANCES!
    */

    address internal backendAddress;
    address internal contractsManager;

    address internal owner;
    bytes32 internal detailsIpfsHash;
    uint internal votelimit;
    uint internal deadline;
    uint internal creation;
    bool internal active;
    bool internal status;
    bytes32[] internal options;
    bytes32[] internal ipfsHashes;

    mapping(address => uint8) internal memberOptions;
    mapping(address => uint) internal memberVotes;
    mapping(uint8 => uint) internal optionsBalance;

    /**
     * @dev Contract owner address
     */
    address public contractOwner;

    /**
     * @dev Contract owner address
     */
    address public pendingContractOwner;


    /** Modifiers */

    /**
    * @dev Owner check modifier
    */
    modifier onlyContractOwner {
        if (contractOwner == msg.sender) {
            _;
        }
    }

    /**
    * @dev Guards invocations to an uninialized poll
    */
    modifier onlyInitializedPoll {
        if (owner != 0x0) {
            _;
        }
    }

    /**
    * @dev Guards invocations only for poll's owners
    */
    modifier onlyPollOwner {
        if (owner == msg.sender) {
            _;
        }
    }

    /**
    * @dev Guards invocations only for VotingManager
    */
    modifier onlyVotingManager {
        if (msg.sender == lookupManager("VotingManager")) {
            _;
        }
    }

    /**
    * @dev Guards invocations only for authorized (CBE) accounts
    */
    modifier onlyAuthorized {
        if (isAuthorized(msg.sender)) {
            _;
        }
    }


    /** PUBLIC section */

    function PollEntityBackend() public {
        contractOwner = msg.sender;
    }

    /**
    *  @dev Initializes internal fields.
    *  Will rollback transaction if something goes wrong during initialization.
    *
    *  @param _contractsManager is contract manager, must be not 0x0
    *
    *  @return OK if newly initialized and everything is OK,
    *  or REINITIALIZED if storage already contains some data. Will crash in any other cases.
    */
    function init(address _contractsManager) onlyContractOwner public returns (uint) {
        require(_contractsManager != 0x0);

        bool reinitialized = (contractsManager != 0x0);
        if (contractsManager == 0x0 || contractsManager != _contractsManager) {
            contractsManager = _contractsManager;
        }

        return !reinitialized ? OK : REINITIALIZED;
    }

    /**
     * @dev Destroy contract and scrub a data
     * @notice Only owner can call it
     */
    function destroy() onlyContractOwner public {
        selfdestruct(msg.sender);
    }

    /**
     * @dev Prepares ownership pass.
     * @notice Can only be called by current owner.
     *
     * @param _to address of the next owner. 0x0 is not allowed.
     *
     * @return success.
     */
    function changeContractOwnership(address _to) onlyContractOwner public returns (bool) {
        if (_to == 0x0) {
            return false;
        }

        pendingContractOwner = _to;
        return true;
    }

    /**
     * @dev Finalize ownership pass.
     * @notice Can only be called by pending owner.
     *
     * @return success.
     */
    function claimContractOwnership() public returns (bool) {
        if (pendingContractOwner != msg.sender) {
            return false;
        }

        contractOwner = pendingContractOwner;
        delete pendingContractOwner;

        return true;
    }

    /**
    * @dev Direct ownership pass without change/claim pattern.
    * @notice Can be invoked only by current contract owner
    *
    * @param _to the next contract owner
    *
    * @return `true` if success, `false` otherwise
    */
    function transferContractOwnership(address _to) onlyContractOwner public returns (bool) {
        if (_to == 0x0) {
            return false;
        }

        if (pendingContractOwner != 0x0) {
            pendingContractOwner = 0x0;
        }

        contractOwner = _to;
        return true;
    }

    /**
    * @dev Returns if _address is authorized (CBE)
    *
    * @return `true` if access is allowed, `false` otherwise
    */
    function isAuthorized(address _key) public constant returns (bool) {
        address userManager = lookupManager("UserManager");
        return UserManagerInterface(userManager).getCBE(_key);
    }

    /**
    * @dev Gets eventsHistory for the manager
    *
    * @return address of eventsHistory
    */
    function getEventsHistory() public constant returns (address) {
        return lookupManager("MultiEventsHistory");
    }

    /**
    * @dev Checks if a user is participating in the poll
    * @notice delegatecall only.
    *
    * @param _user address of a user to Checks
    *
    * @return `true` if a participant of a poll, `false` otherwise
    */
    function hasMember(address _user) onlyInitializedPoll public constant returns (bool) {
        return memberOptions[_user] != 0;
    }

    /**
    * @dev Gets vote limit for a poll. Actually shows the value from associated VotingManager
    *
    * @return vote limit value
    */
    function getVoteLimit() public constant returns (uint) {
        return VotingManagerInterface(lookupManager("VotingManager")).getVoteLimit();
    }

    /**
    * @dev Performs a vote of caller with provided choice. When a required balance for an option will reach
    * votelimit value then poll automatically ends.
    * @notice delegatecall only. Should be called by only those contracts that have balance in TimeHolder.
    *
    * @param _choice picked option value by user. Should be between 1 and number of options in a poll
    *
    * @return _resultCode result code of an operation. Returns ERROR_POLL_BACKEND_NO_SHARES if
    * a balance in TimeHolder for the user is equal to zero.
    */
    function vote(uint8 _choice) onlyInitializedPoll public returns (uint _resultCode) {
        require(_choice > 0 && _choice <= ArrayLib.nonEmptyLengthOfArray(options));
        require(status == true);
        require(active);
        require(memberOptions[msg.sender] == 0);

        address timeHolder = lookupManager("TimeHolder");
        uint balance = TimeHolderInterface(timeHolder).depositBalance(msg.sender);

        if (balance == 0) {
            return _emitError(ERROR_POLL_BACKEND_NO_SHARES);
        }

        address votingManager = lookupManager("VotingManager");
        _resultCode = VotingManagerInterface(votingManager).vote(address(this), _choice);
        if (_resultCode != OK) {
            return _emitError(_resultCode);
        }

        uint optionsValue = optionsBalance[_choice].add(balance);
        optionsBalance[_choice] = optionsValue;
        memberVotes[msg.sender] = balance;
        memberOptions[msg.sender] = _choice;

        if (_isReadyToEndPoll(optionsValue)) {
            _endPoll();
        }

        return OK;
    }

    /**
    * @dev Activates poll so users could vote and no more changes can be made.
    * @notice delegatecall only. Multisignature required
    *
    * @return _resultCode result code of an operation.
    */
    function activatePoll() onlyInitializedPoll public returns (uint _resultCode) {
        require(status == true);
        require(ArrayLib.nonEmptyLengthOfArray(options) >= 2);

        _resultCode = multisig();
        if (_resultCode != OK) {
            return _checkAndEmitError(_resultCode);
        }

        _resultCode = VotingManagerInterface(lookupManager("VotingManager")).activatePoll();
        if (_resultCode != OK) {
            return _emitError(_resultCode);
        }

        active = true;
        return OK;
    }

    /**
    * @dev Ends poll so after that users couldn't vote anymore.
    * @notice delegatecall only. Multisignature required
    *
    * @return _resultCode result code of an operation.
    */
    function endPoll() onlyInitializedPoll public returns (uint _resultCode) {
        require(status == true);

        _resultCode = multisig();
        if (OK != _resultCode) {
            return _checkAndEmitError(_resultCode);
        }

        return _endPoll();
    }

    /**
    * @dev Erases poll from records. Should be called before activation or after poll completion.
    * Couldn't be invoked in the middle of voting.
    * @notice delegatecall only. Authorized contracts only.
    *
    * @return _resultCode result code of an operation.
    */
    function killPoll() onlyInitializedPoll onlyAuthorized public returns (uint) {
        require(!active || status == false);

        return _killPoll();
    }

    /**
    * @dev Changes details hash with a new version. Should be called before poll will be activated
    * Emits PollDetailsHashUpdated event
    * @notice delegatecall only. poll owner only
    *
    * @param _detailsIpfsHash updated ipfs hash value
    *
    * @return result code of an operation.
    */
    function updatePollDetailsIpfsHash(bytes32 _detailsIpfsHash) onlyInitializedPoll onlyPollOwner public returns (uint) {
        require(_detailsIpfsHash != bytes32(0));
        require((!active) && (status == true));

        if (_detailsIpfsHash != detailsIpfsHash) {
            detailsIpfsHash = _detailsIpfsHash;
        }

        PollEntityEmitter(getEventsHistory()).emitPollDetailsHashUpdated(_detailsIpfsHash);
        return OK;
    }

    /**
    * @dev Adds an option to a poll. Should be called before poll will be activated.
    * Number of options couldn't be more than OPTIONS_POLLS_MAX value.
    * Emits PollDetailsOptionAdded event.
    * @notice delegatecall only. poll owner only
    *
    * @param _option a new option
    *
    * @return result code of an operation. Returns ERROR_POLL_BACKEND_INVALID_PARAMETER if
    * provided option was already added to this poll.
    */
    function addPollOption(bytes32 _option) onlyInitializedPoll onlyPollOwner public returns (uint) {
        require(_option != bytes32(0));
        require((!active) && (status == true));
        uint _count = ArrayLib.nonEmptyLengthOfArray(options);
        require(_count < OPTIONS_POLLS_MAX);

        if (ArrayLib.arrayIncludes(options, _option)) {
            return _emitError(ERROR_POLL_BACKEND_INVALID_PARAMETER);
        }

        ArrayLib.addToArray(options, _option);
        PollEntityEmitter(getEventsHistory()).emitPollDetailsOptionAdded(_option, _count + 1);
        return OK;
    }

    /**
    * @dev Removes an option to a poll. Should be called before poll will be activated
    * Emits PollDetailsOptionRemoved event.
    * @notice delegatecall only. poll owner only
    *
    * @param _option an existed option
    *
    * @return result code of an operation. Returns ERROR_POLL_BACKEND_INVALID_PARAMETER if
    * provided option was already removed and doesn't exist anymore.
    */
    function removePollOption(bytes32 _option) onlyInitializedPoll onlyPollOwner public returns (uint) {
        require(_option != bytes32(0));
        require((!active) && (status == true));

        if (!ArrayLib.arrayIncludes(options, _option)) {
            return _emitError(ERROR_POLL_BACKEND_INVALID_PARAMETER);
        }

        ArrayLib.removeFirstFromArray(options, _option);
        PollEntityEmitter(getEventsHistory()).emitPollDetailsOptionRemoved(_option, ArrayLib.nonEmptyLengthOfArray(options));
        return OK;
    }

    /**
    * @dev Adds an ipfs hash to a poll. Should be called before poll will be activated.
    * Number of options couldn't be more than IPFS_HASH_POLLS_MAX value.
    * Emits PollDetailsIpfsHashAdded event.
    * @notice delegatecall only. poll owner only
    *
    * @param _hash a new ipfs hash
    *
    * @return result code of an operation. Returns ERROR_POLL_BACKEND_INVALID_PARAMETER if
    * provided hash was already added to this poll.
    */
    function addPollIpfsHash(bytes32 _hash) onlyInitializedPoll onlyPollOwner public returns (uint) {
        require(_hash != bytes32(0));
        require((!active) && (status == true));
        uint _count = ArrayLib.nonEmptyLengthOfArray(ipfsHashes);
        require(_count < IPFS_HASH_POLLS_MAX);

        if (ArrayLib.arrayIncludes(ipfsHashes, _hash)) {
            return _emitError(ERROR_POLL_BACKEND_INVALID_PARAMETER);
        }

        ArrayLib.addToArray(ipfsHashes, _hash);
        PollEntityEmitter(getEventsHistory()).emitPollDetailsIpfsHashAdded(_hash, _count + 1);
        return OK;
    }

    /**
    * @dev Removes an option to a poll. Should be called before poll will be activated
    * Emits PollDetailsIpfsHashRemoved event.
    * @notice delegatecall only. poll owner only
    *
    * @param _hash an existed ipfs hash
    *
    * @return result code of an operation. Returns ERROR_POLL_BACKEND_INVALID_PARAMETER if
    * provided hash was already removed and doesn't exist anymore.
    */
    function removePollIpfsHash(bytes32 _hash) onlyInitializedPoll onlyPollOwner public returns (uint) {
        require(_hash != bytes32(0));
        require((!active) && (status == true));

        if (!ArrayLib.arrayIncludes(ipfsHashes, _hash)) {
            return _emitError(ERROR_POLL_BACKEND_INVALID_PARAMETER);
        }

        ArrayLib.removeFirstFromArray(ipfsHashes, _hash);
        PollEntityEmitter(getEventsHistory()).emitPollDetailsIpfsHashRemoved(_hash, ArrayLib.nonEmptyLengthOfArray(ipfsHashes));
        return OK;
    }


    /** ListenerInterface interface */

    /**
    * @dev Implements deposit method and receives calls from TimeHolder. Updates poll according to changes
    * made with balance and adds value to a member chosen option.
    * In case if were deposited enough amount to end a poll it will be ended automatically. Make sence only
    * for active poll
    * @notice initialized poll only. VotingManager only
    *
    * @param _address address for which changes are made
    * @param _amount a value of change
    * @param _total total amount of tokens on _address's balance
    *
    * @return result code of an operation
    */
    function deposit(address _address, uint _amount, uint _total) onlyInitializedPoll onlyVotingManager public returns (uint) {
        if (!hasMember(_address)) return UNAUTHORIZED;

        if (status && active) {
            uint8 _choice = memberOptions[_address];
            uint _value = optionsBalance[_choice];
            _value = _value.add(_amount);
            memberVotes[_address] = _total;
            optionsBalance[_choice] = _value;
        }

        if (_isReadyToEndPoll(_value)) {
            _endPoll();
        }

        return OK;
    }

    /**
    * @dev Implements withdrawn method and receives calls from TimeHolder. Updates poll according to changes
    * made with balance and removes value from a member's chosen option.
    * In case if _total value is equal to `0` then _address has no more rights to vote and his choice is reset.
    * @notice initialized poll only. VotingManager only
    *
    * @param _address address for which changes are made
    * @param _amount a value of change
    * @param _total total amount of tokens on _address's balance
    *
    * @return result code of an operation
    */
    function withdrawn(address _address, uint _amount, uint _total) onlyInitializedPoll onlyVotingManager public returns (uint) {
        if (!hasMember(_address)) return UNAUTHORIZED;

        if (status && active) {
            uint8 _choice = memberOptions[_address];
            uint _value = optionsBalance[_choice];
            _value = _value.sub(_amount);
            memberVotes[_address] = _total;
            optionsBalance[_choice] = _value;

            if (_total == 0) {
                delete memberOptions[_address];
            }
        }

        return OK;
    }

    /**
    * @dev Makes search in contractsManager for registered contract by some identifier
    *
    * @param _identifier string identifier of a manager
    *
    * @return manager address of a manager, 0x0 if nothing was found
    */
    function lookupManager(bytes32 _identifier) constant returns (address manager) {
        manager = ContractsManagerInterface(contractsManager).getContractAddressByType(_identifier);
        assert(manager != 0x0);
    }

    function () public {
        revert();
    }


    /** PRIVATE section */

    function _isReadyToEndPoll(uint _value) private constant returns (bool) {
        uint _voteLimitNumber = votelimit;
        return _value >= _voteLimitNumber && (_voteLimitNumber > 0 || deadline <= now);
    }

    function _endPoll() private returns (uint _resultCode) {
        require(status == true);

        if (!active) {
            return _emitError(ERROR_POLL_BACKEND_INVALID_INVOCATION);
        }

        _resultCode = VotingManagerInterface(lookupManager("VotingManager")).endPoll();
        if (_resultCode != OK) {
            return _emitError(_resultCode);
        }

        delete status;
        delete active;
    }

    function _killPoll() private returns (uint _resultCode) {
        address votingManager = lookupManager("VotingManager");
        _resultCode = VotingManagerInterface(votingManager).removePoll();
        if (_resultCode != OK) {
            return _emitError(_resultCode);
        }

        this.destroy();
    }


    /** INTERNAL: Events emitting */

    function _checkAndEmitError(uint _error) internal returns (uint) {
        if (_error != OK && _error != MULTISIG_ADDED) {
            return _emitError(_error);
        }

        return _error;
    }

    function _emitError(uint _error) internal returns (uint) {
        PollEntityEmitter(getEventsHistory()).emitError(_error);
        return _error;
    }
}
