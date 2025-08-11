// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./ERC721BaseMarketplace.sol";

/**
 * @title ERC721FixedPriceMarketplace
 * @author Artem Ostapenko
 * @notice A decentralized marketplace for ERC-721 NFTs with fixed-price listings
 * @dev This contract enables users to list their NFTs for a fixed price in ETH.
 * Buyers can purchase listed NFTs by sending the exact price amount. The contract
 * uses a UUPS proxy pattern for upgradeability and inherits from ERC721BaseMarketplace.
 */
contract ERC721FixedPriceMarketplace is Initializable, UUPSUpgradeable, ERC721BaseMarketplace {
    /**
     * @notice Data structure representing a fixed-price NFT listing
     * @dev Stores all information about a listed NFT including token details, price, and status
     */
    struct ItemOnSale {
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        address seller;
        bool isSold;
        bool isCanceled;
    }

    /**
     * @notice The ID of the last created listing
     * @dev Used to generate unique listing IDs (1, 2, 3, ...)
     */
    uint256 public lastItemOnSaleId;

    /**
     * @notice Mapping of listing ID to ItemOnSale struct
     * @dev Stores all active and completed listings
     */
    mapping(uint256 => ItemOnSale) public listOfItemsOnSale;

    /**
     * @notice Emitted when a new NFT is listed for sale at a fixed price
     * @param itemId The unique ID of the listing
     * @param tokenAddress The address of the ERC-721 contract
     * @param tokenId The ID of the specific NFT token
     * @param price The fixed price for the NFT in wei
     * @param seller The address of the seller who listed the NFT
     */
    event ListItem(
        uint256 indexed itemId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 price,
        address seller
    );

    /**
     * @notice Emitted when an NFT is purchased from a fixed-price listing
     * @param itemOnSaleId The ID of the listing that was purchased
     * @param customer The address of the buyer
     * @param price The price paid in wei
     * @param fee The marketplace fee collected in wei
     * @param royaltyAmount The royalty amount paid to the creator in wei
     * @param royaltyRecipient The address of the royalty recipient
     */
    event BuyItem(
        uint256 indexed itemOnSaleId, 
        address indexed customer, 
        uint256 indexed price,
        uint256 fee, 
        uint256 royaltyAmount, 
        address royaltyRecipient
    );

    /**
     * @notice Emitted when a listing is canceled by the seller
     * @param itemOnSaleId The ID of the canceled listing
     */
    event CancelSale(uint256 indexed itemOnSaleId);

    /**
     * @dev Modifier that validates a listing ID exists
     * @param _itemId The listing ID to validate
     */
    modifier itemExists(uint256 _itemId) {
        require(_itemId > 0 && _itemId <= lastItemOnSaleId, "Marketplace: item does not exist");
        _;
    }

    /**
     * @notice Checks if a listing is currently available for purchase
     * @dev A listing is on sale if it is neither sold nor canceled
     * @param item The ItemOnSale struct to check
     * @return True if the listing is available, false otherwise
     */
    function isOnSale(ItemOnSale memory item) internal pure returns (bool) {
        return !item.isSold && !item.isCanceled;
    }

    /**
     * @notice Initializes the contract with required dependencies
     * @dev Overrides the parent initialize function and calls it with provided parameters
     * @param _userStorage The address of the UserStorage contract
     * @param _calculatorServise The address of the CalculatorService contract
     */
    function initialize(address _userStorage, address _calculatorServise) public override(ERC721BaseMarketplace) initializer {
        ERC721BaseMarketplace.initialize(_userStorage, _calculatorServise);
    }

    /**
     * @notice Lists an NFT for sale at a fixed price
     * @dev Transfers the NFT from seller to marketplace and creates a new listing
     * @param _tokenAddress The address of the ERC-721 contract
     * @param _tokenId The ID of the NFT to list
     * @param _price The fixed price for the NFT in wei
     */
    function listItem(address _tokenAddress, uint256 _tokenId, uint256 _price) external whenNotPaused {
        require(_price > 0, "Marketplace: price must be greater than 0");
        require(_tokenAddress != address(0), "Marketplace: zero address");
        require(isERC721(_tokenAddress), "Marketplace: not ERC721");
        require(!userStorage.getUserInfo(msg.sender).isBlacklistedSeller, "Marketplace: msg.sender is in blacklist of sellers");

        IERC721 token = IERC721(_tokenAddress);

        require(isPermitted(token, _tokenId), "Marketplace: not owner or approved");

        token.safeTransferFrom(msg.sender, address(this), _tokenId);

        lastItemOnSaleId++;
        listOfItemsOnSale[lastItemOnSaleId] = ItemOnSale({
            tokenAddress: _tokenAddress,
            tokenId: _tokenId,
            price: _price,
            seller: msg.sender,
            isSold: false,
            isCanceled: false
        });

        userStorage.recordListing(msg.sender, lastItemOnSaleId);

        emit ListItem({
            itemId: lastItemOnSaleId,
            tokenAddress: _tokenAddress,
            tokenId: _tokenId,
            price: _price,
            seller: msg.sender
        });
    }

    /**
     * @notice Purchases an NFT from a fixed-price listing
     * @dev Must send exact price amount in ETH, transfers NFT to buyer and funds to seller
     * @param _itemId The ID of the listing to purchase from
     */
    function buyItem(uint256 _itemId) external payable nonReentrant whenNotPaused {
        require(_itemId <= lastItemOnSaleId, "Marketplace: nonexisted item");

        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(isOnSale(item), "Marketplace: this token not on sale");
        require(msg.value >= item.price, "Marketplace: not enough eth");
        require(token.ownerOf(item.tokenId) == address(this), "Marketplace: token not held by marketplace");

        item.isSold = true;

        uint256 totalPrice = item.price;

        (uint256 actualRoyalty, 
        uint256 actualMarketplaceFee, 
        uint256 sellerAmount, 
        address royaltyRecipient) = 
        calculator.calculateDistribution(
            item.tokenAddress, 
            item.tokenId, 
            totalPrice
        );

        if (actualRoyalty > 0 && royaltyRecipient != address(0)) {
            (bool sent, ) = payable(royaltyRecipient).call{value: actualRoyalty}("");
            if (!sent) {
                emit RoyaltyPaymentFailed(royaltyRecipient, actualRoyalty);
            }
        }

        if (actualMarketplaceFee > 0) {
            (bool feeSent, ) = payable(calculator.feeRecipient()).call{value: actualMarketplaceFee}("");
            require(feeSent, "Marketplace: failed to send fee");
            
            userStorage.recordFeesPaid(msg.sender, actualMarketplaceFee);
        }

        if (sellerAmount > 0) {
            (bool sent, ) = payable(item.seller).call{value: sellerAmount}("");
            require(sent, "Marketplace: failed to send ETH to seller");
        }

        token.safeTransferFrom(address(this), msg.sender, item.tokenId);

        userStorage.recordItemPurchase(msg.sender, item.seller, _itemId, totalPrice);

        if (msg.value > totalPrice) {
            (bool isRefunded, ) = payable(msg.sender).call{value: msg.value - totalPrice}("");
            require(isRefunded, "Marketplace: failed to refund excess ETH");
        }

        emit BuyItem({
            itemOnSaleId: _itemId,
            customer: msg.sender,
            price: totalPrice,
            fee: actualMarketplaceFee,
            royaltyAmount: actualRoyalty,
            royaltyRecipient: royaltyRecipient
        });
    }

    /**
     * @notice Cancels a fixed-price listing
     * @dev Only the seller can cancel their listing
     * @param _itemId The ID of the listing to cancel
     */
    function cancel(uint256 _itemId) external whenNotPaused itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];

        require(msg.sender == item.seller, "Marketplace: not seller");
        require(isOnSale(item), "Marketplace: item not on sale");

        item.isCanceled = true;

        emit CancelSale(_itemId);
    }

    /**
     * @notice Withdraws an NFT after listing cancellation
     * @dev Only the seller can withdraw their NFT if the listing was canceled
     * @param _itemId The ID of the listing from which to withdraw the NFT
     */
    function withdrawToken(uint256 _itemId) external override itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(msg.sender == item.seller, "Marketplace: not seller");
        require(item.isCanceled && !item.isSold, "Marketplace: not canceled");
        require(token.ownerOf(item.tokenId) == address(this), "Marketplace: token not held");

        token.transferFrom(address(this), msg.sender, item.tokenId);

        emit WithdrawToken(item.tokenAddress, item.tokenId, msg.sender);
    }

    /**
     * @dev Internal function that authorizes upgrades to the contract
     * @notice Overrides both parent contracts' authorization logic
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override(ERC721BaseMarketplace, UUPSUpgradeable) {
        super._authorizeUpgrade(newImplementation);
    }
}