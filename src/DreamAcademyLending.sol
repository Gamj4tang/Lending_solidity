pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


interface IPriceOracle {
    function getPrice(address) external view returns (uint256);
    function setPrice(address, uint256) external;
}

contract DreamAcademyLending {
    
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public ethToken;
    IERC20 public usdcToken;
    IPriceOracle public dreamOracle;

    uint256 public constant INTEREST_RATE = 1000000000315522921573372069; // 0.1% per day
    uint256 public constant LTV = 50;
    uint256 public constant LIQUIDATION_THRESHOLD = 75;

    struct UserData {
        uint256 ethDeposited;
        uint256 usdcBorrowed;
    }

    mapping(address => UserData) private userData;

    // lending = new DreamAcademyLending(IPriceOracle(address(dreamOracle)), address(usdc));
    constructor(IPriceOracle _dreamOracle, address _usdcToken) {
        usdcToken = IERC20(_usdcToken);
        dreamOracle = IPriceOracle(_dreamOracle);
    }
    
    // lending.initializeLendingProtocol{value: 1}(address(usdc)); // set reserve ^__^ ?
    function initializeLendingProtocol(address _usdcToken) external payable {
        usdcToken = IERC20(_usdcToken);
    }

    function deposit(address tokenAddress, uint256 amount) external payable{

    }

    function borrow(address tokenAddress, uint256 amount) external {

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

