const Reverter = require('./helpers/reverter')
const bytes32 = require('./helpers/bytes32')
const bytes32fromBase58 = require('./helpers/bytes32fromBase58')
const eventsHelper = require('./helpers/eventsHelper')
const Setup = require('../setup/setup')
const ErrorsEnum = require("../common/errors");
const TimeMachine = require('./helpers/timemachine')

const Clock = artifacts.require('./Clock.sol')
const MultiEventsHistory = artifacts.require('./MultiEventsHistory.sol')
const PendingManager = artifacts.require("./PendingManager.sol")
const ChronoBankAssetProxy = artifacts.require("./ChronoBankAssetProxy.sol")
const VotingManager = artifacts.require("./VotingManager.sol")
const PollEntityInterface = artifacts.require("./PollEntityInterface.sol")
const VotingManagerEmitter = artifacts.require("./VotingManagerEmitter.sol")
const PollEntityEmitter = artifacts.require("./PollEntityEmitter.sol")

const reverter = new Reverter(web3)
const timeMachine = new TimeMachine(web3)


Array.prototype.unique = function() {
    return this.filter(function (value, index, self) {
        return self.indexOf(value) === index;
    });
}

Array.prototype.removeZeros = function() {
    return this.filter(function (value, index, self) {
        return value != 0x0 && value != 0 && value.valueOf() != '0'
    });
}


contract('Vote v1', function(accounts) {
    const admin = accounts[0];
    const owner = accounts[1]
    const owner1 = accounts[2];
    const nonOwner = accounts[7];
    const SYMBOL = 'TIME'

    const totalTimeTokens = 100000000
    const timeTokensBalance = 50
    let timeTokensToWithdraw75Balance = 75
    let timeTokensToWithdraw45Balance = 45
    let timeTokensToWithdraw20Balance = 20
    let timeTokensToWithdraw25Balance = 25
    let timeTokensToWithdraw5Balance = 5

    let votingManager
    let clock

    let proxyForSymbol = async (symbol) => {
        let tokenAddress = await Setup.erc20Manager.getTokenAddressBySymbol.call(symbol)
        let proxy = await ChronoBankAssetProxy.at(tokenAddress)
        return proxy
    }

    let createPolls = async (count, user) => {
        var polls = []
        for (var idx = 0; idx < count; ++idx) {
            var time = await clock.time.call()
            let tx = await votingManager.createPoll([bytes32('11'),bytes32('22')],[bytes32('11'), bytes32('22')], bytes32('auto-created poll'), 150, time.plus(10000), { from: user })
            let emitter = await VotingManagerEmitter.at(votingManager.address)
            let event = (await eventsHelper.findEvent([emitter], tx, 'PollCreated'))[0]
            assert.isDefined(event)
            let poll = await PollEntityInterface.at(event.args.pollAddress)
            await poll.activatePoll({ from: admin })

            polls.push(poll)
        }

        return polls
    }

    let getOptions = async (poll) => {
        return (await poll.getDetails.call())[7]
    }

    let getIpfsHashes = async (poll) => {
        return (await poll.getDetails.call())[8]
    }

    before('setup', async () => {
        eventor = await PendingManager.at(MultiEventsHistory.address)
        votingManager = await VotingManager.deployed()
        clock = await Clock.deployed()
        await Setup.setupPromise()
    });

    context("owner shares deposit", function () {

        it("should be able to send 100 TIME to owner", async () => {
            let token = await proxyForSymbol(SYMBOL)
            let isTransferSuccess = token.transfer.call(owner, totalTimeTokens, { from: admin })
            assert.isOk(isTransferSuccess)

            await token.transfer(owner, totalTimeTokens, { from: admin })
        })

        it("check Owner has 100 TIME", async () => {
            let token = await proxyForSymbol(SYMBOL)
            let balance = await token.balanceOf.call(owner)
            assert.equal(balance, totalTimeTokens)
        })

        it("owner should be able to approve 50 TIME to Vote", async () => {
            let wallet = await Setup.timeHolder.wallet.call()
            let token = await proxyForSymbol(SYMBOL)
            let isApproved = await token.approve.call(wallet, timeTokensBalance, { from: owner })
            assert.isOk(isApproved)

            await token.approve(wallet, timeTokensBalance, { from: owner })
        })

        it("should be able to deposit 50 TIME from owner", async () => {
            let isDepositSuccess = await Setup.timeHolder.deposit.call(timeTokensBalance, { from: owner })
            assert.isOk(isDepositSuccess)

            await Setup.timeHolder.deposit(timeTokensBalance, { from: owner })

            let depositBalance = await Setup.timeHolder.depositBalance.call(owner, { from: owner })
            assert.equal(depositBalance, timeTokensBalance);
        })

        it("should be able to withdraw 25 TIME from owner", async () => {
            let isWithdrawSuccess = await Setup.timeHolder.withdrawShares.call(timeTokensToWithdraw25Balance, { from: owner })
            assert.isOk(isWithdrawSuccess)

            await Setup.timeHolder.withdrawShares(timeTokensToWithdraw25Balance, { from: owner })

            let depositBalance = await Setup.timeHolder.depositBalance.call(owner, { from: owner })
            assert.equal(depositBalance, timeTokensToWithdraw25Balance);
        })

        it("snapshot", reverter.snapshot)
    })

    context("voting", function () {
        let vote1Obj = { details: bytes32fromBase58("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zd999") }
        let pollAddress
        let voteLimit
        let pollEntity
        let otherPollEntity
        let otherPollVotelimit = 75
        let creationTime

        context("single voter (owner)", function () {

            it("should be able to create poll", async () => {
                voteLimit = await votingManager.getVoteLimit.call()
                assert.notEqual(voteLimit.toNumber(), 0)

                let currentTime = await clock.time.call()
                creationTime = currentTime.plus(10000)

                let createdPollResult = await votingManager.createPoll.call(['1', '2'], ['1', '2'], vote1Obj.details, voteLimit.minus(1), creationTime, {
                    from: owner,
                    gas: 3000000
                })
                assert.notEqual(createdPollResult[0], 0x0)
                assert.equal(createdPollResult[1], ErrorsEnum.OK)

                let createdPollTx = await votingManager.createPoll(['1', '2'], ['1', '2'], vote1Obj.details, voteLimit.minus(1), creationTime, {
                    from: owner,
                    gas: 3000000
                })

                let emitter = await VotingManagerEmitter.at(votingManager.address)
                let event = (await eventsHelper.findEvent([emitter], createdPollTx, 'PollCreated'))[0]
                assert.isDefined(event)

                pollAddress = event.args.pollAddress
                pollEntity = await PollEntityInterface.at(pollAddress)
            })

            it("should have owner as an owner of created poll", async () => {
                let pollOwner = await pollEntity.owner.call()
                assert.equal(pollOwner, owner)
            })

            it("should not be able to create a new poll with exceeded vote limit", async () => {
                voteLimit = await votingManager.getVoteLimit.call()
                assert.notEqual(voteLimit.toNumber(), 0)

                let currentTime = await clock.time.call()

                try {
                    let createdPollResult = await votingManager.createPoll.call(['1', '2'], ['1', '2'], vote1Obj.details, voteLimit.plus(1), currentTime.plus(10000), {
                        from: owner,
                        gas: 3000000
                    })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }
            })

            it('should not be able to vote before activation of a poll', async () => {
                try {
                    await pollEntity.vote.call(1, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }
            })

            it('owner should be able to activate a poll if he is an owner and poll wasn\'t activated yes', async () => {
                try {
                    let activationTx = await pollEntity.activatePoll()
                    let emitter = await VotingManagerEmitter.at(votingManager.address)
                    let event = (await eventsHelper.findEvent([emitter], activationTx, "PollActivated"))[0]
                    assert.isDefined(event)

                    let isPollActive = await pollEntity.active.call()
                    assert.isOk(isPollActive)
                } catch (e) {
                    assert.isTrue(false);
                }
            })

            it("owner should be able to vote, option 1 ", async () => {
                let successVotingResultCode = await pollEntity.vote.call(1, { from: owner })
                assert.equal(successVotingResultCode, ErrorsEnum.OK)

                let voteTx = await pollEntity.vote(1, { from: owner })
                console.log('vote in poll', voteTx.tx);

                let emitter = await VotingManagerEmitter.at(votingManager.address)
                let event = (await eventsHelper.findEvent([emitter], voteTx, "PollVoted"))[0]
                assert.isDefined(event)
            })

            it("user shouldn\'t be able to vote twice", async () => {
                try {
                    await pollEntity.vote.call(2, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }
            })

            it("should be able to fetch details for a poll", async () => {
                let details = await pollEntity.getDetails.call()
                assert.lengthOf(details, 9)
                assert.equal(details[0], owner)
                assert.equal(details[1], vote1Obj.details)
                assert.equal(details[3].toNumber(), creationTime.toNumber())
                assert.isOk(details[4])
                assert.isOk(details[5])
            })

            it("voter (owner) should have option 1 as an option (in other words be a member)", async () => {
                let choice = await pollEntity.memberOptions.call(owner)
                assert.equal(choice, 1)
            })

            // other poll

            it("should be able to create another poll by owner", async () => {
                let currentTime = await clock.time.call()
                creationTime = currentTime.plus(10000)

                let createdPollResult = await votingManager.createPoll.call(['3', '4'], ['3', '4'], vote1Obj.details, otherPollVotelimit, creationTime, {
                    from: owner,
                    gas: 3000000
                })

                assert.notEqual(createdPollResult[0], 0x0)
                assert.equal(createdPollResult[1], ErrorsEnum.OK)

                let createdPollTx = await votingManager.createPoll(['3', '4'], ['3', '4'], vote1Obj.details, otherPollVotelimit, creationTime, {
                    from: owner,
                    gas: 3000000
                })
                console.log('create poll', createdPollTx.tx);

                let emitter = await VotingManagerEmitter.at(votingManager.address)
                let event = (await eventsHelper.findEvent([emitter], createdPollTx, 'PollCreated'))[0]
                assert.isDefined(event)

                otherPollEntity = await PollEntityInterface.at(event.args.pollAddress)
                assert.equal(otherPollEntity.address, event.args.pollAddress)
            })

            it('should be different polls created for owner', async () => {
                assert.notEqual(pollEntity.address, otherPollEntity.address)
            })

            it('should return all created polls for owner', async () => {
                let pollsCount = await votingManager.getPollsCount.call()
                let polls = await votingManager.getPollsPaginated.call(0, pollsCount)
                let onlyPolls = polls[0].unique()

                assert.equal(pollsCount, 2)
                assert.lengthOf(onlyPolls, 2)
                assert.include(onlyPolls, pollEntity.address)
                assert.include(onlyPolls, otherPollEntity.address)
            })

            it('should participate in only one poll where owner have voted', async () => {
                let membershipPolls = await votingManager.getMembershipPolls.call(owner)
                let polls = membershipPolls.removeZeros()
                assert.lengthOf(polls, 1)
                assert.include(polls, pollEntity.address)
            })

            it('should be able to have to 2 active polls for owner and vote, option 2', async () => {
                try {
                    await otherPollEntity.activatePoll()

                    let isPollActive = await otherPollEntity.active.call()
                    assert.isOk(isPollActive)
                } catch (e) {
                    assert.isTrue(false);
                }

                let successVotingResultCode = await otherPollEntity.vote.call(2, { from: owner })
                assert.equal(successVotingResultCode, ErrorsEnum.OK)

                let voteTx = await otherPollEntity.vote(2, { from: owner })
            })

            it('should have 2 polls where owner is participating', async () => {
                let membershipPolls = await votingManager.getMembershipPolls.call(owner)
                let polls = membershipPolls.removeZeros()
                assert.lengthOf(polls, 2)
                assert.include(polls, pollEntity.address)
                assert.include(polls, otherPollEntity.address)
            })

            it('should be able to return polls\' details', async () => {
                let pollsDetails = await votingManager.getPollsDetails.call([pollEntity.address, otherPollEntity.address])
                assert.lengthOf(pollsDetails, 7)
                assert.lengthOf(pollsDetails[0], 2)
            })

        })

        context('two voters (+ owner1)', function () {

            it('should be able to send 50 TIME tokens to owner1', async () => {
                let token = await proxyForSymbol(SYMBOL)
                let successTransfer = await token.transfer.call(owner1, timeTokensBalance, { from: admin })
                assert.isOk(successTransfer)

                await token.transfer(owner1, timeTokensBalance, { from: admin })
            })

            it('owner1 should have 50 TIME', async () => {
                let token = await proxyForSymbol(SYMBOL)
                let balance = await token.balanceOf.call(owner1)
                assert.equal(balance, timeTokensBalance)
            })

            it('owner1 should be able to approve 50 TIME tokens to TimeHolder', async () => {
                let wallet = await Setup.timeHolder.wallet.call()
                let token = await proxyForSymbol(SYMBOL)
                let successApprove = await token.approve.call(wallet, timeTokensBalance, { from: owner1 })
                assert.isOk(successApprove)

                await token.approve(wallet, timeTokensBalance, { from: owner1 })
            })

            it('should be able to deposit 50 TIME tokens from owner1', async () => {
                let successDeposit = await Setup.timeHolder.deposit.call(timeTokensBalance, { from: owner1 })
                assert.isOk(successDeposit)

                await Setup.timeHolder.deposit(timeTokensBalance, { from: owner1 })
            })

            it('should show 50 TIME tokens owner1 balance', async () => {
                let balance = await Setup.timeHolder.depositBalance.call(owner1, { from: owner1 })
                assert.equal(balance, timeTokensBalance)
            })

            it('owner1 should be able to vote in poll, option 2', async () => {
                let successVotingResultCode = await pollEntity.vote.call(2, { from: owner1 })
                assert.equal(successVotingResultCode, ErrorsEnum.OK)

                let votingTx = await pollEntity.vote(2, { from: owner1 })
            })

            it('shouldn\'t show poll as finished', async () => {
                let details = await pollEntity.getDetails.call()
                assert.isOk(details[5]) // property: 'active'
            })

            it('should show owner1 as a participant of one poll', async () => {
                let membershipPolls = await votingManager.getMembershipPolls.call(owner1)
                let polls = membershipPolls.removeZeros()
                assert.lengthOf(polls, 1)
                assert.include(polls, pollEntity.address)
            })

            it('shouldn\'t show otherPoll as finished', async () => {
                let details = await otherPollEntity.getDetails.call()
                assert.isOk(details[5]) // property: 'active'
            })

            it('owner1 should be able to vote in otherPoll, options 2', async () => {
                let successVotingResultCode = await otherPollEntity.vote.call(2, { from: owner1 })
                assert.equal(successVotingResultCode, ErrorsEnum.OK)

                let votingTx = await otherPollEntity.vote(2, { from: owner1 })
                let emitter = await VotingManagerEmitter.at(votingManager.address)
                let event = (await eventsHelper.findEvent([emitter], votingTx, "PollVoted"))[0]
            })

            it('otherPoll should be shown as finished', async () => {
                let details = await otherPollEntity.getDetails.call()
                assert.isNotOk(details[5]) // property: 'active'
            })

            it('should show owner1 as a participant of two polls', async () => {
                let membershipPolls = await votingManager.getMembershipPolls.call(owner1)
                let polls = membershipPolls.removeZeros()
                assert.lengthOf(polls, 2)
                assert.include(polls, pollEntity.address)
                assert.include(polls, otherPollEntity.address)
            })

            it('should be able to get balances of votes for poll', async () => {
                let optionsAndBalances = await pollEntity.getVotesBalances.call()
                assert.lengthOf(optionsAndBalances, 2)

                let balances = optionsAndBalances[1]
                assert.equal(balances[0], timeTokensToWithdraw25Balance)
                assert.equal(balances[1], timeTokensBalance)
            })

            it('should be able to get balances of votes for otherPoll', async () => {
                let optionsAndBalances = await otherPollEntity.getVotesBalances.call()
                assert.lengthOf(optionsAndBalances, 2)

                let balances = optionsAndBalances[1]
                assert.equal(balances[0], 0)
                assert.equal(balances[1], timeTokensToWithdraw75Balance)
            })
        })

        const maximumPollsCount = 20
        let multiplePolls

        context('multiple polls', function () {

            it('shouldn\'t be able to create more than 20 ACTIVE polls', async () => {
                multiplePolls = await createPolls(30, owner)
                let activePollsCount = await votingManager.getActivePollsCount.call()
                assert.equal(activePollsCount, maximumPollsCount)

                let totalNumberOfPolls = await votingManager.getPollsCount.call()
                assert.equal(totalNumberOfPolls, multiplePolls.length + 2) // 2 - previously created polls
            })

            it('should allow to delete inactive poll for CBE user', async () => {
                let pollToRemove = multiplePolls.pop()
                let killTx = await pollToRemove.killPoll({ from: admin })
                let emitter = await VotingManagerEmitter.at(votingManager.address)
                let event = (await eventsHelper.findEvent([emitter], killTx, "PollRemoved"))[0]
                assert.isDefined(event)
                assert.equal(event.args.pollAddress, pollToRemove.address)

                let activePollsCount = await votingManager.getActivePollsCount.call()
                assert.equal(activePollsCount, maximumPollsCount)

                let totalNumberOfPolls = await votingManager.getPollsCount.call()
                assert.equal(totalNumberOfPolls, multiplePolls.length + 2) // 2 - previously created polls
            })

            it('shouldn\'t allow to delete inactive poll for non-CBE user', async () => {
                let pollTryToRemove = multiplePolls[multiplePolls.length - 1]

                let failedResultCode = await pollTryToRemove.killPoll.call({ from: owner })
                assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

                let activePollsCount = await votingManager.getActivePollsCount.call()
                assert.equal(activePollsCount, maximumPollsCount)

                let totalNumberOfPolls = await votingManager.getPollsCount.call()
                assert.equal(totalNumberOfPolls, multiplePolls.length + 2) // 2 - previously created polls
            })

            it('shouldn\'t be able to delete active poll by a user with any access rights', async () => {
                let isActive = await pollEntity.active.call()
                assert.isOk(isActive)

                try {
                    let failedResultCode = await pollEntity.killPoll.call({ from: admin })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }

                try {
                    let failedResultCode = await pollEntity.killPoll.call({ from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }
            })

            it('should allow CBE to end poll', async () => {
                let pollToEnd = multiplePolls[0]
                let endTx = await pollToEnd.endPoll({ from: admin })
                let emitter = await VotingManagerEmitter.at(votingManager.address)
                let event = (await eventsHelper.findEvent([emitter], endTx, "PollEnded"))[0]
                assert.isDefined(event)

                let activePollsCount = await votingManager.getActivePollsCount.call()
                assert.equal(activePollsCount, maximumPollsCount - 1)

                let totalNumberOfPolls = await votingManager.getPollsCount.call()
                assert.equal(totalNumberOfPolls, multiplePolls.length + 2) // 2 - previously created polls
            })
        })

        context('manipulate balances', function () {

            it('should be able to withdraw 5 TIME tokens from owner1', async () => {
                let successWithdrawal = await Setup.timeHolder.withdrawShares.call(5, { from: owner1 })
                assert.isOk(successWithdrawal)

                try {
                    await Setup.timeHolder.withdrawShares(5, { from: owner1 })
                    assert.isTrue(true)
                } catch (e) {
                    assert.isTrue(false)
                }
            })

            it('should be able to show updated vote balances for poll', async () => {
                let optionsAndBalances = await pollEntity.getVotesBalances.call()
                assert.lengthOf(optionsAndBalances, 2)

                let balances = optionsAndBalances[1]
                assert.equal(balances[0], timeTokensToWithdraw25Balance)
                assert.equal(balances[1], timeTokensToWithdraw45Balance)
            })

            it('owner1 should take part in 2 polls', async () => {
                let membershipPolls = await votingManager.getMembershipPolls.call(owner1)
                let polls = membershipPolls.removeZeros()
                assert.lengthOf(polls, 2)
            })

            it('should be able to withdraw 45 TIME tokens from owner1', async () => {
                let successWithdrawal = await Setup.timeHolder.withdrawShares.call(45, { from: owner1 })
                assert.isOk(successWithdrawal)

                await Setup.timeHolder.withdrawShares(45, { from: owner1 })
            })

            it('owner1 should take part only in one poll', async () => {
                let membershipPolls = await votingManager.getMembershipPolls.call(owner1)
                let polls = membershipPolls.removeZeros()
                assert.lengthOf(polls, 1)
                assert.include(polls, otherPollEntity.address)
            })

            let remainderTimeTokenBalance = totalTimeTokens - timeTokensToWithdraw25Balance

            it('should be able to approve remainded TIME tokens for voting to owner', async () => {
                let wallet = await Setup.timeHolder.wallet.call()
                let token = await proxyForSymbol(SYMBOL)

                let successApprove = await token.approve.call(wallet, remainderTimeTokenBalance, { from: owner })
                assert.isOk(successApprove)

                await token.approve(wallet, remainderTimeTokenBalance, { from: owner })
            })

            it('should be able to deposit reminded TIME tokens from owner', async () => {
                let successDeposit = await Setup.timeHolder.deposit.call(remainderTimeTokenBalance, { from: owner })
                assert.isOk(successDeposit)

                await Setup.timeHolder.deposit(remainderTimeTokenBalance, { from: owner })
            })

            it('should show 0 TIME tokens for owner1 and all TIME tokens for owner', async () => {
                let token = await proxyForSymbol(SYMBOL)

                // for owner1
                let depositedBalanceForOwner1 = await Setup.timeHolder.depositBalance.call(owner1)
                assert.equal(depositedBalanceForOwner1, 0)

                let totalBalanceForOwner1 = await token.balanceOf.call(owner1)
                assert.equal(totalBalanceForOwner1, timeTokensBalance)

                // for owner
                let depositedBalanceForOwner = await Setup.timeHolder.depositBalance.call(owner)
                assert.equal(depositedBalanceForOwner, totalTimeTokens)

                let totalBalanceForOwner = await token.balanceOf.call(owner)
                assert.equal(totalBalanceForOwner, 0)
            })

            it('should show updated balances for poll votes', async () => {
                let optionsAndBalances = await pollEntity.getVotesBalances.call()
                assert.lengthOf(optionsAndBalances, 2)

                let balances = optionsAndBalances[1]
                assert.equal(balances[0], totalTimeTokens)
                assert.equal(balances[1], 0)
            })
        })

        context('adding/removing parameters in a poll', function () {

            const additionalOption = '5'
            let firstPoll
            let secondPoll

            it('prepare', async () => {
                firstPoll = multiplePolls[multiplePolls.length - 5]
                secondPoll = multiplePolls[multiplePolls.length - 4]
                assert.isDefined(firstPoll)
                assert.isDefined(secondPoll)
            })

            it('owner should be an owner of polls', async () => {
                let firstPollOwner = await firstPoll.owner.call()
                assert.equal(firstPollOwner, owner)

                let secondPollOwner = await secondPoll.owner.call()
                assert.equal(secondPollOwner, owner)
            })

            it('should be able to update options list before activation by a poll owner', async () => {
                let isActivated = await firstPoll.active.call()
                assert.isNotOk(isActivated)

                let originalOptions = await getOptions(firstPoll)
                let originalLength = originalOptions.removeZeros().length

                let successAddOptionResultCode = await firstPoll.addPollOption.call(additionalOption, { from: owner })
                assert.equal(successAddOptionResultCode, ErrorsEnum.OK)

                let addOptionTx = await firstPoll.addPollOption(additionalOption, { from: owner })
                console.log('addOptionTx', addOptionTx.tx);
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], addOptionTx, "PollDetailsOptionAdded"))[0]
                assert.isDefined(event)
                let changedOptions = await getOptions(firstPoll)
                let changedLength = changedOptions.removeZeros().length
                assert.isAbove(changedLength, originalLength)
            })

            it('should be able to remove an option from options list before activation by a poll owner', async () => {
                let originalOptions = await getOptions(firstPoll)
                let originalLength = originalOptions.removeZeros().length

                let successRemoveOptionResultCode = await firstPoll.removePollOption.call(additionalOption, { from: owner })
                assert.equal(successRemoveOptionResultCode, ErrorsEnum.OK)

                let removeOptionTx = await firstPoll.removePollOption(additionalOption, { from: owner })
                console.log('removeOptionTx', removeOptionTx.tx);
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], removeOptionTx, "PollDetailsOptionRemoved"))[0]
                assert.isDefined(event)

                let changedOptions = await getOptions(firstPoll)
                let changedLength = changedOptions.removeZeros().length
                assert.isAbove(originalLength, changedLength)
            })

            it('a non-owner of a poll shouldn\'t be able to add options', async () => {
                let nonPollOwner = nonOwner

                let originalOptions = await getOptions(firstPoll)
                let originalLength = originalOptions.removeZeros().length

                let failedResultCode = await firstPoll.addPollOption.call(additionalOption, { from: nonPollOwner })
                assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

                let addOptionTx = await firstPoll.addPollOption(additionalOption, { from: nonPollOwner })
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], addOptionTx, "PollDetailsOptionAdded"))[0]
                assert.isUndefined(event)

                let notChangedOptions = await getOptions(firstPoll)
                let notChangedLength = notChangedOptions.removeZeros().length
                assert.equal(notChangedLength, originalLength)
            })

            it('a non-owner of a poll shouldn\'t be able to remove options', async () => {
                let nonPollOwner = nonOwner

                let originalOptions = await getOptions(firstPoll)
                let originalLength = originalOptions.removeZeros().length

                let failedResultCode = await firstPoll.removePollOption.call(additionalOption, { from: nonPollOwner })
                assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

                let removeOptionTx = await firstPoll.removePollOption(additionalOption, { from: nonPollOwner })
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], removeOptionTx, "PollDetailsOptionRemoved"))[0]
                assert.isUndefined(event)

                let notChangedOptions = await getOptions(firstPoll)
                let notChangedLength = notChangedOptions.removeZeros().length
                assert.equal(notChangedLength, originalLength)
            })

            it('should allow to update details hash for an inactive poll by an owner', async () => {
                let updatedDetailsHash = bytes32('updatedhash')
                let originalDetails = (await firstPoll.getDetails.call())[1]

                let successUpdateResultCode = await firstPoll.updatePollDetailsIpfsHash.call(updatedDetailsHash, { from: owner })
                assert.equal(successUpdateResultCode, ErrorsEnum.OK)

                let updateDetailsTx = await firstPoll.updatePollDetailsIpfsHash(updatedDetailsHash, { from: owner })
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], updateDetailsTx, "PollDetailsHashUpdated"))[0]
                assert.isDefined(event)

                let newDetails = (await firstPoll.getDetails.call())[1]
                assert.equal(newDetails, updatedDetailsHash)
            })

            it('shouldn\'t allow to update details hash for an inactive poll by a non-owner of a poll', async () => {
                let nonPollOwner = nonOwner

                let updatedDetailsHash = bytes32('updatedhash-333')
                let originalDetails = (await firstPoll.getDetails.call())[1]

                let failedResultCode = await firstPoll.updatePollDetailsIpfsHash.call(updatedDetailsHash, { from: nonPollOwner })
                assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

                let updateDetailsTx = await firstPoll.updatePollDetailsIpfsHash(updatedDetailsHash, { from: nonPollOwner })
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], updateDetailsTx, "PollDetailsHashUpdated"))[0]
                assert.isUndefined(event)

                let newDetails = (await firstPoll.getDetails.call())[1]
                assert.equal(newDetails, originalDetails)
            })

            const additionalIpfsHash = bytes32('2222')

            it('should be able to update ifpsHashes list before activation by a poll owner', async () => {
                let isActivated = await firstPoll.active.call()
                assert.isNotOk(isActivated)

                let originalIpfsHashes = await getIpfsHashes(firstPoll)
                let originalLength = originalIpfsHashes.removeZeros().length

                let successAddIpfsHashResultCode = await firstPoll.addPollIpfsHash.call(additionalIpfsHash, { from: owner })
                assert.equal(successAddIpfsHashResultCode, ErrorsEnum.OK)

                let addIpfsHashTx = await firstPoll.addPollIpfsHash(additionalIpfsHash, { from: owner })
                console.log('addIpfsHashTx', addIpfsHashTx.tx);
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], addIpfsHashTx, "PollDetailsIpfsHashAdded"))[0]
                assert.isDefined(event)

                let changedIpfsHashes = await getIpfsHashes(firstPoll)
                let changedLength = changedIpfsHashes.removeZeros().length
                assert.isAbove(changedLength, originalLength)
            })

            it('should be able to remove an ifpsHash from ifpsHashes list before activation by a poll owner', async () => {
                let originalIpfsHashes = await getIpfsHashes(firstPoll)
                let originalLength = originalIpfsHashes.removeZeros().length

                let successRemoveIpfsHashResultCode = await firstPoll.removePollIpfsHash.call(additionalIpfsHash, { from: owner })
                assert.equal(successRemoveIpfsHashResultCode, ErrorsEnum.OK)

                let removeIpfsHashTx = await firstPoll.removePollIpfsHash(additionalIpfsHash, { from: owner })
                console.log('removeIpfsHashTx', removeIpfsHashTx.tx);
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], removeIpfsHashTx, "PollDetailsIpfsHashRemoved"))[0]
                assert.isDefined(event)

                let changedIpfsHashes = await getIpfsHashes(firstPoll)
                let changedLength = changedIpfsHashes.removeZeros().length
                assert.isAbove(originalLength, changedLength)
            })

            it('a non-owner of a poll shouldn\'t be able to add ifpsHash', async () => {
                let nonPollOwner = nonOwner

                let originalIpfsHashes = await getIpfsHashes(firstPoll)
                let originalLength = originalIpfsHashes.removeZeros().length

                let failedResultCode = await firstPoll.addPollIpfsHash.call(additionalIpfsHash, { from: nonPollOwner })
                assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

                let addIpfsHashTx = await firstPoll.addPollIpfsHash(additionalIpfsHash, { from: nonPollOwner })
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], addIpfsHashTx, "PollDetailsIpfsHashAdded"))[0]
                assert.isUndefined(event)

                let notChangedIpfsHashes = await getIpfsHashes(firstPoll)
                let notChangedLength = notChangedIpfsHashes.removeZeros().length
                assert.equal(notChangedLength, originalLength)
            })

            it('a non-owner of a poll shouldn\'t be able to remove ifpsHash', async () => {
                let nonPollOwner = nonOwner

                let originalIpfsHashes = await getIpfsHashes(firstPoll)
                let originalLength = originalIpfsHashes.removeZeros().length

                let failedResultCode = await firstPoll.removePollIpfsHash.call(additionalIpfsHash, { from: nonPollOwner })
                assert.equal(failedResultCode, ErrorsEnum.UNAUTHORIZED)

                let removeIpfsHashTx = await firstPoll.removePollIpfsHash(additionalIpfsHash, { from: nonPollOwner })
                let emitter = await PollEntityEmitter.at(firstPoll.address)
                let event = (await eventsHelper.findEvent([emitter], removeIpfsHashTx, "PollDetailsIpfsHashRemoved"))[0]
                assert.isUndefined(event)

                let notChangedIpfsHashes = await getIpfsHashes(firstPoll)
                let notChangedLength = notChangedIpfsHashes.removeZeros().length
                assert.equal(notChangedLength, originalLength)
            })

            it('should not allow to change any property in a poll when it was activated', async () => {
                let poll = secondPoll
                await poll.activatePoll({ from: admin })
                let isActivated = await poll.active.call()
                assert.isOk(isActivated)

                try {
                    let addOptionTx = await poll.addPollOption(additionalOption, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }

                try {
                    let removeOptionTx = await poll.removePollOption(additionalOption, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }

                try {
                    let updateDetailsTx = await poll.updatePollDetailsIpfsHash(updatedDetailsHash, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }

                try {
                    let addIpfsHashTx = await poll.addPollIpfsHash(additionalIpfsHash, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }

                try {
                    let removeIpfsHashTx = await poll.removePollIpfsHash(additionalIpfsHash, { from: owner })
                    assert.isTrue(false)
                } catch (e) {
                    assert.isTrue(true)
                }
            })
        })

        it('revert', reverter.revert)
    })

})
