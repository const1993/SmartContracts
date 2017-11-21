pragma solidity ^0.4.11;

import "../../assets/extensions/BaseRouter.sol";
import "./PollEntityEmitter.sol";

/**
* @title Provides an interface to interact with poll's backend to get most needed numbers and services
*/
contract VotingBackendInterface {
    function getVoteLimit() public constant returns (uint);
    function lookupManager(bytes32 _identifier) public constant returns (address);
}

/**
* @title Defines a shell that will redirects almost all actions to a backend address.
* This contract provides storage layout of variables that will be accessed during delegatecall.
* Partially implements PollEntityInterface interface.
*/
contract PollEntityRouter is BaseRouter, PollEntityEmitter {

    /** Constants */

    uint constant OK = 1;
    uint8 constant OPTIONS_POLLS_MAX = 16;
    uint8 constant IPFS_HASH_POLLS_MAX = 5;

    /**
    * Storage variables. DO NOT CHANGE VARIABLES' LAYOUT UNDER ANY CIRCUMSTANCES!
    */

    address internal backendAddress;
    address internal contractsManager;

    address public owner;
    bytes32 internal detailsIpfsHash;
    uint internal votelimit;
    uint internal deadline;
    uint internal creation;
    bool public active;
    bool internal status;
    bytes32[] internal options = new bytes32[](OPTIONS_POLLS_MAX);
    bytes32[] internal ipfsHashes = new bytes32[](IPFS_HASH_POLLS_MAX);

    mapping(address => uint8) public memberOptions;
    mapping(address => uint) public memberVotes;
    mapping(uint8 => uint) public optionsBalance;


    /** Modifiers */

    /**
    * @dev Guards from double invocation after initialization was made
    */
    modifier onlyOneInitialization {
        if (owner != 0x0) revert();
        _;
    }

    /**
    * @dev Guards invocations from only backend address or VotingManager
    */
    modifier onlyBackendOrVotingManager {
        if (msg.sender == backendAddress || msg.sender == VotingBackendInterface(this).lookupManager("VotingManager")) {
            _;
        }
    }


    /** PUBLIC section */

    function PollEntityRouter(address _contractsManager, address _backend) public {
        require(_backend != 0x0);
        require(_contractsManager != 0x0);

        contractsManager = _contractsManager;
        backendAddress = _backend;
    }

    /**
    * @dev Initializes internal variables. Poll by default is not active so to start voting first activate a poll.
    * @notice Could be invoked only once.
    *
    * @param _options list of options to pick on active stage
    * @param _ipfsHashes list of ipfs hashes
    * @param _detailsIpfsHash ipfs hash for poll's details info
    * @param _votelimit votelimit. Should be less than votelimit that is defined on a backend
    * @param _deadline time to end voting
    * @param _owner an owner of a poll
    *
    * @return result code of an operation
    */
    function init(bytes32[16] _options, bytes32[4] _ipfsHashes, bytes32 _detailsIpfsHash, uint _votelimit, uint _deadline, address _owner) onlyOneInitialization public returns (uint) {
        require(_detailsIpfsHash != bytes32(0));
        require(_votelimit < VotingBackendInterface(this).getVoteLimit());
        require(_deadline > now);

        owner = _owner;
        detailsIpfsHash = _detailsIpfsHash;
        votelimit = _votelimit;
        deadline = _deadline;
        creation = now;
        active = false;
        status = true;

        uint8 i;
        uint8 pointer = 0;
        for (i = 0; i < _options.length; i++) {
            if (_options[i] != bytes32(0)) {
                options[pointer++] = _options[i];
            }
        }

        pointer = 0;
        for (i = 0; i < _ipfsHashes.length; i++) {
            if (_ipfsHashes[i] != bytes32(0)) {
                ipfsHashes[pointer++] = _ipfsHashes[i];
            }
        }

        return OK;
    }

    /**
    * @dev Eliminates poll
    * @notice Allowed to be invoked only by a backend or VotingManager
    */
    function destroy() onlyBackendOrVotingManager public {
        selfdestruct(owner);
    }

    /**
    * @dev Gets address of a backend contract
    *
    * @return _backend address of a backend contract
    */
    function backend() internal constant returns (address) {
        return backendAddress;
    }

    /**
    * @dev Gets intermediate retults of a poll by providing options and their balances.
    * @notice Cannot be moved to a backend because of delegatecall and restriction for only one return parameter
    *
    * @return {
    *   _options: poll's options,
    *   _balances: associated balances for options
    * }
    */
    function getVotesBalances() public constant returns (uint8[] _options, uint[] _balances) {
        _options = new uint8[](options.length);
        _balances = new uint[](_options.length);

        for (uint8 _idx = 0; _idx < _balances.length; ++_idx) {
            _options[_idx] = _idx + 1;
            _balances[_idx] = optionsBalance[_options[_idx]];
        }
    }

    /**
    * @dev Gets full details of a poll including a list of options and ipfsHashes.
    * @notice Cannot be moved to a backend because of delegatecall and restriction for only one return parameter
    *
    * @return {
    *   _owner: owner,
    *   _detailsIpfsHash: details ipfs hash,
    *   _votelimit: vote limit,
    *   _deadline: deadline time,
    *   _status: 'is valid' status,
    *   _active: is activated,
    *   _creation: creation time,
    *   _options: list of options,
    *   _hashes: list of ipfs hashes
    * }
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
    ) {
        _owner = owner;
        _detailsIpfsHash = detailsIpfsHash;
        _votelimit = votelimit;
        _deadline = deadline;
        _status = status;
        _active = active;
        _creation = creation;
        _options = options;
        _hashes = ipfsHashes;
    }
}
