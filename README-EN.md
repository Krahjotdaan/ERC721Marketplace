# Decentralized Marketplace Platform

A comprehensive, secure, and scalable marketplace platform for ERC-721 NFTs and ERC-20 tokens with support for fixed-price listings and auctions.

## Overview

This platform provides a complete ecosystem for NFT and token trading with the following key components:

- **CalculatorService**: Centralized fee, royalty, and distribution calculations with Chainlink price feed integration
- **MarketplaceRegistry**: Central registry for managing authorized marketplaces and shared services
- **UserStorage**: Unified storage for user statistics, transaction history, and blacklist management
- **ERC721FixedPriceMarketplace**: Marketplace for fixed-price NFT sales
- **ERC721AuctionMarketplace**: Marketplace for English-style NFT auctions
- **ERC20OrderBookMarketplace**: Marketplace for ERC-20 token orders

## Key Features

### Security & Reliability
- UUPS upgradeable contracts for future improvements
- Chainlink price feeds with stale data protection
- Reentrancy guards on all external functions
- Comprehensive input validation
- Owner-controlled blacklists for sellers and royalty recipients

### Economic Model
- Configurable marketplace fees (percentage-based with minimum USD amount)
- Royalty support via ERC-2981 standard with configurable limits
- Dynamic fee calculation based on ETH/USD price
- Protection against stale price data with conservative fallback calculations

### User Experience
- Unified user statistics across all marketplace types
- Complete transaction history tracking
- Support for multiple marketplace models (fixed price, auction, order book)
- Gas-efficient storage design

## Licence
[MIT](LICENCE)
