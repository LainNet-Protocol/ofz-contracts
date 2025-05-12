// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./IBondOracle.sol";

interface ISyntheticRubble {
    struct UserPosition {
        uint256 debtAmount;
        address[] collateralTokens;
        mapping(address => uint256) collateralAmounts;
    }

    error InvalidCollateral();
    error InsufficientCollateral();
    error PositionNotLiquidatable();
    error InvalidAmount();
    error NotWhitelisted();
    error CollateralNotFound();
    error TooManyCollateralTokens();

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

    // Public variables
    function oracle() external view returns (IBondOracle);
    function COLLATERALIZATION_RATIO() external view returns (uint256);
    function LIQUIDATION_THRESHOLD() external view returns (uint256);
    function LIQUIDATION_PENALTY() external view returns (uint256);
    function MAX_COLLATERAL_TOKENS() external view returns (uint256);
    function lastUpdateTimestamp() external view returns (uint256);
    function userPositions(address user) external view returns (uint256 debtAmount);

    // Public functions
    function depositCollateral(address collateral, uint256 amount) external;
    function decreasePosition(address collateral, uint256 amount) external;
    function liquidatePosition(address user, address collateral) external;
    function getCollateralTokenValue(address collateral, uint256 amount) external view returns (uint256);
    function getTotalCollateralValue(address user) external view returns (uint256);
    function getPositionHealth(address user) external view returns (uint256);
    function getUserCollaterals(address user) external view returns (address[] memory);
    function getUserCollateralAmount(address user, address collateral) external view returns (uint256);
    function getUserDebt(address user) external view returns (uint256);
    function previewDecrease(address collateral, uint256 amount)
        external
        view
        returns (bool canWithdraw, uint256 sRUBToBurn);
}
