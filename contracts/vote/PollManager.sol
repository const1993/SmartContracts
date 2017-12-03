pragma solidity ^0.4.11;

import "./Vote.sol";
import "./PollOldEmitter.sol";
import {TimeHolderInterface as TimeHolder} from "../timeholder/TimeHolderInterface.sol";

contract PollManager is PollOldEmitter, Vote {
    /**
    * Presents a percent of shares used for limiting votes. 1 unit == 0.01%.
    * @dev Used because of absence of floating point numbers
    */
    StorageInterface.UInt sharesPercent;
    StorageInterface.UInt pollsIdCounter;

    uint8 constant DEFAULT_SHARES_PERCENT = 1;
    uint8 constant ACTIVE_POLLS_MAX = 20;
    uint8 constant OPTIONS_POLLS_MAX = 16;
    uint8 constant IPFS_HASH_POLLS_MAX = 5;

    function PollManager(Storage _store, bytes32 _crate) Vote(_store, _crate) {
        sharesPercent.init('sharesPercent');
    }

    function init(address _contractsManager) onlyContractOwner returns (uint) {
        uint result = BaseManager.init(_contractsManager, "PollManager");

        // do not update default values if reinitialization
        if (REINITIALIZED != result) {
            store.set(sharesPercent, DEFAULT_SHARES_PERCENT);
        }

        pollsIdCounter.init('pollsIdCounter');

        return OK;
    }

    function getVoteLimit() constant returns (uint) {
        address timeHolder = lookupManager("TimeHolder");
        return TimeHolder(timeHolder).totalSupply() / 10000 * store.get(sharesPercent); // @see sharesPercent description
    }

    function NewPoll(bytes32[16] _options, bytes32[4] _ipfsHashes, bytes32 _detailsIpfsHash, uint _votelimit, uint _deadline) returns (uint errorCode) {
        if (_detailsIpfsHash == bytes32(0)) {
            return _emitError(ERROR_VOTE_DETAILS_HASH_INVALID_PARAMETER);
        }

        if (_votelimit > getVoteLimit()) {
            return _emitError(ERROR_VOTE_LIMIT_EXCEEDED);
        }

        if (_deadline < now) {
            return _emitError(ERROR_VOTE_DEADLINE_INVALID_PARAMETER);
        }

        uint id = store.get(pollsIdCounter) + 1;
        store.add(polls, id);
        store.set(pollsIdCounter, id);
        store.set(owner, id, msg.sender);
        store.set(detailsIpfsHash, id, _detailsIpfsHash);
        store.set(votelimit, id, _votelimit);
        store.set(deadline, id, _deadline);
        store.set(status, id, true);
        store.set(active, id, false);
        store.set(creationTime, id, now);
        uint i;
        for (i = 0; i < _options.length; i++) {
            if (_options[i] != bytes32(0)) {
                store.add(optionsId, bytes32(id), _options[i]);
            }
        }

        for (i = 0; i < _ipfsHashes.length; i++) {
            if (_ipfsHashes[i] != bytes32(0)) {
                store.add(ipfsHashes, bytes32(id), _ipfsHashes[i]);
            }
        }
        _emitPollCreated(id);
        return OK;
    }

    function addIpfsHashToPoll(uint _id, bytes32 _hash) onlyCreator(_id) returns (uint errorCode) {
        if (!isPollExist(_id)) {
            return _emitError(ERROR_VOTE_POLL_DOES_NOT_EXIST);
        }
        if (_hash == bytes32(0)) {
            return _emitError(ERROR_VOTE_HASH_INVALID_PARAMETER);
        }

        if (store.count(ipfsHashes, bytes32(_id)) >= IPFS_HASH_POLLS_MAX) {
            return _emitError(ERROR_VOTE_POLL_LIMIT_REACHED);
        }

        store.add(ipfsHashes, bytes32(_id), _hash);
        _emitIpfsHashToPollAdded(_id, _hash, store.count(ipfsHashes, bytes32(_id)));
        return OK;
    }

    function setVotesPercent(uint _percent) returns (uint errorCode) {
        if (!(_percent > 0 && _percent < 10000)) {
            return _emitError(ERROR_VOTE_SHARES_PERCENT_OUT_OF_RANGE);
        }

        uint e = multisig();
        if (OK != e) {
            return _checkAndEmitError(e);
        }

        store.set(sharesPercent, _percent);
        _emitSharesPercentUpdated();
        return OK;
    }

    function removePoll(uint _pollId) onlyAuthorized returns (uint errorCode) {
        if (!isPollExist(_pollId)) {
            return _emitError(ERROR_VOTE_POLL_DOES_NOT_EXIST);
        }

        if (!(checkPollIsInactive(_pollId) && store.get(status, _pollId))) {
            return _emitError(ERROR_VOTE_INVALID_INVOCATION);
        }

        return deletePoll(_pollId);
    }

    function cleanInactivePolls() onlyAuthorized returns (uint errorCode) {
        StorageInterface.Iterator memory iterator = store.listIterator(polls);
        uint pollId;
        while(store.canGetNextWithIterator(polls, iterator)) {
            pollId = store.getNextWithIterator(polls, iterator);
            if (checkPollIsInactive(pollId)) {
                deletePoll(pollId);
            }
        }
        return OK;
    }

    function deletePoll(uint _pollId) internal returns (uint) {
        store.remove(polls, _pollId);
        store.set(owner, _pollId, 0x0);
        store.set(detailsIpfsHash, _pollId, bytes32(0));
        store.set(votelimit, _pollId, 0);
        store.set(deadline, _pollId, 0);
        store.set(creationTime, _pollId, 0);

        _emitPollDeleted(_pollId);
        return OK;
    }

    function activatePoll(uint _pollId) returns (uint errorCode) {
        if (!isPollExist(_pollId)) {
            return _emitError(ERROR_VOTE_POLL_DOES_NOT_EXIST);
        }

        if (store.count(optionsId, bytes32(_pollId)) < 2) {
            return _emitError(ERROR_VOTE_OPTIONS_EMPTY_LIST);
        }

        uint e = multisig();
        if (OK != e) {
            return _checkAndEmitError(e);
        }

        if ((store.get(activePollsCount) + 1) > ACTIVE_POLLS_MAX) {
            return _emitError(ERROR_VOTE_ACTIVE_POLL_LIMIT_REACHED);
        }

        if (!store.get(status, _pollId)) {
            return _emitError(ERROR_VOTE_UNABLE_TO_ACTIVATE_POLL);
        }

        store.set(active, _pollId, true);
        store.set(activePollsCount, store.get(activePollsCount) + 1);
        _emitPollActivated(_pollId);
        return OK;
    }

    function adminEndPoll(uint _pollId) returns (uint errorCode) {
        if (!isPollExist(_pollId)) {
            return _emitError(ERROR_VOTE_POLL_DOES_NOT_EXIST);
        }

        uint e = multisig();
        if (OK != e) {
            return _checkAndEmitError(e);
        }

        uint result = endPoll(_pollId);
        return _checkAndEmitError(result);
    }

    function updatePollDetailsIpfsHash(uint _pollId, bytes32 _detailsIpfsHash) onlyCreator(_pollId) returns (uint errorCode) {
        if (!isPollExist(_pollId)) {
            return _emitError(ERROR_VOTE_POLL_DOES_NOT_EXIST);
        }

        if (checkPollIsActive(_pollId)) {
            return _emitError(ERROR_VOTE_POLL_SHOULD_BE_INACTIVE);
        }

        if (_detailsIpfsHash == bytes32(0)) {
            return _emitError(ERROR_VOTE_DETAILS_HASH_INVALID_PARAMETER);
        }

        if (store.get(detailsIpfsHash, _pollId) != _detailsIpfsHash) {
            store.set(detailsIpfsHash, _pollId, _detailsIpfsHash);
        }

        _emitPollDetailsUpdated(_pollId);
        return OK;
    }

    function addPollOption(uint _pollId, bytes32 _option) onlyCreator(_pollId) returns (uint errorCode) {
        errorCode = _checkUpdatablePollOption(_pollId, _option);
        if (errorCode != OK) {
            return _emitError(errorCode);
        }

        if (store.count(optionsId, bytes32(_pollId)) >= OPTIONS_POLLS_MAX) {
            return _emitError(ERROR_VOTE_OPTIONS_LIMIT_REACHED);
        }

        if (store.includes(optionsId, bytes32(_pollId), _option)) {
            return _emitError(ERROR_VOTE_INVALID_PARAMETER);
        }

        store.add(optionsId, bytes32(_pollId), _option);
        _emitOptionAdded(_pollId, _option, store.count(optionsId, bytes32(_pollId)));
        return OK;
    }

    function removePollOption(uint _pollId, bytes32 _option) onlyCreator(_pollId) returns (uint errorCode) {
        errorCode = _checkUpdatablePollOption(_pollId, _option);
        if (errorCode != OK) {
            return _emitError(errorCode);
        }

        if (!store.includes(optionsId, bytes32(_pollId), _option)) {
            return _emitError(ERROR_VOTE_OPTION_INVALID_PARAMETER);
        }

        store.remove(optionsId, bytes32(_pollId), _option);
        _emitOptionRemoved(_pollId, _option, store.count(optionsId, bytes32(_pollId)));
        return OK;
    }

    function _checkUpdatablePollOption(uint _pollId, bytes32 _option) private constant returns (uint errorCode) {
        if (!isPollExist(_pollId)) {
            return ERROR_VOTE_POLL_DOES_NOT_EXIST;
        }

        if (checkPollIsActive(_pollId)) {
            return ERROR_VOTE_POLL_SHOULD_BE_INACTIVE;
        }

        if (_option == bytes32(0)) {
            return ERROR_VOTE_OPTION_INVALID_PARAMETER;
        }

        return OK;
    }

    function _emitError(uint error) internal returns (uint) {
        PollManager(getEventsHistory()).emitError(error );
        return error;
    }

    function _checkAndEmitError(uint error) internal returns (uint) {
        if (error != OK && error != MULTISIG_ADDED) {
            return _emitError(error);
        }

        return error;
    }

    function _emitSharesPercentUpdated() internal {
        PollManager(getEventsHistory()).emitSharesPercentUpdated();
    }

    function _emitPollCreated(uint pollId) internal {
        PollManager(getEventsHistory()).emitPollCreated(pollId);
    }

    function _emitPollDeleted(uint pollId) internal {
        PollManager(getEventsHistory()).emitPollDeleted(pollId);
    }

    function _emitPollEnded(uint pollId) internal {
        PollManager(getEventsHistory()).emitPollEnded(pollId);
    }

    function _emitPollActivated(uint pollId) internal {
        PollManager(getEventsHistory()).emitPollActivated(pollId);
    }

    function _emitIpfsHashToPollAdded(uint id, bytes32 hash, uint count) internal {
        PollManager(getEventsHistory()).emitIpfsHashToPollAdded(id, hash, count);
    }

    function _emitOptionAdded(uint pollId, bytes32 option, uint count) internal {
        PollManager(getEventsHistory()).emitOptionAdded(pollId, option, count);
    }

    function _emitOptionRemoved(uint pollId, bytes32 option, uint count) internal {
        PollManager(getEventsHistory()).emitOptionRemoved(pollId, option, count);
    }

    function _emitPollDetailsUpdated(uint pollId) internal {
        PollManager(getEventsHistory()).emitPollDetailsUpdated(pollId);
    }
}
