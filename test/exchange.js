var Exchange = artifacts.require("./Exchange.sol");
var FakeCoin = artifacts.require("./FakeCoin.sol");
var FakeCoin2 = artifacts.require("./FakeCoin2.sol");
var MultiEventsHistory = artifacts.require("./MultiEventsHistory.sol");
var ContractsManager = artifacts.require("./ContractsManager.sol");
var Reverter = require('./helpers/reverter');
var bytes32 = require('./helpers/bytes32');
var eventsHelper = require('./helpers/eventsHelper');
const ErrorsEnum = require("../common/errors");

contract('Exchange', (accounts) => {
  let reverter = new Reverter(web3);
  afterEach('revert', reverter.revert);

  let exchange;
  let coin;
  let coin2;
  let delegate = '0x0';
  const BUY_PRICE = 1;
  const SELL_PRICE = 2;
  const Fee = 100;
  const BALANCE = 1000;
  const BALANCE_ETH = 100;

  let assertBalance = (address, expectedBalance) => {
    return coin.balanceOf(address)
      .then((balance) => assert.equal(balance, expectedBalance));
  };

  let assertEthBalance = (address, expectedBalance) => {
    return Promise.resolve()
      .then(() => web3.eth.getBalance(address))
      .then((balance) => assert.equal(balance.valueOf(), expectedBalance));
  };

  let getTransactionCost = (hash) => {
   return Promise.resolve().then(() =>
      hash.receipt.gasUsed);
  };

  before('Set Coin contract address', (done) => {
      var eventsHistory
      Exchange.new()
      .then(instance => exchange = instance)
      .then(() => MultiEventsHistory.deployed())
      .then(instance => eventsHistory = instance)
      .then(() => exchange.setupEventsHistory(eventsHistory.address))
      .then(() => eventsHistory.authorize(exchange.address))
      .then(() => FakeCoin.deployed())
      .then(instance => coin = instance)
      .then(() => FakeCoin2.deployed())
      .then(instance => coin2 = instance)
      .then(() => coin.mint(accounts[0], BALANCE))
      .then(() => coin.mint(accounts[1], BALANCE))
      .then(() => coin.mint(exchange.address, BALANCE))
      .then(() => web3.eth.sendTransaction({to: exchange.address, value: BALANCE_ETH, from: accounts[0]}))
      .then(() => reverter.snapshot(done))
      .catch(done);
  });

  it('should receive the right contract address after init() call', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.asset())
      .then((asset) => assert.equal(asset, coin.address));
  });

  it('should not be possible to set another contract after first init() call', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.init.call(ContractsManager.address, '0x1', coin2.address, Fee))
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INVALID_INVOCATION))
      .then(() => exchange.asset())
      .then((asset) => assert.equal(asset, coin.address));
  });

  it('should not be possible to init by non-owner', () => {
    return exchange.init.call(ContractsManager.address, coin.address, coin2.address, Fee, {from: accounts[1]})
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => exchange.asset())
      .then((asset) => assert.equal(asset, '0x0000000000000000000000000000000000000000'));
  });

  it('should not be possible to set prices by non-owner', () => {
    return exchange.setPrices.call(10, 20, {from: accounts[1]})
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => exchange.buyPrice())
      .then((buyPrice) => assert.equal(buyPrice, BUY_PRICE))
      .then(() => exchange.sellPrice())
      .then((sellPrice) => assert.equal(sellPrice, SELL_PRICE));
  });

  it('should be possible to set new prices', () => {
    let newBuyPrice = 10;
    let newSellPrice = 20;

    return exchange.setPrices(newBuyPrice, newSellPrice)
      .then(() => exchange.buyPrice())
      .then((buyPrice) => assert.equal(buyPrice, newBuyPrice))
      .then(() => exchange.sellPrice())
      .then((sellPrice) => assert.equal(sellPrice, newSellPrice));
  });

  it('should not be possible to set prices sellPrice < buyPrice', () => {
    let newBuyPrice = 20;
    let newSellPrice = 10;

    return exchange.setPrices.call(newBuyPrice, newSellPrice)
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INVALID_PRICE))
      .then(() => exchange.buyPrice())
      .then((buyPrice) => assert.equal(buyPrice, BUY_PRICE))
      .then(() => exchange.sellPrice())
      .then((sellPrice) => assert.equal(sellPrice, SELL_PRICE));
  });

  it('should not be possible to sell with price > buyPrice', () => {
    let balance;
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => web3.eth.getBalance(accounts[0]))
      .then((result) => balance = result)
      .then(() => exchange.sell.call(1, BUY_PRICE + 1))
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_TOO_HIGH_PRICE))
      //.then(getTransactionCost)
     // .then((txCost) => assertEthBalance(accounts[0], balance.sub(txCost).valueOf()))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE));
  });

  it('should not be possible to sell more than you have', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.sell.call(BALANCE + 1, BUY_PRICE))
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_BALANCE))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE));
  });

  it('should not be possible to sell tokens if exchange eth balance is less than needed', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.sell.call(BALANCE_ETH + 1, BUY_PRICE))
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_ETHER_SUPPLY))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH));
  });

  it('should be possible to sell tokens', () => {
    let sellAmount = 50;
    let balance;
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => web3.eth.getBalance(accounts[0]))
      .then((result) => balance = result)
      .then(() => exchange.sell(sellAmount, BUY_PRICE))
      //.then(getTransactionCost)
      //.then((txCost) => assertEthBalance(accounts[0], balance.sub(txCost).add(sellAmount).valueOf()))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH - sellAmount))
      .then(() => assertBalance(accounts[0], BALANCE - sellAmount))
      .then(() => assertBalance(exchange.address, BALANCE + sellAmount));
  });

  it('should not be possible to buy with price < sellPrice', () => {
    let balance;
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.buy.call(1, SELL_PRICE - 1, {value: SELL_PRICE})
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_TOO_LOW_PRICE))
      );
  });

  it('should not be possible to buy if exchange token balance is less than needed', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.buy.call(BALANCE + 1, SELL_PRICE, {value: (BALANCE + 1) * SELL_PRICE})
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_BALANCE))
      );
  });

  it('should not be possible to buy if msg.value is less than _amount * _price', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.buy.call(1, SELL_PRICE, {value: SELL_PRICE - 1})
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_ETHER_SUPPLY))
      );
  });

  it('should not be possible to buy if msg.value is greater than _amount * _price', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.buy.call(1, SELL_PRICE, {value: SELL_PRICE + 1})
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_ETHER_SUPPLY))
      );
  });

  it('should not be possible to buy if _amount * _price overflows', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.buy.call(2, web3.toBigNumber(2).pow(255), {value: 0})
      .then(assert.fail, () => true)
      );
  });

  it('should buy tokens with msg.value == _amount * _price', () => {
    let buyAmount = 50;
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.buy(buyAmount, SELL_PRICE, {value: buyAmount * SELL_PRICE}))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH + (buyAmount * SELL_PRICE)))
      .then(() => assertBalance(accounts[0], BALANCE + buyAmount))
      .then(() => assertBalance(exchange.address, BALANCE - buyAmount));
  });

  it('should not be possible to withdraw tokens by non-owner', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawTokens.call(accounts[0], 10, {from: accounts[1]}))
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(accounts[1], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE));
  });

  it('should not be possible to withdraw if exchange token balance is less than _amount', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawTokens.call(accounts[0], BALANCE + 1))
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_BALANCE))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE));
  });

  it('should withdraw tokens, process fee and fire WithdrawTokens event', () => {
    let withdrawValue = 10;
    let watcher;
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => {
        eventsHelper.setupEvents(exchange);
        watcher = exchange.withdrawTokens();
        return exchange.withdrawTokens(accounts[1], withdrawValue);
      })
      .then((txHash) => eventsHelper.getEvents(txHash, watcher))
      .then((events) => {
        assert.equal(events.length, 1);
        assert.equal(events[0].args.recipient.valueOf(), accounts[1]);
        assert.equal(events[0].args.amount.valueOf(), withdrawValue-1);
      })
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(coin2.address, 1))
      .then(() => assertBalance(accounts[1], BALANCE + withdrawValue-1))
      .then(() => assertBalance(exchange.address, BALANCE - withdrawValue))
  });

  it('should not be possible to withdraw all tokens by non-owner', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawAllTokens.call(accounts[0], {from: accounts[1]}))
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(accounts[1], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE));
  });

  it('should not be possible to withdraw eth by non-owner', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawEth.call(accounts[0], 10, {from: accounts[1]}))
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH));
  });

  it('should not be possible to withdraw if exchange eth balance is less than _amount', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawEth.call(accounts[0], BALANCE_ETH + 1))
      .then((r) => assert.equal(r, ErrorsEnum.EXCHANGE_INSUFFICIENT_ETHER_SUPPLY))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH));
  });

  it('should withdraw eth, process Fee, and fire WithdrawEth event', () => {
    let withdrawValue = 10;
    let withdrawTo = '0x0000000000000000000000000000000000000005';
    let watcher;
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => {
        eventsHelper.setupEvents(exchange);
        watcher = exchange.withdrawEth();
        return exchange.withdrawEth(withdrawTo, withdrawValue);
      })
      .then((txHash) => eventsHelper.getEvents(txHash, watcher))
      .then((events) => {
        assert.equal(events.length, 1);
        assert.equal(events[0].args.recipient.valueOf(), withdrawTo);
        assert.equal(events[0].args.amount.valueOf(), withdrawValue-1);
      })
      .then(() => assertEthBalance(coin2.address, 1))
      .then(() => assertEthBalance(withdrawTo, withdrawValue-1))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH - withdrawValue));
  });

  it('should not be possible to withdraw all eth by non-owner', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawAllEth.call(accounts[0], {from: accounts[1]}))
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH));
  });

  it('should not be possible to withdraw all by non-owner', () => {
    return exchange.init(ContractsManager.address, coin.address, coin2.address, Fee)
      .then(() => exchange.withdrawAll.call(accounts[0], {from: accounts[1]}))
      .then((r) => assert.equal(r, ErrorsEnum.UNAUTHORIZED))
      .then(() => assertBalance(accounts[0], BALANCE))
      .then(() => assertBalance(exchange.address, BALANCE))
      .then(() => assertEthBalance(exchange.address, BALANCE_ETH));
  });
});
