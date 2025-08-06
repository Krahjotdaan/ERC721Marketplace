// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "./ERC721MarketplaceBase.sol";

contract ERC721AuctionMarketplace is ERC721MarketplaceBase {
    struct Auction {
        address tokenAddress;
        uint256 tokenId;
        address seller;
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        uint256 currentBid;
        address currentBidder;
        bool isCanceled;
        bool isCompleted;
    }

    uint256 public lastAuctionId;
    uint256 public frozenEth;
    mapping(uint256 => Auction) public listOfAuctions;

    event CreateAuction(uint256 indexed _itemId, address indexed _tokenAddress, uint256 indexed _tokenId, uint256 _startPrice);
    event MakeBid(uint256 indexed _auctionId, address indexed _bidder, uint256 indexed _newBid);
    event CancelAuction(uint256 indexed _auctionId);
    event CompleteAuction(uint256 indexed _auctionId, address indexed _customer, uint256 indexed _price);

    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId > 0 && _auctionId <= lastAuctionId, "Marketplace: auction does not exist");
        _;
    }

    function withdraw() external override onlyOwner {
        payable(msg.sender).transfer(address(this).balance - frozenEth);
    }

    function isOnAuction(Auction memory auction) internal pure returns (bool) {
        return !auction.isCanceled && !auction.isCompleted;
    }

    function createAuction(address _tokenAddress, uint256 _tokenId, uint256 _startPrice) external whenNotPaused {
        require(_startPrice > 0, "Marketplace: price must be greater than 0");
        require(_tokenAddress != address(0), "Marketplace: zero address");
        require(isERC721(_tokenAddress), "Marketplace: not ERC721");

        IERC721 token = IERC721(_tokenAddress);
        require(isPermitted(token, _tokenId), "Marketplace: not owner or approved");

        token.safeTransferFrom(msg.sender, address(this), _tokenId);

        lastAuctionId++;
        listOfAuctions[lastAuctionId] = Auction({
            tokenAddress: _tokenAddress,
            tokenId: _tokenId,
            seller: msg.sender,
            startTime: block.timestamp,
            endTime: block.timestamp + 24 hours,
            startPrice: _startPrice,
            currentBid: 0,
            currentBidder: address(0),
            isCanceled: false,
            isCompleted: false
        });

        emit CreateAuction(lastAuctionId, _tokenAddress, _tokenId, _startPrice);
    }

    function makeBid(uint256 _auctionId) external payable nonReentrant whenNotPaused auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];

        require(msg.value > auction.currentBid && msg.value >= auction.startPrice, "Marketplace: bid too low");
        require(isOnAuction(auction) && auction.endTime > block.timestamp, "Marketplace: auction not active");

        if (auction.currentBidder != address(0)) {
            frozenEth -= auction.currentBid;
        }

        frozenEth += msg.value;
        uint256 prevBid = auction.currentBid;
        address prevBidder = auction.currentBidder;
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        if (prevBidder != address(0)) {
            (bool sent, ) = payable(prevBidder).call{value: prevBid}("");
            require(sent, "Marketplace: failed to refund");
        }

        emit MakeBid(_auctionId, msg.sender, msg.value);
    }

    function cancelAuction(uint256 _auctionId) external nonReentrant whenNotPaused auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];
        require(msg.sender == auction.seller, "Marketplace: not seller");
        require(isOnAuction(auction) && auction.endTime > block.timestamp, "Marketplace: not active");

        auction.isCanceled = true;
        auction.endTime = block.timestamp;

        if (auction.currentBidder != address(0)) {
            frozenEth -= auction.currentBid;
            (bool sent, ) = payable(auction.currentBidder).call{value: auction.currentBid}("");
            require(sent, "Marketplace: failed to refund");
        }

        emit CancelAuction(_auctionId);
    }

    function withdrawToken(uint256 _auctionId) external auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];
        IERC721 token = IERC721(auction.tokenAddress);

        require(msg.sender == auction.seller, "Marketplace: not seller");
        require(auction.isCanceled && !auction.isCompleted, "Marketplace: not canceled");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held");

        token.transferFrom(address(this), msg.sender, auction.tokenId);
    }

    function completeAuction(uint256 _auctionId) external nonReentrant whenNotPaused auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];
        IERC721 token = IERC721(auction.tokenAddress);

        require(auction.endTime <= block.timestamp, "Marketplace: not over");
        require(isOnAuction(auction), "Marketplace: not active");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held");

        auction.isCompleted = true;

        if (auction.currentBidder == address(0)) {
            token.transferFrom(address(this), auction.seller, auction.tokenId);
        } 
        else {
            (bool sent, ) = payable(auction.seller).call{value: auction.currentBid}("");
            require(sent, "Marketplace: failed to send ETH");
            frozenEth -= auction.currentBid;
            token.safeTransferFrom(address(this), auction.currentBidder, auction.tokenId);
        }

        emit CompleteAuction(_auctionId, auction.currentBidder, auction.currentBid);
    }
}