// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./BaseFeeCalculator.sol";

abstract contract ERC20MarketplaceFeeCalculator is BaseFeeCalculator {
    constructor(
        address _feeRecipient,
        uint256 _feePercentage,
        uint256 _minFeeInUSD
    ) BaseFeeCalculator(
        _feeRecipient,
        _feePercentage,
        _minFeeInUSD
    ) {}
}