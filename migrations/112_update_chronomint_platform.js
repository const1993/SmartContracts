const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ERC20Manager = artifacts.require('./ERC20Manager.sol')
const AssetsManager = artifacts.require('./AssetsManager.sol')
const ChronoBankAssetWithFee = artifacts.require('./ChronoBankAssetWithFee.sol')
const ChronoBankAssetWithFeeProxy = artifacts.require('./ChronoBankAssetWithFeeProxy.sol')
const ChronoBankAssetOwnershipManager = artifacts.require('./ChronoBankAssetOwnershipManager.sol')
const BaseTokenManagementExtension = artifacts.require('./BaseTokenManagementExtension.sol')
const LOCWallet = artifacts.require('./LOCWallet.sol')
const RewardsWallet = artifacts.require('./RewardsWallet.sol')

module.exports = function(deployer, network, accounts) {
    if (network === 'main') {
        return
    }
    
    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_platformsManager => platformsManager = _platformsManager)
    .then(() => AssetsManager.deployed())
    .then(_manager => assetsManager = _manager)
    .then(() => ERC20Manager.deployed())
    .then(_manager => erc20Manager = _manager)
    .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, 0))
    .then(_platformAddr => {
        return Promise.resolve()
        .then(() => assetsManager.getTokenExtension.call(_platformAddr))
        .then(_tokenExtensionAddr => {
            return Promise.resolve()
            .then(() => BaseTokenManagementExtension.at(_tokenExtensionAddr))
            .then(_tokenExtension => _tokenExtension.getAssetOwnershipManager.call())
            .then(_addr => ChronoBankAssetOwnershipManager.at(_addr))
            .then(_assetOwnershipManager => _assetOwnershipManager.removePartOwner(_tokenExtensionAddr))
            .then(() => assetsManager.unregisterTokenExtension(_tokenExtensionAddr))
        })
        .then(() => assetsManager.requestTokenExtension(_platformAddr))
        .then(() => assetsManager.getTokenExtension.call(_platformAddr))
        .then(_tokenExtensionAddr => {
            return Promise.resolve()
            .then(() => BaseTokenManagementExtension.at(_tokenExtensionAddr))
            .then(_tokenExtension => _tokenExtension.getAssetOwnershipManager.call())
            .then(_addr => ChronoBankAssetOwnershipManager.at(_addr))
            .then(_assetOwnershipManager => _assetOwnershipManager.addPartOwner(_tokenExtensionAddr))
        })
    })
}
