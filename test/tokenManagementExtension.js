const Setup = require("../setup/setup")
const eventsHelper = require('./helpers/eventsHelper')
const ErrorsEnum = require("../common/errors")
const Reverter = require('./helpers/reverter')
const TokenManagementExtension = artifacts.require("./TokenManagementExtension.sol")
const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const ChronoBankAssetWithFee = artifacts.require('./ChronoBankAssetWithFee.sol')
const RewardsWallet = artifacts.require('./RewardsWallet.sol')

contract("TokenManagementExtension", function(accounts) {
    const contractOwner = accounts[0]
    const systemOwner = accounts[0]
    const owner1 = accounts[1]
    const owner2 = accounts[2]
    const nonOwner = accounts[6]

    const reverter = new Reverter(web3)

    let utils = web3._extend.utils
    const zeroAddress = '0x' + utils.padLeft(utils.toHex("0").substr(2), 40)

    function toBytes32(str) {
        return utils.padRight(utils.toHex(str), 66)
    }

    before('setup', function(done) {
        Setup.setup((e) => {
            console.log(e);
            reverter.snapshot((e) => {
                done(e)
            })
        })
    })

    context("asset creation", function () {
        const TOKEN_SYMBOL = "MTT"
        const TOKEN_NAME = "My test tokens"
        const TOKEN_DESCRIPTION = "description of MTT"

        const TOKEN_WITH_FEE_SYMBOL = "MTTF"
        const TOKEN_WITH_FEE_NAME = "My test tokens with fee"
        const TOKEN_WITH_FEE_DESCRIPTION = "description of MTTF"

        let owner = owner1
        let platform
        let platformId
        let tokenExtension

        it("prepare", async () => {
            let newPlatformTx = await Setup.platformsManager.createPlatform("default", { from: owner })
            let event = eventsHelper.extractEvents(newPlatformTx, "PlatformRequested")[0]
            assert.isDefined(event)
            assert.notEqual(event.args.tokenExtension, zeroAddress)
            platformId = event.args.platformId
            platform = await ChronoBankPlatform.at(event.args.platform)
            await platform.claimContractOwnership({ from: owner })
            tokenExtension = await TokenManagementExtension.at(event.args.tokenExtension)
        })

        it("should be able to create an asset by platform owner", async () => {
            let assetCreationResultCode = await tokenExtension.createAssetWithoutFee.call(TOKEN_SYMBOL, TOKEN_NAME, TOKEN_DESCRIPTION, 0, 2, true, { from: owner })
            assert.equal(assetCreationResultCode, ErrorsEnum.OK)

            let assetCreationTx  = await tokenExtension.createAssetWithoutFee(TOKEN_SYMBOL, TOKEN_NAME, TOKEN_DESCRIPTION, 0, 2, true, { from: owner })
            let event = eventsHelper.extractEvents(assetCreationTx, "AssetCreated")[0]
            assert.isDefined(event)

            let isSymbolCreated = await platform.isCreated.call(TOKEN_SYMBOL)
            assert.isOk(isSymbolCreated)
            let tokenMetadata = await Setup.erc20Manager.getTokenMetaData.call(event.args.token)
            assert.notEqual(tokenMetadata[0], zeroAddress)
            assert.equal(tokenMetadata[0], event.args.token)
            assert.equal(tokenMetadata[2], toBytes32(TOKEN_SYMBOL))
        })

        it("should be able to create an asset with fee and ownership request event should be triggered", async () => {
            let assetCreationResultCode = await tokenExtension.createAssetWithFee.call(TOKEN_WITH_FEE_SYMBOL, TOKEN_WITH_FEE_NAME, TOKEN_WITH_FEE_DESCRIPTION, 0, 5, true, RewardsWallet.address, 10, { from: owner })
            assert.equal(assetCreationResultCode, ErrorsEnum.OK)

            let assetCreationTx  = await tokenExtension.createAssetWithFee(TOKEN_WITH_FEE_SYMBOL, TOKEN_WITH_FEE_NAME, TOKEN_WITH_FEE_DESCRIPTION, 0, 5, true, RewardsWallet.address, 10, { from: owner })
            let event = eventsHelper.extractEvents(assetCreationTx, "AssetCreated")[0]
            assert.isDefined(event)

            let isSymbolCreated = await platform.isCreated.call(TOKEN_WITH_FEE_SYMBOL)
            assert.isOk(isSymbolCreated)
            let tokenMetadata = await Setup.erc20Manager.getTokenMetaData.call(event.args.token)
            assert.notEqual(tokenMetadata[0], zeroAddress)
            assert.equal(tokenMetadata[0], event.args.token)
            assert.equal(tokenMetadata[2], toBytes32(TOKEN_WITH_FEE_SYMBOL))
        })

        it("should be able to identify an owner as owner of two assets", async () => {
            let assets = []
            let assetsCount = await Setup.assetsManager.getAssetsForOwnerCount.call(platform.address, owner)
            for (var assetsIdx = 0; assetsIdx < assetsCount; ++assetsIdx) {
                let asset = await Setup.assetsManager.getAssetForOwnerAtIndex.call(platform.address, owner, assetsIdx)
                assets.push(asset)
            }

            assert.isAtLeast(assetsCount, 2)
            assert.include(assets, toBytes32(TOKEN_SYMBOL))
            assert.include(assets, toBytes32(TOKEN_WITH_FEE_SYMBOL))
        })

        it("should not be able to create an asset with already existed symbol", async () => {
            let failedAssetCreationResultCode = await tokenExtension.createAssetWithoutFee.call(TOKEN_SYMBOL, TOKEN_NAME, TOKEN_DESCRIPTION, 0, 5, false, { from: owner })
            assert.equal(failedAssetCreationResultCode, ErrorsEnum.TOKEN_EXTENSION_ASSET_TOKEN_EXISTS)
        })
        it("should not be able to create an asset by non-platform owner", async () => {
            const TOKEN_NS_SYMBOL = "TNS"
            let failedAssetCreationResultCode = await tokenExtension.createAssetWithoutFee.call(TOKEN_NS_SYMBOL, "", "", 0, 1, false, { from: nonOwner })
            assert.equal(failedAssetCreationResultCode, ErrorsEnum.UNAUTHORIZED)
        })

        it('revert', reverter.revert)
    })

    context("crowdsale", function () {
        it("should not be possible to create a crowdsale campaign by non-asset owner")
        it("should be able to create a crowdsale campaign by asset owner")
        it("should not be able to delete a crowdsale campaign by non-asset owner")
        it("should not be able to delete a crowdsale campaign that is not ended")
        it("should be able to delete a crowdsale campaign by an asset owner when time has ended")
    })
})
