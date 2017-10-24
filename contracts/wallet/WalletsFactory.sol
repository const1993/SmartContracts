pragma solidity ^0.4.11;

import "./Wallet.sol";

contract WalletsFactory {

    function createWallet(address[] _owners, uint _required, address _contractsManager, address _eventsEmiter, bytes32 _name, bool _use2FA, uint _releaseTime) returns(address) {
        address wallet;
        wallet = new Wallet(_owners,_required, _contractsManager, _eventsEmiter,  _name, _use2FA, _releaseTime);
        return wallet;
    }

    function() {
        revert();
    }
}
