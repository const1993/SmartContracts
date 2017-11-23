pragma solidity ^0.4.11;

import '../core/event/MultiEventsHistoryAdapter.sol';

contract WalletEmitter is MultiEventsHistoryAdapter {

    // EVENTS

    // Funds has arrived into the wallet (record how much).
    event MultisigWalletDeposit(address indexed self, address from, uint value);
    // Single transaction going out of the wallet (record who signed for it, how much, and to whom it's going).
    event MultisigWalletSingleTransact(address indexed self, address indexed owner, uint value, address to, bytes32 symbol);
    // Multi-sig transaction going out of the wallet (record who signed for it last, the operation hash, how much, and to whom it's going).
    event MultisigWalletMultiTransact(address indexed self, address indexed owner, bytes32 operation, uint value, address to, bytes data);
    // Confirmation still needed for a transaction.
    event MultisigWalletConfirmationNeeded(address indexed self, bytes32 operation, address indexed initiator, uint value, address to, bytes data);

    event MultisigWalletConfirmation(address indexed self, address indexed owner, bytes32 operation);

    event MultisigWalletRevoke(address indexed self, address indexed owner, bytes32 operation);
    // some others are in the case of an owner changing.
    event MultisigWalletOwnerChanged(address indexed self, address indexed oldOwner, address indexed newOwner);

    event MultisigWalletOwnerAdded(address indexed self, address indexed newOwner);

    event MultisigWalletOwnerRemoved(address indexed self, address indexed oldOwner);
    // the last one is emitted if the required signatures change
    event MultisigWalletRequirementChanged(address indexed self, uint newRequirement);

    event MultisigWallet2FAChanged(address indexed self, bool enabled);

    event Error(address indexed self, uint errorCode);

    function emitError(uint errorCode) {
        Error(_self(), errorCode);
    }

    function emitDeposit(address from, uint value) {
        MultisigWalletDeposit(_self(), from, value);
    }

    function emitSingleTransact(address owner, uint value, address to, bytes32 symbol) {
        MultisigWalletSingleTransact(_self(), owner, value, to, symbol);
    }

    function emitMultiTransact(address owner, bytes32 operation, uint value, address to, bytes data) {
        MultisigWalletMultiTransact(_self(), owner, operation, value, to, data);
    }

    function emitConfirmationNeeded(bytes32 operation, address initiator, uint value, address to, bytes data) {
        MultisigWalletConfirmationNeeded(_self(), operation, initiator, value, to, data);
    }

    function emitConfirmation(address owner, bytes32 operation) {
        MultisigWalletConfirmation(_self(), owner, operation);
    }

    function emitRevoke(address owner, bytes32 operation) {
        MultisigWalletRevoke(_self(), owner, operation);
    }

    function emitOwnerChanged(address oldOwner, address newOwner) {
        MultisigWalletOwnerChanged(_self(), oldOwner, newOwner);
    }

    function emitOwnerAdded(address newOwner) {
        MultisigWalletOwnerAdded(_self(), newOwner);
    }

    function emitOwnerRemoved(address oldOwner) {
        MultisigWalletOwnerAdded(_self(), oldOwner);
    }

    function emitRequirementChanged(uint newRequirement) {
        MultisigWalletRequirementChanged(_self(), newRequirement);
    }

    function emit2FAChanged(bool enabled) {
        MultisigWallet2FAChanged(_self(), enabled);
    }
}
