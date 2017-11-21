pragma solidity ^0.4.11;

/**
* @title TODO
*/
library ArrayLib {

    /**
    * @dev TODO
    */
    function nonEmptyLengthOfArray(bytes32[] storage _arr) public constant returns (uint _length) {
        for (uint _idx = 0; _idx < _arr.length; ++_idx) {
            if (_arr[_idx] != bytes32(0)) {
                ++_length;
            }
        }
    }

    /**
    * @dev TODO
    */
    function addToArray(bytes32[] storage _arr, bytes32 _value) public returns (bool) {
        uint _notFoundIdx = 2**254;
        uint _insertIdx = _notFoundIdx;
        for (uint _idx = 0; _idx < _arr.length; ++_idx) {
            bytes32 _e = _arr[_idx];
            if (_e == _value) {
                return true;
            }

            if (_insertIdx == _notFoundIdx && _e == bytes32(0)) {
                _insertIdx = _idx;
                break;
            }
        }

        if (_insertIdx == _notFoundIdx) {
            return false;
        }

        _arr[_idx] = _value;
        return true;
    }

    /**
    * @dev TODO
    */
    function arrayIncludes(bytes32[] storage _arr, bytes32 _value) public returns (bool) {
        for (uint _idx = 0; _idx < _arr.length; ++_idx) {
            if (_arr[_idx] == _value) {
                return true;
            }
        }
    }

    /**
    * @dev TODO
    */
    function removeFirstFromArray(bytes32[] storage _arr, bytes32 _value) public {
        for (uint _idx = 0; _idx < _arr.length; ++_idx) {
            if (_arr[_idx] == _value) {
                delete _arr[_idx];
                return;
            }
        }
    }
}
