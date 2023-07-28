// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@aa-template/contracts/interfaces/IAccount.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interface/IValidator.sol";
import "../common/Enum.sol";
import "../common/Executor.sol";
import "../common/Singleton.sol";
import "../base/FallbackManager.sol";
import "../base/EntryPointManager.sol";
import "./OmniValidatorManager.sol";
import "./BaseOmniApp.sol";

/**
 * @title VersaOmniWallet
 */
contract VersaOmniWallet is
    IAccount,
    Executor,
    Singleton,
    Initializable,
    FallbackManager,
    EntryPointManager,
    OmniValidatorManager,
    BaseOmniApp
{
    using BytesLib for bytes;
    using ExcessivelySafeCall for address;

    /**
     * @dev The execution type of a transaction.
     * - Sudo: Transaction executed with full permissions.
     * - Normal: Regular transaction executed limited access.
     */
    enum ExecutionType {
        Sudo,
        Normal
    }

    event SyncExecuted(uint16 toChainId);
    event SyncReceived(uint16 fromChainId);

    string public constant VERSA_OMNI_VERSION = "1.0.0";

    // `sudoExecute` function selector
    bytes4 internal constant SUDO_SPECIFIC_EXECUTE = this.sudoSpecificExecute.selector;
    bytes4 internal constant SUDO_SYNC_EXECUTE = this.sudoSyncExecute.selector;
    // `batchSudoExecute` function selector
    bytes4 internal constant BATCH_SUDO_SPECIFIC_EXECUTE = this.batchSudoSpecificExecute.selector;
    bytes4 internal constant BATCH_SUDO_SYNC_EXECUTE = this.batchSudoSyncExecute.selector;

    uint256[] public remoteChainIds;
    mapping(uint256 remoteChainId => uint16 remoteLzChainId) internal _chainIdsMap;

    modifier onlyFromEntryPointOrLzEndpoint() {
        require(
            msg.sender == entryPoint() || msg.sender == address(lzEndpoint),
            "VersaOmni: not from EntryPoint or LzEndpoint"
        );
        _;
    }

    /**
     * @dev Disable initializers to prevent the implementation contract
     * from being used
     */
    constructor(address entryPoint, address lzEndpoint) EntryPointManager(entryPoint) BaseOmniApp(lzEndpoint) {
        _disableInitializers();
        _transferOwnership(address(0));
    }

    /**
     * @dev Initializes the VersaWallet contract.
     * @param fallbackHandler The address of the fallback handler contract.
     * @param validators The addresses of the validators.
     * @param validatorInitData The initialization data for each validator.
     * @param validatorType The types of the validators.
     */
    function initialize(
        address fallbackHandler,
        address[] memory validators,
        ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256[] memory _remoteChainIds,
        uint16[] memory remoteLzChainIds
    ) external initializer {
        _checkInitializationDataLength(
            validators.length,
            validatorType.length,
            validatorInitData.length,
            _remoteChainIds.length,
            remoteLzChainIds.length
        );

        internalSetFallbackHandler(fallbackHandler);

        bool hasSudoValidator;
        for (uint i = 0; i < validators.length; ++i) {
            _enableValidator(validators[i], validatorType[i], validatorInitData[i]);
            if (!hasSudoValidator && validatorType[i] == ValidatorType.Sudo) {
                hasSudoValidator = true;
            }
        }
        require(hasSudoValidator, "VersaOmni: must set up the initial sudo validator");

        _transferOwnership(address(this));
        for (uint i = 0; i < _remoteChainIds.length; ++i) {
            setTrustedRemoteAddress(remoteLzChainIds[i], abi.encode(address(this)));
            _chainIdsMap[_remoteChainIds[i]] = remoteLzChainIds[i];
        }
        remoteChainIds = _remoteChainIds;
    }

    /**
     * @dev Executes a sudo transaction.
     * @param to The address to which the transaction is directed.
     * @param value The value of the transaction.
     * @param data The data of the transaction.
     * @param operation The operation type of the transaction.
     */
    function sudoSpecificExecute(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external onlyFromEntryPoint {
        _internalExecute(to, value, data, operation, ExecutionType.Sudo);
    }

    /**
     * @dev Executes a batch transaction with sudo privileges.
     * @param to The addresses to which the transactions are directed.
     * @param value The values of the transactions.
     * @param data The data of the transactions.
     * @param operation The operation types of the transactions.
     */
    function batchSudoSpecificExecute(
        address[] memory to,
        uint256[] memory value,
        bytes[] memory data,
        Enum.Operation[] memory operation
    ) external onlyFromEntryPoint {
        _checkBatchDataLength(to.length, value.length, data.length, operation.length);
        for (uint256 i = 0; i < to.length; ++i) {
            _internalExecute(to[i], value[i], data[i], operation[i], ExecutionType.Sudo);
        }
    }

    /**
     * @dev Executes a sudo transaction.
     * @param to The address to which the transaction is directed.
     * @param value The value of the transaction.
     * @param data The data of the transaction.
     * @param operation The operation type of the transaction.
     */
    function sudoSyncExecute(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external onlyFromEntryPointOrLzEndpoint {
        (uint16[] memory toLzChainIds, uint256[] memory nativeFees) = _checkAndGetSyncExecuteToAndFee();
        _internalExecute(to, value, data, operation, ExecutionType.Sudo);
        if (toLzChainIds.length != 0 && nativeFees.length != 0) {
            _syncExecute(toLzChainIds, nativeFees);
        }
    }

    /**
     * @dev Executes a batch transaction with sudo privileges.
     * @param to The addresses to which the transactions are directed.
     * @param value The values of the transactions.
     * @param data The data of the transactions.
     * @param operation The operation types of the transactions.
     */
    function batchSudoSyncExecute(
        address[] memory to,
        uint256[] memory value,
        bytes[] memory data,
        Enum.Operation[] memory operation
    ) external onlyFromEntryPointOrLzEndpoint {
        _checkBatchDataLength(to.length, value.length, data.length, operation.length);
        (uint16[] memory toLzChainIds, uint256[] memory nativeFees) = _checkAndGetSyncExecuteToAndFee();
        for (uint256 i = 0; i < to.length; ++i) {
            _internalExecute(to[i], value[i], data[i], operation[i], ExecutionType.Sudo);
        }
        if (toLzChainIds.length != 0 && nativeFees.length != 0) {
            _syncExecute(toLzChainIds, nativeFees);
        }
    }

    function _checkAndGetSyncExecuteToAndFee()
        internal
        view
        returns (uint16[] memory toLzChainIds, uint256[] memory nativeFees)
    {
        if (msg.sender != address(lzEndpoint)) {
            uint256 totalNativeFee;
            for (uint i = 0; i < remoteChainIds.length; ++i) {
                toLzChainIds[i] = _chainIdsMap[remoteChainIds[i]];
                nativeFees[i] = estimateNativeFee(toLzChainIds[i], msg.data);
                totalNativeFee += nativeFees[i];
            }
            require(address(this).balance >= totalNativeFee, "VersaOmni: not enough native fee");
        }
    }

    function _syncExecute(uint16[] memory toLzChainIds, uint256[] memory nativeFees) internal {
        for (uint i = 0; i < toLzChainIds.length; ++i) {
            _sendOmniMessage(toLzChainIds[i], msg.data, nativeFees[i]);
            emit SyncExecuted(toLzChainIds[i]);
        }
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        (_nonce);

        address remote = address(bytes20(_srcAddress.slice(0, 20)));
        require(remote == address(this), "VersaOmni: remote address incorrect");

        bytes4 selector = bytes4(_payload.slice(0, 4));
        require(
            selector == SUDO_SYNC_EXECUTE || selector == BATCH_SUDO_SYNC_EXECUTE,
            "VersaOmni: sync receive selector doesn't match"
        );

        (bool success, ) = address(this).excessivelySafeCall(gasleft(), 0, _payload);
        require(success, "VersaOmni: sync receive failed");
        emit SyncReceived(_srcChainId);
    }

    /**
     * @dev Executes a normal transaction.
     * @param to The address to which the transaction is directed.
     * @param value The value of the transaction.
     * @param data The data of the transaction.
     * @param operation The operation type of the transaction.
     */
    function normalExecute(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external onlyFromEntryPoint {
        _internalExecute(to, value, data, operation, ExecutionType.Normal);
    }

    /**
     * @dev Executes a batch normal transaction.
     * @param to The addresses to which the transactions are directed.
     * @param value The values of the transactions.
     * @param data The data of the transactions.
     * @param operation The operation types of the transactions.
     */
    function batchNormalExecute(
        address[] memory to,
        uint256[] memory value,
        bytes[] memory data,
        Enum.Operation[] memory operation
    ) external onlyFromEntryPoint {
        _checkBatchDataLength(to.length, value.length, data.length, operation.length);
        for (uint256 i = 0; i < to.length; ++i) {
            _internalExecute(to[i], value[i], data[i], operation[i], ExecutionType.Normal);
        }
    }

    /**
     * @dev A normal execution has following restrictions:
     * 1. Cannot selfcall, i.e., change wallet's config
     * 2. Cannot call to an enabled plugin, i.e, change plugin's config or call wallet from plugin
     * 3. Cannot perform a delegatecall
     * @param to The address to which the transaction is directed.
     * @param _operation The operation type of the transaction.
     */
    function _checkBeforeNormalExecute(address to, Enum.Operation _operation) internal view {
        require(
            to != address(this) && !isValidatorEnabled(to) && _operation != Enum.Operation.DelegateCall,
            "VersaOmni: operation is not allowed"
        );
    }

    /**
     * @dev Internal function to execute a transaction.
     * @param to The address to which the transaction is directed.
     * @param value The value of the transaction.
     * @param data The data of the transaction.
     * @param operation The operation type of the transaction.
     * @param execution The execution type of the transaction.
     */
    function _internalExecute(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        ExecutionType execution
    ) internal {
        if (execution == ExecutionType.Sudo) {
            executeAndRevert(to, value, data, operation);
        } else {
            _checkBeforeNormalExecute(to, operation);
            // _beforeTransaction(to, value, data, operation);
            executeAndRevert(to, value, data, operation);
            // _afterTransaction(to, value, data, operation);
        }
    }

    /**
     * @dev Validates an user operation before execution.
     * @param userOp The user operation data.
     * @param userOpHash The hash of the user operation.
     * @param missingAccountFunds The amount of missing account funds to be paid.
     * @return validationData The validation data returned by the validator.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override onlyFromEntryPoint returns (uint256 validationData) {
        address validator = _getValidator(userOp.signature);
        _validateValidatorAndSelector(validator, bytes4(userOp.callData[:4]));
        validationData = IOmniValidator(validator).validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /**
     * @dev Extracts the validator address from the first 20 bytes of the signature.
     * @param signature The signature from which to extract the validator address.
     * @return The extracted validator address.
     */
    function _getValidator(bytes calldata signature) internal pure returns (address) {
        return address(bytes20(signature[:20]));
    }

    /**
     * @dev Validates the validator and selector for a user operation.
     * @param _validator The address of the validator to validate.
     * @param _selector The selector of the user operation.
     */
    function _validateValidatorAndSelector(address _validator, bytes4 _selector) internal view {
        ValidatorType validatorType = getValidatorType(_validator);
        require(validatorType != ValidatorType.Disabled, "VersaOmni: invalid validator");
        if (
            _selector == SUDO_SPECIFIC_EXECUTE ||
            _selector == SUDO_SYNC_EXECUTE ||
            _selector == BATCH_SUDO_SPECIFIC_EXECUTE ||
            _selector == BATCH_SUDO_SYNC_EXECUTE
        ) {
            require(validatorType == ValidatorType.Sudo, "VersaOmni: selector doesn't match validator");
        }
    }

    /**
     * @dev Sends the missing funds for this transaction to the entry point (msg.sender).
     * Subclasses may override this method for better funds management
     * (e.g., send more than the minimum required to the entry point so that in future transactions
     * it will not be required to send again).
     * @param missingAccountFunds The minimum value this method should send to the entry point.
     * This value may be zero in case there is enough deposit or the userOp has a paymaster.
     */
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            // Note: May pay more than the minimum to deposit for future transactions
            (bool success, ) = payable(entryPoint()).call{ value: missingAccountFunds, gas: type(uint256).max }("");
            (success);
            // Ignore failure (it's EntryPoint's job to verify, not the account)
        }
    }

    /**
     * @dev Check the length of the initialization data arrays
     */
    function _checkInitializationDataLength(
        uint256 validatorsLen,
        uint256 validatorTypeLen,
        uint256 validatorInitDataLen,
        uint256 remoteChainIdsLen,
        uint256 remoteLzChainIdsLen
    ) internal pure {
        require(
            validatorsLen == validatorTypeLen &&
                validatorTypeLen == validatorInitDataLen &&
                remoteChainIdsLen == remoteLzChainIdsLen,
            "VersaOmni: data length doesn't match"
        );
    }

    /**
     * @dev Checks the lengths of the batch transaction data arrays.
     */
    function _checkBatchDataLength(
        uint256 toLen,
        uint256 valueLen,
        uint256 dataLen,
        uint256 operationLen
    ) internal pure {
        require(toLen == valueLen && dataLen == operationLen && toLen == dataLen, "VersaOmni: invalid batch data");
    }
}
