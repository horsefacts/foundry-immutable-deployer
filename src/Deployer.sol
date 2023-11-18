// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import {ImmutableCreate2Factory} from "./interfaces/ImmutableCreate2Factory.sol";

/**
 * @dev Deployment status.
 *      - UNKNOWN: Empty enum field, should not be used.
 *      - FOUND: The contract has already been deployed.
 *      - CREATED: The contract was created in the current deployment tx.
 */
enum Status {
    UNKNOWN,
    FOUND,
    CREATED
}

/**
 * @dev Deployment information for a contract.
 *
 * @param name               Contract name
 * @param salt               CREATE2 salt
 * @param creationCode       Contract creationCode bytes
 * @param constructorArgs    ABI-encoded constructor argument bytes
 * @param initCodeHash       Contract initCode (creationCode + constructorArgs) hash
 * @param deploymentAddress  Deterministic deployment address
 */
struct Deployment {
    string name;
    bytes32 salt;
    bytes creationCode;
    bytes constructorArgs;
    bytes32 initCodeHash;
    address deploymentAddress;
    Status status;
}

abstract contract Deployer is Script, Test {
    /// @dev Deterministic address of the cross-chain ImmutableCreate2Factory
    ImmutableCreate2Factory private constant IMMUTABLE_CREATE2_FACTORY =
        ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    /// @dev Default CREATE2 salt
    bytes32 private constant DEFAULT_SALT = bytes32(0);

    /// @dev Array of contract names, used to track contracts "registered" for later deployment.
    string[] internal names;

    /// @dev Mapping of contract name to deployment details.
    mapping(string => Deployment) internal contracts;

    function run() public {
        loadDeployParameters();
        register();
        beforeDeploy();
        deploy(true);
        afterDeploy();
    }

    function loadDeployParameters() internal virtual {}

    function register() internal virtual {}

    function beforeDeploy() internal virtual {}

    function deploy(bool broadcast) internal virtual {
        deployAll(broadcast);
    }

    function afterDeploy() internal virtual {}

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name         Contract name
     * @param creationCode Contract creationCode bytes
     */
    function register(string memory name, bytes memory creationCode) internal returns (address) {
        return register(name, DEFAULT_SALT, creationCode, "");
    }

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name         Contract name
     * @param salt         CREATE2 salt
     * @param creationCode Contract creationCode bytes
     */
    function register(string memory name, bytes32 salt, bytes memory creationCode) internal returns (address) {
        return register(name, salt, creationCode, "");
    }

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name            Contract name
     * @param creationCode    Contract creationCode bytes
     * @param constructorArgs ABI-encoded constructor argument bytes
     */
    function register(string memory name, bytes memory creationCode, bytes memory constructorArgs)
        internal
        returns (address)
    {
        return register(name, DEFAULT_SALT, creationCode, constructorArgs);
    }

    /**
     * @dev "Register" a contract to be deployed by deploy().
     *
     * @param name            Contract name
     * @param salt            CREATE2 salt
     * @param creationCode    Contract creationCode bytes
     * @param constructorArgs ABI-encoded constructor argument bytes
     */
    function register(string memory name, bytes32 salt, bytes memory creationCode, bytes memory constructorArgs)
        internal
        returns (address)
    {
        _checkName(name);

        bytes memory initCode = bytes.concat(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);
        address deploymentAddress = IMMUTABLE_CREATE2_FACTORY.findCreate2Address(salt, initCode);

        names.push(name);
        contracts[name] = Deployment({
            name: name,
            salt: salt,
            creationCode: creationCode,
            constructorArgs: constructorArgs,
            initCodeHash: initCodeHash,
            deploymentAddress: deploymentAddress,
            status: Status.UNKNOWN
        });
        return deploymentAddress;
    }

    /**
     * @dev Deploy all registered contracts.
     */
    function deployAll(bool broadcast) internal {
        console.log(_pad("State", 9), _pad("Name", _longestNameLen() + 1), _pad("Address", 43), "Initcode hash");
        for (uint256 i; i < names.length; i++) {
            _deploy(names[i], broadcast);
        }
        console.log("\n");
    }

    /**
     * @dev Deploy all registered contracts, broadcasting transactions.
     */
    function deployAll() internal {
        deploy(true);
    }

    /**
     * @dev Deploy a registered contract by name.
     *
     * @param name Contract name
     */
    function deployByName(string memory name, bool broadcast) public {
        console.log(_pad("State", 9), _pad("Name", _longestNameLen() + 1), _pad("Address", 43), "Initcode hash");
        _deploy(name, broadcast);
    }

    /**
     * @dev Deploy a registered contract by name, broadcasting the transaction.
     *
     * @param name Contract name
     */
    function deployByName(string memory name) internal {
        deployByName(name, true);
    }

    function deploymentChanged() public view returns (bool) {
        for (uint256 i; i < names.length; i++) {
            Deployment storage deployment = contracts[names[i]];
            if (deployment.status == Status.CREATED) {
                return true;
            }
        }
        return false;
    }

    function deploymentChanged(string memory name) public view returns (bool) {
        Deployment storage deployment = contracts[name];
        if (deployment.status == Status.CREATED) {
            return true;
        }
        return false;
    }

    function _deploy(string memory name, bool broadcast) internal {
        Deployment storage deployment = contracts[name];
        if (!IMMUTABLE_CREATE2_FACTORY.hasBeenDeployed(deployment.deploymentAddress)) {
            if (broadcast) vm.broadcast();
            deployment.deploymentAddress = IMMUTABLE_CREATE2_FACTORY.safeCreate2(
                deployment.salt, bytes.concat(deployment.creationCode, deployment.constructorArgs)
            );
            deployment.status = Status.CREATED;
        } else {
            deployment.status = Status.FOUND;
        }
        console.log(
            _pad((deployment.status == Status.CREATED) ? "Creating" : "Found", 9),
            _pad(deployment.name, _longestNameLen() + 1),
            _pad(LibString.toHexString(deployment.deploymentAddress), 43),
            LibString.toHexString(uint256(deployment.initCodeHash))
        );
    }

    function getAddress(string memory name) public view returns (address) {
        return contracts[name].deploymentAddress;
    }

    function getDeployment(string memory name) public view returns (Deployment memory) {
        return contracts[name];
    }

    function fail() internal override {
        super.fail();
        revert("Assertion failed");
    }

    function _pad(string memory str, uint256 n) internal pure returns (string memory) {
        string memory padded = str;
        while (bytes(padded).length < n) {
            padded = string.concat(padded, " ");
        }
        return padded;
    }

    function _checkName(string memory name) internal view {
        for (uint256 i; i < names.length; i++) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(name))) {
                revert("Contract already registered");
            }
        }
    }

    function _longestNameLen() internal view returns (uint256) {
        uint256 longest;
        for (uint256 i; i < names.length; i++) {
            if (_strlen(names[i]) > longest) {
                longest = _strlen(names[i]);
            }
        }
        return longest;
    }

    function _strlen(string memory s) internal pure returns (uint256) {
        uint256 len;
        uint256 i = 0;
        uint256 bytelength = bytes(s).length;
        for (len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }
}
