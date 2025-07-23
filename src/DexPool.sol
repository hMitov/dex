// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @title Simple DEX Pool with Liquidity Provision and Swapping
/// @notice A decentralized exchange pool that allows users to provide liquidity and swap ETH for tokens
contract DexPool is ERC20, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    /// @notice The ERC20 token that can be swapped with ETH

    IERC20 public immutable token;

    uint256 private constant FEE_BASIS_POINTS = 100; // 1%
    uint256 private constant FEE_DENOMINATOR = 10000;

    mapping(address => uint256) private lastLPTokensMinted;
    mapping(address => uint256) private lastEthReturned;
    mapping(address => uint256) private lastTokenReturned;

    /// @notice Role identifier for admin accounts with elevated privileges
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role identifier for accounts authorized to pause and unpause contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Emitted when liquidity is added to the pool
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 lpTokensMinted);

    /// @notice Emitted when liquidity is removed from the pool
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 lpTokensBurned);

    /// @notice Emitted when ETH is swapped for tokens
    event EthToTokenSwap(address indexed swapper, uint256 ethIn, uint256 tokensOut);

    /// @notice Emitted when tokens are swapped for ETH
    event TokenToEthSwap(address indexed swapper, uint256 tokensIn, uint256 ethOut);

    /// @notice Error thrown when caller is not an admin
    error CallerIsNotAdmin();

    /// @notice Error thrown when caller is not a pauser
    error CallerIsNotPauser();

    /// @notice Error thrown when token amount is insufficient
    error InsufficientTokenAmount();

    /// @notice Error thrown when zero address is provided
    error ZeroAddressNotAllowed();

    /// @notice Error thrown when ETH amount is insufficient
    error InsufficientEthAmount();

    /// @notice Error thrown when ETH transfer fails
    error EthTransferFailed();

    /// @notice Error thrown when insufficient LP tokens are minted
    error InsufficientLiquidityMinted();

    /// @notice Error thrown when liquidity amount is insufficient
    error InsufficientLiquidityAmount();

    /// @notice Error thrown when user doesn't have enough tokens
    error NotEnoughTokens();

    /// @notice Error thrown when output amount is invalid
    error InvalidOutputAmount();

    /// @notice Error thrown when direct ETH transfers are attempted
    error DirectEthTransfersNotSupported();

    /// @notice Constructs the DEX pool with the specified token
    /// @param _token The ERC20 token address for the pool
    constructor(address _token) ERC20("Simple DEX LP Token", "SDLP") {
        if (_token == address(0)) revert ZeroAddressNotAllowed();
        token = IERC20(_token);

        address deployer = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(ADMIN_ROLE, deployer);
        _grantRole(PAUSER_ROLE, deployer);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    /// @notice Modifier that restricts access to admin accounts only
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert CallerIsNotAdmin();
        _;
    }

    /// @notice Modifier that restricts access to pauser accounts only
    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender)) revert CallerIsNotPauser();
        _;
    }

    /// @notice Pauses all trading and liquidity operations
    function pause() external onlyPauser {
        _pause();
    }

    /// @notice Unpauses all trading and liquidity operations
    function unpause() external onlyPauser {
        _unpause();
    }

    /// @notice Grants the pauser role to an account
    /// @param account The address to grant the pauser role to
    function grantPauserRole(address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        grantRole(PAUSER_ROLE, account);
    }

    /// @notice Revokes the PAUSER_ROLE from an account
    /// @param account The address to revoke the pauser role from
    function revokePauserRole(address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        revokeRole(PAUSER_ROLE, account);
    }

    /// @notice Adds liquidity to the pool by providing ETH and tokens
    /// @param amountOfToken The amount of tokens to provide
    function addLiquidity(uint256 amountOfToken) external payable nonReentrant whenNotPaused {
        if (amountOfToken == 0) revert InsufficientTokenAmount();
        if (msg.value == 0) revert InsufficientEthAmount();

        uint256 ethAmount = msg.value;
        uint256 reserveEth = address(this).balance - ethAmount;
        uint256 reserveToken = token.balanceOf(address(this));
        uint256 lpTokensMinted;
        if (reserveEth == 0 && reserveToken == 0) {
            token.transferFrom(msg.sender, address(this), amountOfToken);

            lpTokensMinted = ethAmount;

            _mint(msg.sender, lpTokensMinted);
        } else {
            uint256 tokenRequired = (ethAmount * reserveToken) / reserveEth;
            if (amountOfToken < tokenRequired) revert InsufficientTokenAmount();
            token.transferFrom(msg.sender, address(this), tokenRequired);

            lpTokensMinted = (totalSupply() * ethAmount) / reserveEth;

            if (lpTokensMinted == 0) revert InsufficientLiquidityMinted();

            _mint(msg.sender, lpTokensMinted);
        }

        lastLPTokensMinted[msg.sender] = lpTokensMinted;

        emit LiquidityAdded(msg.sender, ethAmount, amountOfToken, lpTokensMinted);
    }

    /// @notice Removes liquidity from the pool by burning LP tokens
    /// @param amountOfLPTokens The amount of LP tokens to burn
    function removeLiquidity(uint256 amountOfLPTokens) external nonReentrant whenNotPaused {
        if (amountOfLPTokens == 0) revert InsufficientLiquidityAmount();
        if (balanceOf(msg.sender) < amountOfLPTokens) revert NotEnoughTokens();

        uint256 totalSupply_ = totalSupply();
        uint256 ethAmount = (address(this).balance * amountOfLPTokens) / totalSupply_;
        uint256 tokenAmount = (token.balanceOf(address(this)) * amountOfLPTokens) / totalSupply_;

        _burn(msg.sender, amountOfLPTokens);
        _safeTransferETH(msg.sender, ethAmount);

        token.transfer(msg.sender, tokenAmount);

        lastEthReturned[msg.sender] = ethAmount;
        lastTokenReturned[msg.sender] = tokenAmount;

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount, amountOfLPTokens);
    }

    /// @notice Swaps ETH for tokens
    function ethToTokenSwap() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert InsufficientEthAmount();

        uint256 ethInput = msg.value;
        uint256 reserveEth = address(this).balance - ethInput;
        uint256 reserveToken = token.balanceOf(address(this));
        uint256 ethInputAfterFee = ethInput * (FEE_DENOMINATOR - FEE_BASIS_POINTS) / FEE_DENOMINATOR;
        uint256 tokensOutput = (ethInputAfterFee * reserveToken) / (reserveEth + ethInputAfterFee);

        if (tokensOutput == 0 || tokensOutput >= reserveToken) revert InvalidOutputAmount();
        token.transfer(msg.sender, tokensOutput);

        emit EthToTokenSwap(msg.sender, ethInput, tokensOutput);
    }

    /// @notice Swaps tokens for ETH
    /// @param tokensToSwap The amount of tokens to swap
    function tokenToEthSwap(uint256 tokensToSwap) external nonReentrant whenNotPaused {
        if (tokensToSwap == 0) revert InsufficientTokenAmount();
        token.safeTransferFrom(msg.sender, address(this), tokensToSwap);

        uint256 reserveEth = address(this).balance;
        uint256 reserveToken = token.balanceOf(address(this));
        uint256 tokensInAfterFee = (tokensToSwap * (FEE_DENOMINATOR - FEE_BASIS_POINTS)) / FEE_DENOMINATOR;
        uint256 ethOutput = (tokensInAfterFee * reserveEth) / (reserveToken + tokensInAfterFee);

        if (ethOutput == 0 || ethOutput >= reserveEth) revert InvalidOutputAmount();
        _safeTransferETH(msg.sender, ethOutput);

        emit TokenToEthSwap(msg.sender, tokensToSwap, ethOutput);
    }

    /// @notice Returns the last amount of LP tokens minted for the caller
    /// @return The amount of LP tokens last minted
    function getLPTokensToMint() external view returns (uint256) {
        return lastLPTokensMinted[msg.sender];
    }

    /// @notice Returns the last amounts of ETH and tokens returned to the caller
    /// @return ethAmount The amount of ETH last returned
    /// @return tokenAmount The amount of tokens last returned
    function getEthAndTokenToReturn() external view returns (uint256, uint256) {
        return (lastEthReturned[msg.sender], lastTokenReturned[msg.sender]);
    }

    /// @notice Returns the current token reserve in the pool
    /// @return The current token balance of the pool
    function getReserve() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Returns the LP token balance of a user
    /// @param user The address to query
    /// @return The LP token balance of the user
    function getBalance(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    /// @notice Prevents direct ETH transfers to the contract
    receive() external payable {
        revert DirectEthTransfersNotSupported();
    }

    /// @notice Prevents direct ETH transfers to the contract
    fallback() external payable {
        revert DirectEthTransfersNotSupported();
    }

    /// @notice Safely transfers ETH to a recipient
    /// @param receiver The address to send ETH to
    /// @param amount The amount of ETH to send
    function _safeTransferETH(address receiver, uint256 amount) internal {
        (bool success,) = receiver.call{value: amount}("");
        if (!success) revert EthTransferFailed();
    }
}
