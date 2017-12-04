const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ERC20Manager = artifacts.require('./ERC20Manager.sol')
const AssetsManager = artifacts.require('./AssetsManager.sol')
const LOCWallet = artifacts.require('./LOCWallet.sol')
const RewardsWallet = artifacts.require('./RewardsWallet.sol')

module.exports = function(deployer, network, accounts) {
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
        .then(() => {
            return Promise.resolve()
            .then(() => platformsManager.getPlatformsForUserCount.call(systemOwner))
            .then(_numberOfPlatforms => {
                var next = Promise.resolve()
                for (var _platformIdx = 0; _platformIdx < _numberOfPlatforms; ++_platformIdx) {
                    (function () {
                        let idx = _platformIdx;
                        next = next
                        .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, idx))
                        .then(_platformAddr => platforms.push(_platformAddr))
                    })()
                }

                return next
            })
        })
        .then(() => {
            return Promise.resolve()
            .then(() => {
                var tokensPromise = Promise.resolve()
                for (var platformIdx = 0; platformIdx < platforms.length; ++platformIdx) {
                    (function() {
                        let _platformAddr = platforms[platformIdx]
                        tokensPromise = tokensPromise
                        .then(() => platformsManager.detachPlatform(_platformAddr))
                        .then(() => assetsManager.getTokenExtension.call(_platformAddr))
                        .then(_addr => {
                            if (_addr != 0) {
                                return assetsManager.unregisterTokenExtension(_addr)
                            }
                        })
                    })()
                }

                return tokensPromise
            })
        })
    })
    .then(() => erc20Manager.removeTokenBySymbol("LHT"))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Platforms cleanup: #done"))
}
