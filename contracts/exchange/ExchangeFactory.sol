pragma solidity ^0.4.15;

import "./Exchange.sol";

// @title Exchange Factory contract
//
// @notice Just util contract used for Exchange creation
contract ExchangeFactory {
    // @notice Creates Exchange contract and transfers ownership to sender
    // @return exchange's address
    function createExchange() public returns (address) {
        Exchange exchange = new Exchange();
        if (!exchange.transferContractOwnership(msg.sender)) {
            revert();
        }

        return exchange;
    }
}
