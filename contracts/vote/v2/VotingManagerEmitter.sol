pragma solidity ^0.4.11;

import '../../core/event/MultiEventsHistoryAdapter.sol';


/// @title Emitter with support of events history for VotingManager
contract VotingManagerEmitter is MultiEventsHistoryAdapter {

    /** Events */

    event PollCreated(address indexed self, address indexed pollAddress);

    event PollRemoved(address indexed self, address indexed pollAddress);

    event VotingSharesPercentUpdated(address indexed self);

    event Error(address indexed self, uint errorCode);


    /** Emitters */

    function emitPollCreated(address pollAddress) public {
        PollCreated(_self(), pollAddress);
    }

    function emitPollRemoved(address pollAddress) public {
        PollRemoved(_self(), pollAddress);
    }

    function emitVotingSharesPercentUpdated() public {
        VotingSharesPercentUpdated(_self());
    }

    function emitError(uint errorCode) public {
        Error(_self(), errorCode);
    }
}
