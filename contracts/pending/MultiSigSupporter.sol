pragma solidity ^0.4.11;

import { PendingManagerInterface as Shareable } from "./PendingManagerInterface.sol";


/**
* @title Defines a way to support multisignature invocation integrated into smart contracts.
* Uses a system of contracts connected by ContractsManager.
* Partially abstract contact.
*/
contract MultiSigSupporter {

    /** Constants */

    uint constant OK = 1;
    uint constant MULTISIG_ADDED = 3;

    /**
    * @dev Registers and checks invocations for signature and provided multisignature support
    * via ContractsManager and PendingManager.
    *
    * @return _resultCode result code of an operation. In case of successful registration of
    * signature returns MULTISIG_ADDED until all required signatures will be gathered.
    */
    function multisig() internal returns (uint _resultCode) {
        address _shareable = lookupManager("PendingManager");

        if (msg.sender != _shareable) {
            bytes32 _r = keccak256(msg.data);
            _resultCode = Shareable(_shareable).addTx(_r, msg.data, this, msg.sender);

            return (_resultCode == OK) ? MULTISIG_ADDED : _resultCode;
        }

        return OK;
    }

    /**
    * @dev Abstract. Implementation is needed in contracts that will inherit from this one.
    */
    function lookupManager(bytes32 _identifier) public constant returns (address);
}
