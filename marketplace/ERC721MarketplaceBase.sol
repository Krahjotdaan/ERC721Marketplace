// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract ERC721MarketplaceBase is IERC721Receiver, ReentrancyGuard {
    address public owner;
    uint256 public feePercentage; // base 10000 (e.x. 250 = 2,5%)
    address public feeRecipient;
    bool public paused;

    event Paused(bool indexed paused);
    event Withdraw(uint256 indexed amount);
    event WithdrawToken(address indexed _tokenAddress, uint256 indexed _tokenId, address indexed seller);
    event SetFeePercentage(uint256 indexed oldFeePercentage, uint256 indexed newFeePercentage);
    event SetFeeRecepient(address indexed oldFeeRecepient, address indexed newFeeRecepient);

    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Marketplace: paused");
        _;
    }

    constructor() {
        owner = msg.sender;
        feePercentage = 250;
        feeRecipient = owner;
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function isERC721(address _tokenAddress) internal view returns (bool) {
        try IERC165(_tokenAddress).supportsInterface(type(IERC721Metadata).interfaceId) returns (bool result) {
            return result;
        } 
        catch {
            return false;
        }
    }

    function isPermitted(IERC721 _token, uint256 _tokenId) internal view returns (bool) {
        address ownerOfToken = _token.ownerOf(_tokenId);
        return msg.sender == ownerOfToken ||
               msg.sender == _token.getApproved(_tokenId) ||
               _token.isApprovedForAll(ownerOfToken, msg.sender);
    }

    function withdraw() external virtual onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Marketplace: failed to send ETH");
        
        emit Withdraw(amount);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 1000, "Marketplace: fee percentage too high (max 10%)");
        uint256 oldFeePercentage = feePercentage;
        feePercentage = _feePercentage;

        emit SetFeePercentage(oldFeePercentage, feePercentage);
    }

    function setFeeRecepient(address _feeRecepient) external onlyOwner {
        require(_feeRecepient != address(0), "Marketplace: zero address");
        require(_feeRecepient != feeRecipient, "Marketplace: same recipient");
        
        address oldFeeRecepient = feeRecipient;
        feeRecipient = _feeRecepient;

        emit SetFeeRecepient(oldFeeRecepient, feeRecipient);
    }

    function countFee(uint256 _totalPrice, uint256 _orderFee) internal pure returns(uint256) {
        uint256 minFee = 0.000001 ether;
        uint256 fee = _totalPrice * _orderFee / 10000;
        if (fee < minFee) {
            fee = minFee;
        }
        if (fee > _totalPrice) {
            fee = _totalPrice;
        }
        
        return fee;
    }
}