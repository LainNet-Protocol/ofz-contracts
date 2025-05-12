// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IBondOracle.sol";
import "./interfaces/IBondFactory.sol";
import "./interfaces/ISoulBoundIdentityNFT.sol";
import "./BondToken.sol";

contract BondFactory is IBondFactory, AccessControl {
    bytes32 public constant BOND_ISSUER_ROLE = keccak256("BOND_ISSUER_ROLE");

    address public BOND_ORACLE;
    address public IDENTITY_NFT;

    mapping(address => BondDetails) internal bonds;

    constructor(address initialIssuer) {
        if (initialIssuer == address(0)) {
            revert InvalidAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BOND_ISSUER_ROLE, initialIssuer);
    }

    function setDependencies(address _bondOracle, address _identityNFT) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (BOND_ORACLE != address(0) || IDENTITY_NFT != address(0)) {
            revert DependenciesAlreadySet();
        }
        if (_bondOracle == address(0) || _identityNFT == address(0)) {
            revert InvalidAddress();
        }

        BOND_ORACLE = _bondOracle;
        IDENTITY_NFT = _identityNFT;

        emit DependenciesSet(_bondOracle, _identityNFT);
    }

    function getBondDetails(address bondAddress)
        external
        view
        returns (string memory name, uint160 initialPrice, uint160 maturityPrice, uint40 maturityAt)
    {
        BondDetails memory details = bonds[bondAddress];
        return (details.name, details.initialPrice, details.maturityPrice, details.maturityAt);
    }

    function issueBond(string memory name, uint160 initialPrice, uint160 maturityPrice, uint40 maturityAt)
        external
        onlyRole(BOND_ISSUER_ROLE)
        returns (address)
    {
        if (BOND_ORACLE == address(0) || IDENTITY_NFT == address(0)) {
            revert DependenciesNotSet();
        }

        if (maturityAt <= block.timestamp) {
            revert InvalidMaturityTime();
        }

        if (initialPrice == 0 || maturityPrice == 0) {
            revert InvalidPrice();
        }

        string memory symbol = string(abi.encodePacked("BOND-", name));

        // Disallows creating multiple bonds with the same name
        bytes32 salt = keccak256(abi.encode(name));
        BondToken bond = new BondToken{salt: salt}(name, symbol, maturityPrice, maturityAt);

        // Store bond details
        bonds[address(bond)] =
            BondDetails({name: name, initialPrice: initialPrice, maturityPrice: maturityPrice, maturityAt: maturityAt});

        // Create price feed in oracle
        IBondOracle(BOND_ORACLE).addPriceFeed(address(bond), uint40(initialPrice), maturityAt);

        emit BondCreated(address(bond), name, initialPrice, maturityPrice, maturityAt);

        return address(bond);
    }
}
