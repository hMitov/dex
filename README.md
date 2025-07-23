# DEX Pool System

A decentralized exchange (DEX) pool implementation built with Solidity and Foundry, enabling users to provide liquidity and swap ETH for ERC20 tokens using the Uniswap V1 formula.

## Overview

This project implements a robust DEX pool solution with the following core components:

**SimpleToken**: A basic ERC20 token contract for development and testing purposes, featuring unrestricted minting and standard ERC20 functionality.

**DexPool**: The main DEX pool contract that manages liquidity provision, token swapping, and LP token distribution, all protected with role-based access control and security features.

## Features

### SimpleToken Contract
- Standard ERC20 token with transfer, approve, and transferFrom functionality
- Unrestricted minting for development and testing purposes
- 18 decimals precision
- Customizable name and symbol
- Comprehensive NatSpec documentation

### DexPool Contract
- Liquidity provision and removal using Uniswap V1 formula
- ETH ↔ ERC20 token swapping with 1% fee
- LP token minting and burning for liquidity providers
- Role-based access control (ADMIN_ROLE, PAUSER_ROLE)
- Emergency pause/unpause functionality
- Reentrancy protection on all external functions
- Prevents direct ETH transfers to the contract
- Emits detailed events for off-chain monitoring

## Technical Details

### Contracts
- **SimpleToken.sol**: Basic ERC20 token implementation with minting capabilities
- **DexPool.sol**: DEX pool logic managing liquidity, swapping, and LP token operations

### Dependencies
- OpenZeppelin Contracts (ERC20, AccessControl, ReentrancyGuard, Pausable)
- Foundry for testing and deployment

## Deployment

The project uses Foundry for contract deployment. The deployment process involves:

1. Deploying the SimpleToken contract
2. Deploying the DexPool contract with the token address
3. Setting up initial liquidity and testing the pool

### Deployment Commands

The `--broadcast` flag can be used with different verbosity levels:

- `-v`: Basic transaction information
- `-vv`: Transaction information and contract addresses
- `-vvv`: Transaction information, contract addresses, and function calls
- `-vvvv`: Full transaction information, contract addresses, function calls, and stack traces

### Deploy on Ethereum Sepolia

Deploy the SimpleToken:
```bash
source .env
forge script script/DeployToken.s.sol:DeployTokenScript --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast -vvv
```

Deploy the DexPool:
```bash
source .env
forge script script/DeployDexPool.s.sol:DeployDexPoolScript --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast -vvv
```

**IMPORTANT**: After deploying the SimpleToken and DexPool contracts, you must update your `.env` file with their addresses:

Set `ETHEREUM_SEPOLIA_SIMPLE_TOKEN_ADDRESS` to the deployed SimpleToken address
Set `ETHEREUM_SEPOLIA_DEX_POOL_ADDRESS` to the deployed DexPool address

These values are required for proper interaction with the deployed contracts.

## Environment Variables

Required environment variables in `.env`:

### Common
- `DEPLOYER_PRIVATE_KEY`: Private key for deployment (hex string, no 0x prefix)
- `RPC_URL`: RPC endpoint for the target network

### Token Configuration
- `TOKEN_NAME`: Name for the SimpleToken (e.g., "Test Token")
- `TOKEN_SYMBOL`: Symbol for the SimpleToken (e.g., "TEST")

### For Ethereum Sepolia
- `ETHEREUM_SEPOLIA_RPC_URL`: RPC endpoint for Ethereum Sepolia testnet
- `ETHEREUM_SEPOLIA_SIMPLE_TOKEN_ADDRESS`: Address of the deployed SimpleToken contract on Ethereum Sepolia
- `ETHEREUM_SEPOLIA_DEX_POOL_ADDRESS`: Address of the deployed DexPool contract on Ethereum Sepolia

### For Base Sepolia
- `BASE_SEPOLIA_RPC_URL`: RPC endpoint for Base Sepolia testnet
- `BASE_SEPOLIA_SIMPLE_TOKEN_ADDRESS`: Address of the deployed SimpleToken contract on Base Sepolia
- `BASE_SEPOLIA_DEX_POOL_ADDRESS`: Address of the deployed DexPool contract on Base Sepolia

### Example .env
```bash
DEPLOYER_PRIVATE_KEY=your_private_key

# Token Configuration
TOKEN_NAME="Test Token"
TOKEN_SYMBOL="TEST"

# Ethereum Sepolia
ETHEREUM_SEPOLIA_RPC_URL="https://sepolia.gateway.tenderly.co"
ETHEREUM_SEPOLIA_SIMPLE_TOKEN_ADDRESS=0xYourSimpleTokenAddress
ETHEREUM_SEPOLIA_DEX_POOL_ADDRESS=0xYourDexPoolAddress

```

All variables are required and validated for non-emptiness or non-zero values by the deployment scripts.

## Testing

The project includes comprehensive tests for all contracts:

### Unit Tests
- Role management and access control
- Token minting and transfer functionality
- Pausing and unpausing operations
- Liquidity provision and removal
- Token swapping (ETH ↔ ERC20)
- Event emission verification
- Error handling and edge cases

### Integration Tests
- Complete DEX lifecycle (add liquidity, swap, remove liquidity)
- Fee calculation and distribution
- LP token minting and burning
- Emergency pause and withdrawal scenarios
- Reentrancy protection verification

The integration tests verify key scenarios like proper fee calculation, LP token distribution, and secure fund handling.

## Usage

### Adding Liquidity

1. Approve tokens for the DEX pool:
```solidity
token.approve(dexPoolAddress, amount);
```

2. Add liquidity:
```solidity
dexPool.addLiquidity{value: ethAmount}(tokenAmount);
```

### Removing Liquidity

```solidity
dexPool.removeLiquidity(lpTokenAmount);
```

### Swapping ETH for Tokens

```solidity
dexPool.ethToTokenSwap{value: ethAmount}();
```

### Swapping Tokens for ETH

```solidity
dexPool.tokenToEthSwap(tokenAmount);
```

### Role Management
- Only accounts with `ADMIN_ROLE` can grant/revoke `PAUSER_ROLE`
- Only accounts with `PAUSER_ROLE` can pause/unpause the contract
- Only accounts with `ADMIN_ROLE` can manage role assignments

## Security Features

- Reentrancy protection on all external functions
- Role-based access control
- Safe ETH and ERC20 transfers
- Emergency pause and withdrawal capabilities
- Input validation for all parameters
- Zero address checks
- Event logging for all critical actions

## Foundry Commands

### Build
```bash
forge build
```
Compiles all contracts in the project.

### Test
```bash
# Run all tests
forge test

# Run tests with detailed gas information
forge test --gas-report

# Run a specific test file
forge test --match-path test/DexPool.t.sol

# Run a specific test function
forge test --match-test testAddLiquidity

# Run tests with more verbose output
forge test -vv
```