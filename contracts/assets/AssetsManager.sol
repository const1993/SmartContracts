pragma solidity ^0.4.11;

import "../core/common/BaseManager.sol";
import "../core/common/Once.sol";
import "../core/erc20/ERC20ManagerInterface.sol";
import "../core/platform/ChronoBankAssetProxyInterface.sol";
import "../core/platform/ChronoBankAssetOwnershipManager.sol";
import "../core/platform/ChronoBankPlatformInterface.sol";
import "./TokenManagementInterface.sol";
import "./AssetsManagerInterface.sol";
import "./AssetsManagerEmitter.sol";
import "./PlatformsManagerInterface.sol";

contract OwnedContract {
    address public contractOwner;
}


contract TokenExtensionsFactory {
    function createTokenExtension(address _platform) returns (address);
}


/**
* TODO
*/
contract AssetsManager is AssetsManagerInterface, TokenExtensionRegistry, BaseManager, AssetsManagerEmitter {

    /** Error codes */

    uint constant ERROR_ASSETS_MANAGER_SYMBOL_ALREADY_EXISTS = 30001;
    uint constant ERROR_ASSETS_MANAGER_INVALID_INVOCATION = 30002;
    uint constant ERROR_ASSETS_MANAGER_EXTENSION_ALREADY_EXISTS = 30003;

    /** Storage keys */

    /** TODO */
    StorageInterface.Address tokenExtensionFactory;

    /** TODO */
    StorageInterface.Address tokenFactory;

    /** TODO */
    StorageInterface.AddressAddressMapping platformToExtension;

    /** TODO */
    StorageInterface.OrderedAddressesSet tokenExtensions;

    /**
    * @dev TODO
    */
    modifier onlyPlatformOwner(address _platform) {
        if (OwnedContract(_platform).contractOwner() == msg.sender) {
            _;
        }
    }

    function AssetsManager(Storage _store, bytes32 _crate) BaseManager(_store, _crate) {
        tokenExtensionFactory.init("tokenExtensionFactory");
        tokenFactory.init("tokenFactory");
        platformToExtension.init("platformToExtension");
        tokenExtensions.init("tokenExtensions");
    }

    /**
    * @dev TODO
    */
    function init(address _contractsManager, address _tokenExtensionFactory, address _tokenFactory) onlyContractOwner public returns (uint) {
        BaseManager.init(_contractsManager, "AssetsManager");
        setTokenExtensionFactory(_tokenExtensionFactory);
        setTokenFactory(_tokenFactory);

        return OK;
    }

    /**
    * @dev TODO
    */
    function getTokenExtensionFactory() public constant returns (address) {
        return store.get(tokenExtensionFactory);
    }

    /**
    * @dev TODO
    */
    function setTokenExtensionFactory(address _tokenExtensionFactory) onlyContractOwner public returns (uint) {
        require(_tokenExtensionFactory != 0x0);

        store.set(tokenExtensionFactory, _tokenExtensionFactory);
        return OK;
    }

    /**
    * @dev TODO
    */
    function getTokenFactory() public constant returns (address) {
        return store.get(tokenFactory);
    }

    /**
    * @dev TODO
    */
    function setTokenFactory(address _tokenFactory) onlyContractOwner public returns (uint) {
        require(_tokenFactory != 0x0);

        store.set(tokenFactory, _tokenFactory);
        return OK;
    }

    /**
    * @dev TODO
    */
    function containsTokenExtension(address _tokenExtension) public constant returns (bool) {
        return store.includes(tokenExtensions, _tokenExtension);
    }

    /**
    * @dev TODO
    */
    function registerTokenExtension(address _tokenExtension) onlyPlatformOwner(TokenManagementInterface(_tokenExtension).platform()) public returns (uint) {
        if (store.includes(tokenExtensions, _tokenExtension)) {
            return _emitError(ERROR_ASSETS_MANAGER_EXTENSION_ALREADY_EXISTS);
        }

        address _platform = TokenManagementInterface(_tokenExtension).platform();
        if (store.get(platformToExtension, _platform) != 0x0) {
            return _emitError(ERROR_ASSETS_MANAGER_EXTENSION_ALREADY_EXISTS);
        }

        store.add(tokenExtensions, _tokenExtension);
        store.set(platformToExtension, _platform, _tokenExtension);
        _emitTokenExtensionRegistered(_platform, _tokenExtension);
        return OK;
    }

    /**
    * @dev TODO
    */
    function unregisterTokenExtension(address _tokenExtension) onlyPlatformOwner(TokenManagementInterface(_tokenExtension).platform()) public returns (uint) {
        if (!store.includes(tokenExtensions, _tokenExtension)) {
            return _emitError(ERROR_ASSETS_MANAGER_INVALID_INVOCATION);
        }

        store.remove(tokenExtensions, _tokenExtension);
        store.set(platformToExtension, TokenManagementInterface(_tokenExtension).platform(), 0x0);
        _emitTokenExtensionUnregistered(_tokenExtension);
        return OK;
    }

    /**
    * @dev TODO
    */
    function requestTokenExtension(address _platform) public returns (uint) {
        address _tokenExtension = getTokenExtension(_platform);
        if (_tokenExtension != 0x0) {
            _emitTokenExtensionRequested(_platform, _tokenExtension);
            return OK;
        }

        TokenExtensionsFactory _extensionsFactory = TokenExtensionsFactory(store.get(tokenExtensionFactory));
        _tokenExtension = _extensionsFactory.createTokenExtension(_platform);
        store.set(platformToExtension, _platform, _tokenExtension);
        store.add(tokenExtensions, _tokenExtension);

        _emitTokenExtensionRequested(_platform, _tokenExtension);
        return OK;
    }

    /**
    * @dev TODO
    */
    function getTokenExtension(address _platform) public constant returns (address) {
        return store.get(platformToExtension, _platform);
    }

    /**
    * @dev TODO
    */
    function isAssetOwner(bytes32 _symbol, address _user) public constant returns (bool) {
        address _token = getAssetBySymbol(_symbol);
        address _platform = ChronoBankAssetProxyInterface(_token).chronoBankPlatform();
        address _tokenExtension = getTokenExtension(_platform);
        address _assetOwnershipManager = TokenManagementInterface(_tokenExtension).getAssetOwnershipManager();
        return ChronoBankAssetOwnershipManager(_assetOwnershipManager).hasAssetRights(_user, _symbol);
    }

    /**
    * @dev TODO
    */
    function isAssetSymbolExists(bytes32 _symbol) public constant returns (bool) {
        return getAssetBySymbol(_symbol) != 0x0;
    }

    /**
    * @dev TODO
    */
    function getAssetBySymbol(bytes32 _symbol) public constant returns (address) {
        return ERC20ManagerInterface(lookupManager("ERC20Manager")).getTokenAddressBySymbol(_symbol);
    }

    /**
    * @dev TODO
    */
    function getAssetsForOwnerCount(address _platform, address _owner) public constant returns (uint count) {
        TokenManagementInterface _tokenExtension = TokenManagementInterface(getTokenExtension(_platform));
        ChronoBankAssetOwnershipManager _assetsOwnershipManager = ChronoBankAssetOwnershipManager(_tokenExtension.getAssetOwnershipManager());

        uint symbolsCount = _assetsOwnershipManager.symbolsCount();
        uint symbolsIdx;
        bytes32 _symbol;
        for (symbolsIdx = 0; symbolsIdx < symbolsCount; ++symbolsIdx) {
            _symbol = _assetsOwnershipManager.symbols(symbolsIdx);
            if (_assetsOwnershipManager.hasAssetRights(_owner, _symbol)) {
                count++;
            }
        }
    }

    /**
    * @dev TODO
    */
    function getAssetForOwnerAtIndex(address _platform, address _owner, uint _idx) public constant returns (bytes32) {
        TokenManagementInterface _tokenExtension = TokenManagementInterface(getTokenExtension(_platform));
        ChronoBankAssetOwnershipManager _assetsOwnershipManager = ChronoBankAssetOwnershipManager(_tokenExtension.getAssetOwnershipManager());

        uint currentIdx = _idx - 1;
        uint symbolsCount = _assetsOwnershipManager.symbolsCount();
        uint symbolsIdx;
        bytes32 _symbol;
        for (symbolsIdx = _idx; symbolsIdx < symbolsCount; ++symbolsIdx) {
            _symbol = _assetsOwnershipManager.symbols(symbolsIdx);
            if (_assetsOwnershipManager.hasAssetRights(_owner, _symbol) && ++currentIdx == _idx) {
                return _symbol;
            }
        }
    }

    /**
    * @dev TODO
    */
    function getAssetsForOwner(address _platform, address _owner) public constant returns (bytes32[] _symbols) {
        _symbols = new bytes32[](getAssetsForOwnerCount(_platform, _owner));

        TokenManagementInterface _tokenExtension = TokenManagementInterface(getTokenExtension(_platform));
        ChronoBankAssetOwnershipManager _assetsOwnershipManager = ChronoBankAssetOwnershipManager(_tokenExtension.getAssetOwnershipManager());

        uint _originalSymbolsCount = _assetsOwnershipManager.symbolsCount();
        uint _symbolIdx;
        bytes32 _originalSymbol;

        for (uint _originalSymbolIdx = 0; _originalSymbolIdx < _originalSymbolsCount; ++_originalSymbolIdx) {
            _originalSymbol = _assetsOwnershipManager.symbols(_originalSymbolIdx);
            if (_assetsOwnershipManager.hasAssetRights(_owner, _originalSymbol)) {
                _symbols[_symbolIdx++] = _originalSymbol;
            }
        }
    }

    /**
    * @dev TODO
    */
    function getAssetsForOwner(address _owner) public constant returns (bytes32[] _symbols) {
        PlatformsManagerInterface _platformsManager = PlatformsManagerInterface(lookupManager("PlatformsManager"));

        address[] memory _platforms = _getPlatformsForOwner(_owner);
        var (_countAssets, _totalAssetsCount) = _countAssetsForPlatforms(_platforms, _owner);

        _symbols = new bytes32[](_totalAssetsCount);
        uint _platformIdx = 0;
        address _platform;
        for (uint _symbolIdx = 0; _symbolIdx < _totalAssetsCount; ++_platformIdx) {
            _platform = _platforms[_platformIdx];
            for (uint _assetIdx = 0; _assetIdx < _countAssets[_platformIdx]; ++_assetIdx) {
                _symbols[_symbolIdx++] = getAssetForOwnerAtIndex(_platform, _owner, _assetIdx);
            }
        }
    }

    /**
    * @dev TODO
    */
    function getManagersForPlatform(address _platform) public constant returns (address[] _managers) {
        ChronoBankManagersRegistry _managersRegistry = ChronoBankManagersRegistry(_platform);
        uint _managersCount = _managersRegistry.holdersCount();
        uint _managerPointer = 0;
        uint _assetsCount = ChronoBankPlatformInterface(_platform).symbolsCount();
        _managers = new address[](_managersCount);
        for (uint _managerIdx = 0; _managerIdx <= _managersCount; ++_managerIdx) {
            address _manager = _managersRegistry.holders(_managerIdx);

            if (containsTokenExtension(_manager)) {
                continue;
            }

            for (uint _assetIdx = 0; _assetIdx < _assetsCount; ++_assetIdx) {
                bytes32 _symbol = ChronoBankPlatformInterface(_platform).symbols(_assetIdx);

                if (ChronoBankAssetOwnershipManager(_platform).hasAssetRights(_manager, _symbol)) {
                    _managers[_managerPointer++] = _manager;
                    break;
                }
            }
        }
    }

    /**
    * @dev TODO
    */
    function getManagers(address _owner) public constant returns (address[] _managers) {
        PlatformsManagerInterface _platformsManager = PlatformsManagerInterface(lookupManager("PlatformsManager"));
        uint _platformsCount = _platformsManager.getPlatformsForUserCount(_owner);
        _managers = new address[](_numberOfManagers(_owner));
        uint _managersPointer = 0;
        address[] memory _platformManagers;
        for (uint _platformIdx = 0; _platformIdx < _platformsCount; ++_platformIdx) {
            var (_platform,) = _platformsManager.getPlatformForUserAtIndex(_owner, _platformIdx);
            _platformManagers = getManagersForPlatform(_platform);
            _managersPointer = _copyArrayIntoArray(_platformManagers, _managers, _managersPointer);
        }
    }

    /** Helper functions */

    function _getPlatformsForOwner(address _owner) private constant returns (address[] _platforms) {
        PlatformsManagerInterface _platformsManager = PlatformsManagerInterface(lookupManager("PlatformsManager"));
        uint _platformsCount = _platformsManager.getPlatformsForUserCount(_owner);
        _platforms = new address[](_platformsCount);
        for (uint _platformIdx = 0; _platformIdx < _platformsCount; ++_platformIdx) {
            (_platforms[_platformIdx],) = _platformsManager.getPlatformForUserAtIndex(_owner, _platformIdx);
        }
    }

    function _countAssetsForPlatforms(address[] _platforms, address _owner) private constant returns (uint[] _countAssets, uint _totalAssetsCount) {
        _countAssets = new uint[](_platforms.length);
        for (uint _platformIdx = 0; _platformIdx < _platforms.length; ++_platformIdx) {
            _countAssets[_platformIdx] = getAssetsForOwnerCount(_platforms[_platformIdx], _owner);
            _totalAssetsCount += _countAssets[_platformIdx];
        }
    }

    /**
    * @dev TODO
    */
    function _numberOfManagers(address _owner) private constant returns (uint _count) {
        PlatformsManagerInterface _platformsManager = PlatformsManagerInterface(lookupManager("PlatformsManager"));
        uint _platformsCount = _platformsManager.getPlatformsForUserCount(_owner);

        for (uint _platformIdx = 0; _platformIdx < _platformsCount; ++_platformIdx) {
            var (_platform,) = _platformsManager.getPlatformForUserAtIndex(_owner, _platformIdx);
            _count += ChronoBankManagersRegistry(_platform).holdersCount();
        }
    }

    /**
    * @dev TODO
    */
    function _copyArrayIntoArray(address[] _origin, address[] _destination, uint _pointer) private returns (uint) {
        for (uint _originIdx = 0; _originIdx < _origin.length && _origin[_originIdx] != 0x0; ++_originIdx) {
            _destination[_pointer++] = _origin[_originIdx];
        }
        return _pointer;
    }

    /** Events emitting */

    function _emitError(uint _errorCode) private returns (uint) {
        AssetsManagerEmitter(getEventsHistory()).emitError(_errorCode);
        return _errorCode;
    }

    function _emitTokenExtensionRequested(address _platform, address _tokenExtension) private {
        AssetsManagerEmitter(getEventsHistory()).emitTokenExtensionRequested(_platform, _tokenExtension);
    }

    function _emitTokenExtensionRegistered(address _platform, address _tokenExtension) private {
        AssetsManagerEmitter(getEventsHistory()).emitTokenExtensionRegistered(_platform, _tokenExtension);
    }

    function _emitTokenExtensionUnregistered(address _tokenExtension) private {
        AssetsManagerEmitter(getEventsHistory()).emitTokenExtensionUnregistered(_tokenExtension);
    }
}
