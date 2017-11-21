pragma solidity ^0.4.11;

/**
* @title Defines public interface for polls: how to interact and what could be asked.
*/
contract PollEntityInterface {

    /** Getters */

    /**
    * @dev Gets poll's owner address
    */
    function owner() public constant returns (address);

    /**
    * @dev Gets if poll is active or not
    */
    function active() public constant returns (bool);

    /**
    * @dev Gets an index of an option chosen by user
    *
    * @param _member voted user
    *
    * @return choice of provided user
    */
    function memberOptions(address _member) public constant returns (uint8);

    /**
    * @dev Checks if provided user is already voted in this poll
    *
    * @param _user user to check
    *
    * @return `true` if user has voted, `false` otherwise
    */
    function hasMember(address _user) public constant returns (bool);

    /**
    * @dev Initializes a poll. Should not activate poll on this stage.
    */
    function init(
        bytes32[16] _options,
        bytes32[4] _ipfsHashes,
        bytes32 _detailsIpfsHash,
        uint _votelimit,
        uint _deadline,
        address _owner
    ) public returns (uint);

    /**
    * @dev Votes for a picked option. Usually numbers from `1` to max value are used.
    */
    function vote(uint8 _choice) public returns (uint);

    /**
    * @dev Activates poll, so users can start voting.
    */
    function activatePoll() public returns (uint);

    /**
    * @dev Ends poll, stops any activity and users couldn't vote anymore.
    */
    function endPoll() public returns (uint);

    /**
    * @dev Eliminates poll, should be allowed to perform before activation or after poll will end.
    */
    function killPoll() public returns (uint);

    /**
    * @dev Get full poll details
    */
    function getDetails() public constant returns (
        address _owner,
        bytes32 _detailsIpfsHash,
        uint _votelimit,
        uint _deadline,
        bool _status,
        bool _active,
        uint _creation,
        bytes32[] _options,
        bytes32[] _hashes
    );

    /**
    * @dev Get information about current poll situation for existed options: how much tokens are placed for which options.
    */
    function getVotesBalances() public constant returns (uint8[], uint[]);


    /** Methods to update a poll's state before it will be activated */

    /**
    * @dev Updates poll details hash. Should be done when poll isn't active
    */
    function updatePollDetailsIpfsHash(bytes32 _detailsIpfsHash) public returns (uint);

    /**
    * @dev Adds a new options. Should be done when poll isn't active
    */
    function addPollOption(bytes32 _option) public returns (uint);

    /**
    * @dev Removes existed option from a poll. Should be done when poll isn't active
    */
    function removePollOption(bytes32 _option) public returns (uint);

    /**
    * @dev Adds ipfs hash to a list. Should be done when poll isn't active
    */
    function addPollIpfsHash(bytes32 _hash) public returns (uint);

    /**
    * @dev Removes ipfs hash from a list. Should be done when poll isn't active
    */
    function removePollIpfsHash(bytes32 _hash) public returns (uint);
}
