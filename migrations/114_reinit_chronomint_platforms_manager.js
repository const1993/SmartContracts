const PlatformsManager = artifacts.require("./PlatformsManager.sol")
const ContractsManager = artifacts.require("./ContractsManager.sol")
const ChronoBankPlatformFactory = artifacts.require("./ChronoBankPlatformFactory.sol")

module.exports = function(deployer, network) {
    if (network === 'kovan') {
        return
    }
    
    deployer
    .then(() => ContractsManager.deployed())
    .then(_contractsManager => _contractsManager.removeContract(PlatformsManager.address))
    .then(() => PlatformsManager.deployed())
    .then(_platformsManager => _platformsManager.init(ContractsManager.address, ChronoBankPlatformFactory.address))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] PlatformsManager reinit: #done"))
}
