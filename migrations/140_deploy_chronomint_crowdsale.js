var CrowdsaleManager = artifacts.require("./CrowdsaleManager.sol");
const Storage = artifacts.require('./Storage.sol');

module.exports = function (deployer, network) {
    deployer
    .then(() => deployer.deploy(CrowdsaleManager, Storage.address, 'CrowdsaleManager'))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] CrowdsaleManager deploy: #done"))
}
