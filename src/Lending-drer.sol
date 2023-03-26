// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/utils/math/SafeMath.sol";
import "./DreamOracle2.sol";
import "forge-std/console.sol";
import "./ABDKMath64x64.sol";

/*
ETH를 담보로 사용해서 USDC를 빌리고 빌려줄 수 있는 서비스를 구현하세요.
이자율은 24시간에 0.1% (복리) -> 0.001

Loan To Value (LTV)는 50% -> 맡기는 돈의 50%에 상응하는 토큰을 빌려줌 -> 300만원 가치의 USDC를 맡기면 150만원에 상응하는 토큰을 빌려줌
liquidation threshold는 75% -> 대출금이 담보의 75%가 되면 청산
담보 가격 정보는 “참고코드"를 참고해 생성한 컨트랙트에서 갖고 오세요. -> IPriceOracle
Deposit (ETH, USDC 입금)
Borrow (담보만큼 USDC 대출)
Repay (대출 상환) ->
Liquidate (담보를 청산하여 USDC 확보)
청산 방법은 다양하기 때문에 조사 후 bad debt을 최소화에 가장 적합하다고 생각하는 방식을 적용하고 그 이유를 쓰세요.
실제 토큰을 사용하지 않고 컨트랙트 생성자의 인자로 받은 주소들을 토큰의 주소로 간주합니다.
*/

contract DreamAcademyLending is IPriceOracle {
    IPriceOracle public priceoracle;
    ERC20 usdc;
    ERC20 eth;

    mapping(address => uint256) _depositETH; // 누가 얼만큼 예치했는지
    mapping(address => uint256) _depositUSDC;
    mapping(address => uint256) _borrow; //누가 얼만큼 빌려갔는지

    // uint256 LTV = 50;
    // uint256 LIQUIDITYTHRESHOLD = 75;

    constructor (IPriceOracle _oracle, address _addr){
        priceoracle = _oracle;
        usdc = ERC20(_addr);
    }

    // 예금 (eth랑 usdc 받음))
    function deposit(address tokenAddress, uint256 amount) external payable {
        if(tokenAddress == address(0)){ //ether
            require(msg.value == amount, "");
            _depositETH[msg.sender] += msg.value;

        } else { //usdc
            _depositUSDC[msg.sender] += amount;
            usdc.transferFrom(msg.sender, address(this), amount);
        }
    }
    
    /* 대출 (돈 빌려주는 거)
    * ETH를 담보로 USDC 빌려주는 것
    * LTV = 50%
    * tokenaddress를 amount만큼 빌려주는 것
    */
    function borrow(address tokenAddress, uint256 amount) external{
        uint256 ETHPrice = priceoracle.getPrice(address(0));
        uint256 USDCPrice = priceoracle.getPrice(tokenAddress);

        uint256 enable = ((_depositETH[msg.sender] * ETHPrice / USDCPrice) / 2) - _borrow[msg.sender];
        require(enable >= amount, "");

        _borrow[msg.sender] += amount;
        usdc.transfer(msg.sender, amount); 
    }

    // 대출 상환 (이자 + 원금)
    // tokenAddress를 amount만큼 상환
    // usdc를 갚는 거지
    function repay(address tokenAddress, uint256 amount) external{
        require(tokenAddress == address(usdc), "only USDC");
        require(usdc.balanceOf(msg.sender) >= amount, "over");

        _borrow[msg.sender] -= amount;
        usdc.transferFrom(msg.sender, address(this), amount);
    }

    // 담보 청산
    // 전체 / 일부
    function liquidate(address user, address tokenAddress, uint256 amount) external{
        uint256 ETHPrice = priceoracle.getPrice(address(0));
        uint256 USDCPrice = priceoracle.getPrice(tokenAddress);

        uint256 price = _borrow[user] * USDCPrice / ETHPrice;
        
        console.log("111111");
        console.log(price, _depositETH[user]);
        require(price > _depositETH[user] * 75 / 100, "no liquidate");
        console.log("2222222");
        require(_borrow[user] < 100 || amount == (_borrow[user] * 25 / 100), "");
        console.log("3333333");


        _borrow[user] -= amount;
        _depositETH[user] -= amount * USDCPrice / ETHPrice;

    }

    /*
    * usdc, eth 나눠서 출금
    */
    function withdraw(address tokenAddress, uint256 amount) external{
        if (tokenAddress == address(0)) { // 대출한 사람 eth
            require(_depositETH[msg.sender] >= amount, "over");

            uint256 ETHPrice = priceoracle.getPrice(address(0));
            uint256 USDCPrice = priceoracle.getPrice(address(usdc));

            uint256 price = _borrow[msg.sender] * USDCPrice / ETHPrice; //usdc -> ether
            
            console.log(ETHPrice, USDCPrice);            
            require(price <= (_depositETH[msg.sender]-amount)*75/100, "can't withdraw");
            _depositETH[msg.sender] -= amount;
            (bool success, ) = msg.sender.call{value:amount}("");
        }
        else { // 공급자 usdc
            require(usdc.balanceOf(address(this)) >= amount, "");
            _depositUSDC[msg.sender] -= amount;
            usdc.transferFrom(address(this), msg.sender, amount);
        }
    }

    // usdc 넣어주기
    function initializeLendingProtocol(address _addr) external payable {
        usdc.transferFrom(msg.sender, address(this), msg.value);
        _depositETH[msg.sender] += msg.value;
        _depositUSDC[msg.sender] += msg.value;
    }

    // usdc 누적된 금액 -> 이자 + 원금
    function getAccruedSupplyAmount(address _addr) external payable returns (uint256) {

    }
}