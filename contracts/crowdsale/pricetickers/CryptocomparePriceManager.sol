pragma solidity ^0.4.11;

import "../../core/common/Object.sol";
import "../base/PriceTicker.sol";
import "oraclize/usingOraclize.sol";
import "../../core/lib/StringsLib.sol";


/**
*  @title CryptoCompare Price Ticker
*/
contract CryptocomparePriceManager is PriceTicker, usingOraclize, Object {
    uint constant EXCHANGE_RATE_DECIMALS = 18;

    struct ExchangePrice {
        uint rate;
    }

    struct Query {
        address sender;
        bytes32 fsym;
        bytes32 tsym;
    }

    /* bytes32(from, to) -> price * 10**EXCHANGE_RATE_DECIMALS */
    mapping (bytes32 => ExchangePrice) exchangePrices;
    /* query id -> original sender */
    mapping (bytes32 => Query) queries;

    /**
    *  Only Oraclize access rights checks
    */
    modifier onlyOraclize {
        if (msg.sender != oraclize_cbAddress()) revert();
        _;
    }

    /**
    *  Implement PriceTicker interface.
    */
    function isPriceAvailable(bytes32 _fsym, bytes32 _tsym) public constant returns (bool) {
        if (isEquivalentSymbol(_fsym, _tsym)) return true;

        return exchangePrices[keccak256(_fsym, _tsym)].rate != 0;
    }

    /**
    *  Implement PriceTicker interface.
    */
    function price(bytes32 _fsym, bytes32 _tsym) public constant returns (uint, uint) {
        if (isEquivalentSymbol(_fsym, _tsym)) return (1, 0);

        return (exchangePrices[keccak256(_fsym, _tsym)].rate, EXCHANGE_RATE_DECIMALS);
    }

    /**
    *  Implement PriceTicker interface.
    */
    function requestPrice(bytes32 _fsym, bytes32 _tsym) payable public returns (bytes32, uint) {
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
    function __callback(bytes32 _queryId, string _result) public onlyOraclize {
        Query memory query = queries[_queryId];

        // invalid query, nothing to do
        if (query.sender == 0x0) revert();

        uint exchangePrice = parseInt(_result, EXCHANGE_RATE_DECIMALS);
        assert(exchangePrice > 0);

        if (exchangePrice != 0) {
            exchangePrices[keccak256(query.fsym, query.tsym)] = ExchangePrice(exchangePrice);
        }

        delete queries[_queryId];

        ExchangePriceUpdated(query.sender, query.fsym, query.tsym, now, exchangePrice, EXCHANGE_RATE_DECIMALS);
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
        queries[queryId] = Query(_sender, _fsym, _tsym);

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
                          StringsLib.bytes32ToString(_fsym),
                          "&tsyms=",
                          StringsLib.bytes32ToString(_tsym),
                          ").",
                          StringsLib.bytes32ToString(_format));
    }

    function strConcat(string _a, string _b, string _c, string _d, string _e, string _f) internal constant returns (string) {
        return strConcat(strConcat(_a, _b, _c, _d, _e), _f);
    }
}
