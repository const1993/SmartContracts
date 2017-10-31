const CrowdsaleManager = artifacts.require("./CrowdsaleManager.sol");
const Storage = artifacts.require('./Storage.sol');
const StorageManager = artifacts.require("./StorageManager.sol");
const ContractsManager = artifacts.require("./ContractsManager.sol");
const MultiEventsHistory = artifacts.require("./MultiEventsHistory.sol");

module.exports = function (deployer, network) {
    deployer
    .then(() => StorageManager.deployed())
    .then((_storageManager) => storageManager = _storageManager)

    .then(() => storageManager.giveAccess(CrowdsaleManager.address, 'CrowdsaleManager'))
    .then(() => CrowdsaleManager.deployed())
    .then(_manager => manager = _manager)
    .then(() => manager.init(ContractsManager.address))
    .then(() => MultiEventsHistory.deployed())
    .then(_history => _history.authorize(CrowdsaleManager.address))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] CrowdsaleManager init: #done"))
}
