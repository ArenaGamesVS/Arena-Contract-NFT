# Arena Contracts NFT

## ArenaGamesToken

Basic ERC20 token

## Collection

Basic NFT collections contract for deploying via factory.

### Methods

- mintToken - used by collection creator for minting NFT

- mintWithFixedPriceCreator - used by collection creator for minting and listing fixed price NFT

- mintWithFixedPrice - used for minting and listing fixed price NFT with the signers approval

- mintManyWithFixedPrice - bulk variant of mintWithFixedPrice

- mintWithAuction - used for minting and listing NFT for auction with the signers approval

- setCreator, setSigner, setGallery - admin methods for setting up

## CollectionFactory

Factory for creating new Collections

### Methods

- createCollection - create and setup new collection

## Gallery

Marketplace for collections

### Methods

All "...onlyOwner" methods can be called only by collection creator.

- createListing - used for listing NFT on marketplace

- createListingFromCollection - used for listing NFT on markeplace by Collection contract

- buy - used for buying fixed price NFT

- buyETH - used for buying fixed price NFT with native currency

- bid - used for making a bid on auction lot

- bidETH - used for making a bid on auction lot with native currency

- cancelBid - used for revert bids

- priceReduction - used by seller for reduce price of fixed-price lots

- revertToken - used by seller for canceling listing

- claimCollectible - used for claiming lot after auction ends

- withdrawPending - used for withdraw native currency in case of failed transfer

- setCollectionCreator, setCurrency, setFeePlatformAddress, setCollection - admin methods