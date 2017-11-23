const WalletsFactory = artifacts.require("./WalletsFactory.sol");

module.exports = function (deployer, network) {
        deployer.deploy(WalletsFactory)
            .then(() => console.log("[MIGRATION] [133] WalletsFactory: #done"))
}
