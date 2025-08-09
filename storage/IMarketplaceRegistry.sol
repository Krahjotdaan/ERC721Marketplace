// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IMarketplaceRegistry {
    event MarketplaceAuthorized(address indexed marketplace);
    event MarketplaceDeauthorized(address indexed marketplace);

    function authorizeMarketplace(address marketplace) external;
    function deauthorizeMarketplace(address marketplace) external;
    function isAuthorizedMarketplace(address marketplace) external view returns (bool);
}