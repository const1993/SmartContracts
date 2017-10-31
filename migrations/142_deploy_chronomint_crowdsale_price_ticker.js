var CryptocomparePriceTicker = artifacts.require("./CryptocomparePriceTicker.sol");

module.exports = function (deployer, network) {
    deployer
    .then(() => deployer.deploy(CryptocomparePriceTicker))

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Cryptocompare Price Ticker deploy: #done"))
}