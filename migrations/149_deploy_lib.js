const ArrayLib = artifacts.require('./ArrayLib.sol')

var PollEntityBackend = artifacts.require('./PollEntityBackend.sol')

module.exports = async (deployer, network, accounts) => {
    deployer.then(async () => {
        await deployer.deploy(ArrayLib)
        await deployer.link(ArrayLib, [PollEntityBackend])
    })
}
