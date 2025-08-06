// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC721FixedPriceMarketplace is IERC721Receiver, ReentrancyGuard {

    struct ItemOnSale {
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        address seller;
        bool isSold;
        bool isCanceled;
    }

    address public owner;
    uint256 public lastItemOnSaleId;
    bool paused;

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

    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    modifier whenNotPaused() { 
        require(!paused, "Marketplace: paused"); 
        _; 
    }

    function isPermitted(IERC721 _token, uint256 _tokenId) internal view returns(bool) {
        address _tokenOwner = _token.ownerOf(_tokenId);

        bool isApproved = msg.sender == _token.getApproved(_tokenId);
        bool _isApprovedForAll = _token.isApprovedForAll(_tokenOwner, msg.sender);

        return msg.sender == _tokenOwner || isApproved || _isApprovedForAll;
    }

    function isOnSale(ItemOnSale memory itemOnSale) internal pure returns(bool) {
        return itemOnSale.seller != address(0) && 
                !itemOnSale.isCanceled && 
                !itemOnSale.isSold;
    }

    constructor() {
        owner = msg.sender;
        paused = false;
    }

    receive() external payable {}

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function listItem(address _tokenAddress, uint256 _tokenId, uint256 _price) external whenNotPaused {

        require(_price > 0, "Marketplace: price must be greater than 0");
        require(_tokenAddress != address(0), "Marketplace: zero address");
        require(
            IERC165(_tokenAddress).supportsInterface(type(IERC721Metadata).interfaceId),
            "Marketplace: not ERC721"
        );

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

    function buyItem(uint256 _itemId) external payable nonReentrant whenNotPaused {

        require(_itemId <= lastItemOnSaleId, "Marketplace: nonexisted item");

        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(isOnSale(item), "Marketplace: this token not on sale");
        require(msg.value >= item.price, "Marketplace: not enough eth");
        require(
            token.ownerOf(item.tokenId) == address(this),
            "Marketplace: token not held by marketplace"
        );

        item.isSold = true;

        (bool isSent, ) = payable(item.seller).call{value: item.price}("");
        require(isSent, "Marketplace: failed to send ETH to seller");
        token.transferFrom(address(this), msg.sender, item.tokenId);

        if (msg.value > item.price) {
            (bool isRefunded, ) = payable(msg.sender).call{value: msg.value - item.price}("");
            require(isRefunded, "Marketplace: failed to refund excess ETH");
        }

        emit BuyItem(_itemId, msg.sender);
    }

    function cancel(uint256 _itemId) external whenNotPaused {

        require(_itemId <= lastItemOnSaleId, "Marketplace: nonexisted item");

        ItemOnSale storage item = listOfItemsOnSale[_itemId];

        require(msg.sender == item.seller, "Marketplace: permission denied");
        require(isOnSale(item), "Marketplace: this token not on sale");
        
        item.isCanceled = true;

        emit CancelSale(_itemId);
    }

    function withdrawToken(uint256 _itemId) external {

        require(_itemId <= lastItemOnSaleId, "Marketplace: nonexisted item");

        ItemOnSale storage item = listOfItemsOnSale[_itemId];
        IERC721 token = IERC721(item.tokenAddress);

        require(msg.sender == item.seller, "Marketplace: not seller");
        require(item.isCanceled && !item.isSold, "Marketplace: item is not canceled or still on sale");
        require(
            token.ownerOf(item.tokenId) == address(this),
            "Marketplace: token not held by marketplace"
        );

        token.transferFrom(address(this), msg.sender, item.tokenId);
    }

    function setPaused(bool _paused) external onlyOwner { 
        paused = _paused; 
    }
}