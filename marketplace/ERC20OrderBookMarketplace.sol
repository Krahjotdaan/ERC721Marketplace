// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "calculators/CalculatorService.sol";
import "storage/UserStorage.sol";

/**
 * @title ERC20OrderBookMarketplace
 * @author Artem Ostapenko
 * @notice A decentralized marketplace for ERC-20 token orders with order book functionality
 * @dev This contract allows users to list ERC-20 tokens for sale at fixed prices and enables
 * buyers to purchase these tokens using ETH. It uses a UUPS proxy pattern for upgradeability.
 */
contract ERC20OrderBookMarketplace is Initializable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @notice Data structure representing a token listing
     * @dev Stores all information about a token order including seller, price, and quantity
     */
    struct Order {
        address seller;
        address tokenAddress;
        uint256 price;
        uint256 tokensOnSale;
        uint256 cancelledTokens;
        bool isSold;
        bool isCancelled;
    }

    /**
     * @notice The address of the marketplace owner/administrator
     * @dev Owner has special privileges like pausing the marketplace
     */
    address public owner;

    /**
     * @notice The ID of the last created order
     * @dev Used to generate unique order IDs (1, 2, 3, ...)
     */
    uint256 public lastOrderId;

    /**
     * @notice Whether the marketplace is currently paused
     * @dev When paused, no new orders or purchases can be made
     */
    bool public paused;

    /**
     * @notice Reference to the UserStorage contract for user data and blacklists
     * @dev Used for recording transaction data and checking seller blacklists
     */
    UserStorage public userStorage;

    /**
     * @notice Reference to the CalculatorService for fee calculations
     * @dev Used to calculate marketplace fees and validate price feeds
     */
    CalculatorService public calculator;

    /**
     * @notice Mapping of order ID to Order struct
     * @dev Stores all active and completed orders
     */
    mapping(uint256 => Order) public listOfOrders;

    /**
     * @notice Emitted when a new order is listed on the marketplace
     * @param orderId The unique ID of the new order
     * @param seller The address of the seller who listed the order
     * @param tokenAddress The address of the ERC-20 token being sold
     * @param price The price per token in wei
     * @param amount The number of tokens listed for sale
     */
    event ListOrder(
        uint256 indexed orderId, 
        address indexed seller, 
        address indexed tokenAddress, 
        uint256 price, 
        uint256 amount
    );

    /**
     * @notice Emitted when the price of an existing order is changed
     * @param orderId The ID of the order with changed price
     * @param oldPrice The previous price per token in wei
     * @param newPrice The new price per token in wei
     */
    event ChangePrice(uint256 indexed orderId, uint256 indexed oldPrice, uint256 indexed newPrice);

    /**
     * @notice Emitted when a purchase is made on the marketplace
     * @param orderId The ID of the order that was purchased from
     * @param tokenAddress The address of the purchased ERC-20 token
     * @param customer The address of the buyer
     * @param price The price per token in wei at the time of purchase
     * @param amount The number of tokens purchased
     * @param fee The marketplace fee collected in wei
     * @param isSold Whether the order is now completely sold out
     */
    event Purchase(
        uint256 indexed orderId, 
        address indexed tokenAddress, 
        address indexed customer, 
        uint256 price, 
        uint256 amount,
        uint256 fee,
        bool isSold
    );

    /**
     * @notice Emitted when tokens are cancelled from an order
     * @param orderId The ID of the order from which tokens were cancelled
     * @param amount The number of tokens cancelled
     * @param isCancelled Whether the entire order is now cancelled
     */
    event Cancel(uint256 indexed orderId, uint256 indexed amount, bool indexed isCancelled);

    /**
     * @notice Emitted when ETH is withdrawn from the marketplace
     * @param amount The amount of ETH withdrawn in wei
     */
    event Withdraw(uint256 indexed amount);

    /**
     * @notice Emitted when tokens are withdrawn after cancellation
     * @param orderId The ID of the order from which tokens were withdrawn
     * @param seller The address of the seller who withdrew tokens
     * @param amount The number of tokens withdrawn
     */
    event WithdrawTokens(uint256 indexed orderId, address indexed seller, uint256 indexed amount);

    /**
     * @notice Emitted when the marketplace is paused or unpaused
     * @param paused The new paused state of the marketplace
     */
    event Paused(bool indexed paused);

    /**
     * @dev Modifier that validates the price is greater than zero
     * @param _price The price to validate
     */
    modifier validPrice(uint256 _price) {
        require(_price > 0, "Marketplace: price must be over 0");
        _;
    }

    /**
     * @dev Modifier that validates the amount is greater than zero
     * @param _amount The amount to validate
     */
    modifier validAmount(uint256 _amount) {
        require(_amount > 0, "Marketplace: amount must be over 0");
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
     * @dev Modifier that restricts function access to the owner
     * @notice Only the owner can call functions with this modifier
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    /**
     * @dev Modifier that validates an order ID exists
     * @param _orderId The order ID to validate
     */
    modifier orderExists(uint256 _orderId) {
        require(_orderId > 0 && _orderId <= lastOrderId, "Marketplace: item does not exist");
        _;
    }

    /**
     * @notice Checks if an order is currently available for purchase
     * @dev An order is on sale if it is neither sold nor cancelled
     * @param order The Order struct to check
     * @return True if the order is on sale, false otherwise
     */
    function isOnSale(Order memory order) internal pure returns (bool) {
        return !order.isSold && !order.isCancelled;
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
    function initialize(address _userStorage, address _calculatorServise) public initializer {
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
     * @notice Withdraws all ETH from the contract to the owner
     * @dev Only callable by the owner when the marketplace is not paused
     */
    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Marketplace: failed to send ETH");
        
        emit Withdraw(amount);
    }

    /**
     * @notice Lists an ERC-20 token order for sale
     * @dev Transfers tokens from seller to marketplace and creates a new order
     * @param _tokenAddress The address of the ERC-20 token to sell
     * @param _price The price per token in wei
     * @param _amount The number of tokens to list for sale
     */
    function listOrder(address _tokenAddress, uint256 _price, uint256 _amount) external whenNotPaused nonReentrant validPrice(_price) validAmount(_amount) {
        require(_tokenAddress != address(0), "Marketplace: tokenAddress is address(0)");
        require(_tokenAddress.code.length > 0, "Marketplace: tokenAddress is not a contract");
        require(!userStorage.getUserInfo(msg.sender).isBlacklistedSeller, "Marketplace: msg.sender is in blacklist of sellers");

        IERC20 token = IERC20(_tokenAddress);

        require(token.balanceOf(msg.sender) >= _amount, "Marketplace: not enough balance");
        require(
            token.allowance(msg.sender, address(this)) >= _amount,
            "Marketplace: not enough approved tokens to marketplace. Call function 'approve' to grant permission to marketplace to dispose of tokens"
        );
        require(token.trySafeTransferFrom(msg.sender, address(this), _amount), "Marketplace: token transfer failed");

        lastOrderId++;

        listOfOrders[lastOrderId] = Order({
            seller: msg.sender,
            tokenAddress: _tokenAddress,
            price: _price,
            tokensOnSale: _amount,
            cancelledTokens: 0,
            isSold: false,
            isCancelled: false
        });

        userStorage.recordOrder(msg.sender, lastOrderId);

        emit ListOrder({
            orderId: lastOrderId,
            seller: msg.sender,
            tokenAddress: _tokenAddress,
            price: _price,
            amount: _amount
        });
    }

    /**
     * @notice Changes the price of an existing order
     * @dev Only the seller can change the price of their order
     * @param _orderId The ID of the order to update
     * @param _newPrice The new price per token in wei
     */
    function changePrice(uint256 _orderId, uint256 _newPrice) external whenNotPaused orderExists(_orderId) validPrice(_newPrice) {
        Order storage order = listOfOrders[_orderId];
        
        require(order.price != _newPrice, "Marketplace: new price and current price must be different");
        require(isOnSale(order), "Marketplace: order is not on sale");
        require(msg.sender == order.seller, "Marketplace: permission denied");

        uint256 oldPrice = order.price;
        order.price = _newPrice;

        emit ChangePrice(_orderId, oldPrice, _newPrice);
    }

    /**
     * @notice Purchases tokens from an order
     * @dev Transfers tokens to buyer, sends ETH to seller, and collects marketplace fee
     * @param _orderId The ID of the order to purchase from
     * @param _amount The number of tokens to purchase
     */
    function purchase(uint256 _orderId, uint256 _amount) external payable nonReentrant whenNotPaused orderExists(_orderId) validAmount(_amount) {
        Order storage order = listOfOrders[_orderId];

        require(isOnSale(order), "Marketplace: order is not on sale");
        require(order.tokensOnSale >= _amount, "Marketplace: too many tokens to purchase");

        uint256 requiredEth = order.price * _amount;

        require(requiredEth / _amount == order.price, "Marketplace: multiplication overflow");
        require(msg.value >= requiredEth, "Marketplace: not enough eth"); 

        IERC20 token = IERC20(order.tokenAddress);

        require(token.balanceOf(address(this)) >= _amount, "Marketplace: not enough tokens in the contract");

        order.tokensOnSale -= _amount;
        if (order.tokensOnSale == 0) {
            order.isSold = true;
        }

        uint256 fee = calculator.calculateFee(requiredEth);

        (bool feeSent, ) = payable(calculator.feeRecipient()).call{value: fee}("");
        require(feeSent, "Marketplace: failed to send fee");

        userStorage.recordFeesPaid(msg.sender, fee);

        uint256 sellerAmount = requiredEth - fee;

        if (sellerAmount > 0) {
            (bool sent, ) = payable(order.seller).call{value: sellerAmount}("");
            require(sent, "Marketplace: failed to send ETH");
        }
        
        token.safeTransfer(msg.sender, _amount);

        userStorage.recordOrderPurchase(msg.sender, order.seller, _orderId, requiredEth);

        if (msg.value > requiredEth) {
            (bool refunded, ) = payable(msg.sender).call{value: msg.value - requiredEth}("");
            require(refunded, "Marketplace: failed to refund");
        }

        emit Purchase({
            orderId: _orderId,
            tokenAddress: order.tokenAddress,
            customer: msg.sender,
            price: order.price,
            amount: _amount,
            fee: fee,
            isSold: order.isSold
        });
    }

    /**
     * @notice Cancels tokens from an existing order
     * @dev Returns cancelled tokens to the seller and updates order status
     * @param _orderId The ID of the order to cancel tokens from
     * @param _amount The number of tokens to cancel
     */
    function cancel(uint256 _orderId, uint256 _amount) external whenNotPaused orderExists(_orderId) validAmount(_amount) {
        Order storage order = listOfOrders[_orderId];
        
        require(isOnSale(order), "Marketplace: order is not on sale");
        require(msg.sender == order.seller, "Marketplace: permission denied");
        require(order.tokensOnSale >= _amount, "Marketplace: too many tokens to cancel");

        order.tokensOnSale -= _amount;
        order.cancelledTokens += _amount;

        if (order.tokensOnSale == 0) {
            order.isCancelled = true;
        }
        
        emit Cancel(_orderId, _amount, order.isCancelled);
    }

    /**
     * @notice Withdraws cancelled tokens back to the seller
     * @dev Can only withdraw tokens that have been cancelled
     * @param _orderId The ID of the order to withdraw tokens from
     * @param _amount The number of tokens to withdraw
     */
    function withdrawTokens(uint256 _orderId, uint256 _amount) external orderExists(_orderId) validAmount(_amount) {
        Order storage order = listOfOrders[_orderId];

        require(order.cancelledTokens >= _amount, "Marketplace: too many tokens to withdraw");
        require(msg.sender == order.seller, "Marketplace: permission denied");

        IERC20 token = IERC20(order.tokenAddress);

        require(token.balanceOf(address(this)) >= _amount, "Marketplace: not enough tokens in the contract");

        order.cancelledTokens -= _amount;
        
        require(token.trySafeTransfer(msg.sender, _amount), "Marketplace: token transfer failed");

        emit WithdrawTokens(_orderId, msg.sender, _amount);
    }

    /**
     * @notice Pauses or unpauses the marketplace
     * @dev Only the owner can pause/unpause the marketplace
     * @param _paused The new paused state (true to pause, false to unpause)
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(paused);
    }

    /**
     * @dev Internal function that authorizes upgrades to the contract
     * @notice Only the owner can authorize upgrades
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}