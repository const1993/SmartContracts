pragma solidity ^0.4.11;

import "./TokenExtensionFallbackInterface.sol";
import "../core/common/Managed.sol";
import "../core/platform/ChronoBankPlatformInterface.sol";
import "../assets/AssetsManagerInterface.sol";
import "../assets/TokenManagementInterface.sol";

/**
* @title This contract is currently deprecated and should not be used througout the system.
* Initial idea that stands behind its creation was supporting old implementation of
* ChronoBankPlatform to be compatible with token extensions and assets manager. But since
* this implementation is currently used only for hosting TIME tokens and all new tokens
* will be created on another version of platform contract, so it is obvious not to use
* it anymore
*
* DEPRECATED.
*/
contract ChronoBankWalletFallbackSupporter is Managed, TokenExtensionFallbackInterface {

    /**
    * @dev Guards methods for calling only by one of platform token extensions.
    */
    modifier onlyTokenExtension() {
        if (!TokenExtensionRegistry(lookupManager("AssetsManager")).containsTokenExtension(msg.sender)) {
            revert();
        }
        _;
    }

    function ChronoBankWalletFallbackSupporter(Storage _store, bytes32 _crate) Managed(_store, _crate) {
    }

    /**
    * @dev Designed to check if a wallet supports fallback interface. Should be simple and return `true` or `false`
    * depending on wether a contract wants to support this interface or not.
    *
    * @param _symbol asset's symbol
    *
    * @return `true` if a contract (wallet) supports fallback interface, `false` otherwise
    */
    function fallbackAsset(bytes32 _symbol) public onlyTokenExtension returns (bool)  {
        return true;
    }

    /**
    * @dev Defines main operation that will be performed throughout fallback interface. This method will be invoked only in case
    * if `fallbackAsset` returns `true`. Purpose is to delegate invocation of any method that contract is allowed to call to
    * a token extension.
    *
    * @param _symbol asset's symbol
    * @param _from destination of calling. Contract that will be proposed to be called with data
    * @param _data data passed to `call` on _from address
    *
    * @return `true` if call is successful, `false` otherwise
    */
    function fallbackAssetInvoke(bytes32 _symbol, address _from, bytes _data) public onlyTokenExtension returns (bool) {
        return _from.call(_data);
    }

    /**
    * @dev Helper method to provide a way to pass ownership of the platform after all operations are done to its real owner.
    *
    * @param _symbol asset's symbol
    * @param _to real platform owner
    *
    * @return `true` if passing ownership is successful, `false` otherwise
    */
    function fallbackAssetPassOwnership(bytes32 _symbol, address _to) public onlyTokenExtension returns (bool) {
        address _platform = TokenManagementInterface(msg.sender).platform();
        return ChronoBankPlatformInterface(_platform).changeOwnership(_symbol, _to) == OK;
    }
}
