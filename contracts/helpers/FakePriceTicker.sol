pragma solidity ^0.4.11;

import "../crowdsale/base/PriceTicker.sol";

contract FakePriceTicker is PriceTicker {

    function isPriceAvailable(bytes32 fsym, bytes32 tsym) constant returns (bool) {
        return true;
    }

    function price(bytes32 fsym, bytes32 tsym) constant returns (uint, uint) {
        return (10, 1);
    }

    function requestPrice(bytes32 fsym, bytes32 tsym) payable returns (bytes32, uint) {
        ExchangePriceUpdated(msg.sender, fsym, tsym, now, 10, 1);
    }
}
