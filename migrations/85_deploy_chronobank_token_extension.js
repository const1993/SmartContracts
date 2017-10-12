var ChronoBankTokenManagementExtension = artifacts.require('./ChronoBankTokenManagementExtension.sol')
var ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
var ContractsManager = artifacts.require('./ContractsManager.sol')

// already unnecessary
module.exports = function (deployer, network) {
    return;

    deployer
    .then(() => deployer.deploy(ChronoBankTokenManagementExtension, ChronoBankPlatform.address, ContractsManager.address))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] ChronoBankPlatform token extension deploy: #done"))
}
