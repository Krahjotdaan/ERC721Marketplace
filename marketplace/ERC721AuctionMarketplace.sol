// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.20;

import "./ERC721BaseMarketplace.sol";

contract ERC721AuctionMarketplace is Initializable, UUPSUpgradeable, ERC721BaseMarketplace {
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

    event CreateAuction(
        uint256 indexed itemId, 
        address indexed tokenAddress, 
        uint256 indexed tokenId, 
        uint256 startPrice
    );
    event MakeBid(uint256 indexed auctionId, address indexed bidder, uint256 indexed newBid);
    event CancelAuction(uint256 indexed auctionId);
    event CompleteAuction(
        uint256 indexed auctionId, 
        address indexed customer, 
        uint256 indexed price, 
        uint256 fee, 
        uint256 royaltyAmount,
        address royaltyRecipient
    );
    event AuctionExpired(uint256 indexed auctionId);

    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId > 0 && _auctionId <= lastAuctionId, "Marketplace: auction does not exist");
        _;
    }

    function isOnAuction(Auction memory auction) internal pure returns (bool) {
        return !auction.isCanceled && !auction.isCompleted;
    }

    function initialize(address _userStorage, address _calculatorServise) public override(ERC721BaseMarketplace) initializer {
        ERC721BaseMarketplace.initialize(_userStorage, _calculatorServise);
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
        require(!userStorage.getUserInfo(msg.sender).isBlacklistedSeller, "Marketplace: msg.sender is in blacklist of sellers");

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

        userStorage.recordAuctionCreation(msg.sender, lastAuctionId);

        emit CreateAuction(lastAuctionId, _tokenAddress, _tokenId, _startPrice);
    }

    function makeBid(uint256 _auctionId) external payable nonReentrant whenNotPaused auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];

        require(msg.sender != auction.seller, "Marketplace: you are seller");
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

    function withdrawToken(uint256 _auctionId) external override auctionExists(_auctionId) {
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

        require(auction.endTime <= block.timestamp, "Marketplace: auction is not over");
        require(isOnAuction(auction), "Marketplace: this auction is not being held");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held by marketplace");

        auction.isCompleted = true;

        if (auction.currentBidder == address(0)) {
            token.transferFrom(address(this), auction.seller, auction.tokenId);

            emit AuctionExpired(_auctionId);

            return;
        }

        uint256 totalPrice = auction.currentBid;

        (uint256 actualRoyalty, 
        uint256 actualMarketplaceFee, 
        uint256 sellerAmount, 
        address royaltyRecipient) = 
        calculator.calculateDistribution(
            auction.tokenAddress, 
            auction.tokenId, 
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
            
            userStorage.recordFeesPaid(auction.currentBidder, actualMarketplaceFee);
        }

        if (sellerAmount > 0) {
            (bool sent, ) = payable(auction.seller).call{value: sellerAmount}("");
            require(sent, "Marketplace: failed to send ETH to seller");
        }

        token.safeTransferFrom(address(this), auction.currentBidder, auction.tokenId);

        userStorage.recordAuctionPurchase(auction.currentBidder, auction.seller, _auctionId, totalPrice);

        emit CompleteAuction({
            auctionId: _auctionId,
            customer: auction.currentBidder,
            price: totalPrice,
            fee: actualMarketplaceFee,
            royaltyAmount: actualRoyalty,
            royaltyRecipient: royaltyRecipient
        });
    }

    function _authorizeUpgrade(address newImplementation) internal override(ERC721BaseMarketplace, UUPSUpgradeable) {
        super._authorizeUpgrade(newImplementation);
    }
}