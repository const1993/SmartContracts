pragma solidity ^0.4.11;

import "../../core/common/BaseManager.sol";
import "../../core/common/OwnedInterface.sol";
import "../../core/common/ListenerInterface.sol";
import "../../core/event/MultiEventsHistory.sol";
import "../../timeholder/TimeHolderInterface.sol";
import "./PollInterface.sol";
import "./PollFactory.sol";
import "./VotingManagerEmitter.sol";


/// @title Contract is supposed to the central point to enter to manipulate (create and navigate) polls.
/// It aggregates:
/// - creation of a new poll,
/// - tracking a number of currently active polls,
/// - getting paginated lists of all created polls,
/// - implements ListenerInterface to support and use TimeHolder's functionality
contract VotingManager is BaseManager, VotingManagerEmitter, ListenerInterface, PollListenerInterface {

    /** Constants */

    uint8 constant DEFAULT_SHARES_PERCENT = 1;
    uint8 constant ACTIVE_POLLS_MAX = 20;


    /** Error codes */

    uint constant ERROR_VOTING_ACTIVE_POLL_LIMIT_REACHED = 27001;


    /** Storage keys */

    /** @dev set(address) stands for set of polls  */
    StorageInterface.AddressesSet pollsStorage;

    /** @dev a number of active polls */
    StorageInterface.UInt activeCountStorage;

    /** @dev address of a poll factory */
    StorageInterface.Address pollsFactoryStorage;

    /** @dev percent of shares to treat a poll as finished */
    StorageInterface.UInt sharesPercentStorage;

    /** @dev backend address used for polls */
    StorageInterface.Address pollBackendStorage;


    /** Modifiers */

    /** @dev Guards invocation only to TimeHolder */
    modifier onlyTimeHolder {
        if (msg.sender != lookupManager("TimeHolder")) revert();
        _;
    }

    /** @dev Guards invocation only to a poll registered in this manager */
    modifier onlyPoll {
        if (!store.includes(pollsStorage, msg.sender)) revert();
        _;
    }


    /** PUBLIC section */

    function VotingManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) public {
        pollsStorage.init("pollsStorage");
        pollsFactoryStorage.init("pollsFactoryStorage");
        sharesPercentStorage.init("sharesPercentStorage");
        activeCountStorage.init("activeCountStorage");
        pollBackendStorage.init("pollBackendStorage");
    }

    /// @notice Initializes contract
    /// @param _contractsManager address of a contracts manager
    /// @param _pollsFactory address of a poll factory
    /// @return _resultCode result code of an operation. REINITIALIZED if it was once initialized.
    function init(address _contractsManager, address _pollsFactory, address _pollBackend) onlyContractOwner public returns (uint _resultCode) {
        require(_pollBackend != 0x0);

        _resultCode = BaseManager.init(_contractsManager, "VotingManager");

        if (_resultCode != OK && _resultCode != REINITIALIZED) {
            return _resultCode;
        }

        if (REINITIALIZED != _resultCode) {
            store.set(sharesPercentStorage, DEFAULT_SHARES_PERCENT);
        }

        store.set(pollsFactoryStorage, _pollsFactory);
        store.set(pollBackendStorage, _pollBackend);

        return OK;
    }

    /// @notice Gets votes limit (or number of tokens to be voted to treat a poll as completed)
    /// @return a number of tokens
    function getVoteLimit() public view returns (uint) {
        address timeHolder = lookupManager("TimeHolder");
        return TimeHolderInterface(timeHolder).totalSupply() / 10000 * store.get(sharesPercentStorage); // @see sharesPercentStorage description
    }

    /// @notice Sets votes percent. Multisignature required.
    /// @param _percent a value of percent for a vote limit. Should be between 0 and 10000 (because not float in a system)
    /// @return _resultCode result code of an operation
    function setVotesPercent(uint _percent) public returns (uint _resultCode) {
        require(_percent > 0 && _percent < 10000);

        _resultCode = multisig();
        if (_resultCode != OK) {
            return _checkAndEmitError(_resultCode);
        }

        store.set(sharesPercentStorage, _percent);

        _emitSharesPercentUpdated();
        return OK;
    }

    /// @notice Sets poll backend address that will be used for future polls
    function setBackend(address _backend) onlyContractOwner public returns (uint) {
        require(_backend != 0x0);

        store.set(pollBackendStorage, _backend);
        return OK;
    }

    /// @notice Gets a number of active polls. Couldn't be more than ACTIVE_POLLS_MAX
    /// @return a number of active polls
    function getActivePollsCount() public view returns (uint) {
        return store.get(activeCountStorage);
    }

    /// @dev Gets a number of polls registered in the manager. Includes a number of both active and inactive polls
    /// @return a number of polls
    function getPollsCount() public view returns (uint) {
        return store.count(pollsStorage);
    }

    /// @notice Gets a paginated results of polls stored in the manager. Could be mixed with getPollsCount() passed as
    /// a pageSize to get full list of polls at one call.
    /// @param _startIndex index of a poll to start. For first call should be equal to `0`
    /// @param _pageSize size of an output list
    /// @return {
    ///   "_polls": "list of polls",
    ///   "_nextIndex": "index that could be used for the next call as _startIndex"
    /// }
    function getPollsPaginated(uint _startIndex, uint32 _pageSize) public view returns (address[] _polls) {
        _polls = new address[](_pageSize);
        uint _pollsCount = store.count(pollsStorage);
        uint _lastIndex = _startIndex + _pageSize;
        _lastIndex = (_lastIndex >= _pollsCount) ? _pollsCount : _lastIndex;
        for (uint _idx = _startIndex; _idx < _lastIndex; ++_idx) {
            _polls[_idx] = store.get(pollsStorage, _idx);
        }
    }

    /// @notice Gets a list of polls where provided user is participating (did a vote)
    /// @param _user user who voted
    /// @return _polls a list of polls
    function getMembershipPolls(address _user) public view returns (address[] _polls) {
        uint _count = store.count(pollsStorage);
        _polls = new address[](_count);

        uint _pointer;
        address _poll;
        for (uint _idx = 0; _idx < _count; ++_idx) {
            _poll = store.get(pollsStorage, _idx);
            if (PollInterface(_poll).hasMember(_user)) {
                _polls[_pointer++] = _poll;
            }
        }
    }

    /// @notice Creates a brand new poll with provided description and properties. Those properties, like _options, _ipfsHashes, could be
    /// updated any time until poll hasn't started.
    /// Emits PollCreated event in case of success.
    /// @param _options list of options for a poll
    /// @param _ipfsHashes ipfs hashes
    /// @param _detailsIpfsHash ipfs hash of poll's description and other details
    /// @param _votelimit limit when poll would be treated as completed
    /// @param _deadline time after which poll isn't active anymore
    /// @return OK if all went all right, error code otherwise
    function createPoll(bytes32[16] _options, bytes32[4] _ipfsHashes, bytes32 _detailsIpfsHash, uint _votelimit, uint _deadline) public returns (uint) {
        PollFactory _pollsFactory = PollFactory(store.get(pollsFactoryStorage));
        address _poll = _pollsFactory.createPoll(contractsManager, store.get(pollBackendStorage), _options, _ipfsHashes, _detailsIpfsHash, _votelimit, _deadline);

        address _eventsHistory = getEventsHistory();
        PollInterface(_poll).setupEventsHistory(_eventsHistory);
        if (!MultiEventsHistory(_eventsHistory).authorize(_poll)) {
            revert();
        }

        if (OK != PollInterface(_poll).setPollListener(this)) {
            revert();
        }

        if (!OwnedInterface(_poll).transferContractOwnership(msg.sender)) {
            revert();
        }

        store.add(pollsStorage, _poll);

        _emitPollCreated(_poll);
        return OK;
    }

    /** PollListenerInterface interface */

    /// @notice Emits PollVoted event in case of successful voting.
    /// @dev DO NOT СALL IT DIRECTLY. Used by a poll contract.
    /// @param _user address of a user who votes
    /// @param _choice option chosen by user
    /// @return result code of an operation
    function onVote(address _user, uint8 _choice) onlyPoll public {
    }

    /// @notice Emits PollRemoved event in case of successful removal.
    /// @dev DO NOT СALL IT DIRECTLY. Used by a poll contract.
    /// @return result code of an operation
    function onRemovePoll() onlyPoll public {
        store.remove(pollsStorage, msg.sender);
        MultiEventsHistory(getEventsHistory()).reject(msg.sender);
        _emitPollRemoved(msg.sender);
    }

    /// @notice Emits PollActivated event in case of successful activation.
    /// @dev DO NOT СALL IT DIRECTLY. Used by a poll contract.
    /// @return result code of an operation
    function onActivatePoll() onlyPoll public {
        uint _activeCount = store.get(activeCountStorage);
        if (_activeCount + 1 > ACTIVE_POLLS_MAX) {
            revert();
        }

        store.set(activeCountStorage, _activeCount + 1);
    }

    /// @notice Emits PollActivated event in case of successful ending (completing).
    /// @dev DO NOT СALL IT DIRECTLY. Used by a poll contract.
    /// @return result code of an operation
    function onEndPoll() onlyPoll public {
        uint _activeCount = store.get(activeCountStorage);
        assert(_activeCount != 0);

        store.set(activeCountStorage, _activeCount - 1);
    }

    /// @notice Gets descriptions for a list of polls (except options and ipfsHashes: platform limitation)
    /// @param _polls a list of polls
    /// @return {
    ///   "_owner": "poll owners",
    ///   "_detailsIpfsHash": p"oll ipfs hashes",
    ///   "_votelimit": "poll vote limits",
    ///   "_deadline": "poll deadlines",
    ///   "_status": "poll statuses",
    ///   "_active": "poll activates",
    ///   "_creation": "poll creation times"
    /// }
    function getPollsDetails(address[] _polls) public view returns (
        address[] _owner,
        bytes32[] _detailsIpfsHash,
        uint[] _votelimit,
        uint[] _deadline,
        bool[] _status,
        bool[] _active,
        uint[] _creation
    ) {
        _owner = new address[](_polls.length);
        _detailsIpfsHash = new bytes32[](_polls.length);
        _votelimit = new uint[](_polls.length);
        _deadline = new uint[](_polls.length);
        _status = new bool[](_polls.length);
        _active = new bool[](_polls.length);
        _creation = new uint[](_polls.length);

        for (uint _idx = 0; _idx < _polls.length; ++_idx) {
            (_owner[_idx], _detailsIpfsHash[_idx], _votelimit[_idx], _deadline[_idx], _status[_idx], _active[_idx], _creation[_idx],,) =
            PollInterface(_polls[_idx]).getDetails();
        }
    }

    /** ListenerInterface interface */

    function deposit(address _address, uint _amount, uint _total) onlyTimeHolder public returns (uint) {
        _forEachPollMembership(_address, _amount, _total, _deposit);
        return OK;
    }

    function withdrawn(address _address, uint _amount, uint _total) onlyTimeHolder public returns (uint) {
        _forEachPollMembership(_address, _amount, _total, _withdrawn);
        return OK;
    }

    /// @dev Don't allow to receive any Ether
    function () public {
        revert();
    }


    /** PRIVATE section */

    function _deposit(address _entity, address _address, uint _amount, uint _total) private {
        ListenerInterface(_entity).deposit(_address, _amount, _total);
    }

    function _withdrawn(address _entity, address _address, uint _amount, uint _total) private {
        ListenerInterface(_entity).withdrawn(_address, _amount, _total);
    }

    function _forEachPollMembership(address _address, uint _amount, uint _total, function (address, address, uint, uint) _action) private {
        uint _count = store.count(pollsStorage);
        address _poll;
        for (uint _idx = 0; _idx < _count; ++_idx) {
            _poll = store.get(pollsStorage, _idx);
            if (PollInterface(_poll).hasMember(_address)) {
                _action(_poll, _address, _amount, _total);
            }
        }
    }


    /** PRIVATE: events emitting */

    function _emitError(uint _error) internal returns (uint) {
        VotingManagerEmitter(getEventsHistory()).emitError(_error);
        return _error;
    }

    function _checkAndEmitError(uint _error) internal returns (uint) {
        if (_error != OK && _error != MULTISIG_ADDED) {
            return _emitError(_error);
        }

        return _error;
    }

    function _emitSharesPercentUpdated() internal {
        VotingManagerEmitter(getEventsHistory()).emitVotingSharesPercentUpdated();
    }

    function _emitPollCreated(address _pollAddress) internal {
        VotingManagerEmitter(getEventsHistory()).emitPollCreated(_pollAddress);
    }
    function _emitPollRemoved(address _pollAddress) internal {
        VotingManagerEmitter(getEventsHistory()).emitPollRemoved(_pollAddress);
    }
}
