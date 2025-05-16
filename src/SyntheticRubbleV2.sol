// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBondOracle.sol";

/**
 * @title Synthetic Ruble V2 (sRUB)
 * @dev A synthetic stablecoin pegged to the Russian Ruble with improved function interface
 * @notice This token uses 6 decimals to match the standard stablecoin format
 */
contract SyntheticRubbleV2 is ERC20 {
    using SafeERC20 for IERC20;

    // Errors
    error InvalidCollateral();
    error InsufficientCollateral();
    error PositionNotLiquidatable();
    error InvalidAmount();
    error CollateralNotFound();
    error TooManyCollateralTokens();

    // Events
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed collateral, uint256 amount);
    event PositionIncreased(address indexed user, uint256 amount);
    event PositionDecreased(address indexed user, uint256 amount);
    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        address collateral,
        uint256 collateralAmount,
        uint256 debtAmount
    );

    // User position struct
    struct UserPosition {
        uint256 debtAmount;
        address[] collateralTokens;
        mapping(address => uint256) collateralAmounts;
    }

    // Constants
    IBondOracle public immutable oracle;

    // Using BIPS (basis points) instead of percentages
    // 1% = 100 BIPS, so 125% = 12500 BIPS
    uint256 public constant COLLATERALIZATION_RATIO = 12500; // 125% in BIPS
    uint256 public constant LIQUIDATION_THRESHOLD = 12000; // 120% in BIPS
    uint256 public constant LIQUIDATION_PENALTY = 1000; // 10% in BIPS
    uint256 public constant MAX_COLLATERAL_TOKENS = 11; // Maximum number of different collateral tokens per position
    uint256 public constant BIPS_PRECISION = 10000; // 100% in BIPS
    uint256 public constant MAX_LTV = 8000; // 80% in BIPS
    uint256 public lastUpdateTimestamp;

    mapping(address => UserPosition) public userPositions;

    constructor(address _oracle) ERC20("Synthetic Ruble", "sRUB") {
        oracle = IBondOracle(_oracle);
        lastUpdateTimestamp = block.timestamp;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function supply(address collateral, uint256 amount) external {
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
    }

    function borrow(uint256 amount) external {
        UserPosition storage position = userPositions[msg.sender];

        // Get total collateral value
        uint256 totalCollateralValue = getTotalCollateralValue(msg.sender);

        // Calculate maximum borrowable amount (80% of collateral value)
        uint256 maxBorrow = (totalCollateralValue * MAX_LTV) / BIPS_PRECISION;

        // Calculate new debt after this borrow
        uint256 newDebtAmount = position.debtAmount + amount;

        // Ensure borrowing doesn't exceed maximum LTV
        if (newDebtAmount > maxBorrow) revert InsufficientCollateral();

        // Ensure minimum collateralization ratio is maintained
        uint256 newHealthFactor = (totalCollateralValue * BIPS_PRECISION) / newDebtAmount;
        if (newHealthFactor < COLLATERALIZATION_RATIO) revert InsufficientCollateral();

        // Update debt position
        position.debtAmount = newDebtAmount;

        // Mint sRUB tokens to borrower
        _mint(msg.sender, amount);

        emit PositionIncreased(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        UserPosition storage position = userPositions[msg.sender];

        // Ensure user has debt to repay
        if (position.debtAmount == 0) revert InvalidAmount();

        // Limit repayment to existing debt amount
        uint256 repayAmount = amount > position.debtAmount ? position.debtAmount : amount;

        // Ensure user has enough sRUB to repay
        if (balanceOf(msg.sender) < repayAmount) revert InvalidAmount();

        // Update debt position
        position.debtAmount -= repayAmount;

        // Burn sRUB tokens
        _burn(msg.sender, repayAmount);

        emit PositionDecreased(msg.sender, repayAmount);
    }

    function withdraw(address collateral, uint256 amount) external {
        UserPosition storage position = userPositions[msg.sender];

        // Check if user has the collateral
        if (position.collateralAmounts[collateral] == 0) revert CollateralNotFound();

        // Check if user has enough of this collateral
        if (amount > position.collateralAmounts[collateral]) revert InsufficientCollateral();

        // Calculate current and future position health
        uint256 totalCollateralValue = getTotalCollateralValue(msg.sender);
        uint256 withdrawCollateralValue = getCollateralTokenValue(collateral, amount);
        uint256 remainingCollateralValue = totalCollateralValue - withdrawCollateralValue;

        // If user has debt, check if position will remain healthy after withdrawal
        if (position.debtAmount > 0) {
            // Calculate health factor after withdrawal
            uint256 newHealthFactor = (remainingCollateralValue * BIPS_PRECISION) / position.debtAmount;

            // Ensure position remains healthy
            if (newHealthFactor < COLLATERALIZATION_RATIO) revert InsufficientCollateral();
        }

        // Update collateral amount
        position.collateralAmounts[collateral] -= amount;

        // Remove collateral token from list if fully withdrawn
        if (position.collateralAmounts[collateral] == 0) {
            removeCollateralToken(msg.sender, collateral);
        }

        // Transfer collateral back to user
        IERC20(collateral).safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, collateral, amount);
    }

    function liquidate(address user, address collateral) external {
        UserPosition storage position = userPositions[user];

        // Check if the collateral exists
        if (position.collateralAmounts[collateral] == 0) {
            revert CollateralNotFound();
        }

        // Check if position is liquidatable
        uint256 totalCollateralValue = getTotalCollateralValue(user);
        uint256 debtValue = position.debtAmount;

        // Check if health factor is below liquidation threshold
        uint256 healthFactor = (totalCollateralValue * BIPS_PRECISION) / debtValue;
        if (healthFactor >= LIQUIDATION_THRESHOLD) {
            revert PositionNotLiquidatable();
        }

        // Get collateral amount and value
        uint256 collateralAmount = position.collateralAmounts[collateral];
        uint256 collateralValue = getCollateralTokenValue(collateral, collateralAmount);

        // Calculate liquidation penalty
        uint256 penaltyAmount = (collateralAmount * LIQUIDATION_PENALTY) / BIPS_PRECISION;
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

    // Internal helper functions
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

    // View functions
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
        return (totalCollateralValue * BIPS_PRECISION) / position.debtAmount;
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
}
