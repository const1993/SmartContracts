pragma solidity ^0.4.11;

import "../core/contracts/ContractsManagerInterface.sol";
import "../assets/AssetsManagerInterface.sol";

contract AssetsManagerMock is AssetsManagerInterface {

    uint constant OK = 1;

    address contractsManager;
    bytes32[] symbols;
    mapping(bytes32 => address) assets;

    function init(address _contractsManager) returns(bool) {
        if(contractsManager != 0x0) {
            return false;
        }

        uint errorCode = ContractsManagerInterface(_contractsManager).addContract(this, "AssetsManager");
        if (OK != errorCode) {
            return false;
        }

        contractsManager = _contractsManager;
        return true;
    }


    function isAssetSymbolExists(bytes32 _symbol) constant returns (bool) {
        return assets[_symbol] != 0x0;
    }

    function getAssetsSymbols() constant returns (bytes32[]) {
        return symbols;
    }

    function getAssetsSymbolsCount() constant returns (uint) {
        return symbols.length;
    }

    function getAssetBySymbol(bytes32 symbol) constant returns (address) {
        return assets[symbol];
    }

    function addAsset(address asset, bytes32 _symbol, address owner) returns (bool) {
        if (assets[_symbol] == 0x0) {
            symbols.push(_symbol);
            assets[_symbol] = asset;
            return true;
        }
        return false;
    }

    function() {
        throw;
    }

    function getAssetsForOwner(address platform, address owner) constant returns (bytes32[]) {
        return symbols;
    }

    function getAssetsForOwnerCount(address platform, address owner) constant returns (uint) {
        return symbols.length;
    }

    function getAssetForOwnerAtIndex(address platform, address owner, uint _index) constant returns (bytes32) {
        return symbols[_index];
    }

    function isAssetOwner(bytes32 _symbol, address _user) constant returns (bool) {
        return true;
    }

    function getTokenExtension(address _platform) constant returns (address) {
        throw;
    }

    function requestTokenExtension(address _platform) returns (uint) {
        throw;
    }
}
