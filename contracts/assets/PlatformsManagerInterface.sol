pragma solidity ^0.4.11;

contract PlatformsManagerInterface {
    function getPlatformForUser(address _user) public constant returns (address);
}
