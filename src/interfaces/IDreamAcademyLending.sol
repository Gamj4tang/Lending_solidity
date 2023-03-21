// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;


// - ETH를 담보로 사용해서 USDC를 빌리고 빌려줄 수 있는 서비스를 구현하세요.
// - 이자율은 24시간에 0.1% (복리), Loan To Value (LTV)는 50%, liquidation threshold는 75%로 하고 담보 가격 정보는 “참고코드"를 참고해 생성한 컨트랙트에서 갖고 오세요.
// - 필요한 기능들은 다음과 같습니다. Deposit (ETH, USDC 입금), Borrow (담보만큼 USDC 대출), Repay (대출 상환), Liquidate (담보를 청산하여 USDC 확보)
// - 청산 방법은 다양하기 때문에 조사 후 bad debt을 최소화에 가장 적합하다고 생각하는 방식을 적용하고 그 이유를 쓰세요.
// - 실제 토큰을 사용하지 않고 컨트랙트 생성자의 인자로 받은 주소들을 토큰의 주소로 간주합니다.
// - 주요 기능 인터페이스는 아래를 참고해 만드시면 됩니다.
//     - function deposit(address tokenAddress, uint256 amount) external;
//     - function borrow(address tokenAddress, uint256 amount) external;
//     - function repay(address tokenAddress, uint256 amount) external;
//     - function liquidate(address user, address tokenAddress, uint256 amount) external;
//     - function withdraw(address tokenAddress, uint256 amount) external;

interface IDreamAcademyLending {
    function deposit(address tokenAddress, uint256 amount) external payable;
    function borrow(address tokenAddress, uint256 amount) external payable;
    function repay(address tokenAddress, uint256 amount) external payable;
    function liquidate(address user, address tokenAddress, uint256 amount) external;
    function withdraw(address tokenAddress, uint256 amount) external;
}