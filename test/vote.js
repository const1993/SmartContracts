const Reverter = require('./helpers/reverter')
const bytes32 = require('./helpers/bytes32')
const bytes32fromBase58 = require('./helpers/bytes32fromBase58')
const Q = require("q");
const eventsHelper = require('./helpers/eventsHelper')
const Setup = require('../setup/setup')
const MultiEventsHistory = artifacts.require('./MultiEventsHistory.sol')
const PendingManager = artifacts.require("./PendingManager.sol")
const ChronoBankAssetProxy = artifacts.require("./ChronoBankAssetProxy.sol")
const ErrorsEnum = require("../common/errors");

var reverter = new Reverter(web3)

function cleanStr(str) {
    return str.replace(/\0/g, '')
}


contract('Vote', function(accounts) {
  const admin = accounts[0];
  const owner = accounts[1]
  const owner1 = accounts[2];
  const owner2 = accounts[3];
  const owner3 = accounts[4];
  const owner4 = accounts[5];
  const owner5 = accounts[6];
  const nonOwner = accounts[7];
  const SYMBOL = 'TIME'
  let unix = Math.round(+new Date()/1000);

  const totalTimeTokens = 100000000
  const timeTokensBalance = 50
  let timeTokensToWithdraw75Balance = 75
  let timeTokensToWithdraw45Balance = 45
  let timeTokensToWithdraw20Balance = 20
  let timeTokensToWithdraw25Balance = 25
  let timeTokensToWithdraw5Balance = 5

  let createPolls = (count) => {
    var chain = Q.when();
    for(var i = 0; i < count; i++) {
	       chain = chain.then(function() {
           return Setup.vote.manager.NewPoll([bytes32('1'),bytes32('2')],[bytes32('1'), bytes32('2')], bytes32('New Poll'),150, unix + 10000, {from: owner, gas:3000000})
           .then((r) => r.logs[0] ? r.logs[0].args.pollId : 0)
           .then((createdPollId) => Setup.vote.manager.activatePoll(createdPollId, {from: admin}))
	       });
    }

    return Q.all(chain);
  }

  function proxyForSymbol(symbol) {
      return Setup.erc20Manager.getTokenAddressBySymbol.call(symbol)
      .then(_tokenAddress => ChronoBankAssetProxy.at(_tokenAddress))
  }

  // let endPolls = (count) => {
  //   let data = [];
  //   for(let i = 0; i < count; i++) {
  //     data.push(Setup.vote.adminEndPoll(i))
  //   }
  //   return Promise.all(data)
  // }
  //
  // let createPollWithActivePolls = (count, active_count) => {
  //   let data = [];
  //   for(let i = 0; i < count; i++) {
  //     data.push(Setup.vote.NewPoll([bytes32('1'),bytes32('2')],[bytes32('1'), bytes32('2')],bytes32('New Poll'),150, unix + 10000, {from: owner, gas:3000000}).then(() => {
  //       return Setup.vote.activatePoll(i).then(() => {
  //         return Setup.vote.adminEndPoll(i)
  //       })
  //     }))
  //   }
  //   for(let i =0; i < active_count; i++) {
  //     data.push(Setup.vote.NewPoll([bytes32('1'),bytes32('2')],[bytes32('1'), bytes32('2')],bytes32('New Poll'),150, unix + 10000, {from: owner, gas:3000000}));
  //   }
  //   return Promise.all(data)
  // }

  before('setup', function(done) {
    PendingManager.at(MultiEventsHistory.address).then((instance) => {
      eventor = instance;
      Setup.setup(done);
    });
  });

  context("owner shares deposit", function(){

    it("should be able to send 100 TIME to owner", function() {
        return proxyForSymbol(SYMBOL)
        .then(_token => {
            return _token.transfer.call(owner, totalTimeTokens, { from: admin })
            .then(_isSuccess => {
                return _token.transfer(owner, totalTimeTokens, { from: admin }).then(() => {
                    assert.isOk(_isSuccess)
                })
            })
        })
    });

    it("check Owner has 100 TIME", function() {
      return proxyForSymbol(SYMBOL)
      .then(_proxy => _proxy.balanceOf.call(owner))
      .then(_balance => {
        assert.equal(_balance, totalTimeTokens);
      });
    });

    it("owner should be able to approve 50 TIME to Vote", function() {
        return Setup.timeHolder.wallet.call().then(_wallet => {
            return proxyForSymbol(SYMBOL).then(_proxy => {
                return _proxy.approve.call(_wallet, timeTokensBalance, {from: owner}).then(_isSuccess => {
                    return _proxy.approve(_wallet, timeTokensBalance, {from: owner}).then(() => {
                        assert.isOk(_isSuccess);
                    })
                })
            });
        })
    });

    it("should be able to deposit 50 TIME from owner", function() {
      return Setup.timeHolder.deposit.call(timeTokensBalance, {from: owner}).then((r) => {
        assert.isOk(r);
        return Setup.timeHolder.deposit(timeTokensBalance, {from: owner}).then(() => {
          return Setup.timeHolder.depositBalance.call(owner, {from: owner}).then((r2) =>
          {
            assert.equal(r2, 50);
          });
        });
      });
    });

    it("should be able to withdraw 25 TIME from owner", function() {
      return Setup.timeHolder.withdrawShares.call(timeTokensToWithdraw25Balance, {from: owner}).then((r) => {
        assert.isOk(r);
        return Setup.timeHolder.withdrawShares(timeTokensToWithdraw25Balance, {from: owner}).then(() => {
          return Setup.timeHolder.depositBalance.call(owner, {from: owner}).then((r2) => {
            assert.equal(r2, timeTokensToWithdraw25Balance);
          });
        });
      });
    });

    it("should snapshot", reverter.snapshot)
  });

  context("voting", function(){
      let vote1Obj = { details: bytes32fromBase58("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zd999") }

    it("should be able to create Poll 1", function() {
        let newPollId;
      return Setup.vote.manager.getVoteLimit.call().then((r) => {
        return Setup.vote.manager.NewPoll(['1', '2'], ['1', '2'], vote1Obj.details, r - 1, unix + 10000, {
          from: owner,
          gas: 3000000
      }).then((_tx) => {
          console.log("create", _tx.tx);
          return Setup.vote.details.pollsCount.call().then((r) => {
            assert.equal(r, 1);
          });
        })
        .then(() => {
            return Setup.vote.details.getPoll.call(1)
        })
        .then(_details => {
            assert.equal(owner, _details[1])
        })
      });
    });

    it("shouldn't be able to create Poll 1 with votelimit exceeded", function() {
      return Setup.vote.manager.getVoteLimit.call().then((r) => {
        return Setup.vote.manager.NewPoll.call(['1', '2'],['1', '2'], vote1Obj.details, r + 1, unix + 10000, {
          from: owner,
          gas: 3000000
      }).then((r) => assert.equal(r, ErrorsEnum.VOTE_LIMIT_EXCEEDED))
      })
    })

    it("should be able to activate Poll 1", function() {
        return Setup.vote.manager.activatePoll(1, { from: admin }).then((_tx) => {
            return Setup.vote.details.getActivePollsCount.call().then((r) => {
                assert.equal(r, 1)
            })
        })
    })

    it("should show owner as Poll 1 owner", function() {
      return Setup.vote.details.isPollOwner.call(1, { from: owner }).then((r) => {
        assert.isOk(r);
      });
    });

    it("owner1 shouldn't be able to add IPFS hash to Poll 1", function() {
      return Setup.vote.manager.addIpfsHashToPoll.call(1, bytes32('1234567890'), {from: owner1}).then((r) => {
        return Setup.vote.manager.addIpfsHashToPoll(1, bytes32('1234567890'), {from: owner1}).then(() => {
          return Setup.vote.details.getIpfsHashesFromPoll.call(1, {from: owner1}).then((r2) => {
            assert.equal(r, ErrorsEnum.UNAUTHORIZED);
            assert.notEqual(r2[3], bytes32('1234567890'));
          });
        });
      });
    });

    it("owner should be able to add IPFS hash to Poll 1", function() {
      return Setup.vote.manager.addIpfsHashToPoll.call(1, bytes32('1234567890'), {from: owner}).then(function (r) {
        return Setup.vote.manager.addIpfsHashToPoll(1, bytes32('1234567890'), {from: owner}).then(function () {
          return Setup.vote.details.getIpfsHashesFromPoll.call(1, {from: owner}).then(function (r2) {
            assert.equal(r2[2], bytes32('1234567890'));
          });
        });
      });
    });

    it("should provide IPFS hashes list from Poll 1 by ID", function() {
      return Setup.vote.details.getIpfsHashesFromPoll.call(1, {from: owner}).then((r) => {
        assert.equal(r.length,3);
      });
    });

    it("should be able to fetch polls details hashes", function() {
      return Setup.vote.details.getPollsDetailsIpfsHashes.call({from: owner}).then((r) => {
        assert.equal(r.length,1);
      });
    });

    it("owner should be able to vote Poll 1, Option 1", function() {
      return Setup.vote.actor.vote.call(1,1, {from: owner}).then((r) => {
        return Setup.vote.actor.vote(1,1, {from: owner}).then((r2) => {
            console.log("vote", r2.tx);
          assert.isOk(r);
        });
      });
    });

    it("owner shouldn't be able to vote Poll 1 twice", function() {
      return Setup.vote.actor.vote.call(1,2, {from: owner}).then((r) => {
          assert.equal(r, ErrorsEnum.VOTE_POLL_ALREADY_VOTED);
      });
    });

    it("should be able to get Polls list owner took part", function() {
      return Setup.vote.details.getMemberPolls.call({from: owner}).then((r) => {
        assert.equal(r.length,1);
      });
    });

    it("should be able to get owner1option for Poll 1", function() {
      return Setup.vote.details.getMemberVotesForPoll.call(1,{from: owner}).then((r) => {
        assert.equal(r,1);
      });
    });

    it("should be able to create another Poll 2", function() {
      return Setup.vote.manager.NewPoll([bytes32('Test Option 1'),bytes32('Test Option 2')],[bytes32('1'), bytes32('2')],bytes32('New Poll2'),75, unix + 1000, {
          from: owner,
          gas:3000000
      })
          .then((r2) => {
        return Setup.vote.details.pollsCount.call().then((r) => {
          assert.equal(r,2);
        });
      });
    });

    it("should be able to activate Poll 2", function() {
      return Setup.vote.manager.activatePoll(2, {from: admin}).then(() => {
        return Setup.vote.details.getActivePollsCount.call().then((r) => {
          assert.equal(r,2);
        });
      });
    });

    it("should be able to show all options for Poll 1", function() {
      return Setup.vote.details.getOptionsForPoll.call(1).then((r) => {
        assert.equal(r.length,2)
      })
    })

    it("owner should be able to vote Poll 2, Option 1", function() {
      return Setup.vote.actor.vote.call(2,1, {from: owner}).then((r) => {
        return Setup.vote.actor.vote(2,1, {from: owner}).then((r2) => {
          assert.isOk(r)
        })
      })
    })

    it("should be able to get Polls list voter took part", function() {
      return Setup.vote.details.getMemberPolls.call({from: owner}).then((r) => {
        assert.equal(r.length,2)
      })
    })

    it("should be able to show Poll by id", function() {
      return Setup.vote.details.getPoll.call(1, {from: owner}).then((r) => {
        return Setup.vote.details.getPoll.call(2, {from: owner}).then((r2) => {
          assert.equal(r[2],vote1Obj.details);
          assert.equal(r2[2],bytes32('New Poll2'));
        })
      })
    })

    it("owner1 shouldn't be able to vote Poll 1, Option 1", function() {
      return Setup.vote.actor.vote.call(1,1, {from: owner1}).then((r) => {
        assert.equal(r, ErrorsEnum.VOTE_POLL_NO_SHARES)
      })
    })
  })

  context("owner1 shares deposit and voting", function() {
    it("should be able to send 50 TIME to owner", function() {
        return proxyForSymbol(SYMBOL)
        .then(_token => {
            return _token.transfer.call(owner1, timeTokensBalance, { from: admin })
            .then(_isSuccess => {
                return _token.transfer(owner1, timeTokensBalance, { from: admin })
                .then(() => {
                    assert.isOk(_isSuccess)
                })
            })
        })
    })

    it("check Owner1 has 50 TIME", function() {
      return proxyForSymbol(SYMBOL)
      .then(_proxy => _proxy.balanceOf.call(owner1))
      .then(_balance => {
        assert.equal(_balance, timeTokensBalance)
      })
    })

    it("owner should be able to approve 50 TIME to TimeHolder", function() {
        return Setup.timeHolder.wallet.call().then(_wallet => {
            return proxyForSymbol(SYMBOL)
            .then(_proxy => {
                return _proxy.approve.call(_wallet, timeTokensBalance, {from: owner1}).then((r) => {
                    return _proxy.approve(_wallet, timeTokensBalance, {from: owner1}).then(() => {
                        assert.isOk(r)
                    })
                })

            })
        })
    })

    it("should be able to deposit 50 TIME from owner1", function() {
      return Setup.timeHolder.deposit.call(timeTokensBalance, {from: owner1}).then((r) => {
        return Setup.timeHolder.deposit(timeTokensBalance, {from: owner1}).then(() => {
          assert.isOk(r)
        })
      })
    })

    it("should show 50 TIME owner balance", function() {
      return Setup.timeHolder.depositBalance.call(owner1, {from: owner1}).then((r) => {
        assert.equal(r,timeTokensBalance)
      })
    })

    it("owner should be able to vote Poll 1, Option 2", function() {
      return Setup.vote.actor.vote.call(1,2, {from: owner1}).then((r) => {
        return Setup.vote.actor.vote(1,2, {from: owner1}).then((r2) => {
          assert.isOk(r)
        })
      })
    })

    it("Polls count should be equal to active + inactive polls", function() {
        return Setup.vote.details.getActivePollsCount.call().then((activePollsCount) => {
          return Setup.vote.details.getInactivePollsCount.call().then((inactivePollsCount) => {
            return Setup.vote.details.pollsCount.call().then((pollsCount) => {
              assert.isTrue(pollsCount.cmp(activePollsCount.add(inactivePollsCount)) == 0)
            })
          })
        })
    })

    it("shouldn't show Poll 2 as finished", function() {
      return Setup.vote.details.getPoll.call(2).then((r) => {
        assert.equal(r[6],true)
      });
    });

    it("owner1 should be able to vote Poll 2, Option 1", function() {
      return Setup.vote.actor.vote.call(2,1, {from: owner1}).then((r) => {
        return Setup.vote.actor.vote(2,1, {from: owner1}).then((r2) => {
          assert.isOk(r)
        })
      })
    })

    it("should show Poll 2 as finished", function() {
      return Setup.vote.details.getPoll.call(2).then((r) => {
        assert.equal(r[6],false)
      });
    });

    it("should be able to show number of Votes for each Option for Poll 1", function() {
      return Setup.vote.details.getOptionsVotesForPoll.call(1).then((r) => {
        assert.equal(r[0],timeTokensToWithdraw25Balance)
        assert.equal(r[1],timeTokensBalance)
      })
    })

    it("should be able to show number of Votes for each Option for Poll 2", function() {
      return Setup.vote.details.getOptionsVotesForPoll.call(2).then((r) => {
        assert.equal(r[0],timeTokensToWithdraw75Balance)
      })
    })

    it("should be able to get Polls list owner1 took part", function() {
      return Setup.vote.details.getMemberPolls.call({from: owner1}).then((r) => {
        assert.equal(r.length,2);
      })
    })

    it("shouldn't be able to create more then 20 active Polls", function() {
      this.timeout(1000000);
      return createPolls(199).then(() => {
        return Setup.vote.details.getActivePollsCount.call().then((r) => {
          return Setup.vote.details.getInactivePollsCount.call().then((r2) => {
            assert.equal(r, 20)
            assert.equal(r2, 181)
          })
        })
      })
    })

    it("should allow to delete inactive Polls for CBE admins", function() {
      return Setup.vote.manager.removePoll(100).then(() => {
        return Setup.vote.details.getActivePollsCount.call().then((r) => {
          return Setup.vote.details.getInactivePollsCount.call().then((r2) => {
            assert.equal(r, 20)
            assert.equal(r2, 180)
          })
        })
      })
    })

    it("shouldn't allow to delete inactive Polls for non CBE admins", function() {
      return Setup.vote.manager.removePoll(101,{from: owner1}).then(() => {
        return Setup.vote.details.getActivePollsCount.call().then((r) => {
          return Setup.vote.details.getInactivePollsCount.call().then((r2) => {
            assert.equal(r, 20)
            assert.equal(r2, 180)
          })
        })
      })
    })

    it("shouldn't allow to delete acvite Polls for non CBE admins", function() {
      return Setup.vote.details.checkPollIsActive.call(1).then((r) => {
        return Setup.vote.manager.removePoll(1, {from: owner1}).then(() => {
          return Setup.vote.details.getActivePollsCount.call().then((r2) => {
            return Setup.vote.details.getInactivePollsCount.call().then((r3) => {
              assert.isOk(r)
              assert.equal(r2, 20)
              assert.equal(r3, 180)
            })
          })
        })
      })
    })

    it("should be able to show number of Votes for each Option for Poll 1", function() {
      return Setup.vote.details.getOptionsVotesForPoll.call(1).then((r) => {
        assert.equal(r[0],timeTokensToWithdraw25Balance)
        assert.equal(r[1],timeTokensBalance)
      })
    })

    it("should be able to withdraw 5 TIME from owner1", function() {
      return Setup.timeHolder.withdrawShares.call(5, {from: owner1}).then((r) => {
        return Setup.timeHolder.withdrawShares(5, {from: owner1}).then(() => {
          assert.isOk(r)
        })
      })
    })

    it("should be able to show number of Votes for each Option for Poll 1", function() {
      return Setup.vote.details.getOptionsVotesForPoll.call(1).then((r) => {
        assert.equal(r[0],timeTokensToWithdraw25Balance)
        assert.equal(r[1],timeTokensToWithdraw45Balance)
      })
    })

    it("shouldn't show Poll 1 as finished", function() {
      return Setup.vote.details.getPoll.call(1).then((r) => {
        assert.equal(r[6],true)
      })
    })

    it("should show owner1 took part in poll 0 and 1", function() {
      return Setup.vote.details.getMemberPolls.call({from: owner1}).then((r) => {
        assert.equal(r.length,2);
      })
    })

    it("should be able to withdraw 45 TIME from owner1", function() {
      return Setup.timeHolder.withdrawShares.call(45, {from: owner1}).then((r) => {
        return Setup.timeHolder.withdrawShares(45, {from: owner1}).then(() => {
          assert.isOk(r)
        })
      })
    })

    it("should show owner1 took part only in finished poll 1", function() {
      return Setup.vote.details.getMemberPolls.call({from: owner1}).then((r) => {
        assert.equal(r.length,1)
      })
    })

    it("should decrese acvite Polls count", function() {
      return Setup.vote.details.getActivePollsCount.call().then((r) => {
        assert.equal(r, 20)
      })
    })

    let remainderTimeTokenBalance = totalTimeTokens - timeTokensToWithdraw25Balance

    it("owner should be able to approve 9999975 TIME to Vote", function() {
        return Setup.timeHolder.wallet.call().then(_wallet => {
            return proxyForSymbol(SYMBOL)
            .then(_proxy => {
                return _proxy.approve.call(_wallet, remainderTimeTokenBalance, { from: owner }).then((r) => {
                    return _proxy.approve(_wallet, remainderTimeTokenBalance, { from: owner }).then(() => {
                        assert.isOk(r)
                    })
                })

            })
        })
    })

    it("should be able to deposit 9999975 TIME from owner", function() {
      return Setup.timeHolder.deposit.call(remainderTimeTokenBalance, {from: owner}).then((r) => {
        return Setup.timeHolder.deposit(remainderTimeTokenBalance, {from: owner}).then(() => {
          assert.isOk(r)
        })
      })
    })

    it("should show 0 TIME owner balance", function() {
      return Setup.timeHolder.depositBalance.call(owner1).then((r) => {
        assert.equal(r,0)
        return proxyForSymbol(SYMBOL)
        .then(_token => _token.balanceOf.call(owner1))
        .then(_balance => {
            assert.equal(_balance, timeTokensBalance)
        })
      })
    })

    it("shouldn't show Poll 1 as finished", function() {
      return Setup.vote.details.getPoll.call(1).then((r) => {
        assert.equal(r[6],true)
      })
    })

    it("should decrese active Polls count", function() {
      return Setup.vote.details.getActivePollsCount.call().then((r) => {
        assert.equal(r, 20)
      })
    })

    it("should be able to show number of Votes for each Option for Poll 1", function() {
      return Setup.vote.details.getOptionsVotesForPoll.call(1).then((r) => {
        assert.equal(r[0],totalTimeTokens)
        assert.equal(r[1],0)
      })
    })

    it("should be able to show number of Votes for each Option for Poll 2", function() {
      return Setup.vote.details.getOptionsVotesForPoll.call(2).then((r) => {
        assert.equal(r[0],timeTokensToWithdraw75Balance)
        assert.equal(r[1],0)
      })
    })

    it("should allow admin to end poll", function() {
      return Setup.vote.manager.adminEndPoll(3, { from: admin }).then((_tx) => {
          console.log('end', _tx.tx);
        return Setup.vote.details.getPoll.call(3).then((r) => {
          assert.equal(r[6], false)
        })
      })
    })

    it("should decrese active Polls count", function() {
      return Setup.vote.details.getActivePollsCount.call().then((r) => {
        assert.equal(r, 19)
      })
    })

    it("should revert after all", reverter.revert)
  })

  context('MINT-421', function() {
      let vote10DetailsIpfsHash = bytes32fromBase58("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd7d")

      it("should be able to create Poll 10 and check details", function() {
        return Setup.vote.manager.getVoteLimit.call().then((r) => {
          return Setup.vote.manager.NewPoll([web3.fromAscii('1'), web3.fromAscii('2')], ['1', '2'], vote10DetailsIpfsHash, r - 1, unix + 10000, {
            from: owner,
            gas: 3000000
        }).then((tx) => {
            let event = eventsHelper.extractEvents(tx, "PollCreated")[0];
            poll10Id = event.args.pollId

            return Setup.vote.details.pollsCount().then(r => assert.equal(r, 1))
            })
        }).then(() => {
          return Setup.vote.details.getPoll(poll10Id)
            .then(details => {
              assert.equal(web3.toHex(details[0]), web3.toHex(poll10Id))
              assert.equal(details[2], vote10DetailsIpfsHash)
          })
        })
      })

      let vote11DetailsIpfsHash = bytes32fromBase58("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zd999")
      var poll11Id

      it("should be able to create Poll 11 which contains only numbers and get the same details back", function() {
          return Setup.vote.manager.getVoteLimit().then((r) => {
            return Setup.vote.manager.NewPoll([web3.fromAscii('1'), web3.fromAscii('2')], ['1', '2'], vote11DetailsIpfsHash, r - 1, unix + 10000, {
              from: owner,
              gas: 3000000
          }).then((tx) => {
              let event = eventsHelper.extractEvents(tx, "PollCreated")[0];
              poll11Id = event.args.pollId

              return Setup.vote.details.pollsCount().then(r => assert.equal(r, 2))
          }).then(() => {
            return Setup.vote.details.getPoll(poll11Id)
            .then(details => {
                assert.equal(web3.toHex(details[0]), web3.toHex(poll11Id))
                assert.equal(details[2], vote11DetailsIpfsHash)
            })
          })
        })
      })

      var poll12Id

      it('should be able to return a predictable number of polls after adding one more poll', function() {
          return Setup.vote.manager.getVoteLimit().then((r) => {
            return Setup.vote.manager.NewPoll([web3.fromAscii('1'), web3.fromAscii('2')], ['1', '2'], vote11DetailsIpfsHash, r - 1, unix + 10000, {
              from: owner,
              gas: 3000000
          }).then((tx) => {
              let event = eventsHelper.extractEvents(tx, "PollCreated")[0];
              poll12Id = event.args.pollId

              return Setup.vote.details.pollsCount().then(count => assert.equal(count, 3))
          })
        })
      })

      it("should be able to delete polls and have a predictable number of polls after it", function() {
          return Setup.vote.manager.removePoll.call(poll10Id).then((r) => {
              return Setup.vote.manager.removePoll(poll10Id)
              .then((tx) => {
                  console.log('remove', tx.tx);
                    assert.equal(r, ErrorsEnum.OK)
                    let removeEvent = eventsHelper.extractEvents(tx, "PollDeleted")[0]
                    assert.equal(web3.toHex(removeEvent.args.pollId), web3.toHex(poll10Id))
              }).then(() => Setup.vote.details.pollsCount())
              .then(count => assert.equal(count, 2))
              .then(() => Setup.vote.details.getPoll(poll10Id))
              .then(assert.fail)
              .catch(() => {})
              .then(() => Setup.vote.details.getPoll(poll11Id))
              .then(details => {
                  assert.equal(web3.toHex(details[0]), web3.toHex(poll11Id))
              })
          })
      })

      it("should be able to delete Poll 11 after deletion of other poll", function() {
          return Setup.vote.manager.removePoll(poll11Id)
          .then(() => Setup.vote.details.pollsCount())
          .then(count => assert.equal(count, 1))
          .then(() => Setup.vote.details.getPoll(poll12Id))
          .then(details => {
              assert.equal(web3.toHex(details[0]), web3.toHex(poll12Id))
          })
      })

      var poll13Id
      let vote13DetailsIpfsHash = bytes32fromBase58("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zd333")


      it("should add new poll and active previous one", function() {
          return Setup.vote.manager.getVoteLimit().then((r) => {
              return Setup.vote.manager.NewPoll([web3.fromAscii('1'), web3.fromAscii('2')], ['1', '2'], vote13DetailsIpfsHash, r - 1, unix + 10000, {
                  from: owner,
                  gas: 3000000
              }).then((tx) => {
                  let event = eventsHelper.extractEvents(tx, "PollCreated")[0];
                  poll13Id = event.args.pollId
              })
          }).then(() => Setup.vote.manager.activatePoll.call(poll12Id, { from: admin })).then(r => {
              return Setup.vote.manager.activatePoll(poll12Id, { from: admin })
                .then(() => {
                    assert.equal(web3.toHex(r), web3.toHex(ErrorsEnum.MULTISIG_ADDED))

                    return Setup.vote.actor.vote.call(poll12Id, 1, { from: owner })
                }).then(voteResult => {
                    return Setup.vote.actor.vote(poll12Id, 1, { from: owner }).then((voteTx) => {
                        let voteEvent = eventsHelper.extractEvents(voteTx, "VoteCreated")[0]

                        assert.equal(web3.toHex(voteResult), web3.toHex(ErrorsEnum.OK))
                        assert.equal(web3.toHex(voteEvent.args.choice), web3.toHex(1))
                        assert.equal(web3.toHex(voteEvent.args.pollId), web3.toHex(poll12Id))
                    })
                })
          }).then(() => {
              return Setup.vote.actor.vote.call(poll13Id, 1, { from: owner }).then(voteResult => {
                  assert.equal(web3.toHex(voteResult), web3.toHex(ErrorsEnum.VOTE_POLL_INACTIVE))
              })
          })
      })

      it('should be able to receive a list for voters with options', function() {
          return Setup.vote.details.getOptionsVotesStatisticForPoll(poll12Id).then(options => {
              assert.equal(options[0], 1)
              assert.equal(options[1], 0)
          })
      })

      context("Update poll details", function () {

      it("should be able to update details for a not activated poll", function () {
          let updDetailsIpfsHash = bytes32fromBase58("MmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zd333")
          return Setup.vote.manager.updatePollDetailsIpfsHash.call(poll13Id, updDetailsIpfsHash, { from: owner })
          .then(code => {
              return Setup.vote.manager.updatePollDetailsIpfsHash(poll13Id, updDetailsIpfsHash, { from: owner })
              .then(() => {
                  assert.equal(code, ErrorsEnum.OK)
              })
          })
          .then(() => Setup.vote.details.getPoll(poll13Id))
          .then(details => {
              assert.equal(details[2], updDetailsIpfsHash)
          })
      })

      it("should not be able to update details for an activated poll", function () {
          let updDetailsIpfsHash = web3.fromAscii("Other poll12")
          return Setup.vote.manager.updatePollDetailsIpfsHash.call(poll12Id, updDetailsIpfsHash, { from: owner })
          .then(code => {
              assert.equal(code, ErrorsEnum.VOTE_POLL_SHOULD_BE_INACTIVE)
          })
          .then(() => Setup.vote.details.getPoll(poll12Id))
          .then(details => {
              assert.notEqual(details[2], updDetailsIpfsHash)
          })
      })

      it("should be able to add more options to a not activated poll", function() {
          let newOption = web3.fromAscii("3")
          return Setup.vote.manager.addPollOption.call(poll13Id, newOption, { from: owner })
          .then(code => {
              return Setup.vote.manager.addPollOption(poll13Id, newOption, { from: owner })
              .then(() => assert.equal(code, ErrorsEnum.OK))
          })
          .then(() => Setup.vote.details.getOptionsForPoll(poll13Id))
          .then(options => {
              assert.lengthOf(options, 3)
              assert.equal(cleanStr(web3.toAscii(options[2])), web3.toAscii(newOption))
          })
      })

      it("should not be able to add more than 16 options", function () {
          var pollId
          var options = Array.apply(null, Array(16)).map(function (_, i) { return web3.fromAscii("option " + i) })
          let newOption = web3.fromAscii("option err")
          return Setup.vote.manager.getVoteLimit().then((r) => {
              return Setup.vote.manager.NewPoll(options, ['1', '2'], vote11DetailsIpfsHash, r - 1, unix + 10000, {
                  from: owner,
                  gas: 3000000
              }).then((tx) => {
                  let event = eventsHelper.extractEvents(tx, "PollCreated")[0];
                  pollId = event.args.pollId
              })
          })
          .then(() => Setup.vote.manager.addPollOption.call(pollId, newOption, { from: owner }))
          .then(code => {
              assert.equal(code, ErrorsEnum.VOTE_OPTIONS_LIMIT_REACHED)
          })
      })

      it("should not be able to add more options to an activated poll", function () {
          let newOption = web3.fromAscii("3")
          return Setup.vote.manager.addPollOption.call(poll12Id, newOption, { from: owner })
          .then(code => {
              assert.equal(code, ErrorsEnum.VOTE_POLL_SHOULD_BE_INACTIVE)
          })
          .then(() => Setup.vote.details.getOptionsForPoll(poll12Id))
          .then(options => assert.lengthOf(options, 2))
      })

      it("should be able to remove option from a not activated poll", function () {
          let oldOption = web3.fromAscii("3")
          return Setup.vote.manager.removePollOption.call(poll13Id, oldOption, { from: owner })
          .then(code => {
              return Setup.vote.manager.removePollOption(poll13Id, oldOption, { from: owner })
              .then(() => assert.equal(code, ErrorsEnum.OK))
          })
          .then(() => Setup.vote.details.getOptionsForPoll(poll13Id))
          .then(options => {
              assert.lengthOf(options, 2)
              assert.notInclude(options, oldOption)
          })
      })

      it("should not be able to remove option from an activated poll", function () {
          let oldOption = web3.fromAscii("2")
          return Setup.vote.manager.removePollOption.call(poll12Id, oldOption, { from: owner })
          .then(code => {
              assert.equal(code, ErrorsEnum.VOTE_POLL_SHOULD_BE_INACTIVE)
          })
          .then(() => Setup.vote.details.getOptionsForPoll(poll12Id))
          .then(options => {
              assert.lengthOf(options, 2)
              let asciiOptions = options.map(function(e,_) { return cleanStr(web3.toAscii(e))})
              assert.include(asciiOptions, web3.toAscii(oldOption))
          })
      })

      it("cannot update details of a poll by non-owner", function () {
          let updDetailsIpfsHash = web3.fromAscii("Non owner 13")
          return Setup.vote.manager.updatePollDetailsIpfsHash.call(poll13Id, updDetailsIpfsHash, { from: nonOwner })
          .then(code => {
              return Setup.vote.manager.updatePollDetailsIpfsHash(poll13Id, updDetailsIpfsHash, { from: nonOwner })
              .then(() => assert.equal(code, ErrorsEnum.UNAUTHORIZED))
          })
          .then(() => Setup.vote.details.getPoll(poll13Id))
          .then(details => {
              assert.notEqual(details[2], updDetailsIpfsHash)
          })
      })

      it("should revert after all", reverter.revert)
  })
  })
})
