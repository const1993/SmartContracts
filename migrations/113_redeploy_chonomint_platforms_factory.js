var ChronoBankPlatformFactory = artifacts.require('./ChronoBankPlatformFactory.sol');

module.exports = function (deployer, network) {
    if (network === 'kovan') {
        return
    }

    deployer
    .then(() => deployer.deploy(ChronoBankPlatformFactory))
    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] ChronoBank Platform Factory redeploy: #done"))
}
