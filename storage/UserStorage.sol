// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMarketplaceRegistry.sol";

/**
 * @title UserStorage
 * @author Artem Ostapenko
 * @notice A centralized storage contract for user statistics and blacklists across marketplaces
 * @dev This contract stores comprehensive user data including transaction history, 
 * purchase/sale statistics, and blacklist status for both sellers and royalty recipients.
 * It is designed to be used by multiple authorized marketplaces through the MarketplaceRegistry.
 */
contract UserStorage {
    /**
     * @notice Data structure containing comprehensive user information
     * @dev Stores all user statistics, transaction history, and blacklist status
     */
    struct UserInfo {
        uint256 ordersCount;
        uint256 listingsCount;        
        uint256 auctionsCreatedCount; 
        uint256 ordersPurchasesCount;
        uint256 auctionsPurchasesCount; 
        uint256 fixedPricePurchasesCount; 
        uint256 totalPurchases;    
        uint256 totalSales;        
        uint256 totalFeesPaid;
        bool exists;
        bool isBlacklistedSeller;
        bool isBlacklistedRoyalty;
        uint256[] listedOrders;
        uint256[] listedItems;
        uint256[] createdAuctions;
        uint256[] purchasedOrders;
        uint256[] purchasedItems;
        uint256[] purchasedAuctions;
    }

    /**
     * @notice The address of the contract owner/administrator
     * @dev Owner has exclusive rights to manage blacklists
     */
    address public owner;

    /**
     * @notice The address of the MarketplaceRegistry contract
     * @dev Used to verify authorized marketplaces through the registry
     */
    address public registry;

    /**
     * @notice The total number of unique users in the system
     * @dev Incremented when a new user is created
     */
    uint256 public userCount;
    
    /**
     * @notice Mapping of user addresses to their UserInfo struct
     * @dev Stores all user data and statistics
     */
    mapping(address => UserInfo) public users;

    /**
     * @notice Mapping of user ID to user address
     * @dev Enables iteration over all users and lookup by ID
     */
    mapping(uint256 => address) public userAddresses;

    /**
     * @notice Emitted when a new user is created in the system
     * @param user The address of the newly created user
     */
    event UserCreated(address indexed user);

    /**
     * @notice Emitted when a user's seller blacklist status is changed
     * @param user The address of the user whose status was changed
     * @param isSeller The new blacklist status for the user as a seller
     */
    event SetSellerBlacklisted(address indexed user, bool isSeller);

    /**
     * @notice Emitted when a user's royalty blacklist status is changed
     * @param user The address of the user whose royalty status was changed
     * @param isRoyalty The new blacklist status for the user as a royalty recipient
     */
    event SetRoyaltyBlacklisted(address indexed user, bool isRoyalty);
    
    /**
     * @dev Modifier that restricts function access to authorized marketplaces
     * @notice Only contracts authorized in the MarketplaceRegistry can call functions with this modifier
     * Also ensures the caller is a smart contract, not an externally owned account (EOA)
     */
    modifier onlyAuthorizedMarketplace() {
        require(
            IMarketplaceRegistry(registry).isAuthorizedMarketplace(msg.sender), 
            "UserStorage: not authorized marketplace"
        );
        require(msg.sender.code.length > 0, "UserStorage: caller is not a contract");
        _;
    }
    
    /**
     * @notice Initializes the UserStorage contract with the registry address
     * @dev Sets the registry address for authorization checks
     * @param _registry The address of the MarketplaceRegistry contract
     */
    constructor(address _registry) {
        registry = _registry;
    }
    
    /**
     * @notice Creates a new user entry if one doesn't already exist
     * @dev Internal function called before any user data is recorded
     * @param user The address of the user to create
     */
    function _createUserIfNotExists(address user) internal {
        if (!users[user].exists) {
            users[user].exists = true;
            
            userCount++;
            userAddresses[userCount] = user;

            emit UserCreated(user);
        }
    }

    /**
     * @notice Records the creation of an ERC-20 order
     * @dev Increments order count and adds order ID to user's list
     * @param seller The address of the seller who created the order
     * @param orderId The ID of the created order
     */
    function recordOrder(address seller, uint256 orderId) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(seller);
        
        users[seller].ordersCount++;
        users[seller].listedOrders.push(orderId);
    }
    
    /**
     * @notice Records the listing of an ERC-721 NFT for fixed-price sale
     * @dev Increments listings count and adds item ID to user's list
     * @param seller The address of the seller who listed the NFT
     * @param itemId The ID of the listed item
     */
    function recordListing(address seller, uint256 itemId) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(seller);
        
        users[seller].listingsCount++;
        users[seller].listedItems.push(itemId);
    }
    
    /**
     * @notice Records the creation of an auction for an NFT
     * @dev Increments auction creation count and adds auction ID to user's list
     * @param seller The address of the seller who created the auction
     * @param auctionId The ID of the created auction
     */
    function recordAuctionCreation(address seller, uint256 auctionId) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(seller);
        
        users[seller].auctionsCreatedCount++;
        users[seller].createdAuctions.push(auctionId);
    }

    /**
     * @notice Records the purchase of an ERC-20 order
     * @dev Updates buyer's purchase statistics and seller's sales amount
     * @param buyer The address of the buyer
     * @param seller The address of the seller
     * @param orderId The ID of the purchased order
     * @param price The total price of the purchase in wei
     */
    function recordOrderPurchase(address buyer, address seller, uint256 orderId, uint256 price) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(buyer);
        
        users[buyer].ordersPurchasesCount++;
        users[buyer].totalPurchases += price;
        users[buyer].purchasedOrders.push(orderId);
        
        users[seller].totalSales += price;
    }
    
    /**
     * @notice Records the purchase of a fixed-price ERC-721 NFT
     * @dev Updates buyer's purchase statistics and seller's sales amount
     * @param buyer The address of the buyer
     * @param seller The address of the seller
     * @param itemId The ID of the purchased item
     * @param price The total price of the purchase in wei
     */
    function recordItemPurchase(address buyer, address seller, uint256 itemId, uint256 price) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(buyer);
        
        users[buyer].fixedPricePurchasesCount++;
        users[buyer].totalPurchases += price;
        users[buyer].purchasedItems.push(itemId);
        
        users[seller].totalSales += price;
    }
    
    /**
     * @notice Records the purchase of an NFT through auction
     * @dev Updates buyer's auction purchase statistics and seller's sales amount
     * @param buyer The address of the winning bidder
     * @param seller The address of the seller
     * @param auctionId The ID of the completed auction
     * @param price The winning bid amount in wei
     */
    function recordAuctionPurchase(address buyer, address seller, uint256 auctionId, uint256 price) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(buyer);
        
        users[buyer].auctionsPurchasesCount++;
        users[buyer].totalPurchases += price;
        users[buyer].purchasedAuctions.push(auctionId);
        
        users[seller].totalSales += price;
    }

    /**
     * @notice Records fees paid by a user
     * @dev Increments the user's total fees paid amount
     * @param user The address of the user who paid fees
     * @param amount The amount of fees paid in wei
     */
    function recordFeesPaid(address user, uint256 amount) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(user);
        
        users[user].totalFeesPaid += amount;
    }
    
    /**
     * @notice Updates a user's blacklist status for selling
     * @dev Only callable by the contract owner
     * @param user The address of the user to update
     * @param isSeller The new blacklist status for the user as a seller
     */
    function setSellerBlacklisted(address user, bool isSeller) external {
        require(msg.sender == owner, "UserStorage: not owner");
        require(users[user].isBlacklistedSeller != isSeller, "UserStorage: same status");

        _createUserIfNotExists(user);
        users[user].isBlacklistedSeller = isSeller;

        emit SetSellerBlacklisted(user, isSeller);    
    }

    /**
     * @notice Updates a user's blacklist status for receiving royalties
     * @dev Only callable by the contract owner
     * @param user The address of the user to update
     * @param isRoyalty The new blacklist status for the user as a royalty recipient
     */
    function setRoyaltyBlacklisted(address user, bool isRoyalty) external {
        require(msg.sender == owner, "UserStorage: not owner");
        require(users[user].isBlacklistedRoyalty != isRoyalty, "UserStorage: same status");

        _createUserIfNotExists(user);
        users[user].isBlacklistedRoyalty = isRoyalty;

        emit SetRoyaltyBlacklisted(user, isRoyalty);
    }
    
    /**
     * @notice Retrieves all information about a user
     * @dev Returns the complete UserInfo struct for the specified user
     * @param user The address of the user to retrieve information for
     * @return The UserInfo struct containing all user data
     */
    function getUserInfo(address user) external view returns (UserInfo memory) {
        return users[user];
    }
    
    /**
     * @notice Retrieves the address of a user by their ID
     * @dev Enables iteration over users by ID
     * @param id The ID of the user (1-based index)
     * @return The address of the user with the specified ID
     */
    function getUserAddress(uint256 id) external view returns (address) {
        require(id > 0 && id <= userCount);
        return userAddresses[id];
    }
    
    /**
     * @notice Retrieves a list of all user addresses in the system
     * @dev Returns an array of all user addresses ordered by creation
     * @return An array containing all user addresses
     */
    function getAllUsers() external view returns (address[] memory) {
        address[] memory allUsers = new address[](userCount);
        
        for (uint256 i = 0; i < userCount; i++) {
            allUsers[i] = userAddresses[i + 1];
        }

        return allUsers;
    }
    
    /**
     * @notice Retrieves overall statistics for the entire marketplace system
     * @dev Sums up all user statistics to provide system-wide metrics
     * @return totalListings The total number of listings across all users
     * @return totalAuctions The total number of auctions created across all users
     * @return totalPurchases The total value of all purchases in wei
     * @return totalSales The total value of all sales in wei
     * @return totalFees The total amount of fees collected in wei
     */
    function getOverallStatistics() external view returns (
        uint256 totalListings,
        uint256 totalAuctions,
        uint256 totalPurchases,
        uint256 totalSales,
        uint256 totalFees
    ) {
        for (uint256 i = 1; i <= userCount; i++) {
            address user = userAddresses[i];
            totalListings += users[user].listingsCount;
            totalAuctions += users[user].auctionsCreatedCount;
            totalPurchases += users[user].totalPurchases;
            totalSales += users[user].totalSales;
            totalFees += users[user].totalFeesPaid;
        }
    }
    
    /**
     * @notice Retrieves all item IDs listed by a user for fixed-price sale
     * @dev Returns the array of listed item IDs for the specified user
     * @param user The address of the user to retrieve data for
     * @return An array of item IDs listed by the user
     */
    function getUserListedItems(address user) external view returns (uint256[] memory) {
        return users[user].listedItems;
    }
    
    /**
     * @notice Retrieves all auction IDs created by a user
     * @dev Returns the array of created auction IDs for the specified user
     * @param user The address of the user to retrieve data for
     * @return An array of auction IDs created by the user
     */
    function getUserCreatedAuctions(address user) external view returns (uint256[] memory) {
        return users[user].createdAuctions;
    }
    
    /**
     * @notice Retrieves all item IDs purchased by a user through fixed-price listings
     * @dev Returns the array of purchased item IDs for the specified user
     * @param user The address of the user to retrieve data for
     * @return An array of item IDs purchased by the user
     */
    function getUserPurchasedItems(address user) external view returns (uint256[] memory) {
        return users[user].purchasedItems;
    }
    
    /**
     * @notice Retrieves all auction IDs where a user was the winning bidder
     * @dev Returns the array of auction IDs won by the specified user
     * @param user The address of the user to retrieve data for
     * @return An array of auction IDs where the user was the winner
     */
    function getUserPurchasedAuctions(address user) external view returns (uint256[] memory) {
        return users[user].purchasedAuctions;
    }
}