// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

abstract contract BaseFeeCalculator {
    address public feeRecipient;
    uint256 public feePercentage; 
    uint256 public minFeeInUSD; 
    AggregatorV3Interface public priceFeed;

    event FeePercentageChanged(uint256 indexed oldPercentage, uint256 indexed newPercentage);
    event MinFeeInUSDChanged(uint256 indexed oldMinFee, uint256 indexed newMinFee);
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);

    modifier calcOnlyOwner() {
        require(msg.sender == feeRecipient, "Calculator: not owner");
        _;
    }

    constructor(
        address _feeRecipient,
        uint256 _feePercentage,
        uint256 _minFeeInUSD,
        address _priceFeed
    ) {
        require(_feeRecipient != address(0), "Calculator: zero address");
        require(_feePercentage <= 10000, "Calculator: invalid percentage");
        require(_minFeeInUSD > 0, "Calculator: min fee must be > 0");
        
        feeRecipient = _feeRecipient;
        feePercentage = _feePercentage;
        minFeeInUSD = _minFeeInUSD;
        priceFeed = AggregatorV3Interface(_priceFeed);
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
        require(_feePercentage <= 10000, "Calculator: invalid percentage");

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
}