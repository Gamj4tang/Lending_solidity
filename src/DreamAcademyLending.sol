pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IDreamAcademyLending.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract DreamAcademyLending is Ownable, IDreamAcademyLending {
    using SafeERC20 for IERC20;

    IPriceOracle public priceOracle;
    IERC20 public usdc;

    struct UserBalance {
        uint256 ethCollateral;
        uint256 usdcDebt;
    }

    mapping(address => UserBalance) public userBalances;
    uint256 public ethReserve;
    uint256 public usdcReserve;
    // anything...?
    uint256 public constant INTEREST_RATE = 1001; // 24-hour interest rate of 0.1% compounded
    uint256 public constant LTV = 50; // 50% Loan-to-Value ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 75; // 75% Liquidation threshold

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidate(address indexed user, address indexed token, uint256 amount);

    constructor(IPriceOracle _priceOracle, address _usdc) {
        priceOracle = _priceOracle;
        usdc = IERC20(_usdc);
    }

    function initializeLendingProtocol(address _usdc) external payable onlyOwner {
        require(msg.value > 0, "ETH reserve must be greater than 0");
        ethReserve = msg.value;
        usdc.safeTransferFrom(msg.sender, address(this), 1); // Set initial USDC reserve to 1
        usdcReserve = 1;
    }

    // @Gamj4tang state variables, side-effects change!
    function deposit(address tokenAddress, uint256 amount) external payable {
        if (tokenAddress == address(0)) {
            require(msg.value > 0, "ETH deposit amount must be greater than 0");
            require(msg.value >= amount, "ETH deposit amount must be greater than or equal to msg.value");
            userBalances[msg.sender].ethCollateral += msg.value;
            ethReserve += msg.value;
            emit Deposit(msg.sender, tokenAddress, msg.value);
        } else {
            require(amount > 0, "Token deposit amount must be greater than 0");
            usdc.safeTransferFrom(msg.sender, address(this), amount);
            usdcReserve += amount;
            emit Deposit(msg.sender, tokenAddress, amount);
        }
    }

    function borrow(address tokenAddress, uint256 amount) external {
        require(tokenAddress == address(usdc), "Only USDC can be borrowed");
        //?
    }

    function repay(address tokenAddress, uint256 amount) external {

    }

    function liquidate(address user, address tokenAddress, uint256 amount) external {

    }

    function withdraw(address tokenAddress, uint256 amount) external {
    }


    // ?

    // getters, any ?
    // lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);
    function getAccruedSupplyAmount(address tokenAddress) external view returns (uint256) {
        return 0;
    }
}



