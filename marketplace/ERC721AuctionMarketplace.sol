// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ERC721AuctionMarketplace is IERC721Receiver, ReentrancyGuard {

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

    address public owner;
    uint256 public lastAuctionId;
    uint256 frozenEth;
    bool paused;

    mapping(uint256 => Auction) listOfAuctions;

    event CreateAuction(
        uint256 indexed _itemId, 
        address indexed _tokenAddress, 
        uint256 indexed _tokenId, 
        uint256 _startPrice);

    event MakeBid(uint256 indexed _auctionId, address indexed _bidder, uint256 indexed _newBid);
    event CancelAuction(uint256 indexed _auctionId);
    event CompleteAuction(uint256 indexed _auctionId, address indexed _customer, uint256 indexed _price);

    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    modifier whenNotPaused() { 
        require(!paused, "Marketplace: paused"); 
        _; 
    }

    modifier isAuctionExists(uint256 _auctionId) {
        require(_auctionId <= lastAuctionId, "Marketplace: nonexisted auction");
        _;
    }

    function isPermitted(IERC721 _token, uint256 _tokenId) internal view returns(bool) {
        address _tokenOwner = _token.ownerOf(_tokenId);

        bool isApproved = msg.sender == _token.getApproved(_tokenId);
        bool _isApprovedForAll = _token.isApprovedForAll(_tokenOwner, msg.sender);

        return msg.sender == _tokenOwner || isApproved || _isApprovedForAll;
    }

    function isOnAuction(Auction memory auction) internal pure returns(bool) {
        return !auction.isCanceled && !auction.isCompleted;
    }

    constructor() {
        owner = msg.sender;
        frozenEth = 0;
        paused = false;
    }

    receive() external payable {}

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance - frozenEth);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function createAuction(address _tokenAddress, uint256 _tokenId, uint256 _startPrice) external whenNotPaused {
    
        require(_startPrice > 0, "Marketplace: price must be greater than 0");
        require(_startPrice <= type(uint256).max / 2, "Marketplace: price too high");
        require(_tokenAddress != address(0), "Marketplace: zero address");
        require(IERC165(_tokenAddress).supportsInterface(type(IERC721Metadata).interfaceId), "Marketplace: not ERC721");

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

    function makeBid(uint256 _auctionId) external payable nonReentrant whenNotPaused isAuctionExists(_auctionId) {

        Auction storage auction = listOfAuctions[_auctionId];
        
        require(
            msg.value > auction.currentBid && 
            msg.value >= auction.startPrice, 
            "Marketplace: this bid is equal or lower then currentPrice"
        );
        require(
            isOnAuction(auction) &&
            auction.endTime > block.timestamp, 
            "Marketplace: this auction is not being held"
        );

        if (auction.currentBidder != address(0)) {
            frozenEth -= auction.currentBid;
        }

        frozenEth += msg.value;
        uint256 previousBid = auction.currentBid;
        address previousBidder = auction.currentBidder;
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        if (previousBidder != address(0)) {
            (bool isRefunded, ) = payable(previousBidder).call{value: previousBid}("");
            require(isRefunded, "Marketplace: failed to refund previous bid");
        }

        emit MakeBid(_auctionId, msg.sender, msg.value);
    }

    function cancelAuction(uint256 _auctionId) external nonReentrant whenNotPaused isAuctionExists(_auctionId){

        Auction storage auction = listOfAuctions[_auctionId];

        require(msg.sender == auction.seller, "Marketplace: not seller");
        require(
            isOnAuction(auction) &&
            auction.endTime > block.timestamp, 
            "Marketplace: this auction is not being held"
        );
        
        auction.isCanceled = true;
        auction.endTime = block.timestamp;

        if (auction.currentBidder != address(0)) {
            payable(auction.currentBidder).transfer(auction.currentBid);
            frozenEth -= auction.currentBid;
        }

        emit CancelAuction(_auctionId);
    }

    function withdrawToken(uint256 _auctionId) external isAuctionExists(_auctionId) {

        Auction storage auction = listOfAuctions[_auctionId];
        IERC721 token = IERC721(auction.tokenAddress);

        require(msg.sender == auction.seller, "Marketplace: not seller");
        require(auction.isCanceled && !auction.isCompleted, "Marketplace: item is not canceled or still on sale");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held by marketplace");

        token.transferFrom(address(this), msg.sender, auction.tokenId);
    }

    function completeAuction(uint256 _auctionId) external nonReentrant whenNotPaused isAuctionExists(_auctionId) {

        Auction storage auction = listOfAuctions[_auctionId];
        IERC721 token = IERC721(auction.tokenAddress);

        require(auction.endTime <= block.timestamp, "Marketplace: auction is not over");
        require(isOnAuction(auction), "Marketplace: this auction is not being held");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held by marketplace");

        auction.isCompleted = true;

        if (auction.currentBidder == address(0)) {
            token.transferFrom(address(this), auction.seller, auction.tokenId);
        }
        else {
            (bool sent, ) = payable(auction.seller).call{value: auction.currentBid}("");
            require(sent, "Marketplace: failed to send ETH to seller");
            frozenEth -= auction.currentBid;
            token.safeTransferFrom(address(this), auction.currentBidder, auction.tokenId);
        }

        emit CompleteAuction(_auctionId, auction.currentBidder, auction.currentBid);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
}