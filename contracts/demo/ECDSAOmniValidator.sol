// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../library/SignatureHandler.sol";
import "./BaseOmniValidator.sol";

/**
 * @title ECDSAValidator
 */
contract ECDSAOmniValidator is BaseOmniValidator {
    using ECDSA for bytes32;

    event SetSigner(address indexed wallet, address indexed oldSigner, address indexed newSigner);

    mapping(address => address) private _signers;

    //only for demo test
    mapping(address => address) private _demoTempMap;

    /**
     * @dev Sets a new signer for the calling wallet.
     * @param newSigner The address of the new signer.
     */
    function setSigner(address newSigner) external onlyEnabledValidator {
        _setSigner(msg.sender, newSigner);
    }

    /**
     * @dev Get the signer address for a given wallet.
     * @param wallet The address of the wallet.
     * @return The address of the signer.
     */
    function getSigner(address wallet) external view returns (address) {
        return _signers[wallet];
    }

    function getWallet(address signer) external view returns (address) {
        return _demoTempMap[signer];
    }

    /**
     * @dev Validates the signature of a user operation.
     * @param _userOp The user operation data.
     * @param _userOpHash The hash of the user operation.
     * @return validationData The validation data.
     */
    function validateSignature(
        UserOperation calldata _userOp,
        bytes32 _userOpHash
    ) external view override returns (uint256 validationData) {
        uint256 sigLength = _userOp.signature.length;
        // 20 bytes validator address + 1 byte sig type + 65 bytes signature
        // 20 bytes validator address + 1 byte sig type
        // + 12 bytes time range data + 64 bytes fee data + 65 bytes signature
        if (sigLength != 86 && sigLength != 162) {
            return SIG_VALIDATION_FAILED;
        }
        SignatureHandler.SplitedSignature memory splitedSig = SignatureHandler.splitUserOpSignature(
            _userOp,
            _userOpHash
        );
        if (
            !_checkTransactionTypeAndFee(
                splitedSig.signatureType,
                splitedSig.maxFeePerGas,
                splitedSig.maxPriorityFeePerGas,
                _userOp.maxFeePerGas,
                _userOp.maxPriorityFeePerGas
            )
        ) {
            return SIG_VALIDATION_FAILED;
        }
        validationData = _validateSignature(
            _signers[_userOp.sender],
            splitedSig.signature,
            splitedSig.hash,
            splitedSig.validUntil,
            splitedSig.validAfter
        );
    }

    /**
     * @dev Checks if a signature is valid for a given hash and wallet,
     * this is used to support EIP-1271 protocol.
     * @param hash The hash to validate the signature against.
     * @param signature The signature to validate.
     * @param wallet The address of the wallet.
     * @return A boolean indicating whether the signature is valid or not.
     */
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature,
        address wallet
    ) external view override returns (bool) {
        uint256 validUntil;
        uint256 validAfter;
        address signer = _signers[wallet];
        uint256 validationData = _validateSignature(signer, signature, hash, validUntil, validAfter);
        return validationData == 0 ? true : false;
    }

    function getSyncInitData(address wallet) external view override returns (bytes memory validatorInitData) {
        validatorInitData = abi.encode(_signers[wallet]);
    }

    /**
     * @dev Internal function to set a new signer for a specific wallet.
     * @param newSigner The address of the new signer.
     * @param wallet The address of the wallet.
     */
    function _setSigner(address wallet, address newSigner) internal {
        require(newSigner != address(0), "ECDSAOmniValidator: invalid signer address");
        address oldSigner = _signers[wallet];
        _signers[wallet] = newSigner;

        //demo temp
        if (oldSigner != address(0)) {
            _demoTempMap[oldSigner] = address(0);
        }
        _demoTempMap[newSigner] = wallet;
        emit SetSigner(wallet, oldSigner, newSigner);
    }

    /**
     * @dev Initializes the wallet configuration for the calling wallet.
     * @param data The initialization data containing the signer address.
     */
    function _init(bytes memory data) internal override {
        address signer = abi.decode(data, (address));
        _setSigner(msg.sender, signer);
    }

    /**
     * @dev Clears the wallet configuration for the calling wallet.
     * We don't clear signer info here.
     */
    function _clear() internal override {}

    /**
     * @dev Checks if the specified wallet has been initialized.
     * @param wallet The wallet address to check.
     * @return A boolean indicating if the wallet is initialized.
     */
    function _isWalletInited(address wallet) internal view override returns (bool) {
        return _signers[wallet] != address(0);
    }

    /**
     * @dev Internal function to validate a signature.
     * @param signer The address of the signer.
     * @param signature The signature to validate.
     * @param hash The hash to validate the signature against.
     * @param validUntil The valid until timestamp.
     * @param validAfter The valid after timestamp.
     * @return The validation data indicating the result of the signature validation.
     */
    function _validateSignature(
        address signer,
        bytes memory signature,
        bytes32 hash,
        uint256 validUntil,
        uint256 validAfter
    ) internal pure returns (uint256) {
        uint256 sigFailed;
        bytes32 messageHash = _toEthSignedMessageHash(_bytes32ToHexBytes(hash));
        if (signer != messageHash.recover(signature)) {
            sigFailed = SIG_VALIDATION_FAILED;
        }
        return _packValidationData(sigFailed, validUntil, validAfter);
    }

    function _toEthSignedMessageHash(bytes memory hash) internal pure returns (bytes32 messageHash) {
        messageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(hash.length), hash)
        );
    }

    function _bytes32ToHexBytes(bytes32 data) internal pure returns (bytes memory) {
        bytes memory hexBytes = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            uint8 value = uint8(data[i]);
            uint8 highNibble = value >> 4;
            uint8 lowNibble = value & 0x0f;
            hexBytes[i * 2] = _uint8ToBytes1(highNibble);
            hexBytes[i * 2 + 1] = _uint8ToBytes1(lowNibble);
        }
        return hexBytes;
    }

    function _uint8ToBytes1(uint8 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(bytes("0")[0]) + value);
        } else {
            return bytes1(uint8(bytes("a")[0]) + value - 10);
        }
    }
}
