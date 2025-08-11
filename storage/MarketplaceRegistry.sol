// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./UserStorage.sol";
import "./IMarketplaceRegistry.sol";

/**
 * @title MarketplaceRegistry
 * @author Artem Ostapenko
 * @notice A registry contract that manages authorized marketplaces and shared services
 * @dev This contract serves as a central registry for all marketplace instances, providing
 * a single UserStorage instance for user data and blacklists, and managing authorization
 * for marketplace contracts. It implements the IMarketplaceRegistry interface.
 */
contract MarketplaceRegistry is IMarketplaceRegistry {
    /**
     * @notice The address of the registry owner/administrator
     * @dev Owner has exclusive rights to authorize/deauthorize marketplaces
     */
    address public owner;

    /**
     * @notice The shared UserStorage contract for all authorized marketplaces
     * @dev Stores user statistics, blacklists, and transaction history across all marketplaces
     */
    UserStorage public userStorage;
    
    /**
     * @notice Mapping of marketplace addresses to their authorization status
     * @dev True if the marketplace is authorized, false otherwise
     */
    mapping(address => bool) public authorizedMarketplaces;
    
    /**
     * @dev Modifier that restricts function access to the owner
     * @notice Only the owner can call functions with this modifier
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Registry: not owner");
        _;
    }
    
    /**
     * @notice Initializes the registry contract
     * @dev Sets the deployer as owner and creates a new UserStorage instance
     */
    constructor() {
        owner = msg.sender;  
        userStorage = new UserStorage(address(this));
    }
    
    /// @inheritdoc IMarketplaceRegistry
    function authorizeMarketplace(address marketplace) external onlyOwner {
        require(marketplace != address(0), "Registry: zero address");
        authorizedMarketplaces[marketplace] = true;
        
        emit MarketplaceAuthorized(marketplace);
    }
    
    /// @inheritdoc IMarketplaceRegistry
    function deauthorizeMarketplace(address marketplace) external onlyOwner {
        authorizedMarketplaces[marketplace] = false;
        emit MarketplaceDeauthorized(marketplace);
    }
    
    /// @inheritdoc IMarketplaceRegistry
    function isAuthorizedMarketplace(address contractAddress) external view returns (bool) {
        return authorizedMarketplaces[contractAddress];
    }
}