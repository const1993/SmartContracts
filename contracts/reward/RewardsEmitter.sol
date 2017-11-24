pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract RewardsEmitter is MultiEventsHistoryAdapter {

    event WithdrawnSuccess(address addr, uint amount, uint total);
    event WithdrawnRewardSuccess(address asset, address addr, uint amountReward);
    event DepositStored(uint _part);
    event AssetRegistered(address assetAddress);
    event PeriodClosed();
    event Error(address indexed self, uint errorCode);

    function emitWithdrawnReward(address asset, address addr, uint amount) public {
        WithdrawnRewardSuccess(asset, addr, amount);
    }

    function emitWithdrawn(address addr, uint amount, uint total) public {
        WithdrawnSuccess(addr, amount, total);
    }

    function emitPeriodClosed() public {
        PeriodClosed();
    }

    function emitDepositStored(uint _part) public {
        DepositStored(_part);
    }

    function emitAssetRegistered(address assetAddress) public {
        AssetRegistered(assetAddress);
    }

    function emitError(uint error) public {
        Error(_self(), error);
    }
}
