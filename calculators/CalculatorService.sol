// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "storage/UserStorage.sol";

contract CalculatorService is Initializable, UUPSUpgradeable {
    address private constant ETH_USD_MAINNET = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant ETH_USD_SEPOLIA = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address private constant ETH_USD_HOLESKY = 0x1B392212b2E7fe038E8Daf2d389f2A3921A77ADA;
    address private constant ETH_USD_POLYGON = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;
    address private constant ETH_USD_ARBITRUM = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address private constant ETH_USD_OPTIMISM = 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e;

    address public feeRecipient;
    uint256 public feePercentage; 
    uint256 public minFeeInUSD; 
    uint256 public maxFeePercentage = 1000;
    uint256 public maxRoyaltyPercentage = 5000;
    uint256 public staleThreshold = 3600; // 1 hour
    uint256 public maxStaleThreshold = 7200; // 2 hours
    uint256 public riskFactor = 10500; // 105%
    UserStorage public userStorage;
    AggregatorV3Interface public priceFeed;

    event FeePercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);
    event MinFeeInUSDChanged(uint256 indexed oldMinFee, uint256 indexed newMinFee);
    event MaxRoyaltyPercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event NetworkDetected(uint256 indexed chainId, address indexed priceFeed);
    event StaleThresholdChanged(uint256 indexed oldThreshold, uint256 indexed newThreshold);
    event MaxStaleThresholdChanged(uint256 indexed oldThreshold, uint256 indexed newThreshold);
    event RiskFactorChanged(uint256 indexed oldRiskFactor, uint256 indexed newRiskFactor);

    modifier calcOnlyOwner() {
        require(msg.sender == feeRecipient, "Calculator: not owner");
        _;
    }

    function getChainId() internal view returns(uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        return chainId;
    }

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

    function calculateFee(uint256 totalPrice) public view returns (uint256) {
        uint256 fee = totalPrice * feePercentage / 10000;
        uint256 minFeeInETH = getMinFeeInETH();

        fee = fee > minFeeInETH ? fee : minFeeInETH;
        
        return fee > totalPrice ? totalPrice : fee;
    }

    function setFeePercentage(uint256 _feePercentage) external calcOnlyOwner {
        require(_feePercentage <= maxFeePercentage, "Calculator: invalid percentage");
        require(_feePercentage != feePercentage, "Calculator: same fee");

        uint256 oldPercentage = feePercentage;
        feePercentage = _feePercentage;

        emit FeePercentageChanged(oldPercentage, _feePercentage);
    }

    function setMinFeeInUSD(uint256 _minFeeInUSD) external calcOnlyOwner {
        require(_minFeeInUSD > 0, "Calculator: min fee must be > 0");
        require(_minFeeInUSD != minFeeInUSD, "Calculator: same min fee in USD");

        uint256 oldMinFee = minFeeInUSD;
        minFeeInUSD = _minFeeInUSD;

        emit MinFeeInUSDChanged(oldMinFee, _minFeeInUSD);
    }

    function setFeeRecipient(address _feeRecipient) external calcOnlyOwner {
        require(_feeRecipient != address(0), "Calculator: zero address");
        require(_feeRecipient != feeRecipient, "Calculator: same recipient");

        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(oldRecipient, _feeRecipient);
    }

    function setStaleThreshold(uint256 _staleThreshold) external calcOnlyOwner {
        require(_staleThreshold > 0, "Calculator: stale threshold must be > 0");
        require(_staleThreshold < maxStaleThreshold, "Calculator: stale threshold must be < max stale threshold");
        require(_staleThreshold != staleThreshold, "Calculator: same stale threshold");

        uint256 oldStaleThreshold = staleThreshold;
        staleThreshold = _staleThreshold;

        emit StaleThresholdChanged(oldStaleThreshold, staleThreshold);
    }

    function setMaxStaleThreshold(uint256 _maxStaleThreshold) external calcOnlyOwner {
        require(_maxStaleThreshold > staleThreshold, "Calculator: max stale threshold must be > stale threshold");
        require(_maxStaleThreshold != maxStaleThreshold, "Calculator: same max stale threshold");

        uint256 oldMaxStaleThreshold = maxStaleThreshold;
        maxStaleThreshold = _maxStaleThreshold;

        emit MaxStaleThresholdChanged(oldMaxStaleThreshold, maxStaleThreshold);
    }

    function setRiskFactor(uint256 _riskFactor) external calcOnlyOwner {
        require(_riskFactor >= 10000, "Calculator: risk factor must be >= 100%");
        require(_riskFactor <= 11000, "Calculator: risk factor must be <= 110%");
        require(_riskFactor != riskFactor, "Calculator: same risk factor");

        uint256 oldRiskFactor = riskFactor;
        riskFactor = _riskFactor;

        emit RiskFactorChanged(oldRiskFactor, riskFactor);
    }

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
        require(_maxRoyaltyPercentage <= 10000 && _maxRoyaltyPercentage > 0, "Calculator: invalid percentage");
        require(_maxRoyaltyPercentage != maxRoyaltyPercentage, "Calculator: same percentage");
        
        uint256 oldPercentage = maxRoyaltyPercentage;
        maxRoyaltyPercentage = _maxRoyaltyPercentage;

        emit MaxRoyaltyPercentageChanged(oldPercentage, _maxRoyaltyPercentage);
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == feeRecipient, "CalculatorService: not owner");
    }
}