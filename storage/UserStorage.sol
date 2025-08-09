// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./IMarketplaceRegistry.sol";

contract UserStorage {
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

    address public registry;
    uint256 public userCount;
    
    mapping(address => UserInfo) public users;
    mapping(uint256 => address) public userIds;
    mapping(address => bool) public authorizedContracts;

    event UserCreated(address indexed user);
    event UserBlacklisted(address indexed user, bool isSeller, bool isRoyalty);
    
    modifier onlyAuthorizedMarketplace() {
        require(
            IMarketplaceRegistry(registry).isAuthorizedMarketplace(msg.sender), 
            "UserStorage: not authorized marketplace"
        );
        require(msg.sender.code.length > 0, "UserStorage: caller is not a contract");
        _;
    }
    
    constructor(address _registry) {
        registry = _registry;
    }
    
    function addAuthorizedContract(address contractAddress) external onlyAuthorizedMarketplace {
        authorizedContracts[contractAddress] = true;
    }
    
    function removeAuthorizedContract(address contractAddress) external onlyAuthorizedMarketplace {
        authorizedContracts[contractAddress] = false;
    }
    
    function _createUserIfNotExists(address user) internal {
        if (!users[user].exists) {
            users[user].exists = true;
            
            userCount++;
            userIds[userCount] = user;

            emit UserCreated(user);
        }
    }

    function recordOrder(address seller, uint256 orderId) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(seller);
        
        users[seller].ordersCount++;
        users[seller].listedOrders.push(orderId);
    }
    
    function recordListing(address seller, uint256 itemId) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(seller);
        
        users[seller].listingsCount++;
        users[seller].listedItems.push(itemId);
    }
    
    function recordAuctionCreation(address seller, uint256 auctionId) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(seller);
        
        users[seller].auctionsCreatedCount++;
        users[seller].createdAuctions.push(auctionId);
    }

    function recordOrderPurchase(address buyer, address seller, uint256 orderId, uint256 price) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(buyer);
        
        users[buyer].ordersPurchasesCount++;
        users[buyer].totalPurchases += price;
        users[buyer].purchasedOrders.push(orderId);
        
        users[seller].totalSales += price;
    }
    
    function recordItemPurchase(address buyer, address seller, uint256 itemId, uint256 price) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(buyer);
        
        users[buyer].fixedPricePurchasesCount++;
        users[buyer].totalPurchases += price;
        users[buyer].purchasedItems.push(itemId);
        
        users[seller].totalSales += price;
    }
    
    function recordAuctionPurchase(address buyer, address seller, uint256 auctionId, uint256 price) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(buyer);
        
        users[buyer].auctionsPurchasesCount++;
        users[buyer].totalPurchases += price;
        users[buyer].purchasedAuctions.push(auctionId);
        
        users[seller].totalSales += price;
    }

    function recordFeesPaid(address user, uint256 amount) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(user);
        
        users[user].totalFeesPaid += amount;
    }
    
    function setBlacklistStatus(address user, bool isSeller, bool isRoyalty) external onlyAuthorizedMarketplace {
        _createUserIfNotExists(user);
        
        users[user].isBlacklistedSeller = isSeller;
        users[user].isBlacklistedRoyalty = isRoyalty;

        emit UserBlacklisted(user, isSeller, isRoyalty);    
    }
    
    function getUserInfo(address user) external view returns (UserInfo memory) {
        return users[user];
    }
    
    function getUserAddress(uint256 id) external view returns (address) {
        require(id > 0 && id <= userCount, "UserStorage: invalid id");
        return userIds[id];
    }
    
    function getAllUsers() external view returns (address[] memory) {
        address[] memory allUsers = new address[](userCount);
        
        for (uint256 i = 0; i < userCount; i++) {
            allUsers[i] = userIds[i + 1];
        }

        return allUsers;
    }
    
    function getOverallStatistics() external view returns (
        uint256 totalListings,
        uint256 totalAuctions,
        uint256 totalPurchases,
        uint256 totalSales,
        uint256 totalFees
    ) {
        for (uint256 i = 1; i <= userCount; i++) {
            address user = userIds[i];
            totalListings += users[user].listingsCount;
            totalAuctions += users[user].auctionsCreatedCount;
            totalPurchases += users[user].totalPurchases;
            totalSales += users[user].totalSales;
            totalFees += users[user].totalFeesPaid;
        }
    }
    
    function getUserListedItems(address user) external view returns (uint256[] memory) {
        return users[user].listedItems;
    }
    
    function getUserCreatedAuctions(address user) external view returns (uint256[] memory) {
        return users[user].createdAuctions;
    }
    
    function getUserPurchasedItems(address user) external view returns (uint256[] memory) {
        return users[user].purchasedItems;
    }
    
    function getUserPurchasedAuctions(address user) external view returns (uint256[] memory) {
        return users[user].purchasedAuctions;
    }
}