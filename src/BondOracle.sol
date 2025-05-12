// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IBondFactory.sol";
import "./interfaces/IBondOracle.sol";

contract BondOracle is AccessControl, IBondOracle {
    bytes32 public constant PRICE_FEED_UPDATER_ROLE = keccak256("PRICE_FEED_UPDATER_ROLE");

    // EIP-712 domain separator
    bytes32 private immutable DOMAIN_SEPARATOR;

    // EIP-712 type hashes
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public constant PRICE_UPDATE_TYPEHASH =
        keccak256("PriceUpdate(string secid,uint160 price,uint256 nonce,uint256 deadline)");

    // Track nonces per signer to prevent replay attacks
    mapping(address => uint256) public nonces;

    // Track used signatures as additional protection
    mapping(bytes32 => bool) public usedSignatures;

    mapping(address => BondInfo) internal feeds;
    mapping(string => address) public secidToBond;
    mapping(address => string) public bondToSecid;

    address public immutable BOND_FACTORY;

    modifier onlyBondFactory() {
        if (msg.sender != BOND_FACTORY) {
            revert OnlyBondFactory();
        }
        _;
    }

    constructor(address _bondFactory, address _initialPriceFeedUpdater) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        if (_bondFactory == address(0) || _initialPriceFeedUpdater == address(0)) {
            revert InvalidAddress();
        }

        BOND_FACTORY = _bondFactory;

        _grantRole(PRICE_FEED_UPDATER_ROLE, _initialPriceFeedUpdater);

        // Initialize EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("BondOracle"), // name
                keccak256("1"), // version
                block.chainid, // chainId
                address(this) // verifyingContract
            )
        );
    }

    function addPriceFeed(address _asset, uint40 initialPrice, uint40 maturityAt) external onlyBondFactory {
        uint40 currentTimestamp = uint40(block.timestamp);

        feeds[_asset] = BondInfo({lastPrice: initialPrice, lastUpdated: currentTimestamp, maturityAt: maturityAt});

        // Register the SECID mapping using the bond token's name as the SECID
        string memory secid = ERC20(_asset).name();
        secidToBond[secid] = _asset;
        bondToSecid[_asset] = secid;

        emit PriceFeedAdded(_asset, initialPrice, currentTimestamp, maturityAt);
        emit SecidMappingRegistered(secid, _asset);
    }

    function updatePriceFeed(address _feed, uint160 _price) external onlyRole(PRICE_FEED_UPDATER_ROLE) {
        _updatePriceFeed(_feed, _price);
    }

    function updateMultiplePriceFeeds(address[] calldata _feeds, uint160[] calldata _prices)
        external
        onlyRole(PRICE_FEED_UPDATER_ROLE)
    {
        if (_feeds.length != _prices.length) {
            revert InvalidLength();
        }

        for (uint256 i = 0; i < _feeds.length; i++) {
            _updatePriceFeed(_feeds[i], _prices[i]);
        }
    }

    function _updatePriceFeed(address _feed, uint160 _price) internal {
        BondInfo memory bondInfo = feeds[_feed];

        if (bondInfo.lastUpdated == 0) {
            revert NonExistentPriceFeed();
        }

        uint40 currentTimestamp = uint40(block.timestamp);

        if (bondInfo.lastUpdated == currentTimestamp) {
            return; // Price feed is up to date
        }

        if (bondInfo.maturityAt <= currentTimestamp) {
            (,, _price,) = IBondFactory(BOND_FACTORY).getBondDetails(_feed);
            if (_price != bondInfo.lastPrice) {
                feeds[_feed] =
                    BondInfo({lastPrice: _price, lastUpdated: bondInfo.maturityAt, maturityAt: bondInfo.maturityAt});
                emit PriceFeedUpdated(_feed, _price, currentTimestamp);
                return;
            }
        } else {
            feeds[_feed] = BondInfo({lastPrice: _price, lastUpdated: currentTimestamp, maturityAt: bondInfo.maturityAt});
            emit PriceFeedUpdated(_feed, _price, currentTimestamp);
        }
    }

    function getNonce(address signer) external view returns (uint256) {
        return nonces[signer];
    }

    function updatePriceFeedWithSignature(
        string calldata _secid,
        uint160 _price,
        uint256 _deadline,
        uint256 _nonce,
        bytes calldata _signature
    ) external {
        // Check if signature has expired
        if (block.timestamp > _deadline) {
            revert SignatureExpired();
        }

        // Decode signature
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(_signature, (bytes32, bytes32, uint8));

        // Create the EIP-712 hash
        bytes32 digest = _hashTypedData(
            keccak256(abi.encode(PRICE_UPDATE_TYPEHASH, keccak256(bytes(_secid)), _price, _nonce, _deadline))
        );

        // Recover the signer from the signature
        address recoveredSigner = ecrecover(digest, v, r, s);

        // Verify the signer has the required role
        if (!hasRole(PRICE_FEED_UPDATER_ROLE, recoveredSigner)) {
            revert InvalidSignature();
        }

        // Get current nonce for recovered signer
        uint256 lastNonce = nonces[recoveredSigner];

        // Verify nonce is greater than last used
        if (_nonce <= lastNonce) {
            revert InvalidNonce();
        }

        // Update nonce
        nonces[recoveredSigner] = _nonce;

        // Get the bond address from the SECID
        address feed = secidToBond[_secid];
        if (feed == address(0)) {
            revert SecidNotRegistered();
        }

        // Update the price feed
        _updatePriceFeed(feed, _price);
    }

    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function getPriceFeed(address _feed) external view returns (BondInfo memory) {
        return feeds[_feed];
    }

    function getPriceFeeds(address[] calldata _feeds) external view returns (BondInfo[] memory) {
        BondInfo[] memory priceFeeds = new BondInfo[](_feeds.length);
        for (uint256 i = 0; i < _feeds.length; i++) {
            priceFeeds[i] = feeds[_feeds[i]];
        }
        return priceFeeds;
    }
}
