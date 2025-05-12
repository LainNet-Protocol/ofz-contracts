// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ISoulBoundIdentityNFT is IERC721 {
    event SubAccountAdded(address indexed tokenOwner, address subAccount);
    event SubAccountRemoved(address indexed tokenOwner, address subAccount);

    function mint(address to, uint40 expiration) external;
    function revoke(address to) external;
    function addSubAccount(address subAccount) external;
    function removeSubAccount(address subAccount) external;
    function isWhitelisted(address account) external view returns (bool, address mainAccount, uint40 expiration);
    function getSubAccounts() external view returns (address[] memory);
    function getSubAccounts(address mainAccount) external view returns (address[] memory);
}
