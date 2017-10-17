pragma solidity ^0.4.11;

import "../core/platform/ChronoBankPlatformInterface.sol";
import "../core/platform/ChronoBankAssetOwnershipManager.sol";
import "../core/platform/ChronoBankAssetProxyInterface.sol";
import "../core/common/OwnedInterface.sol";
import "../core/contracts/ContractsManagerInterface.sol";
import "../core/erc20/ERC20ManagerInterface.sol";
import "../core/erc20/ERC20Interface.sol";
import "./AssetsManagerInterface.sol";
import "./TokenManagementInterface.sol";
import "./FeeInterface.sol";
import "../timeholder/FeatureFeeAdapter.sol";
import "../core/lib/StringsLib.sol";

contract ChronoBankAsset {
    function init(ChronoBankAssetProxyInterface _proxy) returns (bool);
}


contract TokenFactory {
    function createAsset() returns (address);
    function createAssetWithFee(address owner) returns (address);
    function createProxy() returns (address);
}


contract PlatformFactory {
    function createPlatform(address _eventsHistory, address _owner) returns (address);
}


contract FactoryProvider {
    function getTokenFactory() returns (TokenFactory);
}


contract CrowdsaleManager {
    function createCrowdsale(address _creator, bytes32 _symbol, bytes32 _factoryName) returns (address, uint);
    function deleteCrowdsale(address crowdsale) returns (uint);
}


contract BaseCrowdsale {
    function getSymbol() constant returns (bytes32);
}


contract OwnedContract {
    address public contractOwner;
}


/**
* @dev TODO
*/
contract BaseTokenManagementExtension is TokenManagementInterface, FeatureFeeAdapter {
    uint constant OK = 1;
    uint constant UNAUTHORIZED = 0;
    uint constant ERROR_TOKEN_EXTENSION_ASSET_TOKEN_EXISTS = 23001;
    uint constant ERROR_TOKEN_EXTENSION_ASSET_COULD_NOT_BE_REISSUED = 23002;
    uint constant ERROR_TOKEN_EXTENSION_ASSET_COULD_NOT_BE_REVOKED = 23003;
    uint constant ERROR_TOKEN_EXTENSION_ASSET_OWNER_ONLY = 23004;

    event Error(address indexed self, uint errorCode);
    event AssetCreated(address indexed self, address platform, bytes32 symbol, address token);
    event CrowdsaleCampaignCreated(address indexed self, address platform, bytes32 symbol, address campaign);
    event CrowdsaleCampaignRemoved(address indexed self, address platform, bytes32 symbol, address campaign);

    address public platform;
    address serviceProvider;

    /**
    * @dev TODO
    */
    modifier onlyPlatformOwner() {
        if (OwnedContract(platform).contractOwner() == msg.sender ||
            msg.sender == address(this)) {
            _;
        }
    }

    /**
    * @dev TODO
    */
    modifier onlyPlatform() {
        if (msg.sender == platform ||
            msg.sender == address(this)) {
            _;
        }
    }

    /**
    * @dev TODO
    */
    function BaseTokenManagementExtension(address _platform, address _serviceProvider) {
        platform = _platform;
        serviceProvider = _serviceProvider;
    }

    /**
    * @dev TODO
    */
    function setServiceProvider(address _serviceProvider) onlyPlatformOwner public returns (uint) {
        serviceProvider = _serviceProvider;
        return OK;
    }

    function createAssetWithoutFee(
        bytes32 _symbol,
        string _name,
        string _description,
        uint _value,
        uint8 _decimals,
        bool _isMint,
        bytes32 _tokenImageIpfsHash)
    onlyPlatformOwner
    public
    returns (uint resultCode)
    {
        return _createAssetWithoutFee(_symbol, _name, _description, _value, _decimals, _isMint, _tokenImageIpfsHash, [uint(0)]);
    }

    function _createAssetWithoutFee(
        bytes32 _symbol,
        string _name,
        string _description,
        uint _value,
        uint8 _decimals,
        bool _isMint,
        bytes32 _tokenImageIpfsHash,
        uint[1] memory _result)
    featured(_result)
    private
    returns (uint resultCode)
    {
        resultCode = _prepareAndIssueAssetOnPlatform(_symbol, _name, _description, _value, _decimals, _isMint);
        if (resultCode != OK) {
            return _emitError(resultCode);
        }

        address _asset = _createAsset(getTokenFactory());
        address _token = _bindAssetWithToken(getTokenFactory(), _asset, _symbol, _name, _value, _decimals, _tokenImageIpfsHash);

        AssetCreated(this, platform, _symbol, _token);

        _result[0] = OK;
        return OK;
    }

    function createAssetWithFee(
        bytes32 _symbol,
        string _name,
        string _description,
        uint _value,
        uint8 _decimals,
        bool _isMint,
        address _feeAddress,
        uint32 _feePercent,
        bytes32 _tokenImageIpfsHash)
    onlyPlatformOwner
    public
    returns (uint resultCode) {
        return _createAssetWithFee(_symbol, _name, _description, _value, _decimals,_isMint, _feeAddress, _feePercent, _tokenImageIpfsHash, [uint(0)]);
    }

    function _createAssetWithFee(
        bytes32 _symbol,
        string _name,
        string _description,
        uint _value,
        uint8 _decimals,
        bool _isMint,
        address _feeAddress,
        uint32 _feePercent,
        bytes32 _tokenImageIpfsHash,
        uint[1] memory _result)
    featured(_result)
    private
    returns (uint resultCode)
    {
        require(_feeAddress != 0x0);

        resultCode = _prepareAndIssueAssetOnPlatform(_symbol, _name, _description, _value, _decimals, _isMint);
        if (resultCode != OK) {
            return _emitError(resultCode);
        }

        address _token = _bindAssetWithToken(getTokenFactory(), _deployAssetWithFee(getTokenFactory(), _feeAddress, _feePercent), _symbol, _name, _value, _decimals, _tokenImageIpfsHash);
        AssetCreated(this, platform, _symbol, _token);

        _result[0] = OK;
        return OK;
    }

    function getTokenFactory() constant returns (TokenFactory) {
        return FactoryProvider(lookupManager("AssetsManager")).getTokenFactory();
    }

    /**
    * Creates crowdsale campaign of a token with provided symbol
    *
    * @param _symbol a token symbol
    *
    * @return result code of an operation
    */
    function createCrowdsaleCampaign(bytes32 _symbol, bytes32 _crowdsaleFactoryName)
    onlyPlatformOwner
    public
    returns (uint)
    {
        return _createCrowdsaleCampaign(_symbol, _crowdsaleFactoryName, [uint(0)]);
    }

    function _createCrowdsaleCampaign(
        bytes32 _symbol,
        bytes32 _crowdsaleFactoryName,
        uint[1] memory _result)
    featured(_result)
    private
    returns (uint)
    {
        require(_symbol != 0x0);
        require(_crowdsaleFactoryName != 0x0);

        ChronoBankAssetOwnershipManager _assetOwnershipManager = ChronoBankAssetOwnershipManager(getAssetOwnershipManager());
        CrowdsaleManager crowdsaleManager = CrowdsaleManager(lookupManager("CrowdsaleManager"));

        var (_crowdsale, result) = crowdsaleManager.createCrowdsale(msg.sender, _symbol, _crowdsaleFactoryName);
        if (result != OK) {
            return _emitError(result);
        }

        if( OK != _assetOwnershipManager.addAssetPartOwner(_symbol, _crowdsale)) revert();

        CrowdsaleCampaignCreated(this, platform, _symbol, _crowdsale);

        _result[0] = OK;
        return OK;
    }

    /**
    * Stops token's crowdsale
    *
    * @param _crowdsale a crowdsale address
    *
    * @return result result code of an operation
    */
    function deleteCrowdsaleCampaign(address _crowdsale) onlyPlatformOwner public returns (uint result) {
        bytes32 _symbol = BaseCrowdsale(_crowdsale).getSymbol();
        ChronoBankAssetOwnershipManager _assetOwnershipManager = ChronoBankAssetOwnershipManager(getAssetOwnershipManager());

        CrowdsaleManager crowdsaleManager = CrowdsaleManager(lookupManager("CrowdsaleManager"));

        result = crowdsaleManager.deleteCrowdsale(_crowdsale);
        if (result != OK) {
            return _emitError(result);
        }

        if(OK != _assetOwnershipManager.removeAssetPartOwner(_symbol, _crowdsale)) revert();

        CrowdsaleCampaignRemoved(this, platform, _symbol, _crowdsale);
        return OK;
    }

    /**
    * @dev TODO
    */
    function _prepareAndIssueAssetOnPlatform(bytes32 _symbol, string _name, string _description, uint _value, uint8 _decimals, bool _isMint) private returns (uint) {
        ERC20ManagerInterface _erc20Manager = ERC20ManagerInterface(lookupManager("ERC20Manager"));
        if (_erc20Manager.getTokenAddressBySymbol(_symbol) != 0x0) {
            return ERROR_TOKEN_EXTENSION_ASSET_TOKEN_EXISTS;
        }

        return ChronoBankPlatformInterface(platform).issueAsset(_symbol, _value, _name, _description, _decimals, _isMint, msg.sender);
    }

    /**
    * @dev TODO
    */
    function _bindAssetWithToken(TokenFactory _factory, address _asset, bytes32 _symbol, string _name, uint _value, uint8 _decimals, bytes32 _ipfsHash) private returns (address token) {
        token = _factory.createProxy();

        if (OK != ChronoBankPlatformInterface(platform).setProxy(token, _symbol)) revert();

        ChronoBankAssetOwnershipManager _assetOwnershipManager = ChronoBankAssetOwnershipManager(getAssetOwnershipManager());
        ChronoBankAssetProxyInterface(token).init(platform, StringsLib.bytes32ToString(_symbol), _name);
        ChronoBankAssetProxyInterface(token).proposeUpgrade(_asset);
        ChronoBankAsset(_asset).init(ChronoBankAssetProxyInterface(token));
        _assetCreationSetupFinished(_symbol, platform, token, msg.sender);
        _assetOwnershipManager.addAssetPartOwner(_symbol, this);
        _assetOwnershipManager.changeOwnership(_symbol, msg.sender);

        if(OK != _addToken(token, _symbol, _decimals, _ipfsHash)) revert();
    }

    /**
    * @dev TODO
    */
    function _deployAssetWithFee(TokenFactory _factory, address _feeAddress, uint32 _fee) private returns (address _asset) {
        _asset = _factory.createAssetWithFee(this);
        FeeInterface(_asset).setupFee(_feeAddress, _fee);
        OwnedInterface(_asset).transferContractOwnership(msg.sender);
    }

    /**
    * @dev TODO
    */
    function _createAsset(TokenFactory _factory) private returns (address _asset) {
        _asset = _factory.createAsset();
    }

    /**
    * Adds token to ERC20Manager contract
    * @dev Make as a separate function because of stack size limits
    *
    * @param token token's address
    * @param symbol asset's symbol
    * @param decimals number of digits after floating point
    *
    * @return errorCode result code of an operation
    */
    function _addToken(address token, bytes32 symbol, uint8 decimals, bytes32 _ipfsHash) private returns (uint errorCode) {
        ERC20ManagerInterface erc20Manager = ERC20ManagerInterface(lookupManager("ERC20Manager"));
        errorCode = erc20Manager.addToken(token, bytes32(0), symbol, bytes32(0), decimals, _ipfsHash, bytes32(0));
    }

    /**
    * @dev TODO
    */
    function lookupManager(bytes32 _identifier) constant returns (address manager) {
        manager = ContractsManagerInterface(serviceProvider).getContractAddressByType(_identifier);
        assert(manager != 0x0);
    }

    /**
    * TODO
    * @dev no-op and implement in inhereted contracts
    */
    function _assetCreationSetupFinished(bytes32 _symbol, address _platform, address _token, address _sender) internal {
    }

    function _emitError(uint _errorCode) internal returns (uint) {
        Error(this, _errorCode);
        return _errorCode;
    }
}
