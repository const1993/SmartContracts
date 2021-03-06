pragma solidity ^0.4.11;

import "../../core/common/Object.sol";
import "../base/PriceTicker.sol";
import "oraclize/usingOraclize.sol";

/**
*  @title CryptoCompare Price Ticker
*/
contract CryptocomparePriceTicker is PriceTicker, usingOraclize, Object {
    uint constant EXCHANGE_RATE_DECIMALS = 18;
    uint constant TTL = 60000;

    struct ExchangePrice {
        uint rate;
        uint expiry;
    }

    struct Query {
        address sender;
        bytes32 hash;
    }

    /* bytes32(from, to) -> price * 10**EXCHANGE_RATE_DECIMALS */
    mapping (bytes32 => ExchangePrice) exchangePrices;
    /* query id -> original sender */
    mapping (bytes32 => Query) queries;

    /**
    *  Only Oraclize access rights checks
    */
    modifier onlyOraclize() {
        if (msg.sender != oraclize_cbAddress()) revert();
        _;
    }

    /**
    *  Implement PriceTicker interface.
    */
    function isPriceAvailable(bytes32 _fsym, bytes32 _tsym) constant returns (bool) {
        if (isEquivalentSymbol(_fsym, _tsym)) return true;

        ExchangePrice memory exchangePrice = exchangePrices[sha3(_fsym, _tsym)];
        return exchangePrice.expiry < now;
    }

    /**
    *  Implement PriceTicker interface.
    */
    function price(bytes32 _fsym, bytes32 _tsym) constant returns (uint, uint) {
        if (isEquivalentSymbol(_fsym, _tsym)) return (1, 0);

        ExchangePrice memory exchangePrice = exchangePrices[sha3(_fsym, _tsym)];
        return (exchangePrice.rate, EXCHANGE_RATE_DECIMALS);
    }

    /**
    *  Implement PriceTicker interface.
    */
    function requestPrice(bytes32 _fsym, bytes32 _tsym) payable returns (bytes32, uint) {
        assert(!isEquivalentSymbol(_fsym, _tsym));

        if (_fsym == _tsym) {
            return (0x0, PRICE_TICKER_INVALID_INVOCATION);
        }

        if (isPriceAvailable(_fsym, _tsym)) {
            return (0x0, PRICE_TICKER_INVALID_INVOCATION);
        }

        var (queryId, resultCode) = updatePrice(_fsym, _tsym, msg.sender);
        if (resultCode != OK) {
            return (0x0, resultCode);
        }

        return (queryId, OK);
    }

    /**
    *  Oraclize query callback.
    */
    function __callback(bytes32 _queryId, string _result) onlyOraclize {
        Query memory query = queries[_queryId];

        // invalid query, nothing to do
        if (query.sender == 0x0 || query.hash == 0x0) revert();

        uint exchangePrice = parseInt(_result, EXCHANGE_RATE_DECIMALS);
        assert(exchangePrice > 0);

        if (exchangePrice != 0) {
            exchangePrices[query.hash] = ExchangePrice(exchangePrice, now + TTL);
        }

        delete queries[_queryId];
        PriceTickerCallback(query.sender).receivePrice(_queryId, exchangePrice, EXCHANGE_RATE_DECIMALS);
    }

    /**
    *
    */
    function updatePrice(bytes32 _fsym, bytes32 _tsym, address _sender) internal returns (bytes32, uint) {
        assert(!isEquivalentSymbol(_fsym, _tsym));
        assert(_sender != 0x0);

        if (oraclize_getPrice("URL") > this.balance) {
            return (0x0, PRICE_TICKER_INSUFFICIENT_BALANCE);
        }

        string memory query = buildQuery(_fsym, _tsym, _tsym);
        bytes32 queryId = oraclize_query("URL", query);
        queries[queryId] = Query(_sender, sha3(_fsym, _tsym));

        return (queryId, PRICE_TICKER_OK_UPDATING);
    }

    function isEquivalentSymbol(bytes32 _fsym, bytes32 _tsym) internal constant returns (bool) {
        if (_fsym == _tsym) return true;
        if (_fsym == "Ether" && _tsym == "ETH") return true;
        if (_fsym == "ETH" && _tsym == "Ether") return true;

        return false;
    }

    function buildQuery(bytes32 _fsym, bytes32 _tsym, bytes32 _format) internal constant returns (string) {
        return strConcat("json(https://min-api.cryptocompare.com/data/price?fsym=",
                          bytes32ToString(_fsym),
                          "&tsyms=",
                          bytes32ToString(_tsym),
                          ").",
                          bytes32ToString(_format));
    }

    function strConcat(string _a, string _b, string _c, string _d, string _e, string _f) internal constant returns (string) {
        return strConcat(strConcat(_a, _b, _c, _d, _e), _f);
    }

    // TODO: ahiatsevich - move to library
    function bytes32ToString(bytes32 x) internal constant returns (string) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
}
