// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "./BaseOmniApp.sol";
import "./VersaOmniWallet.sol";
import "./IOmniValidator.sol";

contract VersaOmniFactory is SafeProxyFactory, BaseOmniApp {
    using BytesLib for bytes;

    address public immutable versaSingleton;
    address public immutable fallbackHandler;
    uint256[2] public demoSupportedChainIds;

    mapping(uint256 demoSupportedChainId => uint16 demoSupportedLzChainId) internal _chainIdsMap;
    mapping(address wallet => bytes32 salt) internal _walletSalts;

    constructor(
        address _versaSingleton,
        address _fallbackHandler,
        address _lzEndpoint,
        uint256[2] memory _demoSupportedChainIds,
        uint16[2] memory _demoSupportedLzChainIds
    ) BaseOmniApp(_lzEndpoint) {
        versaSingleton = _versaSingleton;
        fallbackHandler = _fallbackHandler;

        demoSupportedChainIds = _demoSupportedChainIds;
        for (uint i = 0; i < _demoSupportedChainIds.length; ++i) {
            _chainIdsMap[_demoSupportedChainIds[i]] = _demoSupportedLzChainIds[i];
        }

        _transferOwnership(address(this));
        (, uint16[] memory remoteLzChainIds) = _getRemoteChainIds(getChainId());
        for (uint i = 0; i < remoteLzChainIds.length; ++i) {
            setTrustedRemoteAddress(remoteLzChainIds[i], abi.encode(address(this)));
        }
        _transferOwnership(msg.sender);
    }

    function getSpecificAddressWithNonce(
        address[] memory validators,
        OmniValidatorManager.ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256 salt
    ) external view returns (address addr) {
        (uint256[] memory remoteChainIds, uint16[] memory remoteLzChainIds) = _getRemoteChainIds(getChainId());
        bytes memory initializer = _getInitializer(
            validators,
            validatorType,
            validatorInitData,
            remoteChainIds,
            remoteLzChainIds
        );
        bytes32 salt2 = _getSalt2(initializer, salt);
        addr = _getSpecificAddressWithNonce(salt2);
    }

    function createAccount(
        address[] memory validators,
        OmniValidatorManager.ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256 salt
    ) external returns (address account) {
        (uint256[] memory remoteChainIds, uint16[] memory remoteLzChainIds) = _getRemoteChainIds(getChainId());
        bytes memory initializer = _getInitializer(
            validators,
            validatorType,
            validatorInitData,
            remoteChainIds,
            remoteLzChainIds
        );
        bytes32 salt2 = _getSalt2(initializer, salt);
        address addr = _getSpecificAddressWithNonce(salt2);
        require(addr.code.length == 0, "VersaOmniFactory: account already exists");

        account = address(createChainSpecificProxyWithNonce(versaSingleton, initializer, salt));
        require(addr == account, "VersaOmniFactory: account address incorrect");
        _walletSalts[account] = salt2;
    }

    function estimateRemoteCreateFee(address wallet, uint256 remoteChainId) public view returns (uint256 nativeFee) {
        bytes memory payload = _getSyncPayload(wallet, remoteChainId);
        nativeFee = estimateNativeFee(_chainIdsMap[remoteChainId], payload);
    }

    function createAccountOnRemoteChain(uint256 remoteChainId) external payable {
        bytes memory payload = _getSyncPayload(msg.sender, remoteChainId);
        _sendOmniMessage(_chainIdsMap[remoteChainId], payload, msg.value);
    }

    function _getRemoteChainIds(
        uint256 chainId
    ) internal view returns (uint256[] memory remoteChainIds, uint16[] memory remoteLzChainIds) {
        uint dataLength = demoSupportedChainIds.length;
        remoteChainIds = new uint256[](dataLength);
        remoteLzChainIds = new uint16[](dataLength);
        for (uint i = 0; i < dataLength; ++i) {
            uint256 remoteChainId = demoSupportedChainIds[i];
            if (remoteChainId != chainId) {
                remoteChainIds[i] = remoteChainId;
                remoteLzChainIds[i] = _chainIdsMap[remoteChainId];
            }
        }
    }

    function _getInitializer(
        address[] memory validators,
        OmniValidatorManager.ValidatorType[] memory validatorType,
        bytes[] memory validatorInitData,
        uint256[] memory remoteChainIds,
        uint16[] memory remoteLzChainIds
    ) internal view returns (bytes memory initializer) {
        initializer = abi.encodeCall(
            VersaOmniWallet.initialize,
            (fallbackHandler, validators, validatorType, validatorInitData, remoteChainIds, remoteLzChainIds)
        );
    }

    function _getSalt2(bytes memory initializer, uint256 salt) internal view returns (bytes32 salt2) {
        salt2 = keccak256(abi.encodePacked(keccak256(initializer), salt, getChainId()));
    }

    function _getSpecificAddressWithNonce(bytes32 salt2) internal view returns (address addr) {
        bytes memory deploymentData = abi.encodePacked(proxyCreationCode(), uint256(uint160(versaSingleton)));
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

    function _getSyncPayload(address wallet, uint256 remoteChainId) internal view returns (bytes memory payload) {
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
                validators[i] = normalArray[i];
                validatorType[i] = OmniValidatorManager.ValidatorType.Normal;
                validatorInitData[i] = IOmniValidator(normalArray[i]).getSyncInitData(wallet);
            }
        }

        (uint256[] memory remoteChainIds, uint16[] memory remoteLzChainIds) = _getRemoteChainIds(
            _chainIdsMap[remoteChainId]
        );

        bytes memory initializer = _getInitializer(
            validators,
            validatorType,
            validatorInitData,
            remoteChainIds,
            remoteLzChainIds
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

        (address addr, bytes32 salt2, bytes memory initialer) = abi.decode(_payload, (address, bytes32, bytes));
        require(addr.code.length == 0, "VersaOmniFactory: account already exists");

        SafeProxy account = deployProxy(versaSingleton, initialer, salt2);
        require(addr == address(account), "VersaOmniFactory: account address incorrect");
        _walletSalts[address(account)] = salt2;
        emit ProxyCreation(account, versaSingleton);
    }
}
