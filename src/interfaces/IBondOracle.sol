// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IBondOracle is IAccessControl {
    struct BondInfo {
        uint160 lastPrice;
        uint40 lastUpdated;
        uint40 maturityAt;
    }

    error InvalidAddress();
    error InvalidSignature();
    error InvalidLength();
    error SignatureExpired();
    error SignatureAlreadyUsed();
    error InvalidNonce();

    error NonExistentPriceFeed();
    error UnknownBond();
    error OnlyBondFactory();
    error SecidNotRegistered();

    event PriceFeedAdded(address indexed feed, uint160 price, uint40 timestamp, uint40 maturityAt);
    event PriceFeedUpdated(address indexed feed, uint160 price, uint40 timestamp);
    event SecidMappingRegistered(string indexed secid, address indexed bondToken);

    function PRICE_FEED_UPDATER_ROLE() external view returns (bytes32);

    function addPriceFeed(address _asset, uint40 initialPrice, uint40 maturityAt) external;
    function updatePriceFeed(address _feed, uint160 _price) external;
    function updateMultiplePriceFeeds(address[] calldata _feeds, uint160[] calldata _prices) external;

    function updatePriceFeedWithSignature(
        string calldata _secid,
        uint160 _price,
        uint256 _deadline,
        uint256 _nonce,
        bytes calldata _signature
    ) external;

    function getNonce(address signer) external view returns (uint256);
    function getPriceFeed(address _feed) external view returns (BondInfo memory);
    function getPriceFeeds(address[] calldata _feeds) external view returns (BondInfo[] memory);
}
