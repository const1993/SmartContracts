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
    modifier onlyTokenExtension() {
        if (!store.includes(tokenExtensions, msg.sender)) {
            revert();
        }
        _;
    }

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
    function registerTokenExtension(address _tokenExtension) onlyContractOwner public returns (uint) {
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
        store.set(platformToExtension, TokenManagementInterface(_tokenExtension).platform(), _tokenExtension);
        _emitTokenExtensionUnregistered(_tokenExtension);
        return OK;
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
