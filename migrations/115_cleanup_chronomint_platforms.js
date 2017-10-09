const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ERC20Manager = artifacts.require('./ERC20Manager.sol')
const AssetsManager = artifacts.require('./AssetsManager.sol')
const ChronoBankAssetOwnershipManager = artifacts.require('./ChronoBankAssetOwnershipManager.sol')
const BaseTokenManagementExtension = artifacts.require('./BaseTokenManagementExtension.sol')
const LOCWallet = artifacts.require('./LOCWallet.sol')
const RewardsWallet = artifacts.require('./RewardsWallet.sol')

module.exports = function(deployer, network, accounts) {
    if (network === 'kovan') {
        return
    }

    //----------
    const LHT_SYMBOL = 'LHT'

    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_platformsManager => platformsManager = _platformsManager)
    .then(() => AssetsManager.deployed())
    .then(_manager => assetsManager = _manager)
    .then(() => ERC20Manager.deployed())
    .then(_manager => erc20Manager = _manager)
    .then(() => {
        var platforms = []

        return Promise.resolve()
        .then(() => platformsManager.getPlatformsForUserCount.call(systemOwner))
        .then(_platformsCount => {
            var platformsPromise = Promise.resolve()

            for (var platformIdx = 0; platformIdx < _platformsCount; ++platformIdx) {
                (function() {
                    let idx = platformIdx
                    platformsPromise = platformsPromise
                    .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, idx))
                    .then(_addr => platforms.push(_addr))
                })()
            }

            return platformsPromise
        })
        .then(() => {
            return Promise.resolve()
            .then(() => {
                var tokensPromise = Promise.resolve()
                for (var platformIdx = 0; platformIdx < platforms.length; ++platformIdx) {
                    (function() {
                        let _platformAddr = platforms[platformIdx]
                        tokensPromise = tokensPromise
                        .then(() => assetsManager.getTokenExtension.call(_platformAddr))
                        .then(_addr => assetsManager.unregisterTokenExtension(_addr))
                        .then(() => platformsManager.detachPlatform(_platformAddr))
                    })()
                }

                return tokensPromise
            })
        })
    })
    .then(() => erc20Manager.removeTokenBySymbol("LHT"))
}
