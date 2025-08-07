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
        uint256 auctionFeePercentage;
        bool isCanceled;
        bool isCompleted;
    }

    uint256 public lastAuctionId;
    uint256 public frozenEth;
    mapping(uint256 => Auction) public listOfAuctions;

    event CreateAuction(
        uint256 indexed itemId, 
        address indexed tokenAddress, 
        uint256 indexed tokenId, 
        uint256 startPrice,
        uint256 auctionFeePercentage
    );
    event MakeBid(uint256 indexed auctionId, address indexed bidder, uint256 indexed newBid);
    event CancelAuction(uint256 indexed auctionId);
    event CompleteAuction(uint256 indexed auctionId, address indexed customer, uint256 indexed price, uint256 fee);

    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId > 0 && _auctionId <= lastAuctionId, "Marketplace: auction does not exist");
        _;
    }

    function isOnAuction(Auction memory auction) internal pure returns (bool) {
        return !auction.isCanceled && !auction.isCompleted;
    }

    function withdraw() external override onlyOwner {
        uint256 amount = address(this).balance - frozenEth;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Marketplace: failed to send ETH");
        
        emit Withdraw(amount);
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
            auctionFeePercentage: feePercentage,
            isCanceled: false,
            isCompleted: false
        });

        emit CreateAuction(lastAuctionId, _tokenAddress, _tokenId, _startPrice, feePercentage);
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

        emit WithdrawToken(auction.tokenAddress, auction.tokenId, msg.sender);
    }

    function completeAuction(uint256 _auctionId) external nonReentrant whenNotPaused auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];
        IERC721 token = IERC721(auction.tokenAddress);

        require(auction.endTime <= block.timestamp, "Marketplace: not over");
        require(isOnAuction(auction), "Marketplace: not active");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held");

        auction.isCompleted = true;

        uint256 _fee;

        if (auction.currentBidder == address(0)) {
            token.transferFrom(address(this), auction.seller, auction.tokenId);
            _fee = 0;
        } 
        else {
            _fee = countFee(auction.currentBid, auction.auctionFeePercentage);

            (bool sent, ) = payable(auction.seller).call{value: auction.currentBid - _fee}("");
            require(sent, "Marketplace: failed to send ETH");
            frozenEth -= auction.currentBid;
            
            token.safeTransferFrom(address(this), auction.currentBidder, auction.tokenId);

            (bool feeSent, ) = payable(feeRecipient).call{value: _fee}("");
            require(feeSent, "Marketplace: failed to send fee");
        }

        emit CompleteAuction(_auctionId, auction.currentBidder, auction.currentBid, _fee);
    }
}