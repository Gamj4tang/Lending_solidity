// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);

    function setPrice(address token, uint256 price) external;
}

contract DreamAcademyLending {
    IERC20 usdc;
    IPriceOracle dreamOracle;
    mapping(address => mapping(address => uint256)) _reserve;
    mapping(address => mapping(address => uint256)) _borrowed;
    mapping(address => uint256) _totalReserve;
    mapping(address => uint256) _totalBorrowed;
    mapping(address => uint256) _reservedTime;
    mapping(address => uint256) _borrwedTime;
    mapping(address => bool) _borrowedChk;
    address[] users;
    uint256 usersCount;
    uint256 _totalReservePool;
    uint256 _totalBorrowPool;

    uint256 loanToValue;
    uint256 liquidThreshold;
    uint256 constant INTEREST_RATE = 100000013;
    uint256 constant INTEREST_RATE2 = 100000000;

    constructor(IPriceOracle _dreamOracle, address _tokenAddress) {
        dreamOracle = _dreamOracle;
        usdc = IERC20(_tokenAddress);
        loanToValue = 50;
        liquidThreshold = 75;
    }

    function initializeLendingProtocol(address tokenAddress) external payable {
        require(tokenAddress != address(0));
        require(msg.value > 0);

        _reserve[msg.sender][tokenAddress] += msg.value;
    }

    function setTotalPool() internal {
        _totalReservePool = 0;
        _totalBorrowPool = 0;
        for (uint256 i = 0; i < usersCount; i++) {
            _totalReserve[users[i]] = getReserve(users[i]);
            _totalBorrowed[users[i]] = getBorrowed(users[i]);

            _totalReservePool += _totalReserve[users[i]];
            _totalBorrowPool += _totalBorrowed[users[i]];
        }
    }

    function getAccruedSupplyAmount(
        address tokenAddress
    ) public returns (uint256 amount) {
        setTotalPool();
        if (_totalReservePool != 0) {
            if (_totalBorrowPool != 0) {
                amount =
                    getCurReserveValue(tokenAddress) +
                    ((getCurReserveValue(tokenAddress) *
                        (getBorrowInterestRate(_totalBorrowPool) -
                            _totalBorrowPool)) / _totalReservePool);
            } else {
                amount = getCurReserveValue(tokenAddress);
            }
        } else amount = _reserve[msg.sender][tokenAddress];
    }

    function deposit(address tokenAddress, uint256 amount) external payable {
        if (_totalReserve[msg.sender] == 0) {
            users.push();
            users[usersCount++] = msg.sender;
        }
        if (tokenAddress == address(usdc)) {
            require(amount <= usdc.allowance(msg.sender, address(this)));
            _reserve[msg.sender][tokenAddress] += amount;
            usdc.transferFrom(
                msg.sender,
                address(this),
                _reserve[msg.sender][tokenAddress]
            );
        } else {
            require(msg.value >= amount);
            _reserve[msg.sender][tokenAddress] += amount;
        }
        if (_reservedTime[msg.sender] == 0) {
            _reservedTime[msg.sender] = block.number;
        }

        _totalReserve[msg.sender] = getReserve();
    }

    function borrow(address tokenAddress, uint256 amount) external {
        if (!_borrowedChk[msg.sender]) {
            _borrwedTime[msg.sender] = block.number;
            _borrowedChk[msg.sender] = true;
        }
        if (tokenAddress == address(usdc)) {
            console.log(
                amount + getBorrowed(),
                (getReserve() * loanToValue) / 100
            );
            require(
                amount + getBorrowInterestRate(getBorrowed()) <=
                    (getReserve() * loanToValue) / 100
            );

            usdc.transfer(msg.sender, amount);
        } else {
            require(getReserve() >= amount + getBorrowed());
        }
        _borrowed[msg.sender][tokenAddress] += amount;
        _totalBorrowed[msg.sender] = getBorrowed();
    }

    function repay(address tokenAddress, uint256 amount) external {
        require(_borrowed[msg.sender][tokenAddress] >= amount);
        if (tokenAddress == address(usdc)) {
            require(usdc.allowance(msg.sender, address(this)) >= amount);
            usdc.transferFrom(msg.sender, address(this), amount);
        }
        _borrowed[msg.sender][tokenAddress] -= amount;
        _totalBorrowed[msg.sender] = getReserve();
    }

    function liquidate(
        address user,
        address tokenAddress,
        uint256 amount
    ) external {
        require(checkLT(tokenAddress, amount));
    }

    function checkLT(
        address tokenAddress,
        uint256 amount
    ) internal returns (bool) {
        require(getAccruedSupplyAmount(tokenAddress) >= amount);

        uint256 LT = ((getAccruedSupplyAmount(tokenAddress) -
            (amount * dreamOracle.getPrice(tokenAddress)) /
            1e18) * liquidThreshold) / 100;

        if (LT >= _totalBorrowed[msg.sender]) {
            return true;
        }
        return false;
    }

    function getBorrowInterestRate(
        uint256 amount
    ) internal returns (uint256 interestRate) {
        uint256 blockDist = (block.number - _borrwedTime[msg.sender]);
        interestRate = amount;
        if (blockDist >= 500) {
            blockDist -= blockDist % 500;

            while (blockDist > 0) {
                blockDist -= (86400 / 12) * 500;
                interestRate =
                    ((interestRate * (16483094164129481))) /
                    (10000000000000000);
            }
        } else {
            interestRate =
                ((interestRate * INTEREST_RATE ** blockDist)) /
                (INTEREST_RATE2 ** blockDist);
        }
    }

    function withdraw(address tokenAddress, uint256 amount) external {
        require(checkLT(tokenAddress, amount));

        uint256 interestRate = getAccruedSupplyAmount(tokenAddress);

        _totalBorrowed[msg.sender] = getBorrowed();
        if (interestRate > 0 && _totalBorrowed[msg.sender] > 0) {
            require(
                getReserve() >
                    (amount * dreamOracle.getPrice(tokenAddress)) / 1e18
            );

            require(
                ((100 * (getBorrowInterestRate(amount))) /
                    (
                        (getReserve() -
                            (amount * dreamOracle.getPrice(tokenAddress)) /
                            1e18)
                    ) <
                    liquidThreshold),
                "error"
            );
        } else {
            require(interestRate >= amount);
        }

        if (tokenAddress == address(usdc)) {
            usdc.transfer(msg.sender, amount);
        } else {
            payable(msg.sender).call{value: amount}("");
        }
        getReserve();

        if (_totalReserve[msg.sender] >= amount) {
            _totalReserve[msg.sender] -= amount;
            _totalReservePool -= amount;
        } else {
            _totalReserve[msg.sender] = 0;
            _totalReservePool -= amount;
        }
    }

    receive() external payable {}

    function getReserve() internal returns (uint256 reserveValue) {
        reserveValue =
            getCurReserveValue(address(0)) +
            getCurReserveValue(address(usdc));
    }

    function getCurReserveValue(
        address tokenAddress
    ) internal returns (uint256 curValue) {
        curValue =
            (_reserve[msg.sender][tokenAddress] / 1e18) *
            dreamOracle.getPrice(tokenAddress);
    }

    function getReserve(address user) internal returns (uint256 reserveValue) {
        reserveValue =
            getCurReserveValue(user, address(0)) +
            getCurReserveValue(user, address(usdc));
    }

    function getCurReserveValue(
        address user,
        address tokenAddress
    ) internal returns (uint256 curValue) {
        curValue =
            (_reserve[user][tokenAddress] / 1e18) *
            dreamOracle.getPrice(tokenAddress);
    }

    function getBorrowed() internal returns (uint256 borrowValue) {
        borrowValue =
            getBorrowValue(address(0)) +
            getBorrowValue(address(usdc));
    }

    function getBorrowValue(
        address tokenAddress
    ) internal returns (uint256 borrowValue) {
        borrowValue = (_borrowed[msg.sender][tokenAddress]);
    }

    function getBorrowed(address user) internal returns (uint256 borrowValue) {
        borrowValue =
            getBorrowValue(user, address(0)) +
            getBorrowValue(user, address(usdc));
    }

    function getBorrowValue(
        address user,
        address tokenAddress
    ) internal returns (uint256 borrowValue) {
        borrowValue = (_borrowed[user][tokenAddress]);
    }
}
