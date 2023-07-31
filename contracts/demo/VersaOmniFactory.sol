// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "./BaseOmniApp.sol";
import "./VersaOmniWallet.sol";
import "./IOmniValidator.sol";

contract VersaOmniFactory is SafeProxyFactory, BaseOmniApp {
    using BytesLib for bytes;

    address public immutable versaOmniSingleton;
    address public immutable fallbackHandler;

    uint256[] internal _supportedChainIds;
    mapping(uint256 supportedChainId => uint16 supportedLzChainId) internal _supportedLzChainIdsMap;
    mapping(address wallet => bytes32 salt) internal _walletSalts;

    constructor(
        address _versaOmniSingleton,
        address _fallbackHandler,
        address _lzEndpoint,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds
    ) BaseOmniApp(_lzEndpoint) {
        versaOmniSingleton = _versaOmniSingleton;
        fallbackHandler = _fallbackHandler;

        uint256 nativeChainId = getChainId();
        for (uint i = 0; i < supportedChainIds.length; ++i) {
            if (supportedChainIds[i] != nativeChainId) {
                setTrustedRemoteAddress(supportedLzChainIds[i], abi.encodePacked(address(this)));
            }
            _supportedChainIds.push(supportedChainIds[i]);
            _supportedLzChainIdsMap[supportedChainIds[i]] = supportedLzChainIds[i];
        }
    }

    function getSupportedChainIds() external view returns (uint256[] memory supportedChainIds) {
        supportedChainIds = _supportedChainIds;
    }

    function addSupportedChain(uint256 supportedChainId, uint16 supportedLzChainId) public onlyOwner {
        require(
            supportedChainId != 0 && _supportedLzChainIdsMap[supportedChainId] == 0,
            "VersaOmniFactory: this chain has been added"
        );
        setTrustedRemoteAddress(supportedLzChainId, abi.encodePacked(address(this)));
        _supportedChainIds.push(supportedChainId);
        _supportedLzChainIdsMap[supportedChainId] = supportedLzChainId;
    }

    function getSpecificAddressWithNonce(
        address[] memory validators,
        OmniValidatorManager.ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds,
        uint256 salt
    ) external view returns (address addr) {
        bytes memory initializer = _getInitializer(
            validators,
            validatorType,
            validatorInitData,
            supportedChainIds,
            supportedLzChainIds
        );
        bytes32 salt2 = _getSalt2(initializer, salt);
        addr = _getSpecificAddressWithNonce(salt2);
    }

    function createAccount(
        address[] memory validators,
        OmniValidatorManager.ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds,
        uint256 salt
    ) external returns (address account) {
        bytes memory initializer = _getInitializer(
            validators,
            validatorType,
            validatorInitData,
            supportedChainIds,
            supportedLzChainIds
        );
        bytes32 salt2 = _getSalt2(initializer, salt);
        address addr = _getSpecificAddressWithNonce(salt2);
        require(addr.code.length == 0, "VersaOmniFactory: account already exists");

        account = address(createChainSpecificProxyWithNonce(versaOmniSingleton, initializer, salt));
        require(addr == account, "VersaOmniFactory: account address incorrect");
        _walletSalts[account] = salt2;
    }

    function estimateRemoteCreateFee(
        address wallet,
        uint16 remoteLzChainId,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds
    ) public view returns (uint256 nativeFee) {
        bytes memory payload = _getSyncPayload(wallet, supportedChainIds, supportedLzChainIds);
        nativeFee = estimateNativeFee(remoteLzChainId, payload);
    }

    function createAccountOnRemoteChain(
        uint16 remoteLzChainId,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds
    ) external payable {
        bytes memory payload = _getSyncPayload(msg.sender, supportedChainIds, supportedLzChainIds);
        _sendOmniMessage(remoteLzChainId, payload, msg.value);
    }

    function _getInitializer(
        address[] memory validators,
        OmniValidatorManager.ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds
    ) internal view returns (bytes memory initializer) {
        initializer = abi.encodeCall(
            VersaOmniWallet.initialize,
            (fallbackHandler, validators, validatorType, validatorInitData, supportedChainIds, supportedLzChainIds)
        );
    }

    function _getSalt2(bytes memory initializer, uint256 salt) internal view returns (bytes32 salt2) {
        salt2 = keccak256(abi.encodePacked(keccak256(initializer), salt, getChainId()));
    }

    function _getSpecificAddressWithNonce(bytes32 salt2) internal view returns (address addr) {
        bytes memory deploymentData = abi.encodePacked(proxyCreationCode(), uint256(uint160(versaOmniSingleton)));
        addr = Create2.computeAddress(bytes32(salt2), keccak256(deploymentData), address(this));
    }

    function _getValidatorArray(
        address wallet
    ) internal view returns (address[] memory sudoArray, address[] memory normalArray) {
        VersaOmniWallet versaOmniWallet = VersaOmniWallet(payable(wallet));
        (uint256 sudoSize, uint256 normalSize) = versaOmniWallet.validatorSize();
        sudoArray = versaOmniWallet.getValidatorsPaginated(
            address(1),
            sudoSize,
            OmniValidatorManager.ValidatorType.Sudo
        );
        normalArray = versaOmniWallet.getValidatorsPaginated(
            address(1),
            normalSize,
            OmniValidatorManager.ValidatorType.Normal
        );
    }

    function _getSyncPayload(
        address wallet,
        uint256[] memory supportedChainIds,
        uint16[] memory supportedLzChainIds
    ) internal view returns (bytes memory payload) {
        (address[] memory sudoArray, address[] memory normalArray) = _getValidatorArray(wallet);
        uint dataLength = sudoArray.length + normalArray.length;
        require(dataLength > 0, "VersaOmniFactory: dataLength can not be zero");
        address[] memory validators = new address[](dataLength);
        OmniValidatorManager.ValidatorType[] memory validatorType = new OmniValidatorManager.ValidatorType[](
            dataLength
        );
        bytes[] memory validatorInitData = new bytes[](dataLength);
        if (sudoArray.length > 0) {
            for (uint i = 0; i < sudoArray.length; ++i) {
                validators[i] = sudoArray[i];
                validatorType[i] = OmniValidatorManager.ValidatorType.Sudo;
                validatorInitData[i] = IOmniValidator(sudoArray[i]).getSyncInitData(wallet);
            }
        }
        if (normalArray.length > 0) {
            for (uint i = 0; i < normalArray.length; ++i) {
                validators[i + sudoArray.length] = normalArray[i];
                validatorType[i + sudoArray.length] = OmniValidatorManager.ValidatorType.Normal;
                validatorInitData[i + sudoArray.length] = IOmniValidator(normalArray[i]).getSyncInitData(wallet);
            }
        }

        bytes memory initializer = _getInitializer(
            validators,
            validatorType,
            validatorInitData,
            supportedChainIds,
            supportedLzChainIds
        );

        require(_walletSalts[wallet] != bytes32(0), "VersaOmniFactory: salt2 invalid");
        payload = abi.encode(wallet, _walletSalts[wallet], initializer);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        (_srcChainId, _nonce);

        address remote = address(bytes20(_srcAddress.slice(0, 20)));
        require(remote == address(this), "VersaOmniFactory: factory address incorrect");

        (address addr, bytes32 salt2, bytes memory initializer) = abi.decode(_payload, (address, bytes32, bytes));
        require(addr.code.length == 0, "VersaOmniFactory: account already exists");

        SafeProxy account = deployProxy(versaOmniSingleton, initializer, salt2);
        require(addr == address(account), "VersaOmniFactory: account address incorrect");
        _walletSalts[address(account)] = salt2;
        emit ProxyCreation(account, versaOmniSingleton);
    }
}
