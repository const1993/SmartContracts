const Setup = require('../setup/setup')
const ErrorsEnum = require("../common/errors")
var eventsHelper = require('./helpers/eventsHelper');
const bytes32 = require('./helpers/bytes32');
const Reverter = require('./helpers/reverter')

const AssetsManager = artifacts.require('./AssetsManager.sol')
const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const TokenCrowdsaleManagementInterface = artifacts.require('./TokenCrowdsaleManagementInterface.sol')
const TimeLimitedCrowdsale = artifacts.require('./TimeLimitedCrowdsale.sol')
const CrowdsaleManager = artifacts.require('./CrowdsaleManager.sol')
const TimeLimitedCrowdsaleFactory = artifacts.require('./TimeLimitedCrowdsaleFactory.sol')
const FakePriceTicker = artifacts.require('./FakePriceTicker.sol')
const PlatformTokenExtensionGatewayManagerEmitter = artifacts.require('./PlatformTokenExtensionGatewayManagerEmitter.sol')

Array.prototype.unique = function() {
  return this.filter(function (value, index, self) {
    return self.indexOf(value) === index;
  });
}

let sendEtherPromise = (from, to, value) => {
    return new Promise(function (resolve, reject) {
        web3.eth.sendTransaction({from: from, to: to, value: 10, gas: 4700000}, (function (e, result) {
            if (e != null) {
                reject(e);
            } else {
                resolve(result);
            }
        }))
    })
}

contract('CrowdsaleManager', function(accounts) {
    const TOKEN_1 = 'AWSM';   //reissuable
    const TOKEN_2 = 'AWSM2'; //non-reissuable

    const systemOwner = accounts[0]
    const nonOwner = accounts[1];
    const tokenOwner = accounts[5];
    const fund = accounts[9];

    const crowdsaleFactoryName = "TimeLimitedCrowdsaleFactory";

    const reverter = new Reverter(web3)

    let utils = web3._extend.utils
    const zeroAddress = '0x' + utils.padLeft(utils.toHex("0").substr(2), 40)

    let platform
    let tokenExtension
    let tokenExtensionEmitter

    before('setup', function(done) {
        PlatformsManager.deployed()
        .then(_platformsManager => platformsManager = _platformsManager)
        .then(() => platformsManager.createPlatform({ from: tokenOwner }))
        .then(_tx => {
            let platformRequestedEvent = eventsHelper.extractEvents(_tx, "PlatformRequested")[0]
            assert.isDefined(platformRequestedEvent)

            return Promise.resolve()
            .then(() => ChronoBankPlatform.at(platformRequestedEvent.args.platform))
            .then(_platform => platform = _platform)
            .then(() => TokenCrowdsaleManagementInterface.at(platformRequestedEvent.args.tokenExtension))
            .then(_tokenExtension => tokenExtension = _tokenExtension)
            .then(() => PlatformTokenExtensionGatewayManagerEmitter.at(platformRequestedEvent.args.tokenExtension))
            .then(_emitter => tokenExtensionEmitter = _emitter)
        })
        .then(() => tokenExtension.createAssetWithoutFee(TOKEN_1, "Awesome Token 1",'Token 1', 0, 0, true, 0x0, { from: tokenOwner }))
        .then(() => tokenExtension.createAssetWithoutFee(TOKEN_2, "Awesome Token 2",'Token 2', 100, 0, false, 0x0, { from: tokenOwner }))
        .then(() => TimeLimitedCrowdsaleFactory.deployed())
        .then(crowdsaleFactory => crowdsaleFactory.setPriceTicker(FakePriceTicker.address))
        .then(() => {
            Setup.setup(() => {
               reverter.snapshot(done)
            })
        })
    });

    context("Security checks", function () {
        it("CrowdsaleManager has correct ContractsManager address.", async () => {
            let contractsManagerAddr = await Setup.crowdsaleManager.contractsManager.call()
            assert.equal(contractsManagerAddr, Setup.contractsManager.address)
        })

        it("CrowdsaleManager has correct Events History address.", async () => {
            let eventsHistoryAddr = await Setup.crowdsaleManager.getEventsHistory.call()
            assert.equal(eventsHistoryAddr, Setup.multiEventsHistory.address)
        })

        it("Should not be possible to init crowdsaleManager by non-owner", async () => {
            let failedResultCode = await Setup.crowdsaleManager.init.call(Setup.contractsManager.address, { from: nonOwner })
            assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)
        })

        it("Destroy performaed by non-owner has no effect", async () => {
            await Setup.crowdsaleManager.destroy({ from: nonOwner })
            let contractsManagerAddr = await Setup.crowdsaleManager.contractsManager.call()
            assert.equal(contractsManagerAddr, Setup.contractsManager.address)
        })

        it("Should not be possible to start crowdsale via direct `createCrowdsale` execution", async () => {
            let failedResultTuple = await Setup.crowdsaleManager.createCrowdsale.call(nonOwner, "LHT", crowdsaleFactoryName)
            assert.equal(failedResultTuple[0], 0x0)
            assert.equal(failedResultTuple[1].toNumber(), ErrorsEnum.UNAUTHORIZED)
        })

        it("Should not be possible to delete any crowdsale via direct `deleteCrowdsale` execution", async () => {
            let failedResultCode = await Setup.crowdsaleManager.deleteCrowdsale.call(0x0)
            assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)
        })
    })

    context("CRUD test", function() {
        var campaignAddr

        it("Should not be possible to start crowdsale campaign by non-asset-owner", async () => {
            let failedResultCode = await tokenExtension.createCrowdsaleCampaign.call(TOKEN_1, crowdsaleFactoryName, { from: nonOwner })
            assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)
        })

        it("Should be possible to start crowdsale campaign by asset-owner", async () => {
            let successCreateCrowdsaleResultCode = await tokenExtension.createCrowdsaleCampaign.call(TOKEN_1, crowdsaleFactoryName, { from: tokenOwner })
            assert.equal(successCreateCrowdsaleResultCode.toNumber(), ErrorsEnum.OK)

            let createCrowdsaleTx = await tokenExtension.createCrowdsaleCampaign(TOKEN_1, crowdsaleFactoryName, { from: tokenOwner })
            let event = (await eventsHelper.findEvent([tokenExtensionEmitter], createCrowdsaleTx, "CrowdsaleCampaignCreated"))[0]
            assert.isDefined(event)

            campaignAddr = event.args.campaign.valueOf()
            let isAssetOwner = await Setup.assetsManager.isAssetOwner.call(TOKEN_1, campaignAddr)
            assert.isTrue(isAssetOwner)
        })

        it("Should not be possible to delete crowdsale campaign by non-asset-owner", async () => {
            let failedResultCode = await tokenExtension.deleteCrowdsaleCampaign.call(campaignAddr, { from: nonOwner })
            assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)
        })

        it("Should be possible to delete newly created and not started crowdsale campaign by asset-owner", async () => {
            let successDeleteCrowdsaleResultCode = await tokenExtension.deleteCrowdsaleCampaign.call(campaignAddr, { from: tokenOwner })
            assert.equal(successDeleteCrowdsaleResultCode.toNumber(), ErrorsEnum.OK)

            let deleteCrowdsaleTx = await tokenExtension.deleteCrowdsaleCampaign(campaignAddr, { from: tokenOwner })
            let event = (await eventsHelper.findEvent([tokenExtensionEmitter], deleteCrowdsaleTx, "CrowdsaleCampaignRemoved"))[0]
            assert.isDefined(event)

            let deletedCampaign = event.args.campaign.valueOf()
            assert.equal(deletedCampaign, campaignAddr)

            let isAssetOwner = await Setup.assetsManager.isAssetOwner.call(TOKEN_1, deletedCampaign)
            assert.isFalse(isAssetOwner)
        })

        it("revert", reverter.revert)
    })

    context("Ether crowdsale", function() {
        var campaign
        var etherSenderAddr = accounts[0]

        it("Should be possible to start Ether crowdsale campaign by asset-owner", async () => {
            let successCreateCrowdsaleResultCode = await tokenExtension.createCrowdsaleCampaign.call(TOKEN_1, crowdsaleFactoryName, { from: tokenOwner })
            assert.equal(successCreateCrowdsaleResultCode.toNumber(), ErrorsEnum.OK)
            let createCrowdsaleTx = await tokenExtension.createCrowdsaleCampaign(TOKEN_1, crowdsaleFactoryName, { from: tokenOwner })
            let event = (await eventsHelper.findEvent([tokenExtensionEmitter], createCrowdsaleTx, "CrowdsaleCampaignCreated"))[0]
            assert.isDefined(event)

            let campaignAddress = event.args.campaign.valueOf()
            let isAssetOwner = await Setup.assetsManager.isAssetOwner.call(TOKEN_1, campaignAddress)
            assert.isTrue(isAssetOwner)
            campaign = await TimeLimitedCrowdsale.at(campaignAddress)
            let erc20Manager = await campaign.lookupERC20Service.call()
            assert.equal(erc20Manager, Setup.erc20Manager.address)
        })

        it("Should be not possible to send Ether to crowdsale with empty `fund`", async () => {
            let fundAddr = await campaign.fund.call()
            assert.equal(fundAddr, 0x0)

            try {
                await sendEtherPromise(etherSenderAddr, campaign.address, 10)
                assert.isTrue(false)
            } catch(e) {
                assert.isTrue(true)
            }
        })

        it("Should be not possible to init Ether to campaign by non-owner", async () => {
            await campaign.init("USD", 1000, 1000000, 1, 0, Date.now(), Date.now() + 6000, { from: nonOwner })

            let isRunning = await campaign.isRunning.call()
            assert.isFalse(isRunning)
        })

        it("Should be not possible to set `fund` by non-asset-owner", async () => {
            let failedResultCode = await campaign.enableEtherSale.call(fund, { from: nonOwner })
            assert.equal(failedResultCode.toNumber(), ErrorsEnum.UNAUTHORIZED)

            await campaign.enableEtherSale(fund, { from: nonOwner })
            let fundAddr = await campaign.fund.call()
            assert.equal(fundAddr, 0x0)
        })

        it("Should be possible to set `fund` by asset-owner", async () => {
            let successEnableEtherSaleeResultCode = await campaign.enableEtherSale.call(fund, { from: tokenOwner })
            assert.equal(successEnableEtherSaleeResultCode, ErrorsEnum.OK)

            let enableEtherSaleTx = await campaign.enableEtherSale(fund, { from: tokenOwner })
            let event = (await eventsHelper.findEvent([campaign], enableEtherSaleTx, "SaleAgentRegistered"))[0]
            assert.isDefined(event)
            assert.equal(event.args.saleAgent, campaign.address)
            assert.equal(event.args.symbol, bytes32("ETH"))

            let salesAgent = await campaign.getSalesAgent.call("ETH")
            assert.equal(salesAgent, campaign.address)
            let fundAddr = await campaign.fund.call()
            assert.equal(fundAddr, fund)

            let isRunning = await campaign.isRunning.call()
            assert.isFalse(isRunning)
            let priceTickerAddr = await campaign.getPriceTicker.call()
            assert.equal(priceTickerAddr, FakePriceTicker.address)
        })

        it("Should be possible to init campaign by owner", async () => {
            await campaign.init("USD", 1000, 1000000, 1, 0, (Date.now() - 6000) / 1000, (Date.now() + 60000)/1000 , { from: tokenOwner })

            let goal = await campaign.getGoal.call()
            assert.equal("USD", web3.toUtf8(goal[0]))
            assert.equal("1000", goal[1].toNumber())
            assert.equal("1000000", goal[2].toNumber())
            assert.equal("1", goal[3].toNumber())
            assert.equal("0", goal[4].toNumber())

            let isRunning = await campaign.isRunning.call()
            assert.isTrue(isRunning)
        })

        it("Should be not possible to init campaign by owner once again", async () => {
            await campaign.init("DJHF", 1, 10, 1, 0, Date.now() - 6000, Date.now() + 6000, {from: tokenOwner})

            let goal = await campaign.getGoal.call()
            assert.equal("USD", web3.toUtf8(goal[0]))
            assert.equal("1000", goal[1].toNumber())
            assert.equal("1000000", goal[2].toNumber())
            assert.equal("1", goal[3].toNumber())
            assert.equal("0", goal[4].toNumber())
        })

        it("Should be possible to send Ether to crowdsale", async () => {
            try {
                await sendEtherPromise(etherSenderAddr, campaign.address, 10)
                let balance = await platform.balanceOf.call(etherSenderAddr, TOKEN_1)
                assert.equal(balance.toNumber(), 10)
            } catch (e) {
                assert.isTrue(false)
            }
        })

        it("Should be possible to send Ether to crowdsale twice", async () => {
            try {
                await sendEtherPromise(etherSenderAddr, campaign.address, 10)
                let balance = await platform.balanceOf.call(etherSenderAddr, TOKEN_1)
                assert.equal(balance.toNumber(), 20)
            } catch(e) {
                console.log("thrown error", e);
                assert.isTrue(false)
            }
        })

        it("Should be not possible to withdraw Ether if running", async () => {
            try {
                await campaign.refund()
                assert.isTrue(false)
            } catch(e) {
                assert.isTrue(true)
            }
        })

        it("revert", reverter.revert)
    })

    context("aggregation methods: tokens on crowdsale", function () {
        const TOKEN_SYMBOL_1 = "TS1"
        const TOKEN_SYMBOL_2 = "TS2"

        let otherTokenOwner = accounts[7]

        // it("snapshot", reverter.snapshot)

        it("should show 1 token on crowdsale for tokenOwner", async () => {
            let createdTokenTx = await tokenExtension.createAssetWithoutFee(TOKEN_SYMBOL_1, TOKEN_SYMBOL_1, "description of token", 1000, 1, true, 0x0, { from: tokenOwner })
            let tokenEvent = (await eventsHelper.findEvent([tokenExtensionEmitter], createdTokenTx, "AssetCreated"))[0]
            assert.isDefined(tokenEvent)

            let startCrowdsaleTx = await tokenExtension.createCrowdsaleCampaign(TOKEN_SYMBOL_1, crowdsaleFactoryName, { from: tokenOwner })
            let crowdsaleEvent = (await eventsHelper.findEvent([tokenExtensionEmitter], startCrowdsaleTx, "CrowdsaleCampaignCreated"))[0]
            assert.isDefined(crowdsaleEvent)

            let campaign = await TimeLimitedCrowdsale.at(crowdsaleEvent.args.campaign)

            try {
                await campaign.init("USD", 1000, 1000000, 1, 0, (Date.now() - 6000) / 1000, (Date.now() + 60000)/1000 , { from: tokenOwner })
            } catch (e) {
                assert.isTrue(false)
            }

            let tokensOnCrowdsale = await Setup.crowdsaleManager.getTokensOnCrowdsale.call(tokenOwner)
            let uniqueTokens = tokensOnCrowdsale.unique().filter(e => e !== zeroAddress)
            assert.lengthOf(uniqueTokens, 1)
            assert.include(uniqueTokens, tokenEvent.args.token)
        })

        it("should still show 1 token on crowdsale after passing token ownership to other owner", async () => {
            let createdTokenTx = await tokenExtension.createAssetWithoutFee(TOKEN_SYMBOL_2, TOKEN_SYMBOL_2, "description of token", 2000, 1, true, 0x0, { from: tokenOwner })
            let tokenEvent = (await eventsHelper.findEvent([tokenExtensionEmitter], createdTokenTx, "AssetCreated"))[0]
            assert.isDefined(tokenEvent)

            let startCrowdsaleTx = await tokenExtension.createCrowdsaleCampaign(TOKEN_SYMBOL_2, crowdsaleFactoryName, { from: tokenOwner })
            let crowdsaleEvent = (await eventsHelper.findEvent([tokenExtensionEmitter], startCrowdsaleTx, "CrowdsaleCampaignCreated"))[0]
            assert.isDefined(crowdsaleEvent)

            let campaign = await TimeLimitedCrowdsale.at(crowdsaleEvent.args.campaign)

            try {
                await campaign.init("EUR", 1000, 1000000, 1, 0, (Date.now() - 6000) / 1000, (Date.now() + 60000)/1000 , { from: tokenOwner })
            } catch (e) {
                assert.isTrue(false)
            }

            let tokenPlatformAddr = await tokenExtension.platform()
            let tokenPlatform = await ChronoBankPlatform.at(tokenPlatformAddr)
            let changeOwnershipResultCode = await tokenPlatform.changeOwnership.call(TOKEN_SYMBOL_2, otherTokenOwner, { from: tokenOwner })
            assert.equal(changeOwnershipResultCode.toNumber(), ErrorsEnum.OK)

            await tokenPlatform.changeOwnership(TOKEN_SYMBOL_2, otherTokenOwner, { from: tokenOwner })

            {
                let tokensOnCrowdsale = await Setup.crowdsaleManager.getTokensOnCrowdsale.call(tokenOwner)
                let uniqueTokens = tokensOnCrowdsale.unique().filter(e => e !== zeroAddress)
                assert.lengthOf(uniqueTokens, 1)
            }

            {
                let tokensOnCrowdsale = await Setup.crowdsaleManager.getTokensOnCrowdsale.call(otherTokenOwner)
                let uniqueTokens = tokensOnCrowdsale.unique().filter(e => e !== zeroAddress)
                assert.lengthOf(uniqueTokens, 1)
                assert.include(uniqueTokens, tokenEvent.args.token)
            }
        })

        it("should show 2 tokens after adding a new user as a part owner of a token", async () => {
            let token2Addr = await Setup.erc20Manager.getTokenAddressBySymbol.call(TOKEN_SYMBOL_2)
            let tokenPlatformAddr = await tokenExtension.platform()
            let tokenPlatform = await ChronoBankPlatform.at(tokenPlatformAddr)
            await tokenPlatform.addAssetPartOwner(TOKEN_SYMBOL_2, tokenOwner, { from: otherTokenOwner })

            {
                let tokensOnCrowdsale = await Setup.crowdsaleManager.getTokensOnCrowdsale.call(tokenOwner)
                let uniqueTokens = tokensOnCrowdsale.unique().filter(e => e !== zeroAddress)
                assert.lengthOf(uniqueTokens, 2)
                assert.include(uniqueTokens, token2Addr)
            }
        })

        it("revert", reverter.revert)
    })
})
