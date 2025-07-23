// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SimpleToken.sol";
import "./EnvLoader.s.sol";

/// @title DeployToken Script
/// @notice Deploys the SimpleToken contract using environment variables for name and symbol
contract DeployTokenScript is EnvLoader {
    uint256 private privateKey;
    string private tokenName;
    string private tokenSymbol;

    /// @notice Runs the deployment script
    /// @dev Starts and stops broadcasting the deployment transaction
    function run() external {
        loadEnvVars();
        vm.startBroadcast(privateKey);

        SimpleToken token = new SimpleToken(tokenName, tokenSymbol);

        console.log("SimpleToken deployed at:", address(token));

        vm.stopBroadcast();
    }

    /// @notice Loads environment variables into contract state
    /// @dev Called internally by the script runner in `run()`
    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("DEPLOYER_PRIVATE_KEY");
        tokenName = getEnvString("TOKEN_NAME");
        tokenSymbol = getEnvString("TOKEN_SYMBOL");
    }
}
