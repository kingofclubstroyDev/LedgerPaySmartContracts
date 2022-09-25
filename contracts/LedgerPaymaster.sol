// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./BasePaymaster.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LedgerPaymaster is BasePaymaster {

    using ECDSA for bytes32;
    using UserOperationLib for UserOperation;

    address ledgerPaySigner;
    bool requireSignature = true;

    constructor(EntryPoint _entryPoint, address _signer) BasePaymaster(_entryPoint) {
        ledgerPaySigner = _signer;
    }

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterData",
     * which will carry the signature itself.
     */
    function getHash(UserOperation calldata userOp)
    public pure returns (bytes32) {
        //can't use userOp.hash(), since it contains also the paymasterData itself.
        return keccak256(abi.encode(
                userOp.getSender(),
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGas,
                userOp.verificationGas,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                userOp.paymaster
            ));
    }

     /**
     * verify our external signer signed this request.
     * the "paymasterData" is supposed to be a signature over the entire request params
     */
    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32 /*requestId*/, uint256 requiredPreFund)
    external view override returns (bytes memory context) {
        (requiredPreFund);

        if(requireSignature) {

            bytes32 hash = getHash(userOp);
            uint256 sigLength = userOp.paymasterData.length;
            require(sigLength == 64 || sigLength == 65, "LedgerPaymaster: invalid signature length in paymasterData");
            require(ledgerPaySigner == hash.toEthSignedMessageHash().recover(userOp.paymasterData), "LedgerPaymaster: wrong signature");

        }

        //no need for other on-chain validation: entire UserOp should have been checked
        // by the external service prior to signing it.
        return "";
    }

    /**
    * toggle if a signature from ledgerPaySigner is required to cover the gas of a requested transaction
    */
    function toggleRequireSignature() external {
        require(msg.sender == ledgerPaySigner, "LedgerPaymaster: invalid user");
        bool sigRequired = !requireSignature;
        requireSignature = sigRequired;
        emit SignatureRequirementChanged(sigRequired);
    }

    function setSigner(address _newSigner) external {

        require(msg.sender == ledgerPaySigner, "Only signer can call");
        ledgerPaySigner = _newSigner;

    } 

    event SignatureRequirementChanged(bool signatureRequired);


}