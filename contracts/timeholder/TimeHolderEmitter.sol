pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract TimeHolderEmitter is MultiEventsHistoryAdapter {
    /**
    *  User deposited into current period.
    */
    event Deposit(address who, uint amount);

    /**
    *  Shares withdrawn by a shareholder.
    */
    event WithdrawShares(address who, uint amount);

    /**
    *  Shares withdrawn by a shareholder.
    */
    event ListenerAdded(address listener);

    /**
    * Shares listener is removed
    */
    event ListenerRemoved(address listener);

    /**
    * Fee for Feature is taken
    */
    event FeatureFeeTaken(address self, address indexed from, address indexed to, uint amount);

    /**
    *  Something went wrong.
    */
    event Error(address indexed self, uint errorCode);

    function emitDeposit(address who, uint amount) public {
        Deposit(who, amount);
    }

    function emitWithdrawShares(address who, uint amount) public {
        WithdrawShares(who, amount);
    }

    function emitListenerAdded(address listener) public {
        ListenerAdded(listener);
    }

    function emitListenerRemoved(address listener) public {
        ListenerRemoved(listener);
    }

    function emitFeatureFeeTaken(address _from, address _to, uint _amount) public {
        FeatureFeeTaken(_self(), _from, _to, _amount);
    }

    function emitError(uint error) public {
        Error(_self(), error);
    }
}
