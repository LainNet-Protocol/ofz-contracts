// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IBondFactory is IAccessControl {
    struct BondDetails {
        string name;
        uint160 initialPrice;
        uint160 maturityPrice;
        uint40 maturityAt;
    }

    error InvalidAddress();
    error DependenciesNotSet();
    error DependenciesAlreadySet();

    error InvalidMaturityTime();
    error InvalidPrice();

    event BondCreated(
        address indexed bondToken, string name, uint160 initialPrice, uint160 maturityPrice, uint40 maturityAt
    );

    event DependenciesSet(address indexed bondOracle, address indexed identityNFT);

    function BOND_ISSUER_ROLE() external view returns (bytes32);

    function BOND_ORACLE() external view returns (address);
    function IDENTITY_NFT() external view returns (address);

    function setDependencies(address _bondOracle, address _identityNFT) external;
    function getBondDetails(address bondAddress)
        external
        view
        returns (string memory name, uint160 initialPrice, uint160 maturityPrice, uint40 maturityAt);

    function issueBond(string memory name, uint160 initialPrice, uint160 maturityPrice, uint40 maturityAt)
        external
        returns (address);
}
