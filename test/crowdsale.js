const Setup = require('../setup/setup')
const ErrorsEnum = require("../common/errors")
var eventsHelper = require('./helpers/eventsHelper');
const bytes32 = require('./helpers/bytes32');
const abiDecoder = require('abi-decoder')

const AssetsManager = artifacts.require('./AssetsManager.sol')
const PlatformsManager = artifacts.require('./PlatformsManager.sol')
const ChronoBankPlatform = artifacts.require('./ChronoBankPlatform.sol')
const TokenManagementInterface = artifacts.require('./TokenManagementInterface.sol')
const TimeLimitedCrowdsale = artifacts.require('./TimeLimitedCrowdsale.sol')
const CrowdsaleManager = artifacts.require('./CrowdsaleManager.sol')
const TimeLimitedCrowdsaleFactory = artifacts.require('./TimeLimitedCrowdsaleFactory.sol')
const FakePriceTicker = artifacts.require('./FakePriceTicker.sol')
const PlatformTokenExtensionGatewayManagerEmitter = artifacts.require('./PlatformTokenExtensionGatewayManagerEmitter.sol')

contract('CrowdsaleManager', function(accounts) {
    const TOKEN_1 = 'AWSM';   //reissuable
    const TOKEN_2 = 'AWSM2'; //non-reissuable

    const systemOwner = accounts[0]
    const nonOwner = accounts[1];
    const tokenOwner = accounts[5];
    const fund = accounts[9];

    const crowdsaleFactoryName = "TimeLimitedCrowdsaleFactory";

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
            .then(() => TokenManagementInterface.at(platformRequestedEvent.args.tokenExtension))
            .then(_tokenExtension => tokenExtension = _tokenExtension)
            .then(() => PlatformTokenExtensionGatewayManagerEmitter.at(platformRequestedEvent.args.tokenExtension))
            .then(_emitter => tokenExtensionEmitter = _emitter)
            // .then(() => abiDecoder.addABI(tokenExtensionEmitter.abi))
        })
        .then(() => tokenExtension.createAssetWithoutFee(TOKEN_1, "Awesome Token 1",'Token 1', 0, 0, true, 0x0, { from: tokenOwner }))
        .then(() => tokenExtension.createAssetWithoutFee(TOKEN_2, "Awesome Token 2",'Token 2', 100, 0, false, 0x0, { from: tokenOwner }))
        .then(() => TimeLimitedCrowdsaleFactory.deployed())
        .then(crowdsaleFactory => crowdsaleFactory.setPriceTicker(FakePriceTicker.address))
        .then(() => Setup.setup(done))
    });

    after('clean up', function(done) {
        // abiDecoder.removeABI(tokenExtensionEmitter.abi)
        done()
    })

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
            assert.equal(failedResultTuple[1], ErrorsEnum.UNAUTHORIZED)
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
            assert.equal(successCreateCrowdsaleResultCode, ErrorsEnum.OK)

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
            assert.equal(successDeleteCrowdsaleResultCode, ErrorsEnum.OK)

            let deleteCrowdsaleTx = await tokenExtension.deleteCrowdsaleCampaign(campaignAddr, { from: tokenOwner })
            let event = (await eventsHelper.findEvent([tokenExtensionEmitter], deleteCrowdsaleTx, "CrowdsaleCampaignRemoved"))[0]
            assert.isDefined(event)

            let deletedCampaign = event.args.campaign.valueOf()
            assert.equal(deletedCampaign, campaignAddr)

            let isAssetOwner = await Setup.assetsManager.isAssetOwner.call(TOKEN_1, deletedCampaign)
            assert.isFalse(isAssetOwner)
        })
    })

    context("Ether crowdsale", function() {
        var campaign

        it("Should be possible to start Ether crowdsale campaign by asset-owner", async () => {
            let successCreateCrowdsaleResultCode = await tokenExtension.createCrowdsaleCampaign.call(TOKEN_1, crowdsaleFactoryName, { from: tokenOwner })
            assert.equal(successCreateCrowdsaleResultCode, ErrorsEnum.OK)
            let createCrowdsaleTx = await tokenExtension.createCrowdsaleCampaign(TOKEN_1, crowdsaleFactoryName, { from: tokenOwner })
            let event = (await eventsHelper.findEvent([tokenExtensionEmitter], createCrowdsaleTx, "CrowdsaleCampaignCreated"))[0]
            console.log("event", event);
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
                await sendEtherPromise(accounts[0], campaign.address, 10)
                assert.isTrue(false)
            } catch(e) {
                assert.isTrue(true)
            }
        })

        it("Should be not possible to init Ether to campaign by non-owner", async () => {
            let failedResultCode = await campaign.init.call("USD", 1000, 1000000, 1, 0, Date.now(), Date.now() + 6000, { from: nonOwner })
            assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

            let isRunning = await campaign.isRunning.call()
            assert.isFalse(isRunning)
        })

        it("Should be not possible to set `fund` by non-asset-owner", async () => {
          let failedResultCode = await campaign.enableEtherSale.call(fund, { from: nonOwner })
          assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

          await campaign.enableEtherSale(fund, {from: nonOwner})
          let fundAddr = campaign.fund.call()
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
                await sendEtherPromise(accounts[0], campaign.address, 10)
                let balance = await platform.balanceOf.call(accounts[0], TOKEN_1)
                assert.equal(10, balance)
            } catch (e) {
                assert.isTrue(false)
            }
        })

        it("Should be possible to send Ether to crowdsale twice", async () => {
            try {
                await sendEtherPromise(accounts[0], campaign.address, 10)
                let balance = platform.balanceOf.call(accounts[0], TOKEN_1)
                assert.equal(20, balance)
            } catch(e) {
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

        let sendEtherPromise = (from, to, value) => {
            return new Promise(function (resolve, reject) {
                web3.eth.sendTransaction({from: accounts[0], to: campaign.address, value: 10, gas: 4700000}, (function (e, result) {
                    if (e != null) {
                        reject(e);
                    } else {
                        resolve(result);
                    }
                }))
            })
        }
    })
})
