pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "../core/common/OwnedInterface.sol";
import "../core/platform/ChronoBankAssetOwnershipManager.sol";
import "./PlatformsManagerEmitter.sol";
import "./AssetsManagerInterface.sol";
import "./PlatformsManagerInterface.sol";


contract PlatformsFactory {
    function createPlatform(address owner) returns (address);
}


contract OwnedContract {
    address public contractOwner;
}


/**
* @dev TODO
*/
contract PlatformsManager is BaseManager, PlatformsManagerEmitter {

    /** Error codes */

    uint constant ERROR_PLATFORMS_ATTACHING_PLATFORM_ALREADY_EXISTS = 21001;
    uint constant ERROR_PLATFORMS_PLATFORM_DOES_NOT_EXIST = 21002;
    uint constant ERROR_PLATFORMS_INCONSISTENT_INTERNAL_STATE = 21003;

    /** Storage keys */

    /** TODO */
    StorageInterface.Address platformsFactory;

    /** * @dev DEPRECATED. Will be removed in next release */
    StorageInterface.AddressAddressMapping ownerToPlatform;

    /** TODO */
    StorageInterface.AddressesSetMapping ownerToPlatforms;

    /** TODO */
    StorageInterface.OrderedAddressesSet platforms;

    /**
    * @dev TODO
    */
    modifier onlyPlatformOwner(address _platform) {
        if (_isPlatformOwner(_platform)) {
            _;
        }
    }

    /**
    * @dev TODO
    */
    modifier onlyPreviousPlatformOwner(address _platform, address _previousOwner) {
        if (store.includes(ownerToPlatforms, bytes32(_previousOwner), _platform)) {
            _;
        }
    }

    function PlatformsManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) {
        platformsFactory.init("platformsFactory");
        ownerToPlatform.init("ownerToPlatform");
        ownerToPlatforms.init("ownerToPlatforms");
        platforms.init("platforms");
    }

    function init(address _contractsManager, address _platformsFactory) onlyContractOwner public returns (uint) {
        BaseManager.init(_contractsManager, "PlatformsManager");

        store.set(platformsFactory, _platformsFactory);

        return OK;
    }

    /**
    * @dev TODO DEPRECATED. Will be removed in next release
    */
    function getPlatformForUser(address _user) public constant returns (address) {
        return store.get(ownerToPlatform, _user);
    }

    /**
    * @dev TODO
    */
    function getPlatformForUserAtIndex(address _user, uint _idx) public constant returns (address) {
        return store.get(ownerToPlatforms, bytes32(_user), _idx);
    }

    /**
    * @dev TODO
    */
    function getPlatformsForUserCount(address _user) public constant returns (uint) {
        return store.count(ownerToPlatforms, bytes32(_user));
    }

    /**
    * @dev TODO
    */
    function attachPlatform(address _platform) onlyPlatformOwner(_platform) public returns (uint resultCode) {
        if (store.includes(platforms, _platform)) {
            return _emitError(ERROR_PLATFORMS_ATTACHING_PLATFORM_ALREADY_EXISTS);
        }

        _attachPlatformWithoutValidation(_platform, OwnedContract(_platform).contractOwner());
        _emitPlatformAttached(_platform);
        return OK;
    }

    /**
    * @dev TODO
    */
    function detachPlatform(address _platform) onlyPlatformOwner(_platform) public returns (uint) {
        if (!store.includes(platforms, _platform)) {
            return _emitError(ERROR_PLATFORMS_PLATFORM_DOES_NOT_EXIST);
        }

        address _owner = OwnedContract(_platform).contractOwner();
        if (!store.includes(ownerToPlatforms, bytes32(_owner), _platform)) {
            /* @dev TODO: have to think how to avoid this situation */
            return _emitError(ERROR_PLATFORMS_INCONSISTENT_INTERNAL_STATE);
        }

        store.remove(ownerToPlatforms, bytes32(_owner), _platform);
        store.remove(platforms, _platform);

        _emitPlatformDetached(_platform);
        return OK;
    }

    /**
    * @dev TODO
    */
    function replaceAssociatedPlatformFromOwner(address _platform, address _from)
    onlyPlatformOwner(_platform)
    onlyPreviousPlatformOwner(_platform, _from)
    public returns (uint resultCode) {
        store.add(ownerToPlatforms, bytes32(msg.sender), _platform);
        store.remove(ownerToPlatforms, bytes32(_from), _platform);
        return OK;
    }

    /**
    * @dev TODO
    */
    function createPlatform() public returns (uint resultCode) {
        PlatformsFactory factory = PlatformsFactory(store.get(platformsFactory));
        address _platform = factory.createPlatform(msg.sender);
        _attachPlatformWithoutValidation(_platform, msg.sender);

        AssetsManagerInterface assetsManager = AssetsManagerInterface(lookupManager("AssetsManager"));
        resultCode = assetsManager.requestTokenExtension(_platform);
        address _tokenExtension;
        if (resultCode == OK) {
            _tokenExtension = assetsManager.getTokenExtension(_platform);
            ChronoBankAssetOwnershipManager(_platform).addPartOwner(_tokenExtension);
        }

        OwnedInterface(_platform).transferContractOwnership(msg.sender);
        _emitPlatformRequested(_platform, _tokenExtension);
        return OK;
    }

    /**
    * @dev TODO private
    */
    function _attachPlatformWithoutValidation(address _platform, address _owner) private {
        store.add(ownerToPlatforms, bytes32(_owner), _platform);
        store.add(platforms, _platform);
    }

    function _isPlatformOwner(address _platform) private constant returns (bool) {
        return OwnedContract(_platform).contractOwner() == msg.sender;
    }

    /**
    * Events emitting
    */

    function _emitError(uint _errorCode) private returns (uint) {
        PlatformsManagerEmitter(getEventsHistory()).emitError(_errorCode);
        return _errorCode;
    }

    function _emitPlatformAttached(address _platform) private {
        PlatformsManagerEmitter(getEventsHistory()).emitPlatformAttached(_platform);
    }

    function _emitPlatformDetached(address _platform) private {
        PlatformsManagerEmitter(getEventsHistory()).emitPlatformDetached(_platform);
    }

    function _emitPlatformRequested(address _platform, address _tokenExtension) private {
        PlatformsManagerEmitter(getEventsHistory()).emitPlatformRequested(_platform, _tokenExtension);
    }

    function _emitPlatformReplaced(address _fromPlatform, address _toPlatform) private {
        PlatformsManagerEmitter(getEventsHistory()).emitPlatformReplaced(_fromPlatform, _toPlatform);
    }
}
