const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const ErrorsEnum = require('../common/errors')

module.exports = function(deployer, network, accounts) {
    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_manager => platformsManager = _manager)
    .then(() => platformsManager.createPlatform("Platform"))
}
