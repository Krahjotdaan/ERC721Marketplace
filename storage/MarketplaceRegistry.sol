// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./UserStorage.sol";
import "./IMarketplaceRegistry.sol";

contract MarketplaceRegistry is IMarketplaceRegistry {
    address public owner;
    UserStorage public userStorage;
    
    mapping(address => bool) public authorizedMarketplaces;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Registry: not owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;  
        userStorage = new UserStorage(address(this));
    }
    
    function authorizeMarketplace(address marketplace) external onlyOwner {
        require(marketplace != address(0), "Registry: zero address");
        authorizedMarketplaces[marketplace] = true;
        
        emit MarketplaceAuthorized(marketplace);
    }
    
    function deauthorizeMarketplace(address marketplace) external onlyOwner {
        authorizedMarketplaces[marketplace] = false;
        emit MarketplaceDeauthorized(marketplace);
    }
    
    function isAuthorizedMarketplace(address contractAddress) external view returns (bool) {
        return authorizedMarketplaces[contractAddress];
    }
}