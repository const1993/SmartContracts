var CryptocomparePriceManager = artifacts.require("./CryptocomparePriceManager.sol");

module.exports = function (deployer, network) {
    deployer
    .then(() => deployer.deploy(CryptocomparePriceManager))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Cryptocompare Price Ticker deploy: #done"))
}
