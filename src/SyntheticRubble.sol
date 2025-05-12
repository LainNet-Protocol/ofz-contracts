// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBondOracle.sol";
import "./interfaces/ISyntheticRubble.sol";

/**
 * @title Synthetic Ruble (sRUB)
 * @dev A synthetic stablecoin pegged to the Russian Ruble
 * @notice This token uses 6 decimals to match the standard stablecoin format
 */
contract SyntheticRubble is ERC20, ISyntheticRubble {
    using SafeERC20 for IERC20;

    // Constants
    IBondOracle public immutable oracle;
    uint256 public constant COLLATERALIZATION_RATIO = 125; // 125%
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120%
    uint256 public constant LIQUIDATION_PENALTY = 10; // 10%
    uint256 public constant MAX_COLLATERAL_TOKENS = 11; // Maximum number of different collateral tokens per position
    uint256 public lastUpdateTimestamp;

    mapping(address => UserPosition) public userPositions;

    constructor(address _oracle) ERC20("Synthetic Ruble", "sRUB") {
        oracle = IBondOracle(_oracle);
        lastUpdateTimestamp = block.timestamp;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function depositCollateral(address collateral, uint256 amount) external {
        // Check if collateral is accepted by verifying it exists in the oracle
        IBondOracle.BondInfo memory bondInfo = oracle.getPriceFeed(collateral);
        if (bondInfo.maturityAt == 0) revert InvalidCollateral();

        UserPosition storage position = userPositions[msg.sender];

        // If this is a new collateral type for this user, check if they've reached the limit
        if (position.collateralAmounts[collateral] == 0) {
            // Check if adding another token would exceed the maximum
            if (position.collateralTokens.length == MAX_COLLATERAL_TOKENS) {
                revert TooManyCollateralTokens();
            }
            // First time depositing this collateral
            position.collateralTokens.push(collateral);
        }

        // Transfer tokens after validation to avoid unnecessary transfers on error
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

        position.collateralAmounts[collateral] += amount;

        emit CollateralDeposited(msg.sender, collateral, amount);

        // Calculate sRUB amount to mint based on collateral value
        uint256 collateralValue = getCollateralTokenValue(collateral, amount);

        // Mint at most 80% of collateral value (significantly less than 150% ratio)
        // This leaves room for users to increase their position later
        uint256 mintAmount = (collateralValue * 80) / 100;

        if (mintAmount > 0) {
            // Update debt position
            position.debtAmount += mintAmount;
            // Mint sRUB tokens
            _mint(msg.sender, mintAmount);

            emit PositionIncreased(msg.sender, mintAmount);
        }
    }

    function decreasePosition(address collateral, uint256 amount) external {
        UserPosition storage position = userPositions[msg.sender];
        if (amount > position.collateralAmounts[collateral]) revert InsufficientCollateral();
        // Use previewDecrease to check if withdrawal is possible and get sRUB amount to burn
        (bool canWithdraw, uint256 sRUBToBurn) = previewDecrease(collateral, amount);

        if (!canWithdraw) revert InsufficientCollateral();
        if (balanceOf(msg.sender) < sRUBToBurn) revert InvalidAmount();

        // Update position data
        position.debtAmount -= sRUBToBurn;
        position.collateralAmounts[collateral] -= amount;

        // Remove collateral token from list if fully withdrawn
        if (position.collateralAmounts[collateral] == 0) {
            removeCollateralToken(msg.sender, collateral);
        }

        // Burn sRUB tokens
        _burn(msg.sender, sRUBToBurn);

        // Transfer collateral back to user
        IERC20(collateral).safeTransfer(msg.sender, amount);

        emit PositionDecreased(msg.sender, sRUBToBurn);
        emit CollateralWithdrawn(msg.sender, collateral, amount);
    }

    function liquidatePosition(address user, address collateral) external {
        UserPosition storage position = userPositions[user];

        if (position.collateralAmounts[collateral] == 0) {
            revert CollateralNotFound();
        }

        uint256 totalCollateralValue = getTotalCollateralValue(user);
        uint256 debtValue = position.debtAmount;

        if (totalCollateralValue >= (debtValue * LIQUIDATION_THRESHOLD) / 100) {
            revert PositionNotLiquidatable();
        }

        uint256 collateralAmount = position.collateralAmounts[collateral];
        uint256 collateralValue = getCollateralTokenValue(collateral, collateralAmount);

        // Calculate liquidation penalty
        uint256 penaltyAmount = (collateralAmount * LIQUIDATION_PENALTY) / 100;
        uint256 liquidatorReward = collateralAmount - penaltyAmount;

        // Calculate how much debt to reduce based on collateral value
        uint256 debtToCover = (collateralValue * position.debtAmount) / totalCollateralValue;

        // Transfer collateral to liquidator
        IERC20(collateral).safeTransfer(msg.sender, liquidatorReward);

        // Burn liquidator's sRUB equal to the debt covered
        if (debtToCover > 0) {
            _burn(msg.sender, debtToCover);
            position.debtAmount -= debtToCover;
        }

        // Remove this collateral
        position.collateralAmounts[collateral] = 0;
        removeCollateralToken(user, collateral);

        emit PositionLiquidated(user, msg.sender, collateral, collateralAmount, debtToCover);
    }

    function removeCollateralToken(address user, address collateral) internal {
        UserPosition storage position = userPositions[user];
        for (uint256 i = 0; i < position.collateralTokens.length; i++) {
            if (position.collateralTokens[i] == collateral) {
                // Replace the item to remove with the last item
                if (i < position.collateralTokens.length - 1) {
                    position.collateralTokens[i] = position.collateralTokens[position.collateralTokens.length - 1];
                }
                // Remove the last item
                position.collateralTokens.pop();
                break;
            }
        }
    }

    function getCollateralTokenValue(address collateral, uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;

        IBondOracle.BondInfo memory bondInfo = oracle.getPriceFeed(collateral);
        if (bondInfo.maturityAt == 0) revert InvalidCollateral();
        return (amount * bondInfo.lastPrice);
    }

    function getTotalCollateralValue(address user) public view returns (uint256) {
        UserPosition storage position = userPositions[user];
        uint256 totalValue = 0;

        for (uint256 i = 0; i < position.collateralTokens.length; i++) {
            address token = position.collateralTokens[i];
            uint256 amount = position.collateralAmounts[token];
            totalValue += getCollateralTokenValue(token, amount);
        }

        return totalValue;
    }

    function getPositionHealth(address user) external view returns (uint256) {
        UserPosition storage position = userPositions[user];
        if (position.debtAmount == 0) return type(uint256).max;

        uint256 totalCollateralValue = getTotalCollateralValue(user);
        return (totalCollateralValue * 100) / position.debtAmount;
    }

    function getUserCollaterals(address user) external view returns (address[] memory) {
        return userPositions[user].collateralTokens;
    }

    function getUserCollateralAmount(address user, address collateral) external view returns (uint256) {
        return userPositions[user].collateralAmounts[collateral];
    }

    function getUserDebt(address user) external view returns (uint256) {
        return userPositions[user].debtAmount;
    }

    function previewDecrease(address collateral, uint256 amount)
        public
        view
        returns (bool canWithdraw, uint256 sRUBToBurn)
    {
        UserPosition storage position = userPositions[msg.sender];

        // Check if user has the collateral
        if (position.collateralAmounts[collateral] == 0) {
            return (false, 0); // Collateral not found
        }

        // Check if user has enough of this collateral
        if (amount > position.collateralAmounts[collateral]) {
            return (false, 0); // Not enough collateral
        }

        // Calculate current collateral values
        uint256 totalCollateralValue = getTotalCollateralValue(msg.sender);
        uint256 withdrawnCollateralValue = getCollateralTokenValue(collateral, amount);
        uint256 remainingCollateralValue = totalCollateralValue - withdrawnCollateralValue;

        // Calculate what percentage of total collateral is being withdrawn
        uint256 collateralRatio = (withdrawnCollateralValue * 1e18) / totalCollateralValue;

        // Calculate how much debt should be repaid
        sRUBToBurn = (position.debtAmount * collateralRatio) / 1e18;

        // Calculate remaining debt
        uint256 remainingDebt = position.debtAmount - sRUBToBurn;

        // If debt will remain, check if health factor will be sufficient
        if (remainingDebt > 0) {
            // Health factor = collateral value * 100 / debt
            uint256 newHealthFactor = (remainingCollateralValue * 100) / remainingDebt;
            canWithdraw = newHealthFactor >= COLLATERALIZATION_RATIO;
        } else {
            canWithdraw = true; // If no debt remains, withdrawal is allowed
        }

        return (canWithdraw, sRUBToBurn);
    }
}
