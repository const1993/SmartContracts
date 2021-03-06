const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const ErrorsEnum = require('../common/errors')

module.exports = function(deployer, network, accounts) {
    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_manager => platformsManager = _manager)
    .then(() => platformsManager.createPlatform.call())
    .then(_code => {
        if (_code != ErrorsEnum.OK) {
            throw "Bad. Cannot request new platform. Code: " + _code
        }

        return Promise.resolve()
        .then(() => platformsManager.createPlatform())
    })
    .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, 0))
    .then(_platformAddr => ChronoBankPlatform.at(_platformAddr))
    .then(_platform => _platform.claimContractOwnership())
}
