// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title IMarketplaceRegistry
 * @author Artem Ostapenko
 * @notice Interface for a registry contract that manages authorized marketplaces
 * @dev This interface defines the standard functions for marketplace authorization
 * and status checking. It enables a central registry to control which marketplace
 * contracts are allowed to interact with shared services like UserStorage.
 */
interface IMarketplaceRegistry {
    /**
     * @notice Emitted when a marketplace is authorized to use the registry services
     * @param marketplace The address of the marketplace contract that was authorized
     */
    event MarketplaceAuthorized(address indexed marketplace);

    /**
     * @notice Emitted when a marketplace is deauthorized from using the registry services
     * @param marketplace The address of the marketplace contract that was deauthorized
     */
    event MarketplaceDeauthorized(address indexed marketplace);

    /**
     * @notice Authorizes a marketplace contract to use registry services
     * @dev Only the registry owner can call this function
     * @param marketplace The address of the marketplace contract to authorize
     */
    function authorizeMarketplace(address marketplace) external;

    /**
     * @notice Deauthorizes a marketplace contract from using registry services
     * @dev Only the registry owner can call this function
     * @param marketplace The address of the marketplace contract to deauthorize
     */
    function deauthorizeMarketplace(address marketplace) external;

    /**
     * @notice Checks if a marketplace contract is authorized to use registry services
     * @dev Returns true if the marketplace is authorized, false otherwise
     * @param marketplace The address of the marketplace contract to check
     * @return True if the marketplace is authorized, false otherwise
     */
    function isAuthorizedMarketplace(address marketplace) external view returns (bool);
}