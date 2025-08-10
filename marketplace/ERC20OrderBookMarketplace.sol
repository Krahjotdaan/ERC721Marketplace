// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "calculators/CalculatorService.sol";
import "storage/UserStorage.sol";

contract ERC20OrderBookMarketplace is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Order {
        address seller;
        address tokenAddress;
        uint256 price;
        uint256 tokensOnSale;
        uint256 cancelledTokens;
        bool isSold;
        bool isCancelled;
    }

    address public owner;
    uint256 public lastOrderId;
    bool public paused;
    UserStorage public userStorage;
    CalculatorService public calculator;

    mapping(uint256 => Order) public listOfOrders;

    event ListOrder(
        uint256 indexed orderId, 
        address indexed seller, 
        address indexed tokenAddress, 
        uint256 price, 
        uint256 amount
    );
    event ChangePrice(uint256 indexed orderId, uint256 indexed oldPrice, uint256 indexed newPrice);
    event Purchase(
        uint256 indexed orderId, 
        address indexed tokenAddress, 
        address indexed customer, 
        uint256 price, 
        uint256 amount,
        uint256 fee,
        bool isSold
    );
    event Cancel(uint256 indexed orderId, uint256 indexed amount, bool indexed isCancelled);
    event Withdraw(uint256 indexed amount);
    event WithdrawTokens(uint256 indexed orderId, address indexed seller, uint256 indexed amount);
    event Paused(bool indexed paused);

    modifier validPrice(uint256 _price) {
        require(_price > 0, "Marketplace: price must be over 0");
        _;
    }

    modifier validAmount(uint256 _amount) {
        require(_amount > 0, "Marketplace: amount must be over 0");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Marketplace: paused");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Marketplace: not owner");
        _;
    }

    modifier orderExists(uint256 _orderId) {
        require(_orderId > 0 && _orderId <= lastOrderId, "Marketplace: item does not exist");
        _;
    }

    function isOnSale(Order memory order) internal pure returns (bool) {
        return !order.isSold && !order.isCancelled;
    }

    constructor(address _userStorage, address _calculatorServise) {
        owner = msg.sender;
        userStorage = UserStorage(_userStorage);
        calculator = CalculatorService(_calculatorServise);
    }

    receive() external payable {}

    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Marketplace: failed to send ETH");
        
        emit Withdraw(amount);
    }

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

    function changePrice(uint256 _orderId, uint256 _newPrice) external whenNotPaused orderExists(_orderId) validPrice(_newPrice) {
        Order storage order = listOfOrders[_orderId];
        
        require(order.price != _newPrice, "Marketplace: new price and current price must be different");
        require(isOnSale(order), "Marketplace: order is not on sale");
        require(msg.sender == order.seller, "Marketplace: permission denied");

        uint256 oldPrice = order.price;
        order.price = _newPrice;

        emit ChangePrice(_orderId, oldPrice, _newPrice);
    }

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

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(paused);
    }
}