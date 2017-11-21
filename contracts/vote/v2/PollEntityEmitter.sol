pragma solidity ^0.4.11;

import '../../core/event/MultiEventsHistoryAdapter.sol';

/**
* @title Emitter with support of events history for PollEntity implementation
*/
contract PollEntityEmitter is MultiEventsHistoryAdapter {

    /** Events */

    event PollDetailsIpfsHashAdded(address indexed self, bytes32 hash, uint count);
    event PollDetailsIpfsHashRemoved(address indexed self, bytes32 hash, uint count);
    event PollDetailsOptionAdded(address indexed self, bytes32 option, uint count);
    event PollDetailsOptionRemoved(address indexed self, bytes32 option, uint count);
    event PollDetailsHashUpdated(address indexed self, bytes32 hash);

    event Error(address indexed self, uint errorCode);


    /** Emitters */

    function emitError(uint errorCode) public {
        Error(_self(), errorCode);
    }

    function emitPollDetailsIpfsHashAdded(bytes32 hash, uint count) public {
        PollDetailsIpfsHashAdded(_self(), hash, count);
    }

    function emitPollDetailsIpfsHashRemoved(bytes32 hash, uint count) public {
        PollDetailsIpfsHashRemoved(_self(), hash, count);
    }

    function emitPollDetailsOptionAdded(bytes32 option, uint count) public {
        PollDetailsOptionAdded(_self(), option, count);
    }

    function emitPollDetailsOptionRemoved(bytes32 option, uint count) public {
        PollDetailsOptionRemoved(_self(), option, count);
    }

    function emitPollDetailsHashUpdated(bytes32 hash) public {
        PollDetailsHashUpdated(_self(), hash);
    }
}
