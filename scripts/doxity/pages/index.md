# SmartContracts [![Build Status](https://travis-ci.org/ChronoBank/SmartContracts.svg?branch=master)](https://travis-ci.org/ChronoBank/SmartContracts)
ChronoMint, Labour Hours and Time contracts.

Documentation at [chronobank.github.io](https://chronobank.github.io/SmartContracts/).

- ChronoBankPlatform.sol acts as a base for all tokens operation (like issuing, balance storage, transfer).
- ChronoBankAsset.sol adds interface layout (described in ChronoBankAssetInterface.sol)
- ChronoBankAssetWithFee.sol extends ChronoBankAsset.sol with operations fees logic.
- ChronoBankAssetProxy.sol acts as a transaction proxy, provide an ERC20 interface (described in ERC20Interface.sol) and allows additional logic insertions and wallet access recovery in case of key loss.
- ChronoBankPlatformEmitter.sol provides platform events definition.

To understand contract logic better you can take a look at the comments also as at unit tests

[![Smart_Contracts_small_v6-1.png](https://s33.postimg.org/diw8gl1gf/Smart_Contracts_small_v6-1.png)](https://postimg.org/image/oihfs6rvf/) [PDF version](http://docdro.id/l4fNmNX) for detailed preview.

[![Smart_Contracts_full_v6-1.png](https://s33.postimg.org/3x2o0bklb/Smart_Contracts_full_v6-1.png)](https://postimg.org/image/i3ievjvgb/) [PDF version](http://docdro.id/O4kPYpC) for detailed preview.

## Testing
NodeJS 6+ required.
```bash
npm install -g ethereumjs-testrpc
npm install -g truffle
```

Then start TestRPC in a separate terminal by doing
```bash
testrpc
```

Then run tests in a project dir by doing
```bash
truffle test
```
