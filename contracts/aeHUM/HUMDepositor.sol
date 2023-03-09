pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVeERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}          

interface IVeHum is IVeERC20, IERC721Receiver {
    function isUser(address _addr) external view returns (bool);

    function deposit(uint256 _amount) external;

    function claim() external;

    function withdraw(uint256 _amount) external;

    function unstakeNft() external;

    function getStakedNft(address _addr) external view returns (uint256);

    function getStakedHum(address _addr) external view returns (uint256);

    function getVotes(address _account) external view returns (uint256);
}

contract IMasterChef {
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Reward tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that reward token distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated reward tokens per share, times 1e12. See below.
    }

    // Info of each user that stakes LP tokens.
    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Deposit LP tokens to MasterChef.
    function deposit(uint256 _pid, uint256 _amount) external {}

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {}
}

contract aeHUM is ERC20("Aerarium Hummus Token", "aeHUM"), AccessControl, Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 allocPoint; 
        uint256 lastRewardBlock; 
        uint256 accAERAPerShare;
    }
    
    PoolInfo[] public poolInfo; 
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public aeraPerBlock; 
    uint256 public totalAllocPoint = 0;

    uint256 public totalAmountOfSupplyStaked = 0; // total WAVE locked in pools

    uint256 private constant ACC_AERA_PRECISION = 1e12; // Precision for accumulating AERA
    uint256 public constant POOL_PERCENTAGE = 0.876e3; // Percentage of AERA allocated to pools

    IMasterChef public chef; // MasterChef contract for controlling distribution
    uint256 public farmPid; // ID for the farming pool
    uint256 public constant DENOMINATOR = 1e3; // Constant denominator for calculating allocation points

    IERC20 public hum; // veWave ERC721 token
    IERC20 public wave; // AERA ERC20 token

    address public vuhum;

    /* AERA Rewards Events*/
    event LogSetPool(uint256 allocPoint);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);

    /* General Events */
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC20 _hum, // veWave ERC721 token
        IERC20 _wave, // AERA ERC20 token
        address _vuhum,
        IMasterChef _chef, // MasterChef contract for controlling distribution
        uint256 _farmPid
    ) {
        require(address(_hum) != address(0), "invalid veWave's address");
        require(address(_wave) != address(0), "invalid wave's address");
        require(address(_chef) != address(0), "invalid master chef's address");
        hum = _hum;
        vuhum = _vuhum;
        wave = _wave;
        chef = _chef;
        farmPid = _farmPid;
    }

    // Function to deposit veAERA token to the contract and receive rewards
    function depositToChef(uint256 _pid, uint256 amount) external {
        // Wave Rewards attributes
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        IERC20(address(hum)).transferFrom(address(msg.sender), address(this), amount);
        IERC20(address(hum)).approve(address(vuhum), amount);
        IVeHum(address(vuhum)).deposit(amount);

        /******************** AERA Rewards Code ********************/
        totalAmountOfSupplyStaked = totalAmountOfSupplyStaked + amount;
        _mint(address(this), amount); // mint
        _approve(address(this), address(chef), amount);
        chef.deposit(farmPid, amount);
        user.amount = user.amount + amount;
        user.rewardDebt = user.rewardDebt + (amount * pool.accAERAPerShare) / ACC_AERA_PRECISION;
        /*************************************************************/
    
        emit Deposit(msg.sender, 0, amount, msg.sender);
    }

    function withdrawAndDistribute(uint256 _pid, uint256 amount) external {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        /******************** AERA Rewards Code ********************/
        chef.withdraw(farmPid, amount); 
        transferFrom(address(this), address(msg.sender),amount);
        totalAmountOfSupplyStaked = totalAmountOfSupplyStaked - amount; // amount of lockedWave on the contract - amount of locked Wave of that veWAVE
        uint256 accumulatedAERA = (user.amount * pool.accAERAPerShare) / ACC_AERA_PRECISION;
        uint256 eligibleAERA = accumulatedAERA - user.rewardDebt;
        user.amount = user.amount - amount; // put user amount of UserInfo a zero
        user.rewardDebt = (user.amount * pool.accAERAPerShare) / ACC_AERA_PRECISION; // update AERA Reward Debt
        safeAERATransfer(msg.sender, eligibleAERA);
        /************************************************************/

        // Events
        emit Withdraw(msg.sender, 0, amount, msg.sender);
    }

    function harvestAndDistribute(uint256 _pid) public {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        chef.deposit(farmPid, 0);
        uint256 accumulatedAERA = (user.amount * pool.accAERAPerShare) / ACC_AERA_PRECISION;
        uint256 eligibleAERA = accumulatedAERA - user.rewardDebt;

        user.rewardDebt = accumulatedAERA;

        if (eligibleAERA > 0) {
            safeAERATransfer(msg.sender, eligibleAERA);
        }

        emit Harvest(msg.sender, _pid, eligibleAERA);
    }

    function add(
        uint256 _allocPoint
    ) public onlyOwner {
        poolInfo.push(PoolInfo({ allocPoint: _allocPoint, lastRewardBlock: block.number, accAERAPerShare: 0 }));
        totalAllocPoint = totalAllocPoint + _allocPoint;
        emit LogPoolAddition(0, _allocPoint);
    }

    function set(uint256 _allocPoint) public onlyOwner {
        poolInfo[0].allocPoint = _allocPoint;
        emit LogSetPool(_allocPoint);
    }

    function updatePool(uint256 _pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock) {
            if (totalAmountOfSupplyStaked > 0) {
                uint256 blocksSinceLastReward = block.number - pool.lastRewardBlock;
                uint256 waveRewards = (blocksSinceLastReward * aeraPerBlock * pool.allocPoint) / totalAllocPoint;
                uint256 waveRewardsForPool = (waveRewards * POOL_PERCENTAGE) / DENOMINATOR;
                pool.accAERAPerShare =
                    pool.accAERAPerShare +
                    ((waveRewardsForPool * ACC_AERA_PRECISION) / totalAmountOfSupplyStaked);
            }
            pool.lastRewardBlock = block.number;
            poolInfo[_pid] = pool;
        }
    }

    function pendingWave(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pending) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accAERAPerShare = pool.accAERAPerShare;

        if (block.number > pool.lastRewardBlock && totalAmountOfSupplyStaked > 0) {
            uint256 blocksSinceLastReward = block.number - pool.lastRewardBlock;
            uint256 waveRewards = (blocksSinceLastReward * aeraPerBlock * pool.allocPoint) / totalAllocPoint;

            uint256 waveRewardsForPool = (waveRewards * POOL_PERCENTAGE) / DENOMINATOR;

            accAERAPerShare = accAERAPerShare + ((waveRewardsForPool * ACC_AERA_PRECISION) / totalAmountOfSupplyStaked);
        }
        pending = (user.amount * accAERAPerShare) / ACC_AERA_PRECISION - user.rewardDebt;
    }

    function safeAERATransfer(address _to, uint256 _amount) internal {
        uint256 waveBalance = wave.balanceOf(address(this));
        if (_amount > waveBalance) {
            wave.transfer(_to, waveBalance);
        } else {
            wave.transfer(_to, _amount);
        }
    }

    receive() external payable {
    }

    function updateEmissionRate(uint256 _aeraPerBlock) public onlyOwner {
        require(_aeraPerBlock <= 6e18, "maximum emission rate of 6 anothertoken per block exceeded");
        aeraPerBlock = _aeraPerBlock;
    }

    function claimVeHumRewards() public onlyOwner {
        IVeHum(address(vuhum)).claim();
    }

    function withdrawErc20Tokens(address token, uint256 amount) public onlyOwner {
        IERC20(token).transferFrom(address(this),address(msg.sender),amount);
    }

    function withdraw(uint256 amount) public onlyOwner {
        payable(msg.sender).transfer(amount);
    }

}