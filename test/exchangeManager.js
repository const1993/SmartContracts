const FakeCoin = artifacts.require("./FakeCoin.sol")
const ContractsManager = artifacts.require("./ContractsManager.sol")
const FakeCoin2 = artifacts.require("./FakeCoin2.sol")
const Exchange = artifacts.require("./Exchange.sol")
const Setup = require('../setup/setup')
const Reverter = require('./helpers/reverter')
const bytes32 = require('./helpers/bytes32')
const ErrorsEnum = require("../common/errors")
const eventsHelper = require('./helpers/eventsHelper')

contract('Exchange Manager', function(accounts) {
    const owner = accounts[0]
    const owner1 = accounts[1]
    const owner2 = accounts[2]
    const owner3 = accounts[3]
    const owner4 = accounts[4]
    const owner5 = accounts[5]
    const nonOwner = accounts[6]
    const manager = accounts[7]
    const SYMBOL = 'TIME'
    let coin
    let coin2
    let exchange

    before('setup', function (done) {
        FakeCoin.deployed().then(function(instance) {
            coin = instance
            return FakeCoin2.deployed()
        })
        .then(function(instance) {
            coin2 = instance
            return Exchange.new()
        })
        .then(function(instance) {
            exchange = instance
            Setup.setup(done)
        })
    })

    context("CRUD interface test", function () {

        it("should allow to create a new exchange", async () => {
            let exchange;

console.log(1);

            let result = await Setup.exchangeManager.createExchange.call(SYMBOL, 2, 1, manager, true);
            assert.equal(result, ErrorsEnum.OK);

console.log(2);
            let createExchangeTx = await Setup.exchangeManager.createExchange(SYMBOL, 2, 1, manager, true);
            let events = eventsHelper.extractEvents(tx, "ExchangeCreated");
            assert.equal(events.length, 1);

console.log(3);
            exchange = events[0].args.exchange;

            console.log(4);
            let exchangeExists = await Setup.exchangeManager.isExchangeExists.call(exchange);
            assert.isTrue(exchangeExists);
            console.log(5);
            let exchanges = await Setup.exchangeManager.getExchangesForOwner.call(owner);
            assert.equal(exchanges.length, 1);
            assert.equal(exchanges[0], exchange);
        });

        it("shouldn't allow exchange owner to delete exchange contract to nonOwner", function () {
            return Setup.exchangeManager.removeExchange.call(exchange.address, {from: accounts[1]}).then(function (r) {
                assert.equal(r,ErrorsEnum.UNAUTHORIZED);
            });
        });
    });

    context("Security tests", function () {

        it("should allow to add exchange contract by exchange's owners", function () {
            return Setup.exchangeManager.addExchange.call(exchange.address, {from: owner}).then(function (r) {
                return Setup.exchangeManager.addExchange(exchange.address, {from: owner}).then(function () {
                    console.log(r);
                    assert.equal(r, ErrorsEnum.OK);
                });
            });
        });

        it("should show acccount[1] as exchange contract owner", function () {
            return Setup.exchangeManager.getExchangeOwners.call(exchange.address).then(function (r) {
                assert.equal(r[0],owner);
            });
        });

        it("shouldn't allow exchange nonOwner to add owner to exchange contract", function () {
            return Setup.exchangeManager.addExchangeOwner.call(exchange.address,owner).then(function (r) {
                return Setup.exchangeManager.addExchangeOwner(exchange.address, owner).then(function () {
                    return Setup.exchangeManager.getExchangeOwners.call(exchange.address).then(function (r2)
                    {
                        assert.equal(r, ErrorsEnum.UNAUTHORIZED);
                        assert.equal(r2.length, 1);
                    });
                });
            });
        });

        it("should allow exchange owner to add new owner to exchange", function () {
            return Setup.exchangeManager.addExchangeOwner.call(exchange.address, owner, {from: owner1}).then(function (r) {
                return Setup.exchangeManager.addExchangeOwner(exchange.address, owner, {from: owner1}).then(function () {
                    return Setup.exchangeManager.isExchangeOwner.call(exchange.address,owner).then(function (r2) {
                        assert.equal(r, ErrorsEnum.OK);
                        assert.equal(r2, true);
                    });
                });
            });
        });

        it("shouldn't allow exchange nonOwner to delete owner of exchange", function () {
            return Setup.exchangeManager.isExchangeOwner.call(exchange.address, owner).then(function (r) {
                return Setup.exchangeManager.removeExchangeOwner.call(exchange.address, owner, {from: owner2}).then(function (r2) {
                    return Setup.exchangeManager.removeExchangeOwner(exchange.address, owner, {from: owner2}).then(function () {
                        return Setup.exchangeManager.isExchangeOwner.call(exchange.address, owner).then(function (r3) {
                            assert.equal(r, true);
                            assert.equal(r2, ErrorsEnum.UNAUTHORIZED);
                            assert.equal(r3, true);
                        });
                    });
                });
            });
        });

        it("should allow exchange owner to delete owner of exchange", function () {
            return Setup.exchangeManager.isExchangeOwner.call(exchange.address, owner).then(function (r) {
                return Setup.exchangeManager.removeExchangeOwner.call(exchange.address, owner, {from: owner1}).then(function (r2) {
                    return Setup.exchangeManager.removeExchangeOwner(exchange.address, owner, {from: owner1}).then(function () {
                        return Setup.exchangeManager.isExchangeOwner.call(exchange.address, owner).then(function (r3) {
                            assert.equal(r, true);
                            assert.equal(r2, ErrorsEnum.OK);
                            assert.equal(r3, false);
                        });
                    });
                });
            });
        });

        it("shouldn't allow exchange owner to delete himself from exchange owners", function () {
            return Setup.exchangeManager.isExchangeOwner.call(exchange.address, owner1).then(function (r) {
                return Setup.exchangeManager.removeExchangeOwner.call(exchange.address, owner1, {from: owner1}).then(function (r2) {
                    return Setup.exchangeManager.removeExchangeOwner(exchange.address, owner1, {from: owner1}).then(function () {
                        return Setup.exchangeManager.isExchangeOwner.call(exchange.address, owner1).then(function (r3) {
                            assert.equal(r, true);
                            assert.equal(r2, ErrorsEnum.EXCHANGE_STOCK_INVALID_PARAMETER);
                            assert.equal(r3, true);
                        });
                    });
                });
            });
        });

    });


});
