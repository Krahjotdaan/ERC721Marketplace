// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "storage/UserStorage.sol";

/**
 * @title CalculatorService
 * @author Artem Ostapenko
 * @notice A service contract for calculating marketplace fees, royalties, and distributions
 * @dev This contract uses Chainlink Price Feeds for ETH/USD conversion and supports UUPS proxy pattern for upgrades
 */
contract CalculatorService is Initializable, UUPSUpgradeable {
    // Address constants for ETH/USD price feeds on different networks
    address private constant ETH_USD_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant ETH_USD_SEPOLIA = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address private constant ETH_USD_HOLESKY = 0x1B392212b2E7fe038E8Daf2d389f2A3921A77ADA;
    address private constant ETH_USD_POLYGON = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
    address private constant ETH_USD_ARBITRUM = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address private constant ETH_USD_OPTIMISM = 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e;

    /**
     * @notice The address that receives marketplace fees
     * @dev This is also the owner of the contract who can make configuration changes
     */
    address public feeRecipient;

    /**
     * @notice The percentage fee charged by the marketplace (in basis points)
     * @dev 100 = 1%, 250 = 2.5%, etc. Must be <= maxFeePercentage
     */
    uint256 public feePercentage; 

    /**
     * @notice The minimum fee amount in USD (scaled to 18 decimals)
     * @dev This ensures the marketplace fee is never too low, regardless of ETH price
     */
    uint256 public minFeeInUSD; 

    /**
     * @notice The maximum allowed fee percentage (in basis points)
     * @dev Default value is 1000 (10%), prevents excessive fee configuration
     */
    uint256 public maxFeePercentage = 1000;

    /**
     * @notice The maximum allowed royalty percentage (in basis points)
     * @dev Default value is 5000 (50%), prevents excessive royalty claims
     */
    uint256 public maxRoyaltyPercentage = 5000;

    /**
     * @notice The time threshold (in seconds) after which price data is considered stale
     * @dev Default value is 3600 seconds (1 hour)
     */
    uint256 public staleThreshold = 3600; // 1 hour

    /**
     * @notice The maximum time threshold (in seconds) before price data is too stale to use
     * @dev Default value is 7200 seconds (2 hours), beyond this point transactions revert
     */
    uint256 public maxStaleThreshold = 7200; // 2 hours

    /**
     * @notice The risk factor applied to price calculations when data is stale (in basis points)
     * @dev Default value is 10500 (105%), used to conservatively calculate minimum fees
     */
    uint256 public riskFactor = 10500; // 105%

    /**
     * @notice Reference to the UserStorage contract for user data and blacklists
     * @dev Used for checking seller/royalty blacklists and recording transaction data
     */
    UserStorage public userStorage;

    /**
     * @notice The Chainlink AggregatorV3Interface for ETH/USD price data
     * @dev Automatically set based on the current network
     */
    AggregatorV3Interface public priceFeed;

    /**
     * @notice Emitted when the fee percentage is changed
     * @param oldPercentage The previous fee percentage (in basis points)
     * @param newPercentage The new fee percentage (in basis points)
     */
    event FeePercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);

    /**
     * @notice Emitted when the minimum fee in USD is changed
     * @param oldMinFee The previous minimum fee in USD (scaled to 18 decimals)
     * @param newMinFee The new minimum fee in USD (scaled to 18 decimals)
     */
    event MinFeeInUSDChanged(uint256 indexed oldMinFee, uint256 indexed newMinFee);

    /**
     * @notice Emitted when the maximum royalty percentage is changed
     * @param oldPercentage The previous maximum royalty percentage (in basis points)
     * @param newPercentage The new maximum royalty percentage (in basis points)
     */
    event MaxRoyaltyPercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);

    /**
     * @notice Emitted when the fee recipient address is changed
     * @param oldRecipient The previous fee recipient address
     * @param newRecipient The new fee recipient address
     */
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);

    /**
     * @notice Emitted when the contract detects the network and price feed
     * @param chainId The detected chain ID
     * @param priceFeed The address of the price feed used
     */
    event NetworkDetected(uint256 indexed chainId, address indexed priceFeed);

    /**
     * @notice Emitted when the stale threshold is changed
     * @param oldThreshold The previous stale threshold (in seconds)
     * @param newThreshold The new stale threshold (in seconds)
     */
    event StaleThresholdChanged(uint256 indexed oldThreshold, uint256 indexed newThreshold);

    /**
     * @notice Emitted when the maximum stale threshold is changed
     * @param oldThreshold The previous maximum stale threshold (in seconds)
     * @param newThreshold The new maximum stale threshold (in seconds)
     */
    event MaxStaleThresholdChanged(uint256 indexed oldThreshold, uint256 indexed newThreshold);

    /**
     * @notice Emitted when the risk factor is changed
     * @param oldRiskFactor The previous risk factor (in basis points)
     * @param newRiskFactor The new risk factor (in basis points)
     */
    event RiskFactorChanged(uint256 indexed oldRiskFactor, uint256 indexed newRiskFactor);

    /**
     * @dev Modifier that restricts function access to the fee recipient (owner)
     * @notice Only the fee recipient can call functions with this modifier
     */
    modifier calcOnlyOwner() {
        require(msg.sender == feeRecipient, "Calculator: not owner");
        _;
    }

    /**
     * @notice Gets the current chain ID
     * @dev Uses inline assembly for gas efficiency
     * @return The current chain ID
     */
    function getChainId() internal view returns(uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /**
     * @notice Gets the appropriate ETH/USD price feed address for the current network
     * @dev Supports multiple networks: Mainnet, Sepolia, Holesky, Polygon, Arbitrum, Optimism
     * @return The address of the ETH/USD price feed for the current network
     */
    function getNetworkPriceFeed() public view returns (address) {
        uint256 chainId = getChainId();
        
        if (chainId == 1) return ETH_USD_MAINNET; 
        if (chainId == 11155111) return ETH_USD_SEPOLIA; 
        if (chainId == 17000) return ETH_USD_HOLESKY;
        if (chainId == 137) return ETH_USD_POLYGON;
        if (chainId == 42161) return ETH_USD_ARBITRUM;
        if (chainId == 10) return ETH_USD_OPTIMISM;
        
        revert("Calculator: unsupported network");
    }

    /**
     * @notice Initializes the contract with required parameters
     * @dev Can only be called once during contract deployment
     * @param _feeRecipient The address that will receive marketplace fees
     * @param _feePercentage The initial fee percentage (in basis points)
     * @param _minFeeInUSD The initial minimum fee in USD (scaled to 18 decimals)
     * @param _userStorage The address of the UserStorage contract
     */
    function initialize(
        address _feeRecipient,
        uint256 _feePercentage,
        uint256 _minFeeInUSD,
        address _userStorage
    ) public initializer {
        require(_feeRecipient != address(0), "Calculator: zero address");
        require(_feePercentage <= maxFeePercentage, "Calculator: invalid percentage");
        require(_minFeeInUSD > 0, "Calculator: min fee must be > 0");
        require(_userStorage != address(0), "Calculator: zero address");
        
        feeRecipient = _feeRecipient;
        feePercentage = _feePercentage;
        minFeeInUSD = _minFeeInUSD;
        priceFeed = AggregatorV3Interface(getNetworkPriceFeed());
        userStorage = UserStorage(_userStorage);

        emit NetworkDetected(getChainId(), address(priceFeed));
    }

    /**
     * @notice Calculates the minimum fee in ETH based on current price data
     * @dev Applies conservative pricing when price data is stale
     * @return The minimum fee amount in wei (ETH)
     */
    function getMinFeeInETH() public view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        uint256 timeSinceUpdate = block.timestamp - updatedAt;

        if (timeSinceUpdate >= maxStaleThreshold) {
            revert("Calculator: price data too stale, cannot proceed. Please wait for Chainlink to update.");
        }
        
        uint256 priceInWei;
        uint8 decimals = priceFeed.decimals();

        if (timeSinceUpdate >= staleThreshold) {
            priceInWei = uint256(price) * 10 ** (18 - uint256(decimals));
            uint256 conservativePrice = priceInWei * riskFactor / 10000;
        
            return (minFeeInUSD * 10 ** 18) / conservativePrice;
        }

        priceInWei = uint256(price) * 10 ** (18 - uint256(decimals));
        return (minFeeInUSD * 10 ** 18) / priceInWei;
    }

    /**
     * @notice Calculates the marketplace fee for a purchase
     * @dev Returns the greater of the percentage-based fee or minimum fee
     * @param totalPrice The total price of the purchase in wei
     * @return The fee amount in wei, never exceeding the total price
     */
    function calculateFee(uint256 totalPrice) public view returns (uint256) {
        uint256 fee = totalPrice * feePercentage / 10000;
        uint256 minFeeInETH = getMinFeeInETH();

        fee = fee > minFeeInETH ? fee : minFeeInETH;
        
        return fee > totalPrice ? totalPrice : fee;
    }

    /**
     * @notice Updates the fee percentage charged by the marketplace
     * @dev Only callable by the fee recipient (owner)
     * @param _feePercentage The new fee percentage in basis points
     */
    function setFeePercentage(uint256 _feePercentage) external calcOnlyOwner {
        require(_feePercentage <= maxFeePercentage, "Calculator: invalid percentage");
        require(_feePercentage != feePercentage, "Calculator: same fee");

        uint256 oldPercentage = feePercentage;
        feePercentage = _feePercentage;

        emit FeePercentageChanged(oldPercentage, _feePercentage);
    }

    /**
     * @notice Updates the minimum fee amount in USD
     * @dev Only callable by the fee recipient (owner)
     * @param _minFeeInUSD The new minimum fee in USD (scaled to 18 decimals)
     */
    function setMinFeeInUSD(uint256 _minFeeInUSD) external calcOnlyOwner {
        require(_minFeeInUSD > 0, "Calculator: min fee must be > 0");
        require(_minFeeInUSD != minFeeInUSD, "Calculator: same min fee in USD");

        uint256 oldMinFee = minFeeInUSD;
        minFeeInUSD = _minFeeInUSD;

        emit MinFeeInUSDChanged(oldMinFee, _minFeeInUSD);
    }

    /**
     * @notice Updates the fee recipient address
     * @dev Only callable by the current fee recipient (owner)
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external calcOnlyOwner {
        require(_feeRecipient != address(0), "Calculator: zero address");
        require(_feeRecipient != feeRecipient, "Calculator: same recipient");

        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(oldRecipient, _feeRecipient);
    }

    /**
     * @notice Updates the stale threshold for price data
     * @dev Only callable by the fee recipient (owner)
     * @param _staleThreshold The new stale threshold in seconds
     */
    function setStaleThreshold(uint256 _staleThreshold) external calcOnlyOwner {
        require(_staleThreshold > 0, "Calculator: stale threshold must be > 0");
        require(_staleThreshold < maxStaleThreshold, "Calculator: stale threshold must be < max stale threshold");
        require(_staleThreshold != staleThreshold, "Calculator: same stale threshold");

        uint256 oldStaleThreshold = staleThreshold;
        staleThreshold = _staleThreshold;

        emit StaleThresholdChanged(oldStaleThreshold, staleThreshold);
    }

    /**
     * @notice Updates the maximum stale threshold for price data
     * @dev Only callable by the fee recipient (owner)
     * @param _maxStaleThreshold The new maximum stale threshold in seconds
     */
    function setMaxStaleThreshold(uint256 _maxStaleThreshold) external calcOnlyOwner {
        require(_maxStaleThreshold > staleThreshold, "Calculator: max stale threshold must be > stale threshold");
        require(_maxStaleThreshold != maxStaleThreshold, "Calculator: same max stale threshold");

        uint256 oldMaxStaleThreshold = maxStaleThreshold;
        maxStaleThreshold = _maxStaleThreshold;

        emit MaxStaleThresholdChanged(oldMaxStaleThreshold, maxStaleThreshold);
    }

    /**
     * @notice Updates the risk factor for conservative price calculations
     * @dev Only callable by the fee recipient (owner)
     * @param _riskFactor The new risk factor in basis points (10000 = 100%)
     */
    function setRiskFactor(uint256 _riskFactor) external calcOnlyOwner {
        require(_riskFactor >= 10000, "Calculator: risk factor must be >= 100%");
        require(_riskFactor <= 11000, "Calculator: risk factor must be <= 110%");
        require(_riskFactor != riskFactor, "Calculator: same risk factor");

        uint256 oldRiskFactor = riskFactor;
        riskFactor = _riskFactor;

        emit RiskFactorChanged(oldRiskFactor, riskFactor);
    }

    /**
     * @notice Gets the current status of the price feed
     * @dev Useful for frontends to display price feed health
     * @return price The current price in the feed's native precision
     * @return updatedAt The timestamp when the price was last updated
     * @return timeSinceUpdate The number of seconds since the last update
     * @return isStale Whether the price data is considered stale
     * @return isTooStale Whether the price data is too stale to use
     */
    function getPriceFeedStatus() external view returns (
        uint256 price,
        uint256 updatedAt,
        uint256 timeSinceUpdate,
        bool isStale,
        bool isTooStale
    ) {
        (, int256 currentPrice, , uint256 _updatedAt, ) = priceFeed.latestRoundData();
        uint256 _timeSinceUpdate = block.timestamp - updatedAt;
        
        return (
            uint256(currentPrice),
            _updatedAt,
            _timeSinceUpdate,
            _timeSinceUpdate >= staleThreshold,
            _timeSinceUpdate >= maxStaleThreshold
        );
    }

    /**
     * @notice Gets comprehensive fee information
     * @dev Useful for frontends to display fee calculations
     * @return currentPrice The current ETH price in USD (6 decimals)
     * @return minFeeInUSD The minimum fee in USD (18 decimals)
     * @return currentMinFeeInETH The minimum fee in ETH (18 decimals)
     * @return feePercentage The current fee percentage (basis points)
     * @return priceFeedAddress The address of the price feed contract
     */
    function getFeeInfo() external view returns (uint256, uint256, uint256, uint256, address) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        uint256 priceInWei = uint256(price) * 10 ** (18 - uint256(decimals));
        uint256 currentMinFeeInETH = (minFeeInUSD * 10 ** 18) / priceInWei;
        
        return (
            uint256(price) / (10 ** (uint256(decimals) - 6)), // current price of ETH in USD (6 decimals)
            minFeeInUSD,
            currentMinFeeInETH,
            feePercentage,
            address(priceFeed)
        );
    }

    /**
     * @notice Calculates royalties for an NFT purchase
     * @dev Checks ERC-2981 compliance and applies royalty limits
     * @param tokenAddress The address of the NFT contract
     * @param tokenId The ID of the NFT
     * @param totalPrice The total purchase price in wei
     * @return royaltyAmount The calculated royalty amount in wei
     * @return royaltyRecipient The address of the royalty recipient
     */
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
            if (userStorage.getUserInfo(recipient).isBlacklistedRoyalty) {
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

    /**
     * @notice Calculates the complete distribution of funds for an NFT purchase
     * @dev Calculates royalty, marketplace fee, and seller amount
     * @param tokenAddress The address of the NFT contract
     * @param tokenId The ID of the NFT
     * @param totalPrice The total purchase price in wei
     * @return actualRoyalty The actual royalty amount to be paid
     * @return actualMarketplaceFee The actual marketplace fee to be collected
     * @return sellerAmount The amount that goes to the seller
     * @return royaltyRecipient The address of the royalty recipient
     */
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

    /**
     * @notice Updates the maximum allowed royalty percentage
     * @dev Only callable by the fee recipient (owner)
     * @param _maxRoyaltyPercentage The new maximum royalty percentage in basis points
     */
    function setMaxRoyaltyPercentage(uint256 _maxRoyaltyPercentage) external calcOnlyOwner {
        require(_maxRoyaltyPercentage <= 10000 && _maxRoyaltyPercentage > 0, "Calculator: invalid percentage");
        require(_maxRoyaltyPercentage != maxRoyaltyPercentage, "Calculator: same percentage");
        
        uint256 oldPercentage = maxRoyaltyPercentage;
        maxRoyaltyPercentage = _maxRoyaltyPercentage;

        emit MaxRoyaltyPercentageChanged(oldPercentage, _maxRoyaltyPercentage);
    }

    /**
     * @dev Internal function that authorizes upgrades to the contract
     * @notice Only the fee recipient (owner) can authorize upgrades
     */
    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == feeRecipient, "CalculatorService: not owner");
    }
}