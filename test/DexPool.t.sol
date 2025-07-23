// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DexPool} from "../src/DexPool.sol";
import {SimpleToken} from "../src/SimpleToken.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

// contract MockFailingToken is SimpleToken {
//     constructor() SimpleToken("Mock Failing Token", "MFT") {}

//     function transferFrom(address from, address to, uint256 amount) external pure override returns (bool) {
//         return false;
//     }
// }

contract DexPoolTest is Test {
    DexPool private dexPool;
    SimpleToken private token;

    address private user1 = address(0x1);
    address private user2 = address(0x5);
    address private user3 = address(0x4);
    address private admin = address(0x3);
    address private pauser = address(0x2);
    address private nonAdmin = address(0x6);
    address private nonPauser = address(0x7);
    address private deployer = address(0x10);

    uint256 private constant INITIAL_TOKEN_SUPPLY = 1000 ether;
    uint256 private constant ETH_AMOUNT = 10 ether;
    uint256 private constant TOKEN_AMOUNT = 100;
    
    // Fee constants from DexPool contract
    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant FEE_BASIS_POINTS = 100; // 1%

    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 lpTokensMinted);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 lpTokensBurned);
    event EthToTokenSwap(address indexed swapper, uint256 ethIn, uint256 tokensOut);
    event TokenToEthSwap(address indexed swapper, uint256 tokensIn, uint256 ethOut);

    function setUp() public {
        vm.startPrank(deployer);
        // Deploy token
        token = new SimpleToken("Test Token", "TEST");

        // Deploy DEX pool
        dexPool = new DexPool(address(token));

        // Mint tokens to users
        token.mint(user1, INITIAL_TOKEN_SUPPLY);
        token.mint(user2, INITIAL_TOKEN_SUPPLY);
        token.mint(user3, INITIAL_TOKEN_SUPPLY);

        // Grant roles to test addresses
        dexPool.grantRole(dexPool.ADMIN_ROLE(), admin);
        dexPool.grantRole(dexPool.PAUSER_ROLE(), pauser);
        vm.stopPrank();
    }

    function testConstructor() public {
        vm.prank(deployer);
        DexPool newDexPool = new DexPool(address(token));

        assertEq(address(newDexPool.token()), address(token));
        assertEq(newDexPool.name(), "Simple DEX LP Token");
        assertEq(newDexPool.symbol(), "SDLP");
        assertEq(newDexPool.decimals(), 18);
        assertTrue(newDexPool.hasRole(newDexPool.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(newDexPool.hasRole(newDexPool.ADMIN_ROLE(), deployer));
        assertTrue(newDexPool.hasRole(newDexPool.PAUSER_ROLE(), deployer));
    }

    function testConstructorRevertZeroAddress() public {
        vm.expectRevert(DexPool.ZeroAddressNotAllowed.selector);
        new DexPool(address(0));
    }

    function testGrantPauserRole() public {
        vm.prank(admin);
        dexPool.grantPauserRole(user1);
        assertTrue(dexPool.hasRole(dexPool.PAUSER_ROLE(), user1));
    }

    function testGrantPauserRoleRevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(DexPool.CallerIsNotAdmin.selector);
        dexPool.grantPauserRole(user1);
    }

    function testGrantPauserRoleRevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(DexPool.ZeroAddressNotAllowed.selector);
        dexPool.grantPauserRole(address(0));
    }

    function testRevokePauserRole() public {
        // First grant the role
        vm.prank(admin);
        dexPool.grantPauserRole(user1);
        assertTrue(dexPool.hasRole(dexPool.PAUSER_ROLE(), user1));

        // Then revoke it
        vm.prank(admin);
        dexPool.revokePauserRole(user1);
        assertFalse(dexPool.hasRole(dexPool.PAUSER_ROLE(), user1));
    }

    function testRevokePauserRoleRevertNotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(DexPool.CallerIsNotAdmin.selector);
        dexPool.revokePauserRole(user1);
    }

    function testRevokePauserRoleRevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(DexPool.ZeroAddressNotAllowed.selector);
        dexPool.revokePauserRole(address(0));
    }

    function testPause() public {
        vm.prank(pauser);
        dexPool.pause();
        assertTrue(dexPool.paused());
    }

    function testPauseRevertNotPauser() public {
        vm.prank(nonPauser);
        vm.expectRevert(DexPool.CallerIsNotPauser.selector);
        dexPool.pause();
    }

    function testUnpause() public {
        // First pause
        vm.prank(pauser);
        dexPool.pause();
        assertTrue(dexPool.paused());

        // Then unpause
        vm.prank(pauser);
        dexPool.unpause();
        assertFalse(dexPool.paused());
    }

    function testUnpauseRevertNotPauser() public {
        vm.prank(nonPauser);
        vm.expectRevert(DexPool.CallerIsNotPauser.selector);
        dexPool.unpause();
    }

    function testAddLiquidityFirstTime() public {
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);

        uint256 initialBalance = user1.balance;
        uint256 initialTokenBalance = token.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit LiquidityAdded(user1, ETH_AMOUNT, TOKEN_AMOUNT, ETH_AMOUNT);

        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);

        assertEq(dexPool.balanceOf(user1), ETH_AMOUNT);
        assertEq(dexPool.totalSupply(), ETH_AMOUNT);
        assertEq(address(dexPool).balance, ETH_AMOUNT);
        assertEq(token.balanceOf(address(dexPool)), TOKEN_AMOUNT);
        assertEq(dexPool.getLPTokensToMint(), ETH_AMOUNT);
        vm.stopPrank();
    }

    function testAddLiquidityThreeTimes() public {
        // First user adds initial liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Second user adds liquidity (double the amount)
        uint256 secondUserEthAmount = ETH_AMOUNT * 2;
        uint256 secondUserTokenAmount = TOKEN_AMOUNT * 2;
        
        vm.deal(user2, secondUserEthAmount);
        vm.startPrank(user2);
        token.approve(address(dexPool), secondUserTokenAmount);

        // Get state before second user adds liquidity
        uint256 totalSupplyBefore = dexPool.totalSupply();
        uint256 reserveEthBefore = address(dexPool).balance;
        uint256 reserveTokenBefore = dexPool.getReserve();

        // Calculate expected LP tokens: (totalSupply * ethAmount) / reserveEth
        uint256 expectedLPTokens = (totalSupplyBefore * secondUserEthAmount) / reserveEthBefore;
        vm.expectEmit(true, false, false, true);
        emit LiquidityAdded(user2, secondUserEthAmount, secondUserTokenAmount, expectedLPTokens);

        dexPool.addLiquidity{value: secondUserEthAmount}(secondUserTokenAmount);
        vm.stopPrank();

        // Third user adds liquidity (same as first user)
        uint256 thirdUserEthAmount = ETH_AMOUNT;
        uint256 thirdUserTokenAmount = TOKEN_AMOUNT;
        
        vm.deal(user3, thirdUserEthAmount);
        vm.startPrank(user3);
        token.approve(address(dexPool), thirdUserTokenAmount);

        // Get state before third user adds liquidity
        uint256 totalSupplyBeforeUser3 = dexPool.totalSupply();
        uint256 reserveEthBeforeUser3 = address(dexPool).balance;
        uint256 reserveTokenBeforeUser3 = dexPool.getReserve();

        // Calculate expected LP tokens for User3: (totalSupply * ethAmount) / reserveEth
        uint256 expectedLPTokensUser3 = (totalSupplyBeforeUser3 * thirdUserEthAmount) / reserveEthBeforeUser3;

        vm.expectEmit(true, false, false, true);
        emit LiquidityAdded(user3, thirdUserEthAmount, thirdUserTokenAmount, expectedLPTokensUser3);

        dexPool.addLiquidity{value: thirdUserEthAmount}(thirdUserTokenAmount);
        vm.stopPrank();

        // Verify all users received correct LP tokens
        assertEq(dexPool.balanceOf(user1), ETH_AMOUNT, "User1 should have 10 LP tokens");
        assertEq(dexPool.balanceOf(user2), expectedLPTokens, "User2 should have 20 LP tokens");
        assertEq(dexPool.balanceOf(user3), expectedLPTokensUser3, "User3 should have 10 LP tokens");
        
        // Verify total supply
        assertEq(dexPool.totalSupply(), ETH_AMOUNT + expectedLPTokens + expectedLPTokensUser3, "Total supply should be 40 LP tokens");
        
        // Verify pool balances
        assertEq(address(dexPool).balance, ETH_AMOUNT + secondUserEthAmount + thirdUserEthAmount, "Pool should have 40 ETH");
        assertEq(dexPool.getReserve(), TOKEN_AMOUNT + secondUserTokenAmount + thirdUserTokenAmount, "Pool should have 400 tokens");
        
        // Verify ownership proportions
        uint256 user1Ownership = (dexPool.balanceOf(user1) * 100) / dexPool.totalSupply();
        uint256 user2Ownership = (dexPool.balanceOf(user2) * 100) / dexPool.totalSupply();
        uint256 user3Ownership = (dexPool.balanceOf(user3) * 100) / dexPool.totalSupply();
        
        assertEq(user1Ownership, 25, "User1 should own 25% of the pool");
        assertEq(user2Ownership, 50, "User2 should own 50% of the pool");
        assertEq(user3Ownership, 25, "User3 should own 25% of the pool");
    }

    function testAddLiquidityRevertZeroTokenAmount() public {
        vm.deal(user1, ETH_AMOUNT);
        vm.prank(user1);
        vm.expectRevert(DexPool.InsufficientTokenAmount.selector);
        dexPool.addLiquidity{value: ETH_AMOUNT}(0);
    }

    function testAddLiquidityRevertZeroEthAmount() public {
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        vm.expectRevert(DexPool.InsufficientEthAmount.selector);
        dexPool.addLiquidity{value: 0}(TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testAddLiquidityRevertInsufficientTokenAmount() public {
        // First user adds initial liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Second user tries to add liquidity with insufficient tokens
        vm.deal(user2, ETH_AMOUNT);
        vm.startPrank(user2);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        vm.expectRevert(DexPool.InsufficientTokenAmount.selector);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT / 2);
        vm.stopPrank();
    }

    // function testAddLiquidityRevertInsufficientLiquidityMinted() public {
    //     // This test doesn't actually trigger the InsufficientLiquidityMinted error
    //     // because the calculation (totalSupply * ethAmount) / reserveEth
    //     // always results in at least 1 LP token with the current values
    //     // To properly test this, we would need a scenario where the calculation
    //     // actually results in 0 due to integer division
    // }

    function testAddLiquidityRevertWhenPaused() public {
        vm.prank(pauser);
        dexPool.pause();

        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        // Add liquidity first
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);

        uint256 lpTokens = dexPool.balanceOf(user1);
        uint256 initialBalance = user1.balance;
        uint256 initialTokenBalance = token.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit LiquidityRemoved(user1, ETH_AMOUNT, TOKEN_AMOUNT, lpTokens);

        dexPool.removeLiquidity(lpTokens);

        assertEq(dexPool.balanceOf(user1), 0);
        assertEq(dexPool.totalSupply(), 0);
        assertEq(address(dexPool).balance, 0);
        assertEq(token.balanceOf(address(dexPool)), 0);
        
        (uint256 ethReturned, uint256 tokenReturned) = dexPool.getEthAndTokenToReturn();
        assertEq(ethReturned, ETH_AMOUNT);
        assertEq(tokenReturned, TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testRemoveLiquidityPartial() public {
        // Add liquidity first
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);

        uint256 lpTokens = dexPool.balanceOf(user1);
        uint256 removeAmount = lpTokens / 2;

        dexPool.removeLiquidity(removeAmount);

        assertEq(dexPool.balanceOf(user1), lpTokens - removeAmount);
        assertEq(dexPool.totalSupply(), lpTokens - removeAmount);

        // For partial removal, we should get back half of the ETH and tokens
        (uint256 ethReturned, uint256 tokenReturned) = dexPool.getEthAndTokenToReturn();
        assertEq(ethReturned, ETH_AMOUNT / 2);
        assertEq(tokenReturned, TOKEN_AMOUNT / 2);
        vm.stopPrank();
    }

    function testRemoveLiquidityRevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(DexPool.InsufficientLiquidityAmount.selector);
        dexPool.removeLiquidity(0);
    }

    function testRemoveLiquidityRevertNotEnoughTokens() public {
        vm.prank(user1);
        vm.expectRevert(DexPool.NotEnoughTokens.selector);
        dexPool.removeLiquidity(1000);
    }

    function testRemoveLiquidityRevertWhenPaused() public {
        // Add liquidity first (when contract is not paused)
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Verify user has LP tokens
        uint256 userLPTokens = dexPool.balanceOf(user1);
        assertGt(userLPTokens, 0, "User should have LP tokens");

        // Pause the contract
        vm.prank(pauser);
        dexPool.pause();
        assertTrue(dexPool.paused());

        // Try to remove liquidity (should fail because contract is paused)
        vm.startPrank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        dexPool.removeLiquidity(userLPTokens);
        vm.stopPrank();
    }

    function testEthToTokenSwap() public {
        // Add initial liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Perform ETH to token swap
        vm.deal(user2, ETH_AMOUNT);
        vm.startPrank(user2);
        uint256 swapAmount = 1 ether;
        uint256 initialTokenBalance = token.balanceOf(user2);

        // Calculate expected output using Uniswap V1 formula
        uint256 reserveEth = ETH_AMOUNT;
        uint256 reserveToken = TOKEN_AMOUNT;
        uint256 ethInputWithFee = (swapAmount * (FEE_DENOMINATOR - FEE_BASIS_POINTS)) / FEE_DENOMINATOR;
        uint256 expectedTokensOutput = (ethInputWithFee * reserveToken) / (reserveEth + ethInputWithFee);

        dexPool.ethToTokenSwap{value: swapAmount}();

        uint256 actualTokensReceived = token.balanceOf(user2) - initialTokenBalance;

        assertEq(actualTokensReceived, expectedTokensOutput, "Token output should match expected calculation");
        vm.stopPrank();
    }

    function testEthToTokenSwapRevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(DexPool.InsufficientEthAmount.selector);
        dexPool.ethToTokenSwap{value: 0}();
    }

    function testEthToTokenSwapRevertWhenPaused() public {
        // Add liquidity first (when contract is not paused)
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Verify user has LP tokens
        uint256 userLPTokens = dexPool.balanceOf(user1);
        assertGt(userLPTokens, 0, "User should have LP tokens");

        // Pause the contract
        vm.prank(pauser);
        dexPool.pause();
        assertTrue(dexPool.paused());

        // Try to swap
        vm.deal(user2, ETH_AMOUNT);
        vm.startPrank(user2);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        dexPool.ethToTokenSwap{value: 1 ether}();
    }

    function testTokenToEthSwap() public {
        // Add initial liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Perform token to ETH swap
        vm.startPrank(user2);
        uint256 swapAmount = 10;
        uint256 initialBalance = user2.balance;

        // Get reserves before swap
        uint256 reserveEthBefore = address(dexPool).balance;
        uint256 reserveTokenBefore = dexPool.getReserve();

        token.approve(address(dexPool), swapAmount);

        dexPool.tokenToEthSwap(swapAmount);

        uint256 actualEthReceived = user2.balance - initialBalance;
        // Verify the swap worked correctly
        assertGt(actualEthReceived, 0, "User should receive ETH from swap");
        
        // Verify reserves were updated correctly
        uint256 reserveEthAfter = address(dexPool).balance;
        uint256 reserveTokenAfter = dexPool.getReserve();
        assertEq(reserveEthAfter, reserveEthBefore - actualEthReceived, "ETH reserve should decrease by output amount");
        assertEq(reserveTokenAfter, reserveTokenBefore + swapAmount, "Token reserve should increase by input amount");
        vm.stopPrank();
    }

    function testTokenToEthSwapRevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(DexPool.InsufficientTokenAmount.selector);
        dexPool.tokenToEthSwap(0);
    }

    function testTokenToEthSwapRevertWhenPaused() public {
        // Add liquidity first (when contract is not paused)
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Verify user has LP tokens
        uint256 userLPTokens = dexPool.balanceOf(user1);
        assertGt(userLPTokens, 0, "User should have LP tokens");

        // Give tokens to user2 for swapping
        vm.prank(deployer);
        token.mint(user2, TOKEN_AMOUNT);

        // Pause the contract
        vm.prank(pauser);
        dexPool.pause();
        assertTrue(dexPool.paused());

        // Try to swap (should fail because contract is paused)
        vm.startPrank(user2);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        dexPool.tokenToEthSwap(TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testGetLPTokensToMint() public {
        assertEq(dexPool.getLPTokensToMint(), 0);

        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        assertEq(dexPool.getLPTokensToMint(), ETH_AMOUNT);
        vm.stopPrank();
    }

    function testGetEthAndTokenToReturn() public {
        (uint256 ethReturned, uint256 tokenReturned) = dexPool.getEthAndTokenToReturn();
        assertEq(ethReturned, 0);
        assertEq(tokenReturned, 0);

        // Add and remove liquidity
        vm.deal(user1, ETH_AMOUNT);    
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        dexPool.removeLiquidity(dexPool.balanceOf(user1));

        (ethReturned, tokenReturned) = dexPool.getEthAndTokenToReturn();
        assertEq(ethReturned, ETH_AMOUNT);
        assertEq(tokenReturned, TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testGetReserve() public {
        assertEq(dexPool.getReserve(), 0);

        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        assertEq(dexPool.getReserve(), TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function testGetBalance() public {
        assertEq(dexPool.getBalance(user1), 0);

        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        assertEq(dexPool.getBalance(user1), ETH_AMOUNT);
        vm.stopPrank();
    }


    function testReceiveRevert() public {
        vm.expectRevert(DexPool.DirectEthTransfersNotSupported.selector);
        address(dexPool).call{value: 1 ether}("");
    }

    function testFallbackRevert() public {
        vm.expectRevert(DexPool.DirectEthTransfersNotSupported.selector);
        address(dexPool).call{value: 1 ether}("invalid");
    }

    function testSwapWithInsufficientLiquidity() public {
        // Try to swap without any liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.prank(user1);
        vm.expectRevert(DexPool.InvalidOutputAmount.selector);
        dexPool.ethToTokenSwap{value: 1 ether}();
    }

    function testSwapWithVerySmallAmount() public {
        // Add minimal liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), 1000);
        dexPool.addLiquidity{value: 1 ether}(1000);
        vm.stopPrank();

        // Try to swap very small amount
        vm.deal(user2, ETH_AMOUNT);
        vm.prank(user2);
        vm.expectRevert(DexPool.InvalidOutputAmount.selector);
        dexPool.ethToTokenSwap{value: 1}();
    }

    function testMultipleUsersAddLiquidity() public {
        // User 1 adds liquidity
        vm.deal(user1, ETH_AMOUNT);    
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // User 2 adds liquidity
        vm.deal(user2, ETH_AMOUNT);
        vm.startPrank(user2);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // User 3 adds liquidity
        vm.deal(user3, ETH_AMOUNT);
        vm.startPrank(user3);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(dexPool.totalSupply(), ETH_AMOUNT * 3);
        assertEq(address(dexPool).balance, ETH_AMOUNT * 3);
        assertEq(token.balanceOf(address(dexPool)), TOKEN_AMOUNT * 3);
    }

    function testEthToTokenSwapRevertInvalidOutputAmountZero() public {
        // Add liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Try to swap with amount that results in 0 output
        vm.deal(user2, 1);
        vm.prank(user2);
        vm.expectRevert(DexPool.InvalidOutputAmount.selector);
        dexPool.ethToTokenSwap{value: 1}();
    }

    function testTokenToEthSwapRevertInvalidOutputAmountZero() public {
        // Add liquidity
        vm.deal(user1, ETH_AMOUNT);
        vm.startPrank(user1);
        token.approve(address(dexPool), TOKEN_AMOUNT);
        dexPool.addLiquidity{value: ETH_AMOUNT}(TOKEN_AMOUNT);
        vm.stopPrank();

        // Give user2 tokens and try to swap with amount that results in 0 output
        vm.deal(user2, ETH_AMOUNT);
        vm.startPrank(user2);
        token.approve(address(dexPool), 1);
        
        vm.expectRevert(DexPool.InvalidOutputAmount.selector);
        dexPool.tokenToEthSwap(1);
        vm.stopPrank();
    }
}


