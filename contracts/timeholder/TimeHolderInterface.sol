pragma solidity ^0.4.11;

import {ERC20Interface as Asset} from "../core/erc20/ERC20Interface.sol";

contract TimeHolderInterface {

    function wallet() public constant returns (address);
    function totalShares() public constant returns (uint);
    function sharesContract() public constant returns (address);
    function shareholdersCount() public constant returns (uint);
    function totalSupply() public constant returns(uint);
    function depositBalance(address _address) public constant returns(uint);
    function takeFeatureFee(address _account, uint _amount) public returns (uint resultCode);
}
