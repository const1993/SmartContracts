const ContractsManager = artifacts.require('./ContractsManager.sol')
const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ERC20Manager = artifacts.require('./ERC20Manager.sol')
const Rewards = artifacts.require('./Rewards.sol')
const RewardsWallet = artifacts.require('./RewardsWallet.sol')

module.exports = function(deployer, network, accounts) {
    const systemOwner = accounts[0]

    deployer
    .then(() => PlatformsManager.deployed())
    .then(_platformsManager => platformsManager = _platformsManager)
    .then(() => ContractsManager.deployed())
    .then(_contractsManager => _contractsManager.removeContract(Rewards.address))
    .then(() => Rewards.deployed())
    .then(_rewards => {
        return Promise.resolve()
        .then(() => platformsManager.getPlatformForUserAtIndex.call(systemOwner, 0))
        .then(_platformAddr => platformsManager.getIdForPlatform.call(_platformAddr))
        .then(_platformId => _rewards.init(ContractsManager.address, RewardsWallet.address, _platformId, 0))
    })
}
