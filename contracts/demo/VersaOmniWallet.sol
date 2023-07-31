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
    event Shit(bytes reason);

    uint256[] internal _supportedChainIds;
    mapping(uint256 supportedChainId => uint16 supportedLzChainId) internal _supportedLzChainIdsMap;

    string public constant VERSA_OMNI_VERSION = "1.0.0";

    bytes4 internal constant SUDO_SPECIFIC_EXECUTE = this.sudoSpecificExecute.selector;
    bytes4 internal constant SUDO_SYNC_EXECUTE = this.sudoSyncExecute.selector;
    bytes4 internal constant BATCH_SUDO_SPECIFIC_EXECUTE = this.batchSudoSpecificExecute.selector;
    bytes4 internal constant BATCH_SUDO_SYNC_EXECUTE = this.batchSudoSyncExecute.selector;

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

    function initialize(
        address fallbackHandler,
        address[] memory validators,
        ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds
    ) external initializer {
        _checkInitializationDataLength(
            validators.length,
            validatorType.length,
            validatorInitData.length,
            supportedChainIds.length,
            supportedLzChainIds.length
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

        _transferOwnership(msg.sender);
        for (uint i = 0; i < supportedChainIds.length; ++i) {
            require(supportedChainIds[i] != 0, "VersaOmniFactory: chain id can not be zero");
            setTrustedRemoteAddress(supportedLzChainIds[i], abi.encodePacked(address(this)));
            _supportedChainIds.push(supportedChainIds[i]);
            _supportedLzChainIdsMap[supportedChainIds[i]] = supportedLzChainIds[i];
        }
        _transferOwnership(address(this));
    }

    function getSupportedChainIds() external view returns (uint256[] memory supportedChainIds) {
        supportedChainIds = _supportedChainIds;
    }

    function addSupportedChain(uint256 supportedChainId, uint16 supportedLzChainId) public authorized {
        require(
            supportedChainId != 0 && _supportedLzChainIdsMap[supportedChainId] == 0,
            "VersaOmni: this chain has been added"
        );
        setTrustedRemoteAddress(supportedLzChainId, abi.encodePacked(address(this)));
        _supportedChainIds.push(supportedChainId);
        _supportedLzChainIdsMap[supportedChainId] = supportedLzChainId;
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
        (uint16[] memory toLzChainIds, uint256[] memory nativeFees) = _checkBeforeSyncExecute();
        _internalExecute(to, value, data, operation, ExecutionType.Sudo);
        if (toLzChainIds.length != 0) {
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
        (uint16[] memory toLzChainIds, uint256[] memory nativeFees) = _checkBeforeSyncExecute();
        for (uint256 i = 0; i < to.length; ++i) {
            _internalExecute(to[i], value[i], data[i], operation[i], ExecutionType.Sudo);
        }
        if (toLzChainIds.length != 0) {
            _syncExecute(toLzChainIds, nativeFees);
        }
    }

    function _checkBeforeSyncExecute()
        internal
        view
        returns (uint16[] memory toLzChainIds, uint256[] memory nativeFees)
    {
        if (msg.sender != address(lzEndpoint)) {
            uint dataLength = _supportedChainIds.length;
            toLzChainIds = new uint16[](dataLength);
            nativeFees = new uint256[](dataLength);
            uint256 totalNativeFee;
            uint256 nativeChainId = getChainId();
            for (uint i = 0; i < dataLength; ++i) {
                if (_supportedChainIds[i] != nativeChainId) {
                    toLzChainIds[i] = _supportedLzChainIdsMap[_supportedChainIds[i]];
                    nativeFees[i] = estimateNativeFee(toLzChainIds[i], msg.data);
                    totalNativeFee += nativeFees[i];
                } else {
                    toLzChainIds[i] = 0;
                    nativeFees[i] = 0;
                }
            }
            require(address(this).balance >= totalNativeFee, "VersaOmni: not enough native fee");
        }
    }

    function _syncExecute(uint16[] memory toLzChainIds, uint256[] memory nativeFees) internal {
        for (uint i = 0; i < toLzChainIds.length; ++i) {
            if (toLzChainIds[i] != 0) {
                _sendOmniMessage(toLzChainIds[i], msg.data, nativeFees[i]);
                emit SyncExecuted(toLzChainIds[i]);
            }
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

        // (bool success, ) = address(this).excessivelySafeCall(gasleft(), 0, _payload);
        // require(success, "VersaOmni: sync receive failed");
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(gasleft(), 150, _payload);
        if (!success) {
            emit Shit(reason);
        }
        // emit SyncReceived(_srcChainId);
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
        uint256 supportedChainIdsLen,
        uint256 supportedLzChainIdsLen
    ) internal pure {
        require(
            validatorsLen == validatorTypeLen &&
                validatorTypeLen == validatorInitDataLen &&
                supportedChainIdsLen == supportedLzChainIdsLen,
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

    /**
     * @notice Returns the ID of the chain the contract is currently deployed on.
     * @return The ID of the current chain as a uint256.
     */
    function getChainId() public view returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }
}
