const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const ChronoBankTokenManagementExtension = artifacts.require('./ChronoBankTokenManagementExtension.sol')
const ERC20Manager = artifacts.require('./ERC20Manager.sol')
const AssetsManager = artifacts.require('./AssetsManager.sol')
const ErrorsEnum = require('../common/errors')

module.exports = function(deployer, network, accounts) {
    const LHT_SYMBOL = 'LHT'

    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_platformsManager => platformsManager = _platformsManager)
    .then(() => ChronoBankTokenManagementExtension.deployed())
    .then(_chronoBankTokenExtension => _chronoBankTokenExtension.passPlatformOwnership(systemOwner))
    .then(() => ChronoBankPlatform.deployed())
    .then(_chronoBankPlatform => _chronoBankPlatform.claimContractOwnership())
    .then(() => {
        return Promise.resolve()
        .then(() => platformsManager.detachPlatform.call(ChronoBankPlatform.address))
        .then(_code => {
            if (_code != ErrorsEnum.OK) {
                console.log("It's OK, just cannot detach old ChronoBank platform at ", ChronoBankPlatform.address, ". Code: ", _code)
                return
            }

            return Promise.resolve()
            .then(() => platformsManager.detachPlatform(ChronoBankPlatform.address))
        })
    })

    .then(() => {
    if (!(network === 'main' || network === 'ropsten')) {
        return Promise.resolve()
        .then(() => platformsManager.createPlatform())
        .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, 0))
        .then(_platformAddr => ChronoBankPlatform.at(_platformAddr))
        .then(_platform => _platform.claimContractOwnership())
    }
    })
    .then(() => ERC20Manager.deployed())
    .then(_manager => _manager.removeTokenBySymbol(LHT_SYMBOL))
}
