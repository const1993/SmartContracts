pragma solidity ^0.4.11;

import "./FakeCoin.sol";

// For testing purposes.
contract FakeCoin2 is FakeCoin {

    function symbol() constant returns(string) {
        return 'FAKE2';
    }
}
