

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
// import "openzeppelin-contracts/utils/math/SafeMath.sol";
// /import "./DreamOracle2.sol";
import "forge-std/console.sol";
import "./ABDKMath64x64.sol";

import './IPriceOracle.sol';
import './math.sol';
// import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract DreamAcademyLending {

	IPriceOracle _oracle;
	ERC20 _stable;

    uint constant RAY=10**27;

    mapping(address=>uint256) _deposits; //예금 USDC
    //예금 관련
    mapping(address=>uint256) _depositsUpdate;
    mapping(address=>uint256) _depositsAccum; 
    mapping(address=>uint256) _depositsInterest; 
	uint _totalDeposits;
    uint _totalDepositsUpdate;
    uint _totalDepositsAccum;
    address [] _arr;
    

    mapping(address=>uint256) _borrow; // 대출금 USDC
    //대출금 관련
    mapping(address=>uint256) _borrowUpdate;
    mapping(address=>uint256) _borrowAccum;
    mapping(address=>uint256) _borrowInterests; 
	uint _totalBorrow;
    uint _totalBorrowUpdate;
    uint _totalBorrowAccum;


    mapping(address=>uint256) _mortgages; //담보금 BTC
	uint _totalMortgages;

	mapping(address=>uint) _interests; //이자 USDC
	uint _totalInterests;


	constructor(IPriceOracle oracle, address usdc) {
		_stable=ERC20(usdc); 
		_oracle=oracle;
	}

	// _stable은 컨트랙트, usdc 토큰 컨트롤 가능
	function initializeLendingProtocol(address usdc) public payable {
		_stable.transferFrom(msg.sender, address(this), msg.value); 
		_totalDeposits+=msg.value;
	}

    
	// 예금 - ETH,USDC
    // address(0x0) : ETH, address(usdc) : USDC
	function deposit(address tokenAddress, uint256 amount) external payable {
		//USDC
        if (tokenAddress!=address(0)){ 
            require(_stable.balanceOf(msg.sender)>=amount);
            require(amount>0); 
            
            // 예금 이자 체크
            uint256 m=_deposits[msg.sender]*(block.number*12-_depositsUpdate[msg.sender]);
            _deposits[msg.sender]+=amount;
            _depositsAccum[msg.sender]+=m; 
            _depositsUpdate[msg.sender]=block.number*12;
            _totalDeposits+=amount;

            _stable.transferFrom(msg.sender, address(this), amount); 
        
            // 예금 배열
            bool flag=false;
            for (uint i=0; i<_arr.length; i++){
                if(_arr[i]==msg.sender) flag=true;
            }
            if (flag==false) _arr.push(msg.sender);
        }
        else { // ETH 
			require(msg.value>0); 
            require(msg.value==amount);
            _mortgages[msg.sender]+=amount;
			_totalMortgages+=amount; //sum
        }
	}


	// 대출 - USDC (담보)
	function borrow(address tokenAddress, uint256 amount) external payable{
		require(_stable.balanceOf(address(this))>=amount);
        
        // borrow timeblock
        uint time=block.number*12-_borrowUpdate[msg.sender];   
        
        // https://github.com/wolflo/solidity-interest-helper
        _borrow[msg.sender]=Interest(_borrow[msg.sender],1000000011568290959081926677, time-(time/24 hours)*24 hours);
        _borrowUpdate[msg.sender]=block.number*12;

		// LTV - 50%
        uint oracle=_oracle.getPrice(address(0x0))/_oracle.getPrice(tokenAddress); //ETH
        uint test_amount=_mortgages[msg.sender]*oracle/2-_borrow[msg.sender];
        require(test_amount>=amount);

        _borrow[msg.sender]+=amount;
        _borrowUpdate[msg.sender]=block.number*12;
        _totalBorrowAccum+=amount;
		_totalBorrow+=amount;
		_stable.transfer(msg.sender, amount);
	}


	// 대출상환 - USDC 
	function repay(address tokenAddress, uint256 amount) external payable {
		require(_stable.balanceOf(msg.sender)>=amount);
		require(_borrow[msg.sender]>=amount);

		_borrow[msg.sender]-=amount;
        _stable.transferFrom(msg.sender, address(this), amount);
        _totalBorrow-=amount;
	}


	// 청산 ETH->USDC
	function liquidate(address user, address tokenAddress, uint256 amount) external payable {
        require(_borrow[user]>=amount);
		
        uint256 oracle=_oracle.getPrice(address(0x0))/_oracle.getPrice(tokenAddress);
        uint256 mortgage=_mortgages[user]*oracle;

        // liquidation threshold 
        require(_borrow[user]>mortgage*3/4);

        // 청산 금액
        require(_borrow[user]<100 ether||amount==_borrow[user]/4);
		
        _borrow[user]-=amount;
        _totalBorrow-=amount;

        _mortgages[user]-=amount*_oracle.getPrice(tokenAddress)/_oracle.getPrice(address(0x0));
        _totalMortgages-=amount*_oracle.getPrice(tokenAddress)/_oracle.getPrice(address(0x0));
    }


	// 출금 - USDC, ETH
	function withdraw(address tokenAddress, uint256 amount) external payable {
        if (tokenAddress!=address(0)){ // USDC 
			require(_stable.balanceOf(address(this))>=amount);
            _depositsAccum[msg.sender]+=_deposits[msg.sender]*(block.number*12-_depositsUpdate[msg.sender]);

            uint withdrawAmount=getAccruedSupplyAmount(address(_stable));
            require(withdrawAmount>=amount);

            _totalDeposits-=amount;
            _stable.transfer(msg.sender, amount);
		}
		else { //ETH
            //borrow timeblock
            uint time=block.number*12-_borrowUpdate[msg.sender];
            // https://github.com/wolflo/solidity-interest-helper
            _borrow[msg.sender]=Interest(_borrow[msg.sender],1000000011568290959081926677, time-(time/24 hours)*24 hours);
            _borrowUpdate[msg.sender]=block.number*12;

			require(_mortgages[msg.sender]>=amount);
			require(address(this).balance>=amount);
            
			uint256 mortgage =_borrow[msg.sender]*_oracle.getPrice(address(_stable))/_oracle.getPrice(address(0x0));
			require(mortgage<=(_mortgages[msg.sender]-amount)*3/4,"Liquidation threshold");
    
			_mortgages[msg.sender]-=amount;
			msg.sender.call{value:amount}("");
		}
	}


	function getAccruedSupplyAmount(address usdc) public returns (uint256) {
        update(); 
		return _deposits[msg.sender]+_depositsInterest[msg.sender]; //예금+이자
	}
   

    //이자 계산, 외부 라이브러리(rmul, rpow)
    function Interest(uint principal, uint rate, uint age) internal returns (uint) {
        return SafeMath.rmul(principal, SafeMath.rpow(rate, age));
    }


    function update() internal {
        
        _totalDepositsAccum+=_totalDeposits*(block.number*12-_totalDepositsUpdate);
        _totalDepositsUpdate=block.number*12;

        // borrow block, deposit arr ???
        
        
    }
    
}


