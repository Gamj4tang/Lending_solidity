// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IDreamAcademyLending.sol";
import "./FixedPointMathLib.sol";
import "forge-std/console.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract DreamAcademyLending is Ownable, IDreamAcademyLending,ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using FixedPointMathLib for uint256;

    IPriceOracle public priceOracle;
    address public usdc; 
    
    struct UserBalance {
        uint256 balance;
        uint256 debt;
        uint256 collateral;
        uint256 blockNum;
        uint256 reserves;
    }
    struct Update {
        uint256 interestRate;
        uint256 cacheinterestRate;
        address[] actors;
    }

    Update public update;
    mapping(address => UserBalance) public userBalances;
    
    uint256 public immutable INTEREST_RATE = 1e15; // 24-hour interest rate of 0.1% compounded
    uint256 public immutable LTV = 50; // 50% Loan-to-Value ratio
    uint256 public immutable LIQUIDATION_THRESHOLD = 75; // LIQUIDATION_THRESHOLD% Liquidation threshold
    uint256 public immutable BLOCKS_PER_DAY = 7200; // 7200 blocks per day
    uint256 public immutable WAD = 10**18; // FixedPointMathLib's WAD constant

    
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidate(address indexed user, address indexed token, uint256 amount);

    constructor(IPriceOracle _priceOracle, address _usdc) {
        priceOracle = _priceOracle;
        usdc = _usdc;
    }

    function initializeLendingProtocol(address _usdc) external payable onlyOwner {
        require(msg.value > 0, "ETH reserve must be greater than 0");
        IERC20(_usdc).safeTransferFrom(msg.sender, address(this), 1);
    }

    function deposit(address tokenAddress, uint256 amount) external payable nonReentrant {
        require(amount > 0, "Deposit amount must be greater than 0");
    
        if (tokenAddress == address(0)) {
            require(msg.value > 0, "ETH deposit amount must be greater than 0");
            require(msg.value >= amount, "ETH deposit amount must be greater than or equal to msg.value");
            userBalances[msg.sender].collateral += amount;
        } else {
            updateSystem(usdc);
            userBalances[msg.sender].balance += amount;
            update.actors.push(msg.sender);
            ERC20(usdc).transferFrom(msg.sender, address(this), amount);
        }
    
        emit Deposit(msg.sender, tokenAddress, amount);
    }
    

    function borrow(address tokenAddress, uint256 amount) external payable nonReentrant{
        require(tokenAddress == address(usdc), "Only USDC can be borrowed");
        uint256 ethCollateral = userBalances[msg.sender].collateral;
        uint256 maxBorrow = _getMaxBorrowAmount(ethCollateral);
        require(amount <= maxBorrow, "Not enough collateral to borrow this amount");
        uint256 maxBorrowAddress = _getMaxBorrowCurrentDebtCheck(msg.sender);
        require(amount <= maxBorrowAddress, "Not enough collateral to borrow this amount");
    
        (uint256 _oETH, uint256 _oUSDC) = _getCurrentPrices();
        
        require(_oETH.mul(userBalances[msg.sender].collateral).div(2) >= _oUSDC.mul(userBalances[msg.sender].debt).add(amount), "Not enough collateral to borrow this amount");
        ERC20(usdc).transfer(msg.sender, amount);
        userBalances[msg.sender].debt += amount;
        userBalances[msg.sender].blockNum = block.number;
        update.actors.push(msg.sender);
        emit Borrow(msg.sender, tokenAddress, amount);
    }

    function repay(address tokenAddress, uint256 amount) external payable nonReentrant{
        require(tokenAddress == address(usdc), "Only USDC repayment is supported");
        require(amount > 0, "Repay amount must be greater than 0");
        
        _calculateInterest(msg.sender);
        userBalances[msg.sender].debt -= amount;
        ERC20(usdc).transferFrom(msg.sender, address(this), amount);
        emit Repay(msg.sender, tokenAddress, amount);
    }

    function liquidate(address user, address tokenAddress, uint256 amount) external nonReentrant{
        require(amount > 0, "Liquidation amount must be greater than 0");
        require(msg.sender != user, "Cannot liquidate yourself");
        require(tokenAddress == address(usdc), "Only USDC can be used to liquidate");
        require(!_isHealthy(user), "Cannot liquidate a healthy user");

        (uint256 _oETH, uint256 _oUSDC) = _getCurrentPrices();
        require((_oETH * userBalances[user].collateral * LIQUIDATION_THRESHOLD).div(100) < userBalances[user].debt.mul(_oUSDC), "Cannot liquidate a healthy user");
        require((userBalances[user].debt * 25).div(100) >= amount, "Cannot liquidate a healthy user");

        uint256 ethAmountToTransfer = amount * userBalances[user].collateral.div(userBalances[user].debt);
        userBalances[user].debt -= amount;
        ERC20(usdc).transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(ethAmountToTransfer);
        emit Liquidate(user, tokenAddress, amount);
    }

    function withdraw(address tokenAddress, uint256 amount) external nonReentrant{
        // @Gamj4tang withdraw normal check
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(userBalances[msg.sender].balance != 0 || userBalances[msg.sender].collateral != 0, "User has no balance to withdraw");
        _calculateInterest(msg.sender);
        if (tokenAddress == address(0)) {
            if (userBalances[msg.sender].debt == 0) {
                payable(msg.sender).transfer(amount);
                userBalances[msg.sender].collateral -= amount;
            } else {
                (uint256 _oETH, uint256 _oUSDC) = _getCurrentPrices();
                // @Gamj4tang withdraw threshold check
                require(((_oETH.mul((userBalances[msg.sender].collateral.sub(amount)))) * LIQUIDATION_THRESHOLD).div(100) > userBalances[msg.sender].debt.mul(_oUSDC));
                payable(msg.sender).transfer(amount);
                userBalances[msg.sender].collateral -= amount;
            }

        } else {
            amount = getAccruedSupplyAmount(tokenAddress) / WAD * WAD;
            userBalances[msg.sender].balance += amount - userBalances[msg.sender].balance;
            ERC20(usdc).transfer(msg.sender, amount);
            userBalances[msg.sender].balance -= amount;
        }
        emit Withdraw(msg.sender, tokenAddress, amount);
    }


    function _getCurrentPrices() internal view returns (uint256 ethPrice, uint256 usdcPrice) {
        ethPrice = priceOracle.getPrice(address(0x0));
        usdcPrice = priceOracle.getPrice(usdc);
    }
    function _getMaxBorrowAmount(uint256 collateral) internal view returns (uint256) {
        uint256 colateralValueInUsdc = (collateral.mul(priceOracle.getPrice(address(0)))).div(1e18);
        return (colateralValueInUsdc * LTV) / 100;
    }

    function _getMaxBorrowCurrentDebtCheck(address user) internal view returns (uint256) {
        uint256 ethCollateral = userBalances[user].collateral;
        uint256 collateralValueInUsdc = (ethCollateral.mul(priceOracle.getPrice(address(0)))).div(1e18);
        uint256 maxBorrowAmount = (collateralValueInUsdc.mul(LTV)).div(100);
        uint256 currentDebt = userBalances[user].debt;

        return maxBorrowAmount > currentDebt ? maxBorrowAmount - currentDebt : 0;
    }

    function _isHealthy(address user) internal view returns (bool) {
        uint256 currentDebt = userBalances[user].debt;
        uint256 ethCollateral = userBalances[user].collateral;
        uint256 maxBorrowAmount = _getMaxBorrowAmount(ethCollateral);
    
        return currentDebt <= maxBorrowAmount;
    }
    /**
        // rate : 0.1% => 0.001
        // block finality : 12s => (1 per 12s)
        // 24 hours => 7200 block

        // A * (1 + r) ** n 

        // -> 1 block  => Compound Calc
        // A * (1 + 0.001) ** 7200
        // r = (1.001)**(1/7200)-1

        // -> debt, 24 hours 0.1% compound interest rate
        // r = (1 + 0.001)**(1/7200)-1

        // ex)
        // debt = 1000
        // block_distance = 1000

        // => debt * ((1 + r) ** (block_distance ))

        // r = (1.001)**(1/7200)-1
        // r = 0.00013882 => celi 
        // uint256 interest = debt * ((1 + r) ** (blockDistance));  <= overflow check
        // uint256 period = block.number - userBalances[_user].blockNum;
     */
    function _getCompoundInterest(uint256 p, uint256 r, uint256 n) internal pure returns (uint256) {
        uint256 rate = FixedPointMathLib.divWadUp(r, WAD) + FixedPointMathLib.WAD;
        return FixedPointMathLib.mulWadUp(p, rate.rpow(n, FixedPointMathLib.WAD));
    }

    function _calculateInterest(address _user) internal returns(uint) {
        uint distance = block.number.sub(userBalances[_user].blockNum);
        uint blockPerDay = distance.div(BLOCKS_PER_DAY);
        uint blockPerDayLast = distance % BLOCKS_PER_DAY;
        uint currentDebt = userBalances[_user].debt;
        uint compoundInterestDebt = _getCompoundInterest(currentDebt, INTEREST_RATE, blockPerDay);
        if (blockPerDayLast != 0) compoundInterestDebt += (_getCompoundInterest(compoundInterestDebt, INTEREST_RATE, 1).sub(compoundInterestDebt)).mul(blockPerDayLast).div(BLOCKS_PER_DAY);
        uint256 _compound = compoundInterestDebt.sub(currentDebt);
        userBalances[_user].debt = compoundInterestDebt;
        userBalances[_user].blockNum = block.number;
        return _compound;
    }

    function getAccruedSupplyAmount(address _usdc) public returns (uint256) {
        updateSystem(address(0));
        uint256 usdcBalance = ERC20(_usdc).balanceOf(address(this));
        uint256 userBalance = userBalances[msg.sender].balance;
        uint256 reserves = userBalances[msg.sender].reserves;
        uint256 accruedInterest = (update.interestRate.sub(update.cacheinterestRate)).mul(userBalance).div(usdcBalance);
        uint accruedSupply = userBalance.add(reserves).add(accruedInterest);

        return accruedSupply;
    }

    function updateSystem(address _usdc) internal {
        uint256 actorsLen = update.actors.length;
        uint256 interestRate = update.interestRate;
        
        if (_usdc != address(0)) {
            uint256 totalUsdcBalance = ERC20(_usdc).balanceOf(address(this));
            uint256 cacheInterestRate = interestRate;
            for (uint256 i = 0; i < actorsLen; i++) {
                address addr = update.actors[i];
                uint256 reserves = interestRate.mul(userBalances[addr].balance).div(totalUsdcBalance);
                userBalances[addr].reserves = reserves;
            }
            update.cacheinterestRate = cacheInterestRate;
        } else {
            uint256 i = 0;
            while (i < actorsLen) {
                address user = update.actors[i];
                interestRate = interestRate.add(_calculateInterest(user));
                i++;
            }
        }
        update.interestRate = interestRate;
    }
}