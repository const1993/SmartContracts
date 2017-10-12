const StringsLib = artifacts.require('./StringsLib.sol')

// already unnecessary
module.exports = function(deployer, network, accounts) {
    deployer.deploy(StringsLib);
}
