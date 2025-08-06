// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "marketplace/interfaces/IERC721Metadata.sol";
import "marketplace/interfaces/IERC165.sol";
import "marketplace/interfaces/IERC721Receiver.sol";

contract ERC721Marketplace is IERC721Receiver {

    struct ItemOnSale {
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        address tokenOwner;
        bool isSold;
        bool isCanceled;
    }

    uint256 public lastItemOnSaleId;
    mapping(uint256 => ItemOnSale) public listOfItemsOnSale;

    event ListItemOnSale(uint256 indexed _itemOnSaleId, 
                        address indexed _tokenAddress, 
                        uint256 indexed _tokenId, 
                        uint256 _price);

    event CancelSale(uint256 indexed _itemOnSaleId);
    event BuyItemOnSale(uint256 indexed _itemOnSaleId, address indexed _customer);

    modifier _isERC721(address _addr) {
        require(isERC721(_addr), "Marketplace: this address is not a contract of ERC721");
        _;
    }

    function isERC721(address _addr) internal view isContract(_addr) returns(bool result) {
        try IERC165(_addr).supportsInterface(type(IERC721Metadata).interfaceId) returns (bool response) {
            return response;
        }
        catch {
            return false;
        }
    }

    modifier isContract(address _addr) {
        require(_addr.code.length > 0, "Marketplace: this address is not a contract");
        _;
    }

    function isPermitted(address _token, uint256 _tokenId) internal view returns(bool) {
        IERC721 token = IERC721(_token);
        address _tokenOwner = token.ownerOf(_tokenId);

        bool isApproved = msg.sender == token.getApproved(_tokenId);
        bool _isApprovedForAll = token.isApprovedForAll(_tokenOwner, msg.sender);

        return msg.sender == _tokenOwner || isApproved || _isApprovedForAll;
    }

    function isOnSale(ItemOnSale memory itemOnSale) internal pure returns(bool) {
        return itemOnSale.tokenOwner != address(0) && 
                !itemOnSale.isCanceled && 
                !itemOnSale.isSold;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function listItemOnSale(address _tokenAddress, uint256 _tokenId, uint256 _price) external returns(uint256) {

        require(_price > 0, "Marketplace: price must be greater than 0");
        IERC721 token = IERC721(_tokenAddress);

        require(isPermitted(_tokenAddress, _tokenId), "Marketplace: not owner or approved");

        token.safeTransferFrom(msg.sender, address(this), _tokenId);

        lastItemOnSaleId++;
        listOfItemsOnSale[lastItemOnSaleId] = ItemOnSale(
            _tokenAddress,
            _tokenId,
            _price,
            msg.sender,
            false,
            false
        );
        
        emit ListItemOnSale(_tokenId, _tokenAddress, _tokenId, _price);

        return lastItemOnSaleId;
    }

    function buyItem(uint256 _itemToBuyId) external payable {
        ItemOnSale storage itemToBuy = listOfItemsOnSale[_itemToBuyId];

        require(isOnSale(itemToBuy), "Marketplace: this token not on sale");
        require(msg.value >= itemToBuy.price, "Marketplace: not enough eth");

        payable(itemToBuy.tokenOwner).transfer(itemToBuy.price);
        IERC721(itemToBuy.tokenAddress).transferFrom(address(this), msg.sender, itemToBuy.tokenId);

        if (msg.value > itemToBuy.price) {
            payable(msg.sender).transfer(msg.value - itemToBuy.price);
        }

        itemToBuy.isSold = true;

        emit BuyItemOnSale(_itemToBuyId, msg.sender);
    }

    function cancel(uint256 _itemToCancelId) external {

        ItemOnSale storage itemToCancel = listOfItemsOnSale[_itemToCancelId];

        require(isPermitted(itemToCancel.tokenAddress, itemToCancel.tokenId) ||
                msg.sender == itemToCancel.tokenOwner, "Marketplace: permission denied");
        require(isOnSale(itemToCancel), "Marketplace: this token not on sale");

        IERC721(itemToCancel.tokenAddress).transferFrom(address(this), itemToCancel.tokenOwner, itemToCancel.tokenId);
        itemToCancel.isCanceled = true;

        emit CancelSale(_itemToCancelId);
    }
}