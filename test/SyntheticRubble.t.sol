// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SyntheticRubble} from "../src/SyntheticRubble.sol";
import {BondFactory} from "../src/BondFactory.sol";
import {BondOracle} from "../src/BondOracle.sol";
import {BondToken} from "../src/BondToken.sol";
import {SoulBoundIdentityNFT} from "../src/SoulBoundIdentityNFT.sol";
import {ISyntheticRubble} from "../src/interfaces/ISyntheticRubble.sol";

contract sRUBTest is Test {
    SyntheticRubble public srub;
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
        srub = new SyntheticRubble(address(oracle)); // sRUB uses 6 decimals like USDC/USDT
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

    function testDepositSingleCollateral() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);
        vm.stopPrank();

        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount);

        address[] memory collaterals = srub.getUserCollaterals(user1);
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(bond));

        // Check if sRUB was minted
        uint256 mintedAmount = srub.balanceOf(user1);
        uint256 debtAmount = srub.getUserDebt(user1);
        console.log("Minted sRUB amount:", mintedAmount);
        // Debt amount should equal minted amount
        assertEq(mintedAmount, debtAmount);
    }

    function testDepositMultipleCollaterals() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);
        // Deposit first collateral
        bond.approve(address(srub), depositAmount1);
        srub.depositCollateral(address(bond), depositAmount1);

        // Deposit second collateral
        bond2.approve(address(srub), depositAmount2);
        srub.depositCollateral(address(bond2), depositAmount2);
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

    function testWithdrawSpecificCollateral() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;
        uint256 withdrawAmount = COLLATERAL_AMOUNT / 2; // Withdraw half

        vm.startPrank(user1);
        // Deposit both collaterals
        bond.approve(address(srub), depositAmount1);
        srub.depositCollateral(address(bond), depositAmount1);
        bond2.approve(address(srub), depositAmount2);
        srub.depositCollateral(address(bond2), depositAmount2);

        // Get initial debt amount
        uint256 initialDebt = srub.getUserDebt(user1);
        console.log("Initial debt:", initialDebt);

        // Preview how much sRUB will need to be burned
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(bond), withdrawAmount);
        assertTrue(canWithdraw, "Should be able to withdraw");
        console.log("sRUB to burn for withdrawal:", sRUBToBurn);

        // Withdraw part of the first collateral
        srub.decreasePosition(address(bond), withdrawAmount);
        vm.stopPrank();

        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount1 - withdrawAmount);
        assertEq(srub.getUserCollateralAmount(user1, address(bond2)), depositAmount2);
        assertEq(srub.getUserDebt(user1), initialDebt - sRUBToBurn);
    }

    function testRemoveCollateralCompletely() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);
        // Deposit both collaterals
        bond.approve(address(srub), depositAmount1);
        srub.depositCollateral(address(bond), depositAmount1);
        bond2.approve(address(srub), depositAmount2);
        srub.depositCollateral(address(bond2), depositAmount2);

        // Get initial debt amount
        uint256 initialDebt = srub.getUserDebt(user1);
        console.log("Initial debt:", initialDebt);

        // Preview how much sRUB will need to be burned
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(bond), depositAmount1);
        assertTrue(canWithdraw, "Should be able to withdraw");
        console.log("sRUB to burn for withdrawal:", sRUBToBurn);

        // Withdraw all of the first collateral
        srub.decreasePosition(address(bond), depositAmount1);
        vm.stopPrank();

        // Verify bond1 is removed from collaterals array
        address[] memory collaterals = srub.getUserCollaterals(user1);
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(bond2));
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), 0);
        assertEq(srub.getUserCollateralAmount(user1, address(bond2)), depositAmount2);
        assertEq(srub.getUserDebt(user1), initialDebt - sRUBToBurn);
    }

    function testGetTotalCollateralValue() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount1);
        srub.depositCollateral(address(bond), depositAmount1);
        bond2.approve(address(srub), depositAmount2);
        srub.depositCollateral(address(bond2), depositAmount2);
        vm.stopPrank();

        // Calculate approximate expected value
        uint256 collateralValue = srub.getTotalCollateralValue(user1);

        assertGt(collateralValue, 0, "Collateral value should be greater than 0");
        console.log("Total Collateral Value:", collateralValue);
    }

    function testIncreasePosition() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;
        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount * 2);
        srub.depositCollateral(address(bond), depositAmount);
        // Get debt amount after deposit (sRUB)
        uint256 initialDebtAmount = srub.getUserDebt(user1);

        // Deposit more to increase position
        srub.depositCollateral(address(bond), depositAmount);

        // Verify final debt = initial debt + additional mint amount
        assertEq(srub.balanceOf(user1), (80 * 2 * depositAmount * oracle.getPriceFeed(address(bond)).lastPrice) / 100);

        assertEq(srub.getUserDebt(user1), initialDebtAmount * 2);

        bond2.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond2), depositAmount);

        vm.stopPrank();

        // Verify final debt = initial debt + additional mint amount

        assertEq(
            srub.balanceOf(user1),
            80 * (depositAmount * oracle.getPriceFeed(address(bond2)).lastPrice) / 100
                + 80 * (2 * depositAmount * oracle.getPriceFeed(address(bond)).lastPrice) / 100
        );
    }

    function testDecreasePosition() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;
        uint256 withdrawAmount = depositAmount / 2; // Withdraw half of the collateral

        vm.startPrank(user1);

        // Setup initial position
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);

        // Get debt amount after deposit (which now includes auto-minted sRUB)
        uint256 initialDebtAmount = srub.getUserDebt(user1);
        console.log("Initial debt after deposit:", initialDebtAmount);

        // Get initial collateral amount
        uint256 initialCollateral = srub.getUserCollateralAmount(user1, address(bond));

        // Preview how much sRUB will need to be burned
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(bond), withdrawAmount);
        assertTrue(canWithdraw, "Should be able to withdraw");
        console.log("sRUB to burn for withdrawal:", sRUBToBurn);

        // Decrease position by withdrawing half the collateral
        srub.decreasePosition(address(bond), withdrawAmount);

        // Verify final state
        assertEq(srub.getUserDebt(user1), initialDebtAmount - sRUBToBurn);
        assertEq(srub.balanceOf(user1), initialDebtAmount - sRUBToBurn);
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), initialCollateral - withdrawAmount);

        // Verify the collateral was returned to the user
        assertEq(bond.balanceOf(user1), 1_000_000_000 - depositAmount + withdrawAmount);

        vm.stopPrank();
    }

    function testDecreasePositionToZero() public {
        uint256 depositAmount = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);

        // Setup initial position
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);

        // Get debt amount after deposit (auto-minted)
        uint256 initialDebtAmount = srub.getUserDebt(user1);
        console.log("Initial debt after deposit:", initialDebtAmount);

        // Make sure some sRUB was minted
        assertGt(initialDebtAmount, 0, "No sRUB was auto-minted");

        // Preview withdrawal of all collateral
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(bond), depositAmount);
        assertTrue(canWithdraw, "Should be able to withdraw all collateral");

        // The amount of sRUB to burn should approximately equal the initial debt
        assertApproxEqRel(sRUBToBurn, initialDebtAmount, 0.01e18); // 1% tolerance

        // Decrease position completely by withdrawing all collateral
        srub.decreasePosition(address(bond), depositAmount);

        // Verify final state - debt should be zero or close to zero
        assertLe(srub.getUserDebt(user1), 1); // Allow for dust (rounding errors)
        assertLe(srub.balanceOf(user1), 1);
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), 0);

        // All collateral should be returned
        assertEq(bond.balanceOf(user1), 1_000_000_000);

        vm.stopPrank();
    }

    function testDecreasePositionWithMultipleCollaterals() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;
        uint256 withdrawAmount = depositAmount1 / 2; // Withdraw half of the first collateral

        vm.startPrank(user1);

        // Deposit first collateral - this will auto-mint some sRUB
        bond.approve(address(srub), depositAmount1);
        srub.depositCollateral(address(bond), depositAmount1);
        uint256 firstMintAmount = srub.getUserDebt(user1);
        console.log("Auto-minted sRUB after first deposit:", firstMintAmount);

        // Deposit second collateral - this will auto-mint more sRUB
        bond2.approve(address(srub), depositAmount2);
        srub.depositCollateral(address(bond2), depositAmount2);
        uint256 totalAutoMinted = srub.getUserDebt(user1);
        console.log("Total auto-minted sRUB after both deposits:", totalAutoMinted);
        console.log("Auto-minted from second deposit:", totalAutoMinted - firstMintAmount);

        // Check if collateral value is sufficient
        uint256 collateralValue = srub.getTotalCollateralValue(user1);
        console.log("Total collateral value:", collateralValue);

        // Store initial collateral amounts
        uint256 initialCollateral1 = srub.getUserCollateralAmount(user1, address(bond));
        uint256 initialCollateral2 = srub.getUserCollateralAmount(user1, address(bond2));

        // Preview how much sRUB will need to be burned
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(bond), withdrawAmount);
        assertTrue(canWithdraw, "Should be able to withdraw partial collateral");
        console.log("sRUB to burn for withdrawal:", sRUBToBurn);

        // Decrease position by withdrawing part of the first collateral
        srub.decreasePosition(address(bond), withdrawAmount);

        // Verify debt and balance decreased
        assertEq(srub.getUserDebt(user1), totalAutoMinted - sRUBToBurn);
        assertEq(srub.balanceOf(user1), totalAutoMinted - sRUBToBurn);

        // Verify first collateral decreased and second remains unchanged
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), initialCollateral1 - withdrawAmount);
        assertEq(srub.getUserCollateralAmount(user1, address(bond2)), initialCollateral2);

        // Verify the first collateral was returned to the user
        assertEq(bond.balanceOf(user1), 1_000_000_000 - depositAmount1 + withdrawAmount);

        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawingMoreThanAvailable() public {
        uint256 depositAmount = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);

        // Setup initial position
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);

        // Attempt to withdraw more collateral than available
        uint256 excessiveWithdrawAmount = depositAmount * 2;

        // Expect the transaction to revert with InvalidAmount error
        vm.expectRevert(ISyntheticRubble.InsufficientCollateral.selector);

        // This should revert because withdrawAmount > collateral amount
        srub.decreasePosition(address(bond), excessiveWithdrawAmount);

        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawingWouldMakePositionUnsafe() public {
        uint256 depositAmount1 = COLLATERAL_AMOUNT;
        uint256 depositAmount2 = COLLATERAL_AMOUNT_LARGE;

        vm.startPrank(user1);

        // Deposit both collaterals
        bond.approve(address(srub), depositAmount1);
        srub.depositCollateral(address(bond), depositAmount1);

        bond2.approve(address(srub), depositAmount2);
        srub.depositCollateral(address(bond2), depositAmount2);

        uint256 totalDebt = srub.getUserDebt(user1);
        console.log("Total debt:", totalDebt);

        // Advance time by 1 hour to allow oracle update
        vm.stopPrank();
        vm.warp(block.timestamp + 1 hours);

        // Drastically reduce bond price to simulate a price crash
        vm.startPrank(admin);
        oracle.updatePriceFeed(address(bond), BOND_PRICE / 10); // 90% price drop for bond1
        vm.stopPrank();

        vm.startPrank(user1);

        // Now try to withdraw all of bond2, which should make the position unhealthy
        // since bond1's value has dropped drastically
        console.log("Attempting to withdraw all of bond2 after price crash");

        // Check position health before withdrawal
        uint256 healthBefore = srub.getPositionHealth(user1);
        console.log("Health factor before withdrawal:", healthBefore);

        // Preview the withdrawal
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(bond2), depositAmount2);
        console.log("Can withdraw:", canWithdraw);
        console.log("sRUB to burn:", sRUBToBurn);

        // Should revert since the remaining position would be unhealthy
        vm.expectRevert(ISyntheticRubble.InsufficientCollateral.selector);
        srub.decreasePosition(address(bond2), depositAmount2);

        vm.stopPrank();
    }

    function testSimpleDepositAndIncrease() public {
        // Create a very large bond price to avoid division issues
        uint160 testBondPrice = 1e17; // Much higher price

        // Set a higher bond price for this test
        vm.startPrank(admin);
        // Add vm.warp to allow price update
        vm.warp(block.timestamp + 1 hours);
        oracle.updatePriceFeed(address(bond), testBondPrice);
        vm.stopPrank();

        // Verify the price was updated correctly
        vm.startPrank(user1);
        uint160 actualPrice = oracle.getPriceFeed(address(bond)).lastPrice;
        console.log("Actual bond price after update:", actualPrice);
        assertEq(actualPrice, testBondPrice, "Bond price was not updated correctly");

        if (actualPrice != testBondPrice) {
            // If price wasn't updated, skip the test
            console.log("Price not updated, skipping test");
            vm.stopPrank();
            return;
        }

        // Use larger values to ensure we get a non-zero collateral value
        uint256 depositAmount = 1_000_000_000; // 1 billion

        vm.startPrank(user1);

        // Approve tokens
        bond.approve(address(srub), depositAmount);

        // Print diagnostics before the call
        console.log("Bond price:", oracle.getPriceFeed(address(bond)).lastPrice);

        // Manually calculate expected collateral value
        uint256 expectedCollateralValue = (depositAmount * testBondPrice) / 1e18;
        console.log("Expected collateral value:", expectedCollateralValue);
        console.log("Expected auto-mint (80%):", (expectedCollateralValue * 80) / 100);

        // Deposit and increase
        srub.depositCollateral(address(bond), depositAmount);

        // Check final state
        uint256 actualDebt = srub.getUserDebt(user1);
        console.log("Actual debt:", actualDebt);

        // Basic verification
        assertGt(actualDebt, 0, "Should have minted some sRUB");
        assertEq(srub.balanceOf(user1), actualDebt);
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), depositAmount);

        vm.stopPrank();
    }

    function testIncreasePositionRevertsOnInvalidCollateral() public {
        // Use a random address as invalid collateral
        address invalidCollateral = makeAddr("invalidCollateral");
        uint256 collateralAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);

        // Try to increase position with invalid collateral
        vm.expectRevert();
        srub.depositCollateral(invalidCollateral, collateralAmount);

        vm.stopPrank();
    }

    function testDecimals() public view {
        assertEq(srub.decimals(), 6);
    }

    function testLiquidation() public {
        // Set up a position for user1
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);

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
        srub.depositCollateral(address(bond), depositAmount * 3);
        uint256 srubAmount = srub.balanceOf(user2);
        console.log("User2 sRUB balance:", srubAmount);

        // Get user2's bond balance before liquidation
        uint256 bondBalanceBefore = bond.balanceOf(user2);
        console.log("User2 bond balance before liquidation:", bondBalanceBefore);

        // Liquidate user1's position
        srub.liquidatePosition(user1, address(bond));

        // Verify liquidation results
        // 1. User1's position should be cleared
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), 0);

        // 2. User2 should receive liquidation reward
        uint256 bondBalanceAfter = bond.balanceOf(user2);
        console.log("User2 bond balance after liquidation:", bondBalanceAfter);

        // Calculate reward (90% of the collateral)
        uint256 liquidatorReward = depositAmount * (100 - srub.LIQUIDATION_PENALTY()) / 100;
        console.log("Expected liquidator reward:", liquidatorReward);

        // Verify user2 received the reward
        assertEq(bondBalanceAfter - bondBalanceBefore, liquidatorReward);

        vm.stopPrank();
    }

    function testLiquidationRevertsForHealthyPosition() public {
        // Set up a position for user1
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);
        vm.stopPrank();

        // Position should be healthy
        uint256 healthFactor = srub.getPositionHealth(user1);
        console.log("Health factor:", healthFactor);
        assertGe(healthFactor, srub.LIQUIDATION_THRESHOLD());

        // Attempt to liquidate healthy position
        vm.startPrank(user2);
        vm.expectRevert(ISyntheticRubble.PositionNotLiquidatable.selector);
        srub.liquidatePosition(user1, address(bond));
        vm.stopPrank();
    }

    function testLiquidationRevertsForNonexistentCollateral() public {
        // Set up a position for user1 with only bond as collateral
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);
        vm.stopPrank();

        // Make position liquidatable
        vm.warp(block.timestamp + 1 hours);

        vm.startPrank(admin);
        oracle.updatePriceFeed(address(bond), BOND_PRICE / 3); // 66% price drop
        vm.stopPrank();

        // Attempt to liquidate using bond2 which user1 doesn't have
        vm.startPrank(user2);
        vm.expectRevert(ISyntheticRubble.CollateralNotFound.selector);
        srub.liquidatePosition(user1, address(bond2));
        vm.stopPrank();
    }

    function testPreviewDecreaseFailureCases() public {
        uint256 depositAmount = COLLATERAL_AMOUNT;

        vm.startPrank(user1);
        // Setup a position with only bond collateral
        bond.approve(address(srub), depositAmount);
        srub.depositCollateral(address(bond), depositAmount);

        // Case 1: Check non-existent collateral returns false
        (bool canWithdraw1, uint256 sRUBToBurn1) = srub.previewDecrease(address(bond2), 1000);
        assertFalse(canWithdraw1, "Should return false for non-existent collateral");
        assertEq(sRUBToBurn1, 0, "sRUBToBurn should be 0 for non-existent collateral");

        // Case 2: Check excessive withdrawal amount returns false
        uint256 excessiveAmount = depositAmount * 2; // More than deposited
        (bool canWithdraw2, uint256 sRUBToBurn2) = srub.previewDecrease(address(bond), excessiveAmount);
        assertFalse(canWithdraw2, "Should return false for excessive withdrawal");
        assertEq(sRUBToBurn2, 0, "sRUBToBurn should be 0 for excessive withdrawal");

        // Case 3: Check unhealthy position after withdrawal returns false
        // First, make the position close to unhealthy by manipulating collateral price
        vm.stopPrank();

        vm.warp(block.timestamp + 1 hours);

        vm.startPrank(admin);
        // Reduce price so the position will be close to unhealthy
        uint160 newPrice = uint160(BOND_PRICE * 5 / 6); // Drop price by ~17%
        oracle.updatePriceFeed(address(bond), newPrice);
        vm.stopPrank();

        vm.startPrank(user1);

        // Preview a withdrawal that would make the position unhealthy
        uint256 borderlineAmount = depositAmount * 20 / 100; // 20% of deposit
        (bool canWithdraw3, uint256 sRUBToBurn3) = srub.previewDecrease(address(bond), borderlineAmount);

        // This should return false as the withdrawal would make position unhealthy
        assertFalse(canWithdraw3, "Should return false for unhealthy withdrawal");
        assertGt(sRUBToBurn3, 0, "sRUBToBurn should be calculated even if withdrawal is unhealthy");

        vm.stopPrank();
    }

    function testDepositAndIncrease() public {
        // Use a larger amount to ensure sufficient collateral
        uint256 collateralAmount = COLLATERAL_AMOUNT_LARGE; // 50 million

        vm.startPrank(user1);

        // Print initial conditions
        uint256 bondPrice = oracle.getPriceFeed(address(bond)).lastPrice;
        console.log("Bond price:", bondPrice);

        // Check initial state
        assertEq(srub.getUserDebt(user1), 0);
        assertEq(srub.balanceOf(user1), 0);

        // Approve tokens
        bond.approve(address(srub), collateralAmount);

        // Calculate expected collateral value before deposit
        uint256 expectedCollateralValue = (collateralAmount * bondPrice) / 1e18;
        console.log("Expected collateral value:", expectedCollateralValue);

        // Deposit and mint in one transaction
        srub.depositCollateral(address(bond), collateralAmount);

        // Calculate how much should be auto-minted (80% of collateral value)
        uint256 collateralValue = srub.getCollateralTokenValue(address(bond), collateralAmount);
        console.log("Actual collateral value:", collateralValue);

        uint256 expectedAutoMint = (collateralValue * 80) / 100;

        // Total expected debt: auto-minted
        uint256 expectedTotalMint = expectedAutoMint;

        // Log values
        console.log("Auto-minted sRUB:", expectedAutoMint);
        console.log("Total minted sRUB:", expectedTotalMint);
        console.log("Actual debt:", srub.getUserDebt(user1));

        // Verify
        assertEq(srub.getUserDebt(user1), expectedTotalMint);
        assertEq(srub.balanceOf(user1), expectedTotalMint);
        assertEq(srub.getUserCollateralAmount(user1, address(bond)), collateralAmount);

        vm.stopPrank();
    }

    function testWithdrawAfterBondMaturity() public {
        // Calculate a near-term maturity date
        uint40 maturityTime = uint40(block.timestamp + 30 days);

        // Create a bond with 30-day maturity
        vm.startPrank(issuer);
        address shortBondAddress = factory.issueBond("Short Term Bond", 1000 * 1e6, 2000 * 1e6, maturityTime);
        BondToken shortBond = BondToken(shortBondAddress);

        // Mint to user1
        shortBond.mint(user1, COLLATERAL_AMOUNT);
        vm.stopPrank();

        // Set price for the new bond
        vm.startPrank(admin);
        oracle.updatePriceFeed(address(shortBond), BOND_PRICE);
        vm.stopPrank();

        // User deposits the short-term bond
        vm.startPrank(user1);
        shortBond.approve(address(srub), COLLATERAL_AMOUNT);
        srub.depositCollateral(address(shortBond), COLLATERAL_AMOUNT);

        // Check that deposit was successful
        assertEq(srub.getUserCollateralAmount(user1, address(shortBond)), COLLATERAL_AMOUNT);
        uint256 debtBefore = srub.getUserDebt(user1);
        console.log("Initial debt:", debtBefore);

        // Fast forward past maturity date
        vm.warp(maturityTime + 1 days);

        // Update the oracle for the matured bond
        vm.stopPrank();
        vm.startPrank(admin);
        // After maturity, the bond should be worth its face value (redemption value)
        oracle.updatePriceFeed(address(shortBond), BOND_PRICE); // Price might change or stay the same after maturity
        vm.stopPrank();

        // User withdraws the matured bond
        vm.startPrank(user1);

        // Preview the decrease first
        (bool canWithdraw, uint256 sRUBToBurn) = srub.previewDecrease(address(shortBond), COLLATERAL_AMOUNT);
        assertTrue(canWithdraw, "Should be able to withdraw matured bond");
        console.log("sRUB to burn for withdrawal:", sRUBToBurn);

        // Withdraw the matured bond
        uint256 userBalanceBefore = shortBond.balanceOf(user1);
        srub.decreasePosition(address(shortBond), COLLATERAL_AMOUNT);
        uint256 userBalanceAfter = shortBond.balanceOf(user1);

        // Verify the withdrawal was successful
        assertEq(userBalanceAfter - userBalanceBefore, COLLATERAL_AMOUNT, "User should receive matured bond");
        assertEq(srub.getUserCollateralAmount(user1, address(shortBond)), 0, "No bond should remain in position");
        assertEq(srub.getUserDebt(user1), debtBefore - sRUBToBurn, "Debt should be reduced by burned amount");

        // Check that the collateral token was removed from user's list
        address[] memory collaterals = srub.getUserCollaterals(user1);
        for (uint256 i = 0; i < collaterals.length; i++) {
            assertTrue(collaterals[i] != address(shortBond), "Matured bond should be removed from collateral list");
        }

        vm.stopPrank();
    }

    function testMaxCollateralTokensLimit() public {
        // Create exactly 2 bond tokens (we'll use these to test the limit)
        vm.startPrank(issuer);
        uint256 maxCollateralTokens = srub.MAX_COLLATERAL_TOKENS();
        // Create first bond and mint to user1
        address bond1 = factory.issueBond("Test Bond 1", 1000 * 1e6, 2000 * 1e6, uint40(block.timestamp + 365 days));
        BondToken(bond1).mint(user1, COLLATERAL_AMOUNT * 100);

        // Create 10 more bonds to reach the limit (plus the first one = 11 total)
        address[] memory extraBonds = new address[](maxCollateralTokens);
        for (uint256 i = 0; i < maxCollateralTokens; i++) {
            string memory name = string(abi.encodePacked("Extra Bond ", i + 1));
            extraBonds[i] = factory.issueBond(name, 1000 * 1e6, 2000 * 1e6, uint40(block.timestamp + 365 days));
            BondToken(extraBonds[i]).mint(user1, COLLATERAL_AMOUNT);
        }
        vm.stopPrank();

        // Set prices for all bonds
        vm.startPrank(admin);
        oracle.updatePriceFeed(bond1, BOND_PRICE);
        for (uint256 i = 0; i < maxCollateralTokens; i++) {
            // Advance time to allow oracle updates
            vm.warp(block.timestamp + 1 hours);
            oracle.updatePriceFeed(extraBonds[i], BOND_PRICE);
        }
        vm.stopPrank();

        // Now try to deposit all bonds as user1
        vm.startPrank(user1);

        // Deposit first 10 bonds (reaching the MAX_COLLATERAL_TOKENS limit)
        BondToken(bond1).approve(address(srub), COLLATERAL_AMOUNT);
        srub.depositCollateral(bond1, COLLATERAL_AMOUNT);

        for (uint256 i = 0; i < maxCollateralTokens - 1; i++) {
            BondToken(extraBonds[i]).approve(address(srub), COLLATERAL_AMOUNT);
            srub.depositCollateral(extraBonds[i], COLLATERAL_AMOUNT);
            console.log("Deposited bond", i);
        }

        // Verify we've reached the limit (10 tokens)
        address[] memory collaterals = srub.getUserCollaterals(user1);
        assertEq(collaterals.length, maxCollateralTokens, "Should have 10 collateral tokens");

        // Try to add one more - should revert with TooManyCollateralTokens
        BondToken(extraBonds[maxCollateralTokens - 1]).approve(address(srub), COLLATERAL_AMOUNT);
        vm.expectRevert(ISyntheticRubble.TooManyCollateralTokens.selector);
        srub.depositCollateral(extraBonds[maxCollateralTokens - 1], COLLATERAL_AMOUNT);

        // But we should still be able to deposit more of an existing collateral
        BondToken(bond1).approve(address(srub), COLLATERAL_AMOUNT);
        uint256 beforeAmount = srub.getUserCollateralAmount(user1, bond1);
        srub.depositCollateral(bond1, COLLATERAL_AMOUNT);
        uint256 afterAmount = srub.getUserCollateralAmount(user1, bond1);

        // Verify amount increased but token count didn't change
        assertGt(afterAmount, beforeAmount, "Collateral amount should increase");
        collaterals = srub.getUserCollaterals(user1);
        assertEq(collaterals.length, maxCollateralTokens, "Should still have MAX_COLLATERAL_TOKENS collateral tokens");

        vm.stopPrank();
    }
}
