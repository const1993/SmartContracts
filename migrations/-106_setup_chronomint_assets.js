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
    //----------
    // const LHT_SYMBOL = 'LHT'
    // const LHT_NAME = 'Labour-hour Token'
    // const LHT_DESCRIPTION = 'ChronoBank Lht Assets'
    // const LHT_BASE_UNIT = 8
    // const IS_REISSUABLE = true
    // const WITH_FEE = true
    //
    // const FEE_VALUE = 100 // 1%
    //
    // const systemOwner = accounts[0]
    //
    // deployer
    // .then(() => PlatformsManager.deployed())
    // .then(_platformsManager => platformsManager = _platformsManager)
    // .then(() => AssetsManager.deployed())
    // .then(_manager => assetsManager = _manager)
    // .then(() => ERC20Manager.deployed())
    // .then(_manager => erc20Manager = _manager)
    // .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, 0))
    // .then(_platformMeta => {
    //     return Promise.resolve()
    //     .then(() => assetsManager.getTokenExtension.call(_platformMeta[0]))
    //     .then(_tokenExtensionAddr => BaseTokenManagementExtension.at(_tokenExtensionAddr))
    //     .then(_tokenExtension => tokenExtension = _tokenExtension)
    //     .then(() => tokenExtension.createAssetWithFee(LHT_SYMBOL, LHT_NAME, LHT_DESCRIPTION, 0, LHT_BASE_UNIT, IS_REISSUABLE, RewardsWallet.address, FEE_VALUE))
    //     .then(() => tokenExtension.getAssetOwnershipManager.call())
    //     .then(_assetOwnershipManagerAddr => ChronoBankAssetOwnershipManager.at(_assetOwnershipManagerAddr))
    //     .then(_assetOwnershipManager => {
    //         return Promise.resolve()
    //         .then(() => _assetOwnershipManager.addAssetPartOwner(LHT_SYMBOL, LOCWallet.address))
    //     })
    // })
}
