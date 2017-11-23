const WalletsManager = artifacts.require("./WalletsManager.sol");
const Wallet = artifacts.require("./Wallet.sol");
const StorageManager = artifacts.require("./StorageManager.sol");
const ContractsManager = artifacts.require("./ContractsManager.sol");
const MultiEventsHistory = artifacts.require("./MultiEventsHistory.sol");
const WalletsFactory = artifacts.require("./WalletsFactory.sol");

module.exports = async (deployer, network) => {
    deployer.then(async () => {
        let walletsManager = await WalletsManager.deployed();
        await walletsManager.init(ContractsManager.address, WalletsFactory.address);

        console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] TokenFactory setup: #done");
    });
}
