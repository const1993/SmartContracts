pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "../timeholder/FeatureFeeAdapter.sol";
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
contract PlatformsManager is FeatureFeeAdapter, BaseManager, PlatformsManagerEmitter {

    /** Error codes */

    uint constant ERROR_PLATFORMS_ATTACHING_PLATFORM_ALREADY_EXISTS = 21001;
    uint constant ERROR_PLATFORMS_PLATFORM_DOES_NOT_EXIST = 21002;
    uint constant ERROR_PLATFORMS_INCONSISTENT_INTERNAL_STATE = 21003;
    uint constant ERROR_PLATFORMS_UPDATE_PLATFORM_METADATA_THE_SAME_NAME = 21004;

    /** Storage keys */

    /** TODO */
    StorageInterface.Address platformsFactory;

    /** TODO */
    StorageInterface.AddressesSetMapping ownerToPlatforms;

    /** TODO */
    StorageInterface.OrderedAddressesSet platforms;

    /** TODO */
    StorageInterface.AddressBytes32Mapping platformToName;

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
        ownerToPlatforms.init("ownerToPlatforms");
        platforms.init("platforms");
        platformToName.init("platformToName");
    }

    function init(address _contractsManager, address _platformsFactory) onlyContractOwner public returns (uint) {
        BaseManager.init(_contractsManager, "PlatformsManager");

        store.set(platformsFactory, _platformsFactory);

        return OK;
    }

    /**
    * @dev TODO
    */
    function getPlatformName(address _platform) public constant returns (bytes32 _name) {
        _name = store.get(platformToName, _platform);
    }

    /**
    * @dev TODO
    */
    function getPlatformForUserAtIndex(address _user, uint _idx) public constant returns (address _platform, bytes32 _name) {
        _platform = store.get(ownerToPlatforms, bytes32(_user), _idx);
        _name = store.get(platformToName, _platform);
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
    function getPlatformsMetadataForUser(address _user) public constant returns (address[] _platforms, bytes32[] _names) {
        _platforms = store.get(ownerToPlatforms, bytes32(_user));
        _names = new bytes32[](_platforms.length);
        for (uint _platformIdx = 0; _platformIdx < _platforms.length; ++_platformIdx) {
            _names[_platformIdx] = store.get(platformToName, _platforms[_platformIdx]);
        }
    }

    /**
    * @dev TODO
    */
    function setPlatformMetadata(address _platform, bytes32 _name) onlyPlatformOwner(_platform) public returns (uint) {
        if (store.get(platformToName, _platform) == _name) {
            return _emitError(ERROR_PLATFORMS_UPDATE_PLATFORM_METADATA_THE_SAME_NAME);
        }

        store.set(platformToName, _platform, _name);
        return OK;
    }

    /**
    * @dev TODO
    */
    function attachPlatform(address _platform, bytes32 _name) onlyPlatformOwner(_platform) public returns (uint resultCode) {
        if (store.includes(platforms, _platform)) {
            return _emitError(ERROR_PLATFORMS_ATTACHING_PLATFORM_ALREADY_EXISTS);
        }

        _attachPlatformWithoutValidation(_platform, _name, OwnedContract(_platform).contractOwner());
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
        store.set(platformToName, _platform, bytes32(0));

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
    function createPlatform(bytes32 _name) public returns (uint resultCode) {
        return _createPlatform(_name, [uint(0)]);
    }

    function _createPlatform(bytes32 _name, uint[1] memory _result) featured(_result) private returns (uint resultCode) {
        PlatformsFactory factory = PlatformsFactory(store.get(platformsFactory));
        address _platform = factory.createPlatform(msg.sender);
        _attachPlatformWithoutValidation(_platform, _name, msg.sender);

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
    function _attachPlatformWithoutValidation(address _platform, bytes32 _name, address _owner) private {
        store.add(ownerToPlatforms, bytes32(_owner), _platform);
        store.add(platforms, _platform);
        store.set(platformToName, _platform, _name);
    }

    /**
    * @dev TODO private
    */
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
