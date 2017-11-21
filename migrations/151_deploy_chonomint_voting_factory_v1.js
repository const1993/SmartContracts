var PollEntityFactory = artifacts.require('./PollEntityFactory.sol')
const ContractsManager = artifacts.require('./ContractsManager.sol')
const PollEntityBackend = artifacts.require('./PollEntityBackend.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(PollEntityFactory, ContractsManager.address, PollEntityBackend.address)

        console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Voting entity Factory deploy: #done")
    })
}
