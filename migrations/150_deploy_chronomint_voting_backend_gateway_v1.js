var PollEntityBackend = artifacts.require('./PollEntityBackend.sol')
const ContractsManager = artifacts.require('./ContractsManager.sol')
const ArrayLib = artifacts.require('./ArrayLib.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(PollEntityBackend, ContractsManager.address)

        console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Voting Gateway deploy: #done")
    })
}
