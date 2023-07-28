// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./layerzero/lzApp/NonblockingLzApp.sol";

abstract contract BaseOmniApp is NonblockingLzApp {
    uint8 internal constant CONFIG_TYPE_RELAYER = 3;
    uint8 internal constant CONFIG_TYPE_ORACLE = 6;

    uint16 internal constant ADAPTER_PARAMS_VERSION = 1;
    uint256 internal constant ADAPTER_PARAMS_GASLIMIT = 1500000;
    bytes internal constant ADAPTER_PARAMS = abi.encodePacked(ADAPTER_PARAMS_VERSION, ADAPTER_PARAMS_GASLIMIT);

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

    function setRelayer(uint16 _dstChainId, address _sendRelayer, address _receiveRelayer) public onlyOwner {
        lzEndpoint.setConfig(
            lzEndpoint.getSendVersion(address(this)),
            _dstChainId,
            CONFIG_TYPE_RELAYER,
            abi.encode(_sendRelayer)
        );
        lzEndpoint.setConfig(
            lzEndpoint.getReceiveVersion(address(this)),
            _dstChainId,
            CONFIG_TYPE_RELAYER,
            abi.encode(_receiveRelayer)
        );
    }

    function getRelayer(uint16 _dstChainId) external view returns (address _sendRelayer, address _receiveRelayer) {
        bytes memory bytesSendRelayer = lzEndpoint.getConfig(
            lzEndpoint.getSendVersion(address(this)),
            _dstChainId,
            address(this),
            CONFIG_TYPE_RELAYER
        );
        assembly {
            _sendRelayer := mload(add(bytesSendRelayer, 32))
        }
        bytes memory bytesReceiveRelayer = lzEndpoint.getConfig(
            lzEndpoint.getReceiveVersion(address(this)),
            _dstChainId,
            address(this),
            CONFIG_TYPE_RELAYER
        );
        assembly {
            _receiveRelayer := mload(add(bytesReceiveRelayer, 32))
        }
    }

    function setOracle(uint16 _dstChainId, address _sendOracle, address _receiveOracle) public onlyOwner {
        lzEndpoint.setConfig(
            lzEndpoint.getSendVersion(address(this)),
            _dstChainId,
            CONFIG_TYPE_ORACLE,
            abi.encode(_sendOracle)
        );
        lzEndpoint.setConfig(
            lzEndpoint.getReceiveVersion(address(this)),
            _dstChainId,
            CONFIG_TYPE_ORACLE,
            abi.encode(_receiveOracle)
        );
    }

    function getOracle(uint16 _dstChainId) external view returns (address _sendOracle, address _receiveOracle) {
        bytes memory bytesSendOracle = lzEndpoint.getConfig(
            lzEndpoint.getSendVersion(address(this)),
            _dstChainId,
            address(this),
            CONFIG_TYPE_ORACLE
        );
        assembly {
            _sendOracle := mload(add(bytesSendOracle, 32))
        }
        bytes memory bytesReceiveOracle = lzEndpoint.getConfig(
            lzEndpoint.getReceiveVersion(address(this)),
            _dstChainId,
            address(this),
            CONFIG_TYPE_ORACLE
        );
        assembly {
            _receiveOracle := mload(add(bytesReceiveOracle, 32))
        }
    }

    function estimateNativeFee(uint16 _dstChainId, bytes memory _payload) public view returns (uint256 _nativeFee) {
        (_nativeFee, ) = lzEndpoint.estimateFees(_dstChainId, address(this), _payload, false, ADAPTER_PARAMS);
    }

    function _sendOmniMessage(uint16 _dstChainId, bytes memory _payload, uint256 _nativeFee) internal {
        _lzSend(_dstChainId, _payload, payable(msg.sender), address(0), ADAPTER_PARAMS, _nativeFee);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {}
}
