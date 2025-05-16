// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SyntheticRubbleV2} from "../src/SyntheticRubbleV2.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {BondOracle} from "../src/BondOracle.sol";
import {BondToken} from "../src/BondToken.sol";
import {SoulBoundIdentityNFT} from "../src/SoulBoundIdentityNFT.sol";

contract sRUBV2Test is Test {
    SyntheticRubbleV2 public srub;
    BondFactory public factory;
    BondOracle public oracle;
    BondToken public bond;
    BondToken public bond2; // Second bond for testing multiple collaterals
    address public admin;
    address public issuer;
    address public user1;
    address public user2;

    // Realistic bond prices
    uint160 constant BOND_PRICE = 1000000000; // 1 ETH
    uint160 constant BOND2_PRICE = 800000000; // 0.8 ETH

    // Use millions for collateral amounts instead of extreme values
    uint256 constant COLLATERAL_AMOUNT = 10_000; // 10 million
    uint256 constant COLLATERAL_AMOUNT_LARGE = 50_000; // 50 million

    event CollateralDeposited(address indexed user, address indexed collateral, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed collateral, uint256 amount);

    function setUp() public {
        admin = makeAddr("admin");
        issuer = makeAddr("issuer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(admin);
        factory = new BondFactory(issuer);
        oracle = new BondOracle(address(factory), admin);
        SoulBoundIdentityNFT identityNFT = new SoulBoundIdentityNFT(admin, "https://example.com/");
        factory.setDependencies(address(oracle), address(identityNFT));
        srub = new SyntheticRubbleV2(address(oracle)); // sRUB uses 6 decimals like USDC/USDT
        vm.stopPrank();

        // Create test bonds
        vm.startPrank(issuer);
        address bondAddress = factory.issueBond("Test Bond", 1000 * 1e6, 2000 * 1e6, uint40(block.timestamp + 365 days));
        bond = BondToken(bondAddress);

        address bond2Address =
            factory.issueBond("Test Bond 2", 800 * 1e6, 1600 * 1e6, uint40(block.timestamp + 365 days));
        bond2 = BondToken(bond2Address);
        vm.stopPrank();

        vm.startPrank(admin);
        identityNFT.mint(user1, 365 days);
        identityNFT.mint(user2, 365 days);
        identityNFT.mint(address(srub), 365 days);

        // Update the price feed with much higher values for testing
        oracle.updatePriceFeed(address(bond), BOND_PRICE);
        oracle.updatePriceFeed(address(bond2), BOND2_PRICE);
        vm.stopPrank();

        // Mint tokens for the tests - using reasonable amounts instead of extremely large amounts
        vm.startPrank(issuer);
        bond.mint(user1, 1_000_000_000); // 1 billion
        bond.mint(user2, 1_000_000_000);
        bond2.mint(user1, 1_000_000_000);
        bond2.mint(user2, 1_000_000_000);
        vm.stopPrank();
    }

    function testSupplySingleCollateral() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);
        vm.stopPrank();

        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount);

        address[] memory collaterals = srub.getUserCollaterals(user1);
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(bond));

        // No sRUB should be minted with just supply()
        uint256 mintedAmount = srub.balanceOf(user1);
        uint256 debtAmount = srub.getUserDebt(user1);
        assertEq(mintedAmount, 0);
        assertEq(debtAmount, 0);
    }

    function testSupplyMultipleCollaterals() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);
        // Deposit first collateral
        bond.approve(address(srub), depositAmount1);
        srub.supply(address(bond), depositAmount1);

        // Deposit second collateral
        bond2.approve(address(srub), depositAmount2);
        srub.supply(address(bond2), depositAmount2);
        vm.stopPrank();

        // Verify both collaterals were added
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount1);
        assertEq(srub.getUserCollateralAmount(user1, address(bond2)), depositAmount2);

        address[] memory collaterals = srub.getUserCollaterals(user1);
        assertEq(collaterals.length, 2);

        // Check if both bond addresses are in the collaterals array
        bool foundBond1 = false;
        bool foundBond2 = false;
        for (uint256 i = 0; i < collaterals.length; i++) {
            if (collaterals[i] == address(bond)) foundBond1 = true;
            if (collaterals[i] == address(bond2)) foundBond2 = true;
        }
        assertTrue(foundBond1);
        assertTrue(foundBond2);
    }

    function testBorrow() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Get collateral value
        uint256 collateralValue = srub.getTotalCollateralValue(user1);

        // Calculate maximum borrowable amount (80% of collateral value)
        uint256 maxBorrow = (collateralValue * 8000) / 10000;

        // Borrow 50% of max borrowable amount
        uint256 borrowAmount = maxBorrow / 2;
        srub.borrow(borrowAmount);

        // Check that debt and balance were updated
        assertEq(srub.getUserDebt(user1), borrowAmount);
        assertEq(srub.balanceOf(user1), borrowAmount);

        vm.stopPrank();
    }

    function test_RevertWhen_BorrowingTooMuch() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Get collateral value
        uint256 collateralValue = srub.getTotalCollateralValue(user1);

        // Calculate maximum borrowable amount (80% of collateral value)
        uint256 maxBorrow = (collateralValue * 8000) / 10000;

        // Try to borrow more than allowed
        uint256 excessBorrowAmount = maxBorrow + 1;

        // Should revert
        vm.expectRevert(SyntheticRubbleV2.InsufficientCollateral.selector);
        srub.borrow(excessBorrowAmount);

        vm.stopPrank();
    }

    function testRepay() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Get collateral value
        uint256 collateralValue = srub.getTotalCollateralValue(user1);

        // Calculate maximum borrowable amount (80% of collateral value)
        uint256 maxBorrow = (collateralValue * 8000) / 10000;

        // Borrow 50% of max borrowable amount
        uint256 borrowAmount = maxBorrow / 2;
        srub.borrow(borrowAmount);

        // Initial debt amount
        uint256 initialDebt = srub.getUserDebt(user1);

        // Repay half the debt
        uint256 repayAmount = initialDebt / 2;
        srub.repay(repayAmount);

        // Check that debt was reduced
        assertEq(srub.getUserDebt(user1), initialDebt - repayAmount);
        assertEq(srub.balanceOf(user1), initialDebt - repayAmount);

        vm.stopPrank();
    }

    function testFullRepay() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Borrow
        uint256 collateralValue = srub.getTotalCollateralValue(user1);
        uint256 maxBorrow = (collateralValue * 8000) / 10000;
        uint256 borrowAmount = maxBorrow / 2;
        srub.borrow(borrowAmount);

        // Repay entire debt
        srub.repay(borrowAmount);

        // Check that debt is zero
        assertEq(srub.getUserDebt(user1), 0);
        assertEq(srub.balanceOf(user1), 0);

        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;
        uint256 withdrawAmount = depositAmount / 2; // Withdraw half

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Withdraw part of the collateral
        srub.withdraw(address(bond), withdrawAmount);

        // Check that collateral amount was reduced
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount - withdrawAmount);

        // Check that bond was returned to user
        assertEq(bond.balanceOf(user1), 1_000_000_000 - depositAmount + withdrawAmount);

        vm.stopPrank();
    }

    function testWithdrawWithDebt() public {
        uint256 depositAmount = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Borrow
        uint256 collateralValue = srub.getTotalCollateralValue(user1);
        uint256 maxBorrow = (collateralValue * 8000) / 10000;
        uint256 borrowAmount = maxBorrow / 4; // Borrow 25% of max
        srub.borrow(borrowAmount);

        // Use a fixed, small withdrawal amount that we know will work
        uint256 withdrawAmount = depositAmount / 10; // Withdraw 10% of the deposit

        console.log("Total collateral value:", srub.getTotalCollateralValue(user1));
        console.log("User debt:", srub.getUserDebt(user1));
        console.log("Initial health factor:", srub.getPositionHealth(user1));
        console.log("Withdraw amount:", withdrawAmount);

        // Withdraw a small amount of collateral
        srub.withdraw(address(bond), withdrawAmount);

        // Check position is still healthy
        uint256 healthFactor = srub.getPositionHealth(user1);
        console.log("Health factor after withdrawal:", healthFactor);
        assertGe(healthFactor, 12500); // At least 125%

        // Verify the collateral was actually withdrawn
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount - withdrawAmount);

        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawMakesPositionUnhealthy() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        // Supply collateral
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Borrow at 50% LTV
        uint256 collateralValue = srub.getTotalCollateralValue(user1);
        uint256 borrowAmount = (collateralValue * 5000) / 10000;
        srub.borrow(borrowAmount);

        // Try to withdraw too much collateral, making position unhealthy
        vm.expectRevert(SyntheticRubbleV2.InsufficientCollateral.selector);
        srub.withdraw(address(bond), depositAmount);

        vm.stopPrank();
    }

    function testLiquidation() public {
        // Set up a position for user1
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount);
        srub.supply(address(bond), depositAmount);

        // Borrow at high LTV to make position more vulnerable
        uint256 collateralValue = srub.getTotalCollateralValue(user1);
        uint256 borrowAmount = (collateralValue * 7500) / 10000; // 75% LTV
        srub.borrow(borrowAmount);

        // Get user1 position details
        uint256 initialDebt = srub.getUserDebt(user1);
        uint256 initialHealth = srub.getPositionHealth(user1);
        console.log("Initial debt:", initialDebt);
        console.log("Initial health factor:", initialHealth);
        vm.stopPrank();

        // Drastically reduce bond price to make position liquidatable
        // Move forward in time to allow oracle update
        vm.warp(block.timestamp + 1 hours);

        vm.startPrank(admin);
        // Reduce price so health falls below liquidation threshold (120%)
        uint160 newPrice = BOND_PRICE / 2; // 50% price drop
        oracle.updatePriceFeed(address(bond), newPrice);
        vm.stopPrank();

        // Check position is now liquidatable
        uint256 newHealth = srub.getPositionHealth(user1);
        console.log("Health factor after price drop:", newHealth);
        assertLt(newHealth, srub.LIQUIDATION_THRESHOLD());

        // Give user2 enough sRUB to cover the debt for liquidation
        vm.startPrank(issuer);
        bond.mint(user2, depositAmount * 3); // Mint 3x more to ensure enough sRUB is generated
        vm.stopPrank();

        vm.startPrank(user2);
        bond.approve(address(srub), depositAmount * 3);
        srub.supply(address(bond), depositAmount * 3);

        // Borrow to get sRUB for liquidation
        uint256 collateralValue2 = srub.getTotalCollateralValue(user2);
        uint256 borrowAmount2 = (collateralValue2 * 7000) / 10000;
        srub.borrow(borrowAmount2);

        uint256 srubAmount = srub.balanceOf(user2);
        console.log("User2 sRUB balance:", srubAmount);

        // Get user2's bond balance before liquidation
        uint256 bondBalanceBefore = bond.balanceOf(user2);
        console.log("User2 bond balance before liquidation:", bondBalanceBefore);

        // Liquidate user1's position
        srub.liquidate(user1, address(bond));

        // Verify liquidation results
        // 1. User1's position should be cleared
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), 0);

        // 2. User2 should receive liquidation reward
        uint256 bondBalanceAfter = bond.balanceOf(user2);
        console.log("User2 bond balance after liquidation:", bondBalanceAfter);

        // Calculate reward (90% of the collateral)
        uint256 liquidatorReward = depositAmount * (10000 - srub.LIQUIDATION_PENALTY()) / 10000;
        console.log("Expected liquidator reward:", liquidatorReward);

        // Verify user2 received the reward
        assertEq(bondBalanceAfter - bondBalanceBefore, liquidatorReward);

        vm.stopPrank();
    }

    function testDecimals() public view {
        assertEq(srub.decimals(), 6);
    }
}
