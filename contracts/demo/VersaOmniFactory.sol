// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "./BaseOmniApp.sol";
import "../VersaWallet.sol";

contract VersaOmniFactory is SafeProxyFactory, BaseOmniApp {
    using BytesLib for bytes;

    address public immutable versaSingleton;
    address public immutable defaultFallbackHandler;

    mapping(address wallet => bytes32 salt) internal _walletSalts;

    constructor(address _versaSingleton, address _fallbackHandler, address _lzEndpoint) BaseOmniApp(_lzEndpoint) {
        versaSingleton = _versaSingleton;
        defaultFallbackHandler = _fallbackHandler;
    }

    function getSpecificAddressWithNonce(
        address[] memory validators,
        bytes[] memory validatorInitData,
        VersaWallet.ValidatorType[] memory validatorType,
        address[] memory hooks,
        bytes[] memory hooksInitData,
        address[] memory modules,
        bytes[] memory moduleInitData,
        uint256 salt
    ) external view returns (address addr) {
        bytes memory initializer = _getInitializer(
            validators,
            validatorInitData,
            validatorType,
            hooks,
            hooksInitData,
            modules,
            moduleInitData
        );
        bytes32 salt2 = _getSalt2(initializer, salt);
        addr = _getSpecificAddressWithNonce(salt2);
    }

    function getPayload(
        address wallet,
        address[] memory validators,
        bytes[] memory validatorInitData,
        VersaWallet.ValidatorType[] memory validatorType,
        address[] memory hooks,
        bytes[] memory hooksInitData,
        address[] memory modules,
        bytes[] memory moduleInitData
    ) external view returns (bytes memory payload) {
        bytes memory initializer = _getInitializer(
            validators,
            validatorInitData,
            validatorType,
            hooks,
            hooksInitData,
            modules,
            moduleInitData
        );
        bytes32 salt2 = _walletSalts[wallet];
        payload = abi.encode(wallet, salt2, initializer);
    }

    function createAccount(
        address[] memory validators,
        bytes[] memory validatorInitData,
        VersaWallet.ValidatorType[] memory validatorType,
        address[] memory hooks,
        bytes[] memory hooksInitData,
        address[] memory modules,
        bytes[] memory moduleInitData,
        uint256 salt
    ) public returns (address account) {
        bytes memory initializer = _getInitializer(
            validators,
            validatorInitData,
            validatorType,
            hooks,
            hooksInitData,
            modules,
            moduleInitData
        );
        bytes32 salt2 = _getSalt2(initializer, salt);
        address addr = _getSpecificAddressWithNonce(salt2);
        require(addr.code.length == 0, "VersaFactory: account already exists");
        account = address(createChainSpecificProxyWithNonce(versaSingleton, initializer, salt));
        require(addr == account, "VersaFactory: account address incorrect");
        _walletSalts[account] = salt2;
    }

    function createAccountOnRemoteChain(
        uint16 dstChainId,
        address[] memory validators,
        bytes[] memory validatorInitData,
        VersaWallet.ValidatorType[] memory validatorType,
        address[] memory hooks,
        bytes[] memory hooksInitData,
        address[] memory modules,
        bytes[] memory moduleInitData
    ) public payable {
        bytes memory initializer = _getInitializer(
            validators,
            validatorInitData,
            validatorType,
            hooks,
            hooksInitData,
            modules,
            moduleInitData
        );
        bytes memory payload = _getPayload(initializer);
        _sendOmniMessage(dstChainId, payload);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        (_srcChainId, _nonce);
        address remote = address(bytes20(_srcAddress.slice(0, 20)));
        require(remote == address(this), "VersaFactory: factory address incorrect");
        (address addr, bytes32 salt2, bytes memory initialer) = abi.decode(_payload, (address, bytes32, bytes));
        require(addr.code.length == 0, "VersaFactory: account already exists");
        SafeProxy account = deployProxy(versaSingleton, initialer, salt2);
        require(addr == address(account), "VersaFactory: account address incorrect");
        _walletSalts[address(account)] = salt2;
        emit ProxyCreation(account, versaSingleton);
    }

    function _getInitializer(
        address[] memory validators,
        bytes[] memory validatorInitData,
        VersaWallet.ValidatorType[] memory validatorType,
        address[] memory hooks,
        bytes[] memory hooksInitData,
        address[] memory modules,
        bytes[] memory moduleInitData
    ) internal view returns (bytes memory initializer) {
        initializer = abi.encodeCall(
            VersaWallet.initialize,
            (
                defaultFallbackHandler,
                validators,
                validatorInitData,
                validatorType,
                hooks,
                hooksInitData,
                modules,
                moduleInitData
            )
        );
    }

    function _getPayload(bytes memory initializer) internal view returns (bytes memory payload) {
        bytes32 salt2 = _walletSalts[msg.sender];
        payload = abi.encode(msg.sender, salt2, initializer);
    }

    function _getSalt2(bytes memory initializer, uint256 salt) internal view returns (bytes32 salt2) {
        salt2 = keccak256(abi.encodePacked(keccak256(initializer), salt, getChainId()));
    }

    function _getSpecificAddressWithNonce(bytes32 salt2) internal view returns (address addr) {
        bytes memory deploymentData = abi.encodePacked(proxyCreationCode(), uint256(uint160(versaSingleton)));
        addr = Create2.computeAddress(bytes32(salt2), keccak256(deploymentData), address(this));
    }
}
