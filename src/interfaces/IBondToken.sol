// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBondToken is IERC20 {
    error NotWhitelisted();
    error NotBondIssuer();
    error InsufficientBalanceForRedeem();

    event RedeemRequested(address indexed user, uint256 amount);

    function BOND_FACTORY() external view returns (address);
    function IDENTITY_NFT() external view returns (address);

    function maturityPrice() external view returns (uint160);
    function maturityAt() external view returns (uint40);

    function requestRedeem(uint256 amount) external;
    function mint(address to, uint256 amount) external;
    function finalizeRedeem(address user, uint256 amount) external;
}
