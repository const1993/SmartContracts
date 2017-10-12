const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const ChronoBankTokenManagementExtension = artifacts.require('./ChronoBankTokenManagementExtension.sol')
const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const AssetsManager = artifacts.require('./AssetsManager.sol')
const LOCWallet = artifacts.require('./LOCWallet.sol')
const ChronoBankAssetOwnershipManager = artifacts.require('./ChronoBankAssetOwnershipManager.sol')
const ERC20Interface = artifacts.require('./ERC20Interface.sol')
const AssetDonator = artifacts.require('./AssetDonator.sol')
const ContractsManager = artifacts.require('./ContractsManager.sol')

module.exports = function (deployer, network, accounts) {
    const TIME_SYMBOL = "TIME"
    const LHT_SYMBOL = "LHT"

    const systemOwner = accounts[0]

    deployer
    .then(() => ChronoBankPlatform.deployed())
    .then(_platform => chronoBankPlatform = _platform)
    .then(() => PlatformsManager.deployed())
    .then(_manager => platformsManager = _manager)
    .then(() => AssetsManager.deployed())
    .then(_manager => assetsManager = _manager)

    .then(() => {
        if (network !== 'main') {
            return Promise.resolve()
            .then(() => deployer.deploy(AssetDonator))
            .then(() => AssetDonator.deployed())
            .then(_donator => _donator.init(ContractsManager.address))
            .then(() => chronoBankPlatform.proxies(TIME_SYMBOL))
            .then(_proxyAddress => ERC20Interface.at(_proxyAddress))
            .then(_token => _token.transfer(AssetDonator.address, 1000000000000))
        }
    })

    // skip this step as unnecessary
    .then(() => {
        return;

        Promise.resolve()
        .then(() => ChronoBankTokenManagementExtension.deployed())
        .then(_tokenExtension => tokenExtension = _tokenExtension)
        .then(() => platformsManager.attachPlatform(chronoBankPlatform.address, "ChronoBank"))
        .then(() => assetsManager.registerTokenExtension(tokenExtension.address))
        .then(() => chronoBankPlatform.changeContractOwnership(tokenExtension.address))
        .then(() => tokenExtension.claimPlatformOwnership())
        .then(() => {
            return Promise.resolve()
            .then(() => {
                if (network !== 'main') {
                    return Promise.resolve()
                    .then(() => tokenExtension.claimAssetOwnership(TIME_SYMBOL))
                    .then(() => chronoBankPlatform.changeOwnership(TIME_SYMBOL, tokenExtension.address))
                }
            })
            .then(() => {
                return Promise.resolve()
                .then(() => tokenExtension.claimAssetOwnership(LHT_SYMBOL))
                .then(() => chronoBankPlatform.changeOwnership(LHT_SYMBOL, tokenExtension.address))
            })
        })
        .then(() => {
            return Promise.resolve()
            .then(() => tokenExtension.getAssetOwnershipManager.call())
            .then(_assetOwnershipManagerAddr => ChronoBankAssetOwnershipManager.at(_assetOwnershipManagerAddr))
            .then(_assetOwnershipManager => {
                return _assetOwnershipManager.addAssetPartOwner(LHT_SYMBOL, LOCWallet.address)
            })
        })
    })

    .then(() => console.log("[MIGRATION] [" + parseInt(require("path").basename(__filename)) + "] Setup token extension for ChronoBankPlatform setup: #done"))
}
