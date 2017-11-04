pragma solidity ^0.4.11;

import "./GenericCrowdsale.sol";

/**
*  @title ChronoMintEtherBasedCrowdsale contract
*  Accepts Ether.
*/
contract ChronoMintEtherBasedCrowdsale is GenericCrowdsale {
    /*using SafeMath for uint;*/

    /* raised wie will be transfered to this address if success */
    address public fund;
    /* ERC20 tokens white list */

    event NewFund(address indexed sender, address fund);
    event ReceivedEther(address indexed sender, address indexed investor, uint weiValue);
    event RefundedEther(address indexed sender, address indexed investor, uint weiValue);
    event WithdrawEther(address indexed sender, uint amout);

    /**
    *  Check if Ether sale is enabled.
    */
    modifier isEtherSale {
        if (fund == 0x0) revert();
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
    function ChronoMintEtherBasedCrowdsale(address _serviceProvider, bytes32 _symbol, address _priceTicker)
        GenericCrowdsale(_serviceProvider, _symbol, _priceTicker)
        public
    {
    }

    /**
    *  Enable Ether sale
    */
    function enableEtherSale(address _fund) onlyAuthorised public returns (uint) {
        require(_fund != 0x0);
        fund = _fund;

        registerSalesAgent(address(this), "ETH");

        return OK;
    }

    /**
    *  Disable Ether sale
    */
    function disableEtherSale() onlyAuthorised public returns (uint) {
        delete fund;
        unregisterSalesAgent(this, "ETH");

        return OK;
    }

    /**
    * The basic entry point to participate the crowdsale process.
    * Pay for funding, get invested tokens back in the sender address.
    *
    * Ether sale must be enabled.
    */
    function () onlyRunning isEtherSale payable public {
        this.sale(msg.sender, msg.value, "ETH");

        ReceivedEther(address(this), msg.sender, msg.value);
    }

    /**
    * Investors can claim refund (only Ether deposit).
    *
    * Note that any refunds from proxy buyers should be handled separately,
    * and not through this contract.
    */
    function refund() onlyFailure public {
        uint weiDonation = this.refund(msg.sender, "ETH");
        if (!msg.sender.send(weiDonation)) revert();

        RefundedEther(address(this), msg.sender, weiDonation);
    }

    /**
    * @dev Withdrawal Ether balance on successfull finish
    */
    function withdraw() onlySuccess onlyAuthorised isEtherSale public {
        uint balance = this.balance;
        if (!fund.send(balance)) revert();

        WithdrawEther(address(this), balance);
    }
}
