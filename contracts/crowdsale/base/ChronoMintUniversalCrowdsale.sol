pragma solidity ^0.4.11;

import "./ChronoMintERC20BasedCrowdsale.sol";
import "./ChronoMintEtherBasedCrowdsale.sol";


contract ChronoMintUniversalCrowdsale is ChronoMintEtherBasedCrowdsale, ChronoMintERC20BasedCrowdsale {

    function ChronoMintUniversalCrowdsale(address _serviceProvider, bytes32 _symbol, address _priceTicker)
        ChronoMintEtherBasedCrowdsale(_serviceProvider, _symbol, _priceTicker)
        ChronoMintERC20BasedCrowdsale(_serviceProvider, _symbol, _priceTicker)
        public
    {
    }
}
