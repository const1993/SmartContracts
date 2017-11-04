pragma solidity ^0.4.11;

import "./GenericCrowdsale.sol";
import "../../core/erc20/ERC20Interface.sol";
import {ERC20Manager as ERC20Service} from "../../core/erc20/ERC20Manager.sol";

/**
*  @title ChronoMintERC20BasedCrowdsale contract
*  Accepts ERC20 tokens.
*/
contract ChronoMintERC20BasedCrowdsale is GenericCrowdsale {
    /*using SafeMath for uint;*/

    /* ERC20 tokens white list */
    mapping (address => bool) allowedERC20;

    event ReceivedERC20(address indexed sender, address indexed investor, uint erc20Value, bytes32 symbol);
    event RefundedERC20(address indexed sender, address indexed investor, uint erc20Value, bytes32 symbol);

    /**
    * Checks if ERC20 sale is enabled for gined token.
    */
    modifier isERC20Sale(address token) {
        if (token == 0x0 || !allowedERC20[token]) revert();
        _;
    }

    /**
    *  @dev Constructor
    *
    *  @param _serviceProvider address
    *  @param _symbol Bounty token symbol
    *  @param _priceTicker Price ticker address
    *
    *  @notice this contract should be owner of bounty token
    */
    function ChronoMintERC20BasedCrowdsale(address _serviceProvider, bytes32 _symbol, address _priceTicker)
        GenericCrowdsale(_serviceProvider, _symbol, _priceTicker)
        public
    {
    }

    /**
    *  Allow to receive ERC20 token with given symbols.
    */
    function enableERC20Sale(bytes32[] whiteList) onlyAuthorised public returns (uint) {
        ERC20Service erc20Service = lookupERC20Service();
        for (uint i = 0; i < whiteList.length; i++) {
            address allowedToken = erc20Service.getTokenAddressBySymbol(whiteList[i]);
            if (allowedToken != 0x0) {
                allowedERC20[allowedToken] = true;
                registerSalesAgent(this, whiteList[i]);
            }
        }

        return OK;
    }

    /**
    *  Deny to receive ERC20 token with given symbols.
    */
    function disableERC20Sale(bytes32[] blackList) onlyAuthorised public returns (uint) {
        ERC20Service erc20Service = lookupERC20Service();
        for (uint i = 0; i < blackList.length; i++) {
            address disallowedToken = erc20Service.getTokenAddressBySymbol(blackList[i]);
            if (disallowedToken != 0x0) {
                delete allowedERC20[disallowedToken];
                unregisterSalesAgent(this, blackList[i]);
            }
        }

        return OK;
    }

    /**
    * @dev Receive ERC20 Token and send bounty.
    *
    * ERC20 sale must be enabled to token with given symbol.
    */
    function sellERC20(address _token) onlyRunning isERC20Sale(_token) payable public {
        uint remaining = ERC20Interface(_token).allowance(msg.sender, this);
        bytes32 symbol = getTokenSymbol(_token);

        uint initialBalance = ERC20Interface(_token).balanceOf(this);
        if (!ERC20Interface(_token).transferFrom(msg.sender, this, remaining)) revert();

        assert(remaining == ERC20Interface(_token).balanceOf(this) - initialBalance);

        this.sale(msg.sender, remaining, symbol);

        ReceivedERC20(address(this), msg.sender, remaining, symbol);
    }

    /**
    * Investors can claim refund (only ERC20 deposit).
    *
    * Note that any refunds from proxy buyers should be handled separately,
    * and not through this contract.
    */
    function refundERC20(address _token) onlyFailure payable public {
        require(_token != 0x0);
        require(lookupERC20Service().isTokenExists(_token));

        uint erc20Donation = this.refund(msg.sender, getTokenSymbol(_token));
        bytes32 symbol = getTokenSymbol(_token);

        uint initialBalance = ERC20Interface(_token).balanceOf(this);
        if (!ERC20Interface(_token).transfer(msg.sender, erc20Donation)) revert();

        assert(erc20Donation == initialBalance - ERC20Interface(_token).balanceOf(this));

        RefundedERC20(address(this), msg.sender, erc20Donation, symbol);
    }

    function lookupERC20Service() public constant returns (ERC20Service) {
        return ERC20Service(lookupService("ERC20Manager"));
    }

    /**
    *   Returns token symbol by given address.
    */
    function getTokenSymbol(address _token) public constant returns (bytes32) {
        var (,,symbol,,,,) = lookupERC20Service().getTokenMetaData(_token);
        return symbol;
    }
}
