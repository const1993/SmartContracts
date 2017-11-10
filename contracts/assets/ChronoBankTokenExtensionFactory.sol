pragma solidity ^0.4.11;

import "./extensions/TokenExtensionRouter.sol";

/**
* @title Token extension factory. Provides a way to create chronobank token extensions
*/
contract ChronoBankTokenExtensionFactory {

    /** address of ContractsManager contract interface */
    address contractsManager;

    function ChronoBankTokenExtensionFactory(address _contractsManager) {
        contractsManager = _contractsManager;
    }

    /**
    * @dev Creates token extension based on provided platform
    *
    * @param _platform platform address for which token extension will be created
    *
    * @return address of newly created token extension
    */
    function createTokenExtension(address _platform) public returns (address) {
        address tokenExtension = new TokenExtensionRouter(contractsManager, _platform);
        return tokenExtension;
    }
}
