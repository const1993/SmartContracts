pragma solidity ^0.4.11;

/**
* @title Routing contract that is able to provide a way for delegating invocations with dynamic destination address.
*/
contract BaseRouter {

    function() payable public {
        uint r;
        address _backend = backend();

        // Make the call
        assembly {
            calldatacopy(mload(0x40), 0, calldatasize)
            r := delegatecall(sub(gas, 700), _backend, mload(0x40), calldatasize, mload(0x40), 32) // WARNING: 32 - size of the return value
        }

        // Throw if the call failed
        if (r != 1) revert();

        // Pass on the return value
        assembly {
            return(mload(0x40), 32) // WARNING: 32 - size of the return value
        }
    }

    /**
    * @dev Returns destination address for future calls
    *
    * @return destination address
    */
    function backend() internal constant returns (address);
}
