pragma solidity ^0.4.11;

/**
* @title Defines public interface for voting managers.
*/
contract VotingManagerInterface {

    /** Getters */

    /**
    * @dev Gets vote limit that was setup for a manager
    */
    function getVoteLimit() public constant returns (uint);

    /**
    * @dev Gets a number of polls registered in a manager
    */
    function getPollsCount() public constant returns (uint);

    /**
    * @dev Requests paginated results for a list of polls.
    */
    function getPollsPaginated(uint _startIndex, uint32 _pageSize) public constant returns (address[] _votings, uint _nextIndex);

    /**
    * @dev Gets a number of active polls. Could be restricted to some upper bounds.
    */
    function getActivePollsCount() public constant returns (uint);

    /**
    * @dev Gets a list of polls where provided user is participating (means, voted and had non-empty balance).
    */
    function getMembershipPolls(address _user) public constant returns (address[]);

    /**
    * @dev Gets detailed info for a list of provided polls.
    */
    function getPollsDetails(address[] _polls) public constant returns (
        address[] _owner,
        bytes32[] _detailsIpfsHash,
        uint[] _votelimit,
        uint[] _deadline,
        bool[] _status,
        bool[] _active,
        uint[] _creation
    );


    /** Actions */

    /**
    * @dev Creates a new poll and register it in a manager.
    */
    function createPoll(
        bytes32[16] _options,
        bytes32[4] _ipfsHashes,
        bytes32 _detailsIpfsHash,
        uint _votelimit,
        uint _deadline
    ) public returns (address, uint);


    /** Supposed to be invoked only by votings themselfs */

    /**
    * @dev Delegate method. Should be used only by poll instance during activation
    */
    function activatePoll() public returns (uint);

    /**
    * @dev Delegate method. Should be used only by poll instance during voting
    */
    function vote(address _user, uint8 _choice) public returns (uint);

    /**
    * @dev Delegate method. Should be used only by poll instance during ending a poll
    */
    function endPoll() public returns (uint);

    /**
    * @dev Delegate method. Should be used only by poll instance during killing a poll
    */
    function removePoll() public returns (uint);
}
