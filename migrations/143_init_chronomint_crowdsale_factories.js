const TimeLimitedCrowdsaleFactory = artifacts.require("./TimeLimitedCrowdsaleFactory.sol");
const BlockLimitedCrowdsaleFactory = artifacts.require("./BlockLimitedCrowdsaleFactory.sol");
const Storage = artifacts.require('./Storage.sol');
const StorageManager = artifacts.require("./StorageManager.sol");
const ContractsManager = artifacts.require("./ContractsManager.sol");
const CryptocomparePriceManager = artifacts.require("./CryptocomparePriceManager.sol");

module.exports = function (deployer, network) {
    deployer
    .then(() => StorageManager.deployed())
    .then((_storageManager) => storageManager = _storageManager)

    .then(() => storageManager.giveAccess(TimeLimitedCrowdsaleFactory.address, 'TimeLimitedCrowdsaleFactory'))
    .then(() => TimeLimitedCrowdsaleFactory.deployed())
    .then(_crowdsaleFactory => crowdsaleFactory = _crowdsaleFactory)
    .then(() => crowdsaleFactory.init(ContractsManager.address, CryptocomparePriceManager.address))

    .then(() => storageManager.giveAccess(BlockLimitedCrowdsaleFactory.address, 'BlockLimitedCrowdsaleFactory'))
    .then(() => BlockLimitedCrowdsaleFactory.deployed())
    .then(_crowdsaleFactory => crowdsaleFactory = _crowdsaleFactory)
    .then(() => crowdsaleFactory.init(ContractsManager.address, CryptocomparePriceManager.address))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Crowdsale factories init: #done"))
}
