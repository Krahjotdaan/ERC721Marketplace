// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.19;

import "/interfaces/IERC721Metadata.sol";

contract ERC721Marketplace {

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

    function isOwner(address _token, uint256 _tokenId) internal view  returns(bool) {
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

    function checkOnERC721Received(address, uint256 _tokenId, bytes memory _data) external _isERC721(msg.sender) returns (bytes4) {
        require(address(this) == IERC721(msg.sender).ownerOf(_tokenId), "Marketplace: marketplace is not an owner");

        uint256 price = abi.decode(_data, (uint256));
        listItem(msg.sender, _tokenId, price);

        return this.checkOnERC721Received.selector;
    }

    function listItem(address _tokenAddress, uint256 _tokenId, uint256 _price) internal returns(uint256) {
        IERC721 token = IERC721(_tokenAddress);
        address _tokenOwner = token.ownerOf(_tokenId);

        lastItemOnSaleId++;
        listOfItemsOnSale[lastItemOnSaleId] = ItemOnSale(
            _tokenAddress,
            _tokenId,
            _price,
            _tokenOwner,
            false,
            false
        );
        
        emit ListItemOnSale(_tokenId, _tokenAddress, _tokenId, _price);

        return lastItemOnSaleId;
    }

    function buyItem(uint256 _itemToBuyId) external payable {
        ItemOnSale memory itemToBuy = listOfItemsOnSale[_itemToBuyId];

        require(isOnSale(itemToBuy), "Marketplace: this token not on sale");
        require(msg.value >= itemToBuy.price, "Marketplace: not enough eth");

        payable(itemToBuy.tokenOwner).transfer(itemToBuy.price);
        IERC721(itemToBuy.tokenAddress).transferFrom(address(this), msg.sender, itemToBuy.tokenId);

        if (msg.value > itemToBuy.price) {
            payable(msg.sender).transfer(msg.value - itemToBuy.price);
        }

        listOfItemsOnSale[_itemToBuyId].isSold = true;

        emit BuyItemOnSale(_itemToBuyId, msg.sender);
    }

    function cancel(uint256 _itemToCancelId) external {

        ItemOnSale memory itemToCancel = listOfItemsOnSale[_itemToCancelId];

        require(isOwner(itemToCancel.tokenAddress, itemToCancel.tokenId), "Marketplace: permission denied");
        require(isOnSale(itemToCancel), "Marketplace: this token not on sale");

        address _tokenOwner = itemToCancel.tokenOwner;
        IERC721(itemToCancel.tokenAddress).transferFrom(address(this), _tokenOwner, itemToCancel.tokenId);
        listOfItemsOnSale[_itemToCancelId].isCanceled = true;

        emit CancelSale(_itemToCancelId);
    }
}