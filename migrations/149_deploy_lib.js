const ArrayLib = artifacts.require('./ArrayLib.sol')

var PollBackend = artifacts.require('./PollBackend.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(ArrayLib)
        await deployer.link(ArrayLib, [PollBackend])
    })
}
