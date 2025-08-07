// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "./ERC721MarketplaceBase.sol";

contract ERC721FixedPriceMarketplace is ERC721MarketplaceBase {
    struct ItemOnSale {
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        address seller;
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
        address seller
    );
    event BuyItem(uint256 indexed _itemOnSaleId, address indexed _customer);
    event CancelSale(uint256 indexed _itemOnSaleId);

    modifier itemExists(uint256 _itemId) {
        require(_itemId > 0 && _itemId <= lastItemOnSaleId, "Marketplace: item does not exist");
        _;
    }

    function isOnSale(ItemOnSale memory item) internal pure returns (bool) {
        return !item.isSold && !item.isCanceled;
    }

    function listItem(address _tokenAddress, uint256 _tokenId, uint256 _price) external whenNotPaused {
        require(_price > 0, "Marketplace: price must be greater than 0");
        require(_tokenAddress != address(0), "Marketplace: zero address");
        require(isERC721(_tokenAddress), "Marketplace: not ERC721");

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

        emit ListItem(lastItemOnSaleId, _tokenAddress, _tokenId, _price, msg.sender);
    }

    function buyItem(uint256 _itemId) external payable nonReentrant whenNotPaused itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(isOnSale(item), "Marketplace: item not on sale");
        require(msg.value >= item.price, "Marketplace: not enough ETH");
        require(token.ownerOf(item.tokenId) == address(this), "Marketplace: token not held");

        item.isSold = true;

        (bool sent, ) = payable(item.seller).call{value: item.price}("");
        require(sent, "Marketplace: failed to send ETH");
        token.safeTransferFrom(address(this), msg.sender, item.tokenId);

        if (msg.value > item.price) {
            (bool refunded, ) = payable(msg.sender).call{value: msg.value - item.price}("");
            require(refunded, "Marketplace: failed to refund");
        }

        emit BuyItem(_itemId, msg.sender);
    }

    function cancel(uint256 _itemId) external whenNotPaused itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        require(msg.sender == item.seller, "Marketplace: not seller");
        require(isOnSale(item), "Marketplace: item not on sale");

        item.isCanceled = true;
        emit CancelSale(_itemId);
    }

    function withdrawToken(uint256 _itemId) external itemExists(_itemId) {
        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(msg.sender == item.seller, "Marketplace: not seller");
        require(item.isCanceled && !item.isSold, "Marketplace: not canceled");
        require(token.ownerOf(item.tokenId) == address(this), "Marketplace: token not held");

        token.transferFrom(address(this), msg.sender, item.tokenId);

        emit WithdrawToken(item.tokenAddress, item.tokenId, msg.sender);
    }
}