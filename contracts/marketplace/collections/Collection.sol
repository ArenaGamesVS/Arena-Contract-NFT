//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "contracts/functools/VerifySigner.sol";
import "../../interfaces/IAdminContract.sol";

contract Collection is ERC2981, ERC721URIStorage, Ownable, VerifySigner {
  uint256 public constant VERSION = 8;
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  RoyaltyInfo private _defaultRoyaltyInfo;

  IGallery public gallery;
  address public signer;
  address public adminContract;

  mapping(address => bool) public creators;

  uint256 private _lastTokenId;
  string private _slug;

  // EVENTS

  event TokenMinted(uint256 indexed tokenId, string url);

  event CreatorSet(address indexed creator, bool enabled);
  event SignerSet(address indexed account);

  // CONSTRUCTOR

  constructor(
    address owner_,
    string memory name_,
    string memory symbol_,
    string memory slug_,
    address _signer,
    address _gallery,
    address _admin
  ) ERC721(name_, symbol_) Ownable() {
    gallery = IGallery(_gallery);
    transferOwnership(owner_);
    creators[owner_] = true;
    signer = _signer;
    _slug = slug_;
    adminContract = _admin;
    _setDefaultRoyalty(owner_, 500);
  }

  // Public functions

  function getMessageHash(
    address buyer,
    string calldata tokenURI,
    address currency,
    uint256 price,
    uint256 nonce
  ) external view returns (bytes32) {
    return _getMessageHash(buyer, tokenURI, currency, price, nonce);
  }

  function mintWithFixedPrice(
    string calldata tokenURI,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 price,
    uint256 nonce,
    bytes memory signature,
    address recipient
  ) external payable returns (uint256) {
    verifySigner(_getMessageHash(address(gallery), tokenURI, currency, price, nonce), signature, signer);
    uint256 lastTokenId = _mintToken(tokenURI, address(gallery));
    uint256 lastListingId = _listingToken(
      tokenURI,
      address(gallery),
      IGallery.ListingType.FixedPrice,
      timeStart,
      timeEnd,
      currency,
      price,
      0,
      0
    );

    if (currency == address(0)) {
      gallery.buyETH{value: msg.value}(lastListingId);
      super._transfer(address(this), recipient, lastTokenId);
    } else {
      IERC20(currency).transferFrom(recipient, address(this), price);
      IERC20(currency).approve(address(gallery), price);
      gallery.buy(lastListingId);
      super._transfer(address(this), recipient, lastTokenId);
    }

    return lastListingId;
  }

  function mintWithFixedPrice(
    string calldata tokenURI,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 price,
    uint256 nonce,
    bytes memory signature
  ) public payable returns (uint256) {
    verifySigner(_getMessageHash(address(gallery), tokenURI, currency, price, nonce), signature, signer);
    uint256 lastTokenId = _mintToken(tokenURI, address(gallery));
    uint256 lastListingId = _listingToken(
      tokenURI,
      address(gallery),
      IGallery.ListingType.FixedPrice,
      timeStart,
      timeEnd,
      currency,
      price,
      0,
      0
    );
    if (currency == address(0)) {
      gallery.buyETH{value: msg.value}(lastListingId);
      super._transfer(address(this), msg.sender, lastTokenId);
    } else {
      IERC20(currency).transferFrom(msg.sender, address(this), price);
      IERC20(currency).approve(address(gallery), price);
      gallery.buy(lastListingId);
      super._transfer(address(this), msg.sender, lastTokenId);
    }

    return lastListingId;
  }

  function mintManyWithFixedPrice(
    string[] calldata tokenURI,
    address[] calldata mintTo,
    uint256[] calldata timeStart,
    uint256[] calldata timeEnd,
    address[] memory currency,
    uint256[] calldata price
  ) external onlyCreator {
    for (uint256 i = 0; i < tokenURI.length; i++) {
      mintWithFixedPriceCreator(tokenURI[i], mintTo[i], timeStart[i], timeEnd[i], currency[i], price[i]);
    }
  }

  function mintWithAuction(
    string calldata tokenURI,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 minimalBid,
    uint256 bidStep,
    uint256 gracePeriod,
    uint256 nonce,
    bytes memory signature
  ) external returns (uint256) {
    verifySigner(_getMessageHash(address(gallery), tokenURI, currency, minimalBid, nonce), signature, signer);
    _mintToken(tokenURI, address(gallery));
    return
      _listingToken(
        tokenURI,
        address(gallery),
        IGallery.ListingType.Auction,
        timeStart,
        timeEnd,
        currency,
        minimalBid,
        bidStep,
        gracePeriod
      );
  }

  // CREATOR FUNCTIONS

  function mintToken(string calldata tokenURI, address mintTo) external onlyCreator returns (uint256) {
    _lastTokenId++;
    _mint(mintTo, _lastTokenId);
    _setTokenURI(_lastTokenId, tokenURI);
    return _lastTokenId;
  }

  function mintWithFixedPriceCreator(
    string calldata tokenURI,
    address mintTo,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 price
  ) public onlyCreator returns (uint256) {
    _mintToken(tokenURI, mintTo);
    return _listingToken(tokenURI, mintTo, IGallery.ListingType.FixedPrice, timeStart, timeEnd, currency, price, 0, 0);
  }

  // OWNER FUNCTIONS

  function setCreator(address account, bool creator) external onlyOwner {
    // require(creators[account] != creator, "Already in this status");
    creators[account] = creator;
    emit CreatorSet(account, creator);
  }

  function setSigner(address account) external onlyOwner {
    signer = account;
    emit SignerSet(account);
  }

  function setGallery(address _gallery) external onlyOwner {
    gallery = IGallery(_gallery);
  }

  function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyAdmin(ADMIN_ROLE) {
    _setDefaultRoyalty(receiver, feeNumerator);
  }

  function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external onlyAdmin(ADMIN_ROLE) {
    _setTokenRoyalty(tokenId, receiver, feeNumerator);
  }

  function resetTokenRoyalty(uint256 tokenId) external onlyAdmin(ADMIN_ROLE) {
    _resetTokenRoyalty(tokenId);
  }

  // PRIVATE FUNCTIONS

  function _mintToken(string calldata tokenURI, address mintTo) private returns (uint256) {
    _lastTokenId++;
    _mint(mintTo, _lastTokenId);
    _setTokenURI(_lastTokenId, tokenURI);
    return _lastTokenId;
  }

  function _listingToken(
    string calldata tokenURI,
    address mintTo,
    IGallery.ListingType listingType,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 minimalBid,
    uint256 bidStep,
    uint256 gracePeriod
  ) private returns (uint256) {
    bool claimed = mintTo != address(gallery);
    uint256 lastListingId = gallery.createListingFromCollection(
      listingType,
      mintTo,
      _lastTokenId,
      timeStart,
      timeEnd,
      currency,
      minimalBid,
      bidStep,
      gracePeriod,
      claimed
    );

    emit TokenMinted(_lastTokenId, tokenURI);
    return lastListingId;
  }

  // OVERRIDES

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

  function slug() public view virtual returns (string memory) {
    return _slug;
  }

  function _getMessageHash(
    address buyer,
    string calldata tokenURI,
    address currency,
    uint256 price,
    uint256 nonce
  ) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(toUint(buyer), tokenURI, currency, price, nonce, toUint(address(this))));
  }

  // MODIFIERS

  modifier onlyCreator() {
    require(creators[msg.sender], "Caller isn't a creator");
    _;
  }

  modifier onlyAdmin(bytes32 role) {
    require(
      IAdminContract(adminContract).hasRole(role, msg.sender),
      string(
        abi.encodePacked(
          "AccessControl: account ",
          Strings.toHexString(uint160(msg.sender), 20),
          " is missing role ADMIN_ROLE"
        )
      )
    );
    _;
  }
}

interface IGallery {
  enum ListingType {
    None,
    FixedPrice,
    Auction
  }

  function createListingFromCollection(
    ListingType listingType,
    address seller,
    uint256 tokenId,
    uint256 timeStart,
    uint256 timeEnd,
    address currency,
    uint256 minimalBid,
    uint256 bidStep,
    uint256 gracePeriod,
    bool claimed
  ) external returns (uint256);

  function buy(uint256 listingId) external;

  function buyETH(uint256 listingId) external payable;
}

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
