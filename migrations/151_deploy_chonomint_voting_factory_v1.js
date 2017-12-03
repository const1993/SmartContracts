var PollFactory = artifacts.require('./PollFactory.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(PollFactory)

        console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Voting entity Factory deploy: #done")
    })
}
