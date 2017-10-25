pragma solidity ^0.4.11;

import "./Wallet.sol";

contract WalletsFactory {

    function createWallet(address[] _owners, uint _required, address _contractsManager, address _eventsEmiter, bytes32 _name) returns(address) {
        address wallet;
        wallet = new Wallet(_owners,_required, _contractsManager, _eventsEmiter,  _name);
        return wallet;
    }

    function() {
        throw;
    }
}
