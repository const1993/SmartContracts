var VotingManager = artifacts.require('./VotingManager.sol')
const Storage = artifacts.require('./Storage.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(VotingManager, Storage.address, "VotingManager_v1")

        console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Voting Manager deploy: #done")
    })
}
