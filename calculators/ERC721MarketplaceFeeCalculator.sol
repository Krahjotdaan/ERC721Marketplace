// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./BaseFeeCalculator.sol";

abstract contract ERC721MarketplaceFeeCalculator is BaseFeeCalculator {
    uint256 public maxRoyaltyPercentage = 5000; 
    mapping(address => bool) public royaltyBlacklist;

    event MaxRoyaltyPercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);
    event RoyaltyBlacklisted(address indexed recipient);

    constructor(
        address _feeRecipient,
        uint256 _feePercentage,
        uint256 _minFeeInUSD,
        address _priceFeed
    ) BaseFeeCalculator(
        _feeRecipient,
        _feePercentage,
        _minFeeInUSD,
        _priceFeed
    ) {}

    function calculateRoyalties(
        address tokenAddress,
        uint256 tokenId,
        uint256 totalPrice
    ) public view returns (uint256 royaltyAmount, address royaltyRecipient) {
        if (tokenAddress.code.length == 0) {
            return (0, address(0));
        }
        
        if (!IERC165(tokenAddress).supportsInterface(type(IERC2981).interfaceId)) {
            return (0, address(0));
        }
        
        try IERC2981(tokenAddress).royaltyInfo(tokenId, totalPrice) returns (address recipient, uint256 amount) {
            if (royaltyBlacklist[recipient]) {
                return (0, address(0));
            }
            
            uint256 maxAllowed = (totalPrice * maxRoyaltyPercentage) / 10000;
            if (amount > maxAllowed) {
                amount = maxAllowed;
            }
            
            return (amount, recipient);
        } 
        catch {
            return (0, address(0));
        }
    }

    function calculateDistribution(
        address tokenAddress,
        uint256 tokenId,
        uint256 totalPrice
    ) public view returns (uint256, uint256, uint256, address) {
        (uint256 royaltyAmount, address royaltyRecipient) = calculateRoyalties(tokenAddress, tokenId, totalPrice);
        uint256 marketplaceFee = calculateFee(totalPrice); 

        uint256 actualRoyalty = royaltyAmount > totalPrice ? totalPrice : royaltyAmount;
        uint256 remaining = totalPrice - actualRoyalty;
        uint256 actualMarketplaceFee = marketplaceFee > remaining ? remaining : marketplaceFee;
        uint256 sellerAmount = remaining - actualMarketplaceFee;
        
        return (actualRoyalty, actualMarketplaceFee, sellerAmount, royaltyRecipient);
    }

    function setMaxRoyaltyPercentage(uint256 _maxRoyaltyPercentage) external calcOnlyOwner {
        require(_maxRoyaltyPercentage <= 10000, "Calculator: invalid percentage");
        
        uint256 oldPercentage = maxRoyaltyPercentage;
        maxRoyaltyPercentage = _maxRoyaltyPercentage;

        emit MaxRoyaltyPercentageChanged(oldPercentage, _maxRoyaltyPercentage);
    }

    function addToRoyaltyBlacklist(address recipient) external calcOnlyOwner {
        royaltyBlacklist[recipient] = true;
        emit RoyaltyBlacklisted(recipient);
    }
}