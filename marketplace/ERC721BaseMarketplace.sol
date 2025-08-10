// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "calculators/CalculatorService.sol";
import "storage/UserStorage.sol";

abstract contract ERC721BaseMarketplace is IERC721Receiver, ReentrancyGuard {
    address public owner;
    bool public paused;
    UserStorage public userStorage;
    CalculatorService public calculator;

    event Paused(bool indexed paused);
    event Withdraw(uint256 indexed amount);
    event WithdrawToken(address indexed _tokenAddress, uint256 indexed _tokenId, address indexed seller);
    event RoyaltyPaymentFailed(address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Marketplace: paused");
        _;
    }

    constructor(address _userStorage, address _calculatorServise) {
        owner = msg.sender;
        userStorage = UserStorage(_userStorage);
        calculator = CalculatorService(_calculatorServise);
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function isERC721(address _tokenAddress) internal view returns (bool) {
        try IERC165(_tokenAddress).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
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

    function withdrawToken(uint256 _objectId) external virtual {}

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function getERC721Metadata(
        address _tokenAddress, 
        uint256 _tokenId
    ) external view returns(string memory, string memory, string memory) {
        if (_tokenAddress.code.length == 0) {
            return ("", "", "");
        }
        
        try IERC165(_tokenAddress).supportsInterface(type(IERC721Metadata).interfaceId) returns (bool result) {
            if (!result) {
                return ("", "", "");
            }
            
            IERC721Metadata token = IERC721Metadata(_tokenAddress);
            
            string memory name;
            string memory symbol;
            string memory uri;
            
            try token.name() returns (string memory n) {
                name = n;
            } 
            catch {}
            
            try token.symbol() returns (string memory s) {
                symbol = s;
            } 
            catch {}
            
            try token.tokenURI(_tokenId) returns (string memory u) {
                uri = u;
            } 
            catch {}
            
            return (name, symbol, uri);
        } 
        catch {
            return ("", "", "");
        }
    }
}