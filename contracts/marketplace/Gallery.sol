//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "../libraries/UniqueArray.sol";

contract Gallery is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using UniqueArray for address[];

  uint256 public constant VERSION = 14;

  /// @dev The address that will receive a commission from sales
  address public feePlatformAddress;

  /// @dev Types of tokens that can be minted
  enum ListingType {
    None,
    FixedPrice,
    Auction
  }

  struct Listing {
    ListingType listingType;
    address seller;
    ICollection collection;
    uint256 tokenId;
    uint256 timeStart;
    uint256 timeEnd;
    IERC20Upgradeable currency;
    uint256 minimalBid;
    uint256 lastBid;
    address lastBidder;
    bool claimed;
    bool isFirstListing;
    mapping(address => uint256) pendingAmounts;
  }

  struct ListingAuction {
    uint256 gracePeriod;
    uint256 bidStep;
  }

  mapping(uint256 => Listing) public listings;
  mapping(uint256 => mapping(address => uint256)) public bids;
  mapping(uint256 => address[]) public bidsInListings;
  mapping(uint256 => ListingAuction) public listingsAuction;

  mapping(address => mapping(uint256 => uint256)) public tokenToLastListing;

  mapping(address => bool) public isCollection;

  mapping(address => bool) public collectionCreators;

  struct Currency {
    bool enabled;
  }

  mapping(address => Currency) public currencies;

  mapping(address => bool) public isBlacklisted;

  uint256 private _lastListingId;

  // EVENTS

  event ListingCreated(
    uint256 indexed listingId,
    address indexed collection,
    uint256 indexed tokenId,
    ListingType listingType,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 minimalBid
  );

  event ListingBought(uint256 indexed listingId, address indexed buyer);

  event ListingBoughtFull(
    uint256 indexed listingId,
    address indexed buyer,
    address paymentToken,
    address collection,
    address seller,
    uint256 price,
    uint256 tokenId
  );

  event ListingBid(uint256 indexed listingId, address indexed bidder, uint256 amount, uint256 timeEnd);

  event CancelBid(uint256 indexed listingId, address indexed bidder);

  event PendingWithdrawn(uint256 indexed listingId, address indexed claimer, uint256 amount);

  event RevertToken(uint256 indexed listingId, address indexed target);

  event ClaimToken(uint256 indexed listingId, address indexed target);

  event CollectionCreatorSet(address indexed creator, bool enabled);

  event CurrencySet(address indexed currency, bool enabled);

  /// @dev Event about changing the feePlatformAddress
  /// @param feePlatformAddress New feePlatformAddress address
  event FeePlatformAddressSet(address feePlatformAddress);

  event CollectionSet(address indexed collection, bool status);

  event Blacklisted(address indexed account, bool blacklisted);

  event PriceReduction(uint256 indexed listingId, uint256 price);

  // CONSTRUCTOR

  /// @param _feePlatformAddress Explain to an end user what this does
  function initialize(address _feePlatformAddress) public initializer {
    feePlatformAddress = _feePlatformAddress;
    __Ownable_init();
    __ReentrancyGuard_init();
  }

  // CREATOR FUNCTIONS

  // PUBLIC FUNCTIONS

  function createListing(
    ListingType listingType,
    ICollection collection,
    uint256 tokenId,
    uint256 timeStart,
    uint256 timeEnd,
    IERC20Upgradeable currency,
    uint256 minimalBid,
    uint256 bidStep,
    uint256 gracePeriod
  ) external returns (uint256) {
    collection.transferFrom(msg.sender, address(this), tokenId);
    return
      _createListing(
        listingType,
        collection,
        msg.sender,
        tokenId,
        timeStart,
        timeEnd,
        currency,
        minimalBid,
        bidStep,
        gracePeriod,
        false
      );
  }

  function createListingFromCollection(
    ListingType listingType,
    address seller,
    uint256 tokenId,
    uint256 timeStart,
    uint256 timeEnd,
    IERC20Upgradeable currency,
    uint256 minimalBid,
    uint256 bidStep,
    uint256 gracePeriod,
    bool claimed
  ) external returns (uint256) {
    require(isCollection[msg.sender], "Only callable by collection");

    return
      _createListing(
        listingType,
        ICollection(msg.sender),
        seller,
        tokenId,
        timeStart,
        timeEnd,
        currency,
        minimalBid,
        bidStep,
        gracePeriod,
        claimed
      );
  }

  function buy(uint256 listingId) external nonReentrant {
    listings[listingId].currency.safeTransferFrom(msg.sender, address(this), listings[listingId].minimalBid);
    _buy(listingId, msg.sender);
  }

  function buyOnlyOwner(uint256 listingId, address recipient) external nonReentrant onlyCreator {
    listings[listingId].currency.safeTransferFrom(recipient, address(this), listings[listingId].minimalBid);

    _buy(listingId, recipient);
  }

  function buyETH(uint256 listingId) external payable nonReentrant {
    require(address(listings[listingId].currency) == address(0), "Listing not for ETH");
    require(msg.value >= listings[listingId].minimalBid, "Insufficient ETH");

    _buy(listingId, msg.sender);
  }

  function bidOnlyOwner(uint256 listingId, uint256 amount, address recipient) external nonReentrant onlyCreator {
    uint256 totalBid = amount + listings[listingId].pendingAmounts[recipient];
    listings[listingId].pendingAmounts[recipient] = 0;
    listings[listingId].currency.safeTransferFrom(recipient, address(this), totalBid);

    _bid(listingId, amount, recipient);
  }

  function bid(uint256 listingId, uint256 amount) external nonReentrant {
    uint256 totalBid = amount + listings[listingId].pendingAmounts[msg.sender];
    listings[listingId].pendingAmounts[msg.sender] = 0;
    listings[listingId].currency.safeTransferFrom(msg.sender, address(this), totalBid);

    _bid(listingId, amount, msg.sender);
  }

  function bidETH(uint256 listingId) external payable nonReentrant {
    require(address(listings[listingId].currency) == address(0), "Listing not for ETH");

    uint256 totalBid = msg.value + listings[listingId].pendingAmounts[msg.sender];
    listings[listingId].pendingAmounts[msg.sender] = 0;
    _bid(listingId, totalBid, msg.sender);
  }

  function cancelBidOnlyOwner(uint256 listingId, address recipient) external nonReentrant onlyCreator {
    _cancelBid(listingId, recipient);
  }

  function cancelBid(uint256 listingId) external nonReentrant {
    _cancelBid(listingId, msg.sender);
  }

  function priceReduction(uint256 listingId, uint256 price) external nonReentrant {
    require(listings[listingId].listingType == ListingType.FixedPrice, "Only at a fixed price");
    require(listings[listingId].seller == msg.sender, "Only seller can change price");
    require(price < listings[listingId].minimalBid, "Price should be less than current one");
    listings[listingId].minimalBid = price;

    emit PriceReduction(listingId, price);
  }

  function revertToken(uint256 listingId) external nonReentrant {
    require(listings[listingId].seller == msg.sender, "Only seller can cancel");
    _revertTokenToTarget(listingId);
  }

  function claimCollectible(uint256 listingId) external nonReentrant {
    require(block.timestamp >= listings[listingId].timeEnd, "Sale not yet finished");
    _claimCollectible(listingId);
  }

  function withdrawPending(uint256 listingId) external nonReentrant {
    uint256 pending = listings[listingId].pendingAmounts[msg.sender];
    listings[listingId].pendingAmounts[msg.sender] = 0;

    require(pending != 0, "Cannot withdraw zero amount");
    _transferCurrency(listingId, msg.sender, pending);

    emit PendingWithdrawn(listingId, msg.sender, pending);
  }

  function getBid(uint256 listingId, address bidder) external view returns (uint256) {
    return bids[listingId][bidder];
  }

  function getLastId() external view returns (uint256) {
    return _lastListingId;
  }

  // OWNER FUNCTIONS

  function setCollectionCreator(address account, bool creator) external onlyOwner {
    require(collectionCreators[account] != creator, "Already in this status");
    collectionCreators[account] = creator;

    emit CollectionCreatorSet(account, creator);
  }

  /// @dev The currency in which the sale is possible
  /// @dev currency Address ERC20 token
  /// @dev enabled Is the coin active
  function setCurrency(address currency, bool enabled) external onlyOwner {
    currencies[currency] = Currency({enabled: enabled});
    emit CurrencySet(currency, enabled);
  }

  /// @param _feePlatformAddress Explain to an end user what this does
  function setFeePlatformAddress(address _feePlatformAddress) external onlyOwner {
    require(_feePlatformAddress != address(0), "Fee platform address can't be zero address");
    feePlatformAddress = _feePlatformAddress;

    emit FeePlatformAddressSet(feePlatformAddress);
  }

  function setCollection(address _collection, bool _status) external onlyCreator {
    isCollection[_collection] = _status;
    emit CollectionSet(_collection, _status);
  }

  // PRIVATE FUNCTIONS
  function _getSellerByToken(uint256 listingId) internal returns (address) {
    if (listings[listingId].listingType == ListingType.Auction && listings[listingId].lastBidder != address(0)) {
      _distributeValue(listingId);
      return listings[listingId].lastBidder;
    }
    return listings[listingId].seller;
  }

  function _claimCollectible(uint256 listingId) internal {
    require(!listings[listingId].claimed, "Already claimed");
    listings[listingId].claimed = true;

    address recipient = listings[listingId].seller;

    if (listings[listingId].listingType == ListingType.Auction && listings[listingId].lastBidder != address(0)) {
      _distributeValue(listingId);
      recipient = listings[listingId].lastBidder;
      bids[listingId][recipient] = 0;
    }

    listings[listingId].collection.transferFrom(address(this), recipient, listings[listingId].tokenId);
    emit ClaimToken(listingId, recipient);
  }

  function _revertTokenToTarget(uint256 listingId) internal {
    require(!listings[listingId].claimed, "Already claimed");
    if (listings[listingId].listingType == ListingType.Auction && listings[listingId].lastBidder != address(0)) {
      require(block.timestamp < listings[listingId].timeEnd, "Auction has finished");
    }

    listings[listingId].claimed = true;

    address recipient = listings[listingId].seller;

    listings[listingId].collection.transferFrom(address(this), recipient, listings[listingId].tokenId);
    emit RevertToken(listingId, recipient);
  }

  function _createListing(
    ListingType listingType,
    ICollection collection,
    address seller,
    uint256 tokenId,
    uint256 timeStart,
    uint256 timeEnd,
    IERC20Upgradeable currency,
    uint256 minimalBid,
    uint256 bidStep,
    uint256 gracePeriod,
    bool claimed
  ) private returns (uint256) {
    require(listingType != ListingType.None, "Listing should have a type");
    require(isCollection[address(collection)], "Invalid collection");
    require(currencies[address(currency)].enabled, "Currency not allowed");
    if (timeStart < block.timestamp) {
      timeStart = block.timestamp;
    }
    require(
      (timeEnd == 0 && listingType == ListingType.FixedPrice) || timeEnd > timeStart,
      "Sale end should be greater than sale start"
    );

    _lastListingId++;
    listings[_lastListingId].listingType = listingType;
    listings[_lastListingId].seller = seller;
    listings[_lastListingId].collection = collection;
    listings[_lastListingId].tokenId = tokenId;
    listings[_lastListingId].timeStart = timeStart;
    listings[_lastListingId].timeEnd = timeEnd;
    listings[_lastListingId].currency = currency;
    listings[_lastListingId].minimalBid = minimalBid;
    listings[_lastListingId].claimed = claimed;
    listings[_lastListingId].isFirstListing = (tokenToLastListing[address(collection)][tokenId] == 0);

    tokenToLastListing[address(collection)][tokenId] = _lastListingId;

    listingsAuction[_lastListingId].bidStep = bidStep;
    listingsAuction[_lastListingId].gracePeriod = gracePeriod;

    emit ListingCreated(
      _lastListingId,
      address(collection),
      tokenId,
      listingType,
      timeStart,
      timeEnd,
      address(currency),
      minimalBid
    );

    return _lastListingId;
  }

  function _bid(uint256 listingId, uint256 amount, address recipient) private {
    require(listings[listingId].listingType == ListingType.Auction, "Bids only for auctions");
    require(block.timestamp >= listings[listingId].timeStart, "Sale not yet started");
    require(block.timestamp < listings[listingId].timeEnd, "Sale has finished");
    amount = bids[listingId][recipient] + amount;
    require(
      amount >= listings[listingId].lastBid + listingsAuction[listingId].bidStep,
      "Bid should be not less than previous plus bid step"
    );
    require(amount >= listings[listingId].minimalBid, "Bid lower than minimal bid");

    listings[listingId].lastBid = amount;
    listings[listingId].lastBidder = recipient;
    bidsInListings[listingId].addUnique(recipient);
    bids[listingId][recipient] = amount;
    if (listings[listingId].timeEnd - block.timestamp < listingsAuction[listingId].gracePeriod) {
      listings[listingId].timeEnd = block.timestamp + listingsAuction[listingId].gracePeriod;
    }

    emit ListingBid(listingId, recipient, amount, listings[listingId].timeEnd);
  }

  function _cancelBid(uint256 listingId, address bidder) internal returns (address) {
    require(listings[listingId].listingType == ListingType.Auction, "Bids only for auctions");
    require(block.timestamp >= listings[listingId].timeStart, "Sale not yet started");
    require(bids[listingId][bidder] != 0, "You didn't place a bet");
    if (block.timestamp > listings[listingId].timeEnd && !listings[listingId].claimed) {
      require(listings[listingId].lastBidder != bidder, "Winner cannot cancel the bet");
    }

    _transferCurrency(listingId, bidder, bids[listingId][bidder]);
    bids[listingId][bidder] = 0;
    emit CancelBid(listingId, bidder);
    uint256 maxBid = 0;
    address lastBidder = address(0);
    for (uint256 i = 0; i < bidsInListings[listingId].length; i++) {
      address _bidder = bidsInListings[listingId][i];
      if (_bidder != address(0) && bids[listingId][_bidder] != 0 && bids[listingId][_bidder] > maxBid) {
        maxBid = bids[listingId][_bidder];
        lastBidder = _bidder;
      }
    }
    listings[listingId].lastBid = maxBid;
    listings[listingId].lastBidder = lastBidder;
    return listings[listingId].lastBidder;
  }

  function _buy(uint256 listingId, address recipient) private {
    require(recipient != listings[listingId].seller, "You cannot buy a token from yourself");
    require(listings[listingId].listingType == ListingType.FixedPrice, "Buys are only for fixed price");
    require(block.timestamp >= listings[listingId].timeStart, "Sale hasn't started yet");
    if (listings[listingId].timeEnd != 0) {
      require(block.timestamp < listings[listingId].timeEnd, "Sale has finished");
    }
    require(listings[listingId].lastBidder == address(0), "Already purchased");

    listings[listingId].lastBid = listings[listingId].minimalBid;
    listings[listingId].lastBidder = recipient;
    listings[listingId].claimed = true;
    listings[listingId].collection.transferFrom(address(this), recipient, listings[listingId].tokenId);

    _distributeValue(listingId);
    emit ListingBought(
      listingId,
      recipient
    );    
    emit ListingBoughtFull(
      listingId,
      recipient,
      address(listings[listingId].currency),
      address(listings[listingId].collection),
      listings[listingId].seller,
      listings[listingId].lastBid,
      listings[listingId].tokenId
    );
  }

  function _distributeValue(uint256 listingId) private {
    bool supportsInterface = ERC165Checker.supportsInterface(address(listings[listingId].collection), type(IERC2981).interfaceId);
    uint256 remains = listings[listingId].lastBid;
    if (supportsInterface) {
      (address recipient, uint256 fee) = IERC2981(address(listings[listingId].collection)).royaltyInfo(listings[listingId].tokenId, listings[listingId].lastBid);
      _transferCurrency(listingId, recipient, fee);
      remains -= fee;
    }
    uint256 feePlatformValue = (listings[listingId].lastBid * 5) / 100;
    _transferCurrency(listingId, feePlatformAddress, feePlatformValue);
    _transferCurrency(listingId, listings[listingId].seller, remains - feePlatformValue);
    // _transferCurrency(listingId, listings[listingId].seller, listings[listingId].lastBid);
  }

  function _transferCurrency(uint256 listingId, address account, uint256 amount) private {
    if (amount > 0) {
      if (address(listings[listingId].currency) == address(0)) {
        if (!payable(account).send(amount)) {
          listings[listingId].pendingAmounts[account] += amount;
        }
      } else {
        listings[listingId].currency.safeTransfer(account, amount);
      }
    }
  }

  // MODIFIERS

  modifier onlyCreator() {
    require(collectionCreators[msg.sender], "Caller isn't a collection creator");
    _;
  }
}

interface ICollection is IERC721 {}
