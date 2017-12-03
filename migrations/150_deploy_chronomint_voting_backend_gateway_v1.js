var PollBackend = artifacts.require('./PollBackend.sol')
const ContractsManager = artifacts.require('./ContractsManager.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(PollBackend, ContractsManager.address)

        console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Voting Gateway deploy: #done")
    })
}
