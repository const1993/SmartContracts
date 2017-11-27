pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract TimeHolderEmitter is MultiEventsHistoryAdapter {
    /**
    *  User deposited into current period.
    */
    event Deposit(bytes32 symbol, address who, uint amount);

    /**
    *  Shares withdrawn by a shareholder.
    */
    event WithdrawShares(bytes32 symbol, address who, uint amount);

    /**
    *  Shares withdrawn by a shareholder.
    */
    event ListenerAdded(address listener, bytes32 symbol);

    /**
    * Shares listener is removed
    */
    event ListenerRemoved(address listener, bytes32 symbol);

    /**
    * Shares is added to whitelist and start be available to use
    */
    event SharesWhiteListAdded(bytes32 symbol);

    /**
    * Shares is removed from whitelist and stop being available to use
    */
    event SharesWhiteListChanged(bytes32 symbol, bool indexed isAdded);

    /**
    * Fee for Feature is taken
    */
    event FeatureFeeTaken(address self, address indexed from, address indexed to, uint amount);

    /**
    *  Something went wrong.
    */
    event Error(address indexed self, uint errorCode);

    function emitDeposit(bytes32 symbol, address who, uint amount) public {
        Deposit(symbol, who, amount);
    }

    function emitWithdrawShares(bytes32 symbol, address who, uint amount) public {
        WithdrawShares(symbol, who, amount);
    }

    function emitListenerAdded(address listener, bytes32 symbol) public {
        ListenerAdded(listener, symbol);
    }

    function emitListenerRemoved(address listener, bytes32 symbol) public {
        ListenerRemoved(listener, symbol);
    }

    function emitSharesWhiteListChanged(bytes32 symbol, bool isAdded) public {
        SharesWhiteListChanged(symbol, isAdded);
    }

    function emitFeatureFeeTaken(address _from, address _to, uint _amount) public {
        FeatureFeeTaken(_self(), _from, _to, _amount);
    }

    function emitError(uint error) public {
        Error(_self(), error);
    }
}
