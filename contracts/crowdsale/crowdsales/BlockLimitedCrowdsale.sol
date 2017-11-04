pragma solidity ^0.4.11;

import "../base/ChronoMintUniversalCrowdsale.sol";

/**
 * @title BlockLimitedCrowdsale is a crowdsale contract.
 *
 * Crowdsales have a start and end block numbers,
 * where investors can make token purchases and
 * the crowdsale will assign them tokens based on a token per exchange rate.
 *
 * See ChronoMintUniversalCrowdsale.
 */
contract BlockLimitedCrowdsale is ChronoMintUniversalCrowdsale {
    /* Block limited crowdfunding configuration */
    struct Params {
        uint256 startBlock;
        uint256 stopBlock;
    }

    Params public config;

    function BlockLimitedCrowdsale(address _serviceProvider, bytes32 _symbol, address _priceTicker)
        ChronoMintUniversalCrowdsale(_serviceProvider, _symbol, _priceTicker)
        public
    {
    }

    function init(
        bytes32 _currencyCode,
        uint _minValue,
        uint _maxValue,
        uint _exchangeRate,
        uint _exchangeRateDecimals,
        uint256 _startBlock,
        uint256 _stopBlock
    ) onlyAuthorised onlyOnce public {
        require (_stopBlock > _startBlock);
        require (block.number < _stopBlock);

        init(_currencyCode, _minValue, _maxValue, _exchangeRate, _exchangeRateDecimals);

        config.startBlock = _startBlock;
        config.stopBlock = _stopBlock;
    }

    function isRunning() public constant returns (bool) {
        return block.number > config.startBlock
                  && block.number < config.stopBlock
                  && GenericCrowdsale.isRunning();
    }

    function isFailed() public constant returns (bool) {
        return block.number > config.stopBlock
                && !GenericCrowdsale.isSuccessed();
    }
}
