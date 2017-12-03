pragma solidity ^0.4.11;

import "./PollRouter.sol";
import "./PollInterface.sol";

/// @title Defines an implementation of poll factory. Instantiates PollRouter contract
/// as a facade for all requests related to poll's functionality defined in PollInterface.
/// Could be used as an instrument of versioning of polls backends.
contract PollFactory {

    uint constant OK = 1;


    /// @notice Creates a new poll and provides all needed data for its instantiation
    /// @return address of a brand new poll contract
    function createPoll(
        address _contractsManager,
        address _backend,
        bytes32[16] _options,
        bytes32[4] _ipfsHashes,
        bytes32 _detailsIpfsHash,
        uint _votelimit,
        uint _deadline
    ) public returns (address)
    {
        address _poll = address(new PollRouter(_contractsManager, _backend));
        if (OK != PollInterface(_poll).init(_options, _ipfsHashes, _detailsIpfsHash, _votelimit, _deadline)) {
            revert();
        }

        if (!PollInterface(_poll).transferContractOwnership(msg.sender)) {
            revert();
        }

        return _poll;
    }
}
