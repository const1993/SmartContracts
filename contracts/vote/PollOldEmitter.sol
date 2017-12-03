pragma solidity ^0.4.11;

import './VoteEmitter.sol';

contract PollOldEmitter is VoteEmitter {
    function emitError(uint errorCode) {
        Error(_self(), errorCode);
    }

    function emitSharesPercentUpdated() {
        SharesPercentUpdated(_self());
    }

    function emitPollCreated(uint pollId) {
        PollCreated(pollId);
    }

    function emitPollDeleted(uint pollId) {
        PollDeleted(pollId);
    }

    function emitPollActivated(uint pollId) {
        PollActivated(pollId);
    }

    function emitIpfsHashToPollAdded(uint id, bytes32 hash, uint count) {
        IpfsHashToPollAdded(id, hash, count);
    }

    function emitOptionAdded(uint pollId, bytes32 option, uint count) {
        OptionAdded(pollId, option, count);
    }

    function emitOptionRemoved(uint pollId, bytes32 option, uint count) {
        OptionRemoved(pollId, option, count);
    }

    function emitPollDetailsUpdated(uint pollId) {
        PollDetailsUpdated(pollId);
    }
}
