// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "calculators/CalculatorService.sol";
import "storage/UserStorage.sol";

/**
 * @title ERC721BaseMarketplace
 * @author Artem Ostapenko
 * @notice Abstract base contract for ERC-721 NFT marketplaces
 * @dev This contract provides common functionality for ERC-721 marketplaces including
 * ownership management, pause functionality, and metadata retrieval. It is designed to be
 * inherited by specific marketplace implementations like auction and fixed-price marketplaces.
 * Uses UUPS proxy pattern for upgradeability and implements the IERC721Receiver interface
 * to safely receive NFTs.
 */
abstract contract ERC721BaseMarketplace is Initializable, UUPSUpgradeable, IERC721Receiver, ReentrancyGuard {
    /**
     * @notice The address of the marketplace owner/administrator
     * @dev Owner has special privileges like pausing the marketplace and withdrawing funds
     */
    address public owner;

    /**
     * @notice Whether the marketplace is currently paused
     * @dev When paused, most marketplace functions are disabled
     */
    bool public paused;

    /**
     * @notice Reference to the UserStorage contract for user data and blacklists
     * @dev Used for recording transaction data and checking user status
     */
    UserStorage public userStorage;

    /**
     * @notice Reference to the CalculatorService for fee and royalty calculations
     * @dev Used to calculate marketplace fees, royalties, and distributions
     */
    CalculatorService public calculator;

    /**
     * @notice Emitted when the marketplace is paused or unpaused
     * @param paused The new paused state of the marketplace
     */
    event Paused(bool indexed paused);

    /**
     * @notice Emitted when ETH is withdrawn from the marketplace
     * @param amount The amount of ETH withdrawn in wei
     */
    event Withdraw(uint256 indexed amount);

    /**
     * @notice Emitted when an NFT is withdrawn by the seller
     * @param _tokenAddress The address of the ERC-721 contract
     * @param _tokenId The ID of the NFT that was withdrawn
     * @param seller The address of the seller who withdrew the NFT
     */
    event WithdrawToken(address indexed _tokenAddress, uint256 indexed _tokenId, address indexed seller);

    /**
     * @notice Emitted when a royalty payment fails
     * @param recipient The address of the royalty recipient
     * @param amount The amount of ETH that failed to be sent
     */
    event RoyaltyPaymentFailed(address indexed recipient, uint256 amount);

    /**
     * @dev Modifier that restricts function access to the owner
     * @notice Only the owner can call functions with this modifier
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    /**
     * @dev Modifier that ensures the marketplace is not paused
     * @notice Reverts if the marketplace is currently paused
     */
    modifier whenNotPaused() {
        require(!paused, "Marketplace: paused");
        _;
    }

    /**
     * @dev Empty constructor required for proxy pattern
     * @notice The contract is initialized through the initialize() function instead
     */
    constructor() {}

    /**
     * @notice Initializes the contract with required dependencies
     * @dev Can only be called once during contract deployment
     * @param _userStorage The address of the UserStorage contract
     * @param _calculatorServise The address of the CalculatorService contract
     */
    function initialize(address _userStorage, address _calculatorServise) public virtual initializer {
        owner = msg.sender;
        userStorage = UserStorage(_userStorage);
        calculator = CalculatorService(_calculatorServise);
    }

    /**
     * @notice Allows the contract to receive ETH payments
     * @dev This function is called when ETH is sent to the contract
     */
    receive() external payable {}

    /**
     * @notice Handles the receipt of an NFT by implementing the IERC721Receiver interface
     * @dev Required for safe transfers when calling safeTransferFrom on ERC-721 tokens
     * @return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)")) as a magic value
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Checks if a contract implements the ERC-721 interface
     * @dev Uses ERC-165 interface detection to verify ERC-721 compliance
     * @param _tokenAddress The address of the contract to check
     * @return True if the contract implements ERC-721, false otherwise
     */
    function isERC721(address _tokenAddress) internal view returns (bool) {
        try IERC165(_tokenAddress).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
            return result;
        } 
        catch {
            return false;
        }
    }

    /**
     * @notice Checks if the caller has permission to transfer a specific NFT
     * @dev Verifies ownership, direct approval, or operator approval
     * @param _token The IERC721 contract interface
     * @param _tokenId The ID of the NFT to check
     * @return True if the caller is permitted to transfer the NFT, false otherwise
     */
    function isPermitted(IERC721 _token, uint256 _tokenId) internal view returns (bool) {
        address ownerOfToken = _token.ownerOf(_tokenId);
        return msg.sender == ownerOfToken ||
               msg.sender == _token.getApproved(_tokenId) ||
               _token.isApprovedForAll(ownerOfToken, msg.sender);
    }

    /**
     * @notice Withdraws all ETH from the contract to the owner
     * @dev Virtual function that can be overridden by child contracts
     * Child contracts may modify the amount withdrawn (e.g., exclude frozen ETH)
     */
    function withdraw() external virtual onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        
        require(sent, "Marketplace: failed to send ETH");
        
        emit Withdraw(amount);
    }

    /**
     * @notice Abstract function for withdrawing NFTs
     * @dev Must be implemented by child contracts to handle specific withdrawal logic
     * @param _objectId Identifier for the object to withdraw (auction ID, item ID, etc.)
     */
    function withdrawToken(uint256 _objectId) external virtual {}

    /**
     * @notice Pauses or unpauses the marketplace
     * @dev Only callable by the owner
     * @param _paused The new paused state (true to pause, false to unpause)
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    /**
     * @notice Retrieves metadata for an ERC-721 NFT with error handling
     * @dev Safely attempts to retrieve name, symbol, and tokenURI with individual try/catch blocks
     * @param _tokenAddress The address of the ERC-721 contract
     * @param _tokenId The ID of the NFT to retrieve metadata for
     * @return name The name of the NFT collection (empty string if unavailable)
     * @return symbol The symbol of the NFT collection (empty string if unavailable)
     * @return uri The token URI of the specific NFT (empty string if unavailable)
     */
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

    /**
     * @dev Internal function that authorizes upgrades to the contract
     * @notice Virtual function that can be overridden by child contracts
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}