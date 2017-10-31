var TimeLimitedCrowdsaleFactory = artifacts.require("./TimeLimitedCrowdsaleFactory.sol");
var BlockLimitedCrowdsaleFactory = artifacts.require("./BlockLimitedCrowdsaleFactory.sol");
const Storage = artifacts.require('./Storage.sol');

module.exports = function (deployer, network) {
    deployer
    .then(() => deployer.deploy(TimeLimitedCrowdsaleFactory, Storage.address, 'TimeLimitedCrowdsaleFactory'))
    .then(() => deployer.deploy(BlockLimitedCrowdsaleFactory, Storage.address, 'BlockLimitedCrowdsaleFactory'))
    
    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Crowdsale factories: #done"))
}
