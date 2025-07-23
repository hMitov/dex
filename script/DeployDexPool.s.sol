// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DexPool.sol";
import "./EnvLoader.s.sol";

/// @title DeployDexPool Script
/// @notice Deploys the DexPool contract using environment variables for deployer's private key and token address
contract DeployDexPoolScript is EnvLoader {
    uint256 private privateKey;
    address private tokenAddress;

    /// @notice Runs the deployment script
    /// @dev Loads env vars, broadcasts deployment transaction with private key
    function run() external {
        loadEnvVars();
        vm.startBroadcast(privateKey);

        DexPool dexPool = new DexPool(tokenAddress);

        console.log("DexPool deployed at:", address(dexPool));

        vm.stopBroadcast();
    }

    /// @notice Loads environment variables into contract state
    /// @dev Called internally by the script runner in `run()`
    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("DEPLOYER_PRIVATE_KEY");
        tokenAddress = getEnvAddress("TOKEN_ADDRESS");
    }
}
