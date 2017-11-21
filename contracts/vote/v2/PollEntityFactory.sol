pragma solidity ^0.4.11;

import "../../core/common/Owned.sol";
import "./PollEntityRouter.sol";


/**
* @title Defines an implementation of poll factory. Instantiates PollEntityRouter contract
* as a facade for all requests related to poll's functionality defined in PollEntityInterface.
* Could be used as an instrument of versioning of polls backends.
*/
contract PollEntityFactory is Owned {

    /** Storage variables */

    address contractsManager;
    address backend;


    /** PUBLIC section */

    function PollEntityFactory(address _contractsManager, address _backend) public {
        contractsManager = _contractsManager;
        backend = _backend;
    }

    /**
    * @dev Creates a new poll and provides all needed data for its instantiation
    *
    * @return address of a brand new poll contract
    */
    function createPoll() public constant returns (address) {
        PollEntityRouter _voting = new PollEntityRouter(contractsManager, backend);
        return address(_voting);
    }
}
