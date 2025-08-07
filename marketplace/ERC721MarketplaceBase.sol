// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract ERC721MarketplaceBase is IERC721Receiver, ReentrancyGuard {
    address public owner;
    bool public paused;

    event Paused(bool indexed paused);
    event Withdraw(uint256 indexed amount);
    event WithdrawToken(address indexed _tokenAddress, uint256 indexed _tokenId, address indexed seller);

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
}