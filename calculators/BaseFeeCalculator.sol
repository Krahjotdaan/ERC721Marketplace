// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "storage/UserStorage.sol";

abstract contract BaseFeeCalculator {
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
    UserStorage public userStorage;
    AggregatorV3Interface public priceFeed;

    event FeePercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);
    event MinFeeInUSDChanged(uint256 indexed oldMinFee, uint256 indexed newMinFee);
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event NetworkDetected(uint256 indexed chainId, address indexed priceFeed);

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

    constructor(
        address _feeRecipient,
        uint256 _feePercentage,
        uint256 _minFeeInUSD,
        address _userStorage
    ) {
        require(_feeRecipient != address(0), "Calculator: zero address");
        require(_feePercentage <= maxFeePercentage, "Calculator: invalid percentage");
        require(_minFeeInUSD > 0, "Calculator: min fee must be > 0");
        
        feeRecipient = _feeRecipient;
        feePercentage = _feePercentage;
        minFeeInUSD = _minFeeInUSD;
        priceFeed = AggregatorV3Interface(getNetworkPriceFeed());
        userStorage = UserStorage(_userStorage);

        emit NetworkDetected(getChainId(), address(priceFeed));
    }

    function getMinFeeInETH() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        
        uint256 priceInWei = uint256(price) * 10 ** (18 - uint256(decimals));
        
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

        uint256 oldPercentage = feePercentage;
        feePercentage = _feePercentage;

        emit FeePercentageChanged(oldPercentage, _feePercentage);
    }

    function setMinFeeInUSD(uint256 _minFeeInUSD) external calcOnlyOwner {
        require(_minFeeInUSD > 0, "Calculator: min fee must be > 0");

        uint256 oldMinFee = minFeeInUSD;
        minFeeInUSD = _minFeeInUSD;

        emit MinFeeInUSDChanged(oldMinFee, _minFeeInUSD);
    }

    function setFeeRecipient(address _feeRecipient) external calcOnlyOwner {
        require(_feeRecipient != address(0), "Calculator: zero address");

        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;

        emit FeeRecipientChanged(oldRecipient, _feeRecipient);
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
}