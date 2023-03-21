pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "forge-std/console.sol";
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
        uint256 balances;
        uint256 debt;
        uint256 collateral;
        uint256 blocknum;
    }

    mapping(address => UserBalance) public userBalances;
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
        // ethReserve = msg.value;
        usdc.safeTransferFrom(msg.sender, address(this), 1); // Set initial USDC reserve to 1
        // usdcReserve = 1;
    }
    function deposit(address tokenAddress, uint256 amount) external payable {
        if (tokenAddress == address(0)) {
            require(msg.value > 0, "ETH deposit amount must be greater than 0");
            require(msg.value >= amount, "ETH deposit amount must be greater than or equal to msg.value");
            userBalances[msg.sender].collateral += msg.value;
            // ethReserve += msg.value;
            emit Deposit(msg.sender, tokenAddress, msg.value);
        } else {
            require(amount > 0, "Token deposit amount must be greater than 0");
            
            UserBalance storage userBalance = userBalances[msg.sender];
        
            // uint256 interest = calculateInterest(userBalance.usdcDeposit, userBalance.usdcDepositLastBlockNumber, block.number);
            // console.log("interest", interest);
            userBalance.balances += amount;
            // userBalance.usdcDeposit + amount;
            // userBalance.blocknum = block.number;
    
            usdc.safeTransferFrom(msg.sender, address(this), amount);
            // usdcReserve += amount;
            emit Deposit(msg.sender, tokenAddress, amount);
        }
    }
    
    function borrow(address tokenAddress, uint256 amount) external {
        require(tokenAddress == address(usdc), "Only USDC can be borrowed");
        uint256 ethCollateral = userBalances[msg.sender].collateral;
        uint256 maxBorrow = _getMaxBorrowAmount(ethCollateral);
        require(amount <= maxBorrow, "Not enough collateral to borrow this amount");
        uint256 maxBorrowAddress = _getMaxBorrowCurrentDebtCheck(msg.sender);
        require(amount <= maxBorrowAddress, "Not enough collateral to borrow this amount");
    
        UserBalance storage userBalance = userBalances[msg.sender];
        userBalance.blocknum = block.number;
    
        // Add new debt
        userBalance.debt += amount;
        // usdcReserve -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, tokenAddress, amount);
    }
    

    // interest rate => 1.001 = 0.1% per day => 0.1% per 24 hours (block.number check)
    function repay(address tokenAddress, uint256 amount) external {
        require(tokenAddress == address(usdc), "Only USDC repayment is supported");
        require(amount > 0, "Repay amount must be greater than 0");
        UserBalance storage userBalance = userBalances[msg.sender];
        
        console.log("userBalance.usdcDebt", userBalance.debt);
        console.log("userBalance.lastBlockNumber", userBalance.blocknum);
        console.log("block.number", block.number);

        uint256 interest = calculateInterest(userBalance.debt, userBalance.blocknum, block.number);
        console.log("interest", interest);
        userBalance.debt += interest;
        userBalance.blocknum = block.number;
        // require(userBalance.usdcDebt >= amount, "Repay amount exceeds debt");
        // if (userBalance.debt < amount) {
        //     userBalance.debt = 0;
        // } else {
        //     userBalance.debt -= amount;
        // }

        // userBalances[msg.sender].usdcDebt -= amount;
        userBalance.debt -= amount;
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        
        emit Repay(msg.sender, tokenAddress, amount);
    }
    function liquidate(address user, address tokenAddress, uint256 amount) external {
        require(tokenAddress == address(usdc), "Only USDC can be used to liquidate");
        require(!isHealthy(user), "Cannot liquidate a healthy user");
    
        UserBalance storage userBalance = userBalances[user];
    
        // uint256 interest = calculateInterest(userBalance.usdcDebt, userBalance.lastBlockNumber, block.number);
        // userBalance.usdcDebt += interest;
        // userBalance.lastBlockNumber = block.number;
    
        uint256 debt = userBalance.debt;
        uint256 ethCollateral = userBalance.collateral;
        uint256 ltvRatio = (debt * 100 * 1 ether) / (ethCollateral * priceOracle.getPrice(address(0)));
    
        // research 🥲
        uint256 amountToRepay;
        if (ltvRatio >= 75 * 1 ether && ltvRatio < 51 * 1 ether) {
            amountToRepay = debt / 2;
        } else if (ltvRatio < 50 * 1 ether) {
            amountToRepay = (debt * 45) / 100;
        } else {
            revert("Invalid LTV ratio");
        }
    
        require(amount <= amountToRepay, "Cannot liquidate more than allowed amount");
    
        if (debt >= 100 * 1 ether) {
            uint256 maxAmountToLiquidate = (debt * 25) / 100;
            require(amount <= maxAmountToLiquidate, "Cannot liquidate more than 25% at once");
        }
    
        bool success = usdc.transferFrom(msg.sender, address(this), amount);
        require(success, "USDC transfer failed");
        userBalance.debt -= amount;
        uint256 ethAmountToTransfer = (ethCollateral * amount) / debt;
        userBalance.collateral -= ethAmountToTransfer;

        payable(msg.sender).transfer(ethAmountToTransfer);
    
        emit Liquidate(user, tokenAddress, amount);
    }
    
    
    
    function withdraw(address tokenAddress, uint256 amount) external {
        require(amount > 0, "Withdraw amount must be greater than 0");
    
        if (tokenAddress == address(0)) {
            UserBalance storage userBalance = userBalances[msg.sender];
            uint256 totalCollateralInEth = userBalance.collateral;
            uint256 totalDebtInEth = getTotalDebtInEth(msg.sender);
    
            require(totalCollateralInEth * LIQUIDATION_THRESHOLD > totalDebtInEth * 100, "Not enough collateral to withdraw");
            require(totalCollateralInEth >= amount, "Not enough collateral to withdraw the requested amount");
    
            userBalance.collateral -= amount;
            // ethReserve -= amount;
            payable(msg.sender).transfer(amount);
            emit Withdraw(msg.sender, tokenAddress, amount);
        } else {
            UserBalance storage userBalance = userBalances[msg.sender];
            uint256 interest = calculateInterest(userBalance.balances, userBalance.blocknum, block.number);
            userBalance.balances += interest;
            userBalance.blocknum = block.number;
    
            require(userBalance.balances >= amount, "Not enough deposit to withdraw the requested amount");
    
            userBalance.balances -= amount;
            // usdcReserve -= amount;
            usdc.safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, tokenAddress, amount);
        }
    }

    /**
     * Utils
     */
    function _getMaxBorrowAmount(uint256 collateral) internal view returns (uint256) {
        uint256 colateralValueInUsdc = (collateral * priceOracle.getPrice(address(0))) / 1e18;
        return (colateralValueInUsdc * LTV) / 100;
    }

    function _getMaxBorrowCurrentDebtCheck(address user) internal view returns (uint256) {
        uint256 ethCollateral = userBalances[user].collateral;
        uint256 collateralValueInUsdc = (ethCollateral * priceOracle.getPrice(address(0))) / 1e18;
        uint256 maxBorrowAmount = (collateralValueInUsdc * LTV) / 100;
        uint256 currentDebt = userBalances[user].debt;

        return maxBorrowAmount > currentDebt ? maxBorrowAmount - currentDebt : 0;
    }

    function isHealthy(address user) public view returns (bool) {
        uint256 currentDebt = userBalances[user].debt;
        uint256 ethCollateral = userBalances[user].collateral;
        uint256 maxBorrowAmount = _getMaxBorrowAmount(ethCollateral);
    
        return currentDebt <= maxBorrowAmount;
    }
    function calculateInterest(uint256 debt, uint256 lastBlockNumber, uint256 currentBlockNumber) public view returns (uint256) {
        uint256 blockDistance = currentBlockNumber - lastBlockNumber;
        uint256 interest = (debt * ((INTEREST_RATE ** blockDistance) - 1)) / (10 ** 18);
        return interest;
    }
    
    function getTotalDebtInEth(address user) public view returns (uint256) {
        UserBalance storage userBalance = userBalances[user];
        uint256 interest = calculateInterest(userBalance.debt, userBalance.blocknum, block.number);
        uint256 totalDebtInUsdc = userBalance.debt + interest;
        return (totalDebtInUsdc * priceOracle.getPrice(address(usdc))) / 1 ether;
    }

    function getAccruedSupplyAmount(address tokenAddress) external view returns (uint256) {
        require(tokenAddress == address(usdc), "Only USDC is supported for accrued supply amount calculation");
        UserBalance storage userBalance = userBalances[msg.sender];
        uint256 interest = calculateInterest(userBalance.balances, userBalance.blocknum, block.number);
        return userBalance.balances + interest;
    }
}



