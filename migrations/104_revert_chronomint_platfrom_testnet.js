const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ERC20Manager = artifacts.require('./ERC20Manager.sol')
const AssetsManager = artifacts.require('./AssetsManager.sol')

// already unnecessary
module.exports = function(deployer, network, accounts) {
    return;

    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_manager => platformsManager = _manager)
    .then(() => ERC20Manager.deployed())
    .then(_manager => erc20Manager = _manager)
    .then(() => AssetsManager.deployed())
    .then(_manager => assetsManager = _manager)
    .then(() => {
        return Promise.resolve()
        .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, 0))
        .then(_platformMeta => _platformMeta[0])
    })
    .then(_addr => platformAddress = _addr)
    .then(() => {
        return Promise.resolve()
        .then(() => assetsManager.getTokenExtension.call(platformAddress))
        .then(_tokenExtensionAddr => assetsManager.unregisterTokenExtension(_tokenExtensionAddr))
        .then(() => {
            return Promise.resolve()
            .then(() => platformsManager.detachPlatform.call(platformAddress))
            .then(() => platformsManager.detachPlatform(platformAddress))
        })
    })
    .then(() => erc20Manager.removeTokenBySymbol("LHT"))
}
