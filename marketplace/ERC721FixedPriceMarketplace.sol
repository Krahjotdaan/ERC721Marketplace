// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "./ERC721BaseMarketplace.sol";

contract ERC721FixedPriceMarketplace is ERC721BaseMarketplace {
    struct ItemOnSale {
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        address seller;
        uint256 itemOnSaleFeePercentage;
        bool isSold;
        bool isCanceled;
    }

    uint256 public lastItemOnSaleId;
    mapping(uint256 => ItemOnSale) public listOfItemsOnSale;

    event ListItem(
        uint256 indexed itemId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 price,
        address seller,
        uint256 itemOnSaleFeePercentage
    );
    event BuyItem(
        uint256 indexed itemOnSaleId, 
        address indexed customer, 
        uint256 indexed price,
        uint256 fee, 
        uint256 royaltyAmount, 
        address royaltyRecipient
    );
    event CancelSale(uint256 indexed itemOnSaleId);

    modifier itemExists(uint256 _itemId) {
        require(_itemId > 0 && _itemId <= lastItemOnSaleId, "Marketplace: item does not exist");
        _;
    }

    function isOnSale(ItemOnSale memory item) internal pure returns (bool) {
        return !item.isSold && !item.isCanceled;
    }

    constructor(
        address _feeRecipient,
        uint256 _feePercentage,
        uint256 _minFeeInUSD,
        address _userStorage
    ) ERC721BaseMarketplace(
        _feeRecipient,
        _feePercentage,
        _minFeeInUSD,
        _userStorage
    ) {}

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
            itemOnSaleFeePercentage: feePercentage,
            isSold: false,
            isCanceled: false
        });

        userStorage.recordListing(msg.sender, lastItemOnSaleId);

        emit ListItem({
            itemId: lastItemOnSaleId,
            tokenAddress: _tokenAddress,
            tokenId: _tokenId,
            price: _price,
            seller: msg.sender,
            itemOnSaleFeePercentage: feePercentage
        });
    }

    function buyItem(uint256 _itemId) external payable nonReentrant whenNotPaused {
        require(_itemId <= lastItemOnSaleId, "Marketplace: nonexisted item");

        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(isOnSale(item), "Marketplace: this token not on sale");
        require(msg.value >= item.price, "Marketplace: not enough eth");
        require(token.ownerOf(item.tokenId) == address(this), "Marketplace: token not held by marketplace");

        item.isSold = true;

        uint256 totalPrice = item.price;

        (uint256 actualRoyalty, uint256 actualMarketplaceFee, uint256 sellerAmount, address royaltyRecipient) = calculateDistribution(
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
            (bool feeSent, ) = payable(feeRecipient).call{value: actualMarketplaceFee}("");
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

    function cancel(uint256 _itemId) external whenNotPaused itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];

        require(msg.sender == item.seller, "Marketplace: not seller");
        require(isOnSale(item), "Marketplace: item not on sale");

        item.isCanceled = true;

        emit CancelSale(_itemId);
    }

    function withdrawToken(uint256 _itemId) external override itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(msg.sender == item.seller, "Marketplace: not seller");
        require(item.isCanceled && !item.isSold, "Marketplace: not canceled");
        require(token.ownerOf(item.tokenId) == address(this), "Marketplace: token not held");

        token.transferFrom(address(this), msg.sender, item.tokenId);

        emit WithdrawToken(item.tokenAddress, item.tokenId, msg.sender);
    }
}