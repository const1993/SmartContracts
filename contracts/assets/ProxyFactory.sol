pragma solidity ^0.4.11;

import {ChronoBankAssetProxy as Proxy} from "../core/platform/ChronoBankAssetProxy.sol";
import "../core/platform/ChronoBankAssetWithFee.sol";

/**
* @title Implementation of token and proxy factory. Creates instances of ChronoBank assets and proxies
*/
contract ProxyFactory {

    /**
    * @dev Creates ChronoBankAsset contract
    */
    function createAsset() returns(address) {
        address asset;
        asset = new ChronoBankAsset();
        return asset;
    }

    /**
    * @dev Creates ChronoBankAssetWithFee contract
    */
    function createAssetWithFee(address owner) returns(address) {
        ChronoBankAssetWithFee asset;
        asset = new ChronoBankAssetWithFee();
        asset.transferContractOwnership(owner);
        return asset;
    }

    /**
    * @dev Creates ChronoBankAssetProxy contract
    */
    function createProxy() returns(address) {
        address proxy = new Proxy();
        return proxy;
    }

    function() {
        revert();
    }
}
