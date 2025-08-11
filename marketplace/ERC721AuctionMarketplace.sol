// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./ERC721BaseMarketplace.sol";

/**
 * @title ERC721AuctionMarketplace
 * @author Artem Ostapenko
 * @notice A decentralized auction marketplace for ERC-721 NFTs with English auction functionality
 * @dev This contract enables users to create auctions for their NFTs with a 24-hour duration.
 * Bidders can place bids in ETH, with the highest bidder winning when the auction ends.
 * The contract uses a UUPS proxy pattern for upgradeability and inherits from ERC721BaseMarketplace.
 */
contract ERC721AuctionMarketplace is Initializable, UUPSUpgradeable, ERC721BaseMarketplace {
    /**
     * @notice Data structure representing an NFT auction
     * @dev Stores all auction details including token information, timing, pricing, and bidding status
     */
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

    /**
     * @notice The ID of the last created auction
     * @dev Used to generate unique auction IDs (1, 2, 3, ...)
     */
    uint256 public lastAuctionId;

    /**
     * @notice The amount of ETH currently frozen in active auctions
     * @dev Tracks ETH from bids to ensure proper refunds and prevent withdrawal
     */
    uint256 public frozenEth;

    /**
     * @notice Mapping of auction ID to Auction struct
     * @dev Stores all active and completed auctions
     */
    mapping(uint256 => Auction) public listOfAuctions;

    /**
     * @notice Emitted when a new auction is created
     * @param itemId The unique ID of the auction (same as auctionId)
     * @param tokenAddress The address of the ERC-721 token being auctioned
     * @param tokenId The ID of the specific NFT token
     * @param startPrice The minimum starting price for the auction in wei
     */
    event CreateAuction(
        uint256 indexed itemId, 
        address indexed tokenAddress, 
        uint256 indexed tokenId, 
        uint256 startPrice
    );

    /**
     * @notice Emitted when a new bid is placed on an auction
     * @param auctionId The ID of the auction receiving the bid
     * @param bidder The address of the bidder
     * @param newBid The amount of the new bid in wei
     */
    event MakeBid(uint256 indexed auctionId, address indexed bidder, uint256 indexed newBid);

    /**
     * @notice Emitted when an auction is canceled by the seller
     * @param auctionId The ID of the canceled auction
     */
    event CancelAuction(uint256 indexed auctionId);

    /**
     * @notice Emitted when an auction is successfully completed
     * @param auctionId The ID of the completed auction
     * @param customer The address of the winning bidder
     * @param price The final winning bid amount in wei
     * @param fee The marketplace fee collected in wei
     * @param royaltyAmount The royalty amount paid to the creator in wei
     * @param royaltyRecipient The address of the royalty recipient
     */
    event CompleteAuction(
        uint256 indexed auctionId, 
        address indexed customer, 
        uint256 indexed price, 
        uint256 fee, 
        uint256 royaltyAmount,
        address royaltyRecipient
    );

    /**
     * @notice Emitted when an auction expires without any bids
     * @param auctionId The ID of the expired auction
     */
    event AuctionExpired(uint256 indexed auctionId);

    /**
     * @dev Modifier that validates an auction ID exists
     * @param _auctionId The auction ID to validate
     */
    modifier auctionExists(uint256 _auctionId) {
        require(_auctionId > 0 && _auctionId <= lastAuctionId, "Marketplace: auction does not exist");
        _;
    }

    /**
     * @notice Checks if an auction is currently active
     * @dev An auction is on auction if it is neither canceled nor completed
     * @param auction The Auction struct to check
     * @return True if the auction is active, false otherwise
     */
    function isOnAuction(Auction memory auction) internal pure returns (bool) {
        return !auction.isCanceled && !auction.isCompleted;
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
     * @notice Withdraws available ETH from the contract to the owner
     * @dev Only callable by the owner, excludes frozen ETH from active bids
     */
    function withdraw() external override onlyOwner {
        uint256 amount = address(this).balance - frozenEth;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");

        require(sent, "Marketplace: failed to send ETH");
        
        emit Withdraw(amount);
    }

    /**
     * @notice Creates a new auction for an ERC-721 NFT
     * @dev Transfers the NFT from seller to marketplace and creates a 24-hour auction
     * @param _tokenAddress The address of the ERC-721 contract
     * @param _tokenId The ID of the NFT to auction
     * @param _startPrice The minimum starting price for the auction in wei
     */
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

    /**
     * @notice Places a bid on an active auction
     * @dev Must send ETH with the transaction, refunds previous highest bidder
     * @param _auctionId The ID of the auction to bid on
     */
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

    /**
     * @notice Cancels an active auction
     * @dev Only the seller can cancel their auction, refunds current highest bidder
     * @param _auctionId The ID of the auction to cancel
     */
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

    /**
     * @notice Withdraws an NFT after auction cancellation
     * @dev Only the seller can withdraw their NFT if the auction was canceled
     * @param _auctionId The ID of the auction from which to withdraw the NFT
     */
    function withdrawToken(uint256 _auctionId) external override auctionExists(_auctionId) {
        Auction storage auction = listOfAuctions[_auctionId];
        IERC721 token = IERC721(auction.tokenAddress);

        require(msg.sender == auction.seller, "Marketplace: not seller");
        require(auction.isCanceled && !auction.isCompleted, "Marketplace: not canceled");
        require(token.ownerOf(auction.tokenId) == address(this), "Marketplace: token not held");

        token.transferFrom(address(this), msg.sender, auction.tokenId);

        emit WithdrawToken(auction.tokenAddress, auction.tokenId, msg.sender);
    }

    /**
     * @notice Completes an auction that has ended
     * @dev Distributes funds to winner, seller, marketplace, and royalty recipient
     * @param _auctionId The ID of the auction to complete
     */
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

    /**
     * @dev Internal function that authorizes upgrades to the contract
     * @notice Overrides both parent contracts' authorization logic
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override(ERC721BaseMarketplace, UUPSUpgradeable) {
        super._authorizeUpgrade(newImplementation);
    }
}