// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ImmutableCreate2Factory {
    function hasBeenDeployed(address deploymentAddress) external view returns (bool);

    function findCreate2Address(bytes32 salt, bytes calldata initializationCode)
        external
        view
        returns (address deploymentAddress);

    function safeCreate2(bytes32 salt, bytes calldata initializationCode)
        external
        payable
        returns (address deploymentAddress);
}
