// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.8.0;


import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./HFS.sol";
import "./ReentrancyGuard.sol";


contract NewHolderStake is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using SafeERC20 for HFS;

    struct PoolSubData {
        uint256 releaseBlock; // Block number to add to block number instanciation
        uint256 totalLpSupply; // Total supply global of Lp token
        uint256 thisBalanceOfLp; // Balance of Lp token to this contract
        uint256 totalDailyEarning; // current pool0 daily earning of reward token
        uint256 dayLock; // number of day lpToken will be locked
        uint256 percentRewardsToEarn; // percent of reward of pool vs total supply
        uint256 totalRewardsSupply; // Total supply global of reward token
        uint256 percentOfMultiplyByShare; //  Balance of Lp token staked in this contract vs Lp token global Total Supply
        uint256 percentStaked; // Lp token global Total Supply vs balance of Lp token staked in this contract 
        uint256 lpFee; // fee to burn on unstake (100 = 1%)
        uint256 rewardFee; // fee to burn on claim (100 = 1%)
        uint256 poolApr; // pool APR
    }

    // Info of each pool.
    struct PoolInfo {
        ERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Hfs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that hfs distribution occurs.
        uint256 accHfsPerShare; // Accumulated hfs per share, times 1e12. See below.
    }
    
    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt;  // Reward debt. See explanation below. See explanation below.
        uint256 startBlock; // User block that it is enter to stake
        uint256 stakedPosition; // Percent of Lp token staked vs total balance of Lp in this contract
        uint256 lastClaim;

        
        // We do some fancy math here. Basically, any point in time, the amount of Hfs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accHfsPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accHfsPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // The lpToken token!
    ERC20 public lpToken;
    // The Hfs token!
    HFS public hfs;
    // hfs tokens created per block.
    uint256 public hfsPerBlock;
    // Bonus muliplier for early hfs makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Number of block to add to startBlock to release LP.
    uint256 public blockTimeLock;
    // Block since rewards will be closed
    uint256 public stopBlock;
    

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Second endpoint info of each pool
    PoolSubData[] public poolSubdata;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when hfs mining starts.
    uint256 public startBlock;
    // Address where minted token will be burned
    address burnAddress;
    // Address where minted token will be send for team
    address devAddress;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        ERC20 _lpToken,
        HFS _hfs,
        uint256 _hfsPerBlock,
        uint256 _blockTimeLock,
        uint256 _lpFee, 
        uint256 _rewardFee,
        address _burnAddress,
        address _devAddress

    ) public {
        require(_blockTimeLock >= 28800, "pool must be minimum one day");
        lpToken = _lpToken;
        hfs = _hfs;
        hfsPerBlock = _hfsPerBlock;
        startBlock = block.number;
        blockTimeLock = _blockTimeLock;
        stopBlock = startBlock.add(blockTimeLock);
        burnAddress = _burnAddress;
        devAddress = _devAddress;

        // staking pool first endpoint
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accHfsPerShare: 0
        }));
        
        // staking pool second endpoint
        poolSubdata.push(PoolSubData({
            
            releaseBlock: startBlock.add(blockTimeLock),
            totalLpSupply: 0,
            thisBalanceOfLp: 0,
            totalDailyEarning: 0,
            dayLock: 0,
            percentRewardsToEarn: 0,
            totalRewardsSupply: 0,
            percentOfMultiplyByShare: 0,
            percentStaked: 0,
            lpFee: _lpFee,
            rewardFee: _rewardFee,
            poolApr: 0
            
        }));

        totalAllocPoint = 1000;

    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner  {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // Update the given pool's hfs allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner  {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
     function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

       //  View function to see pending hfs on frontend.
    function pendingHfs(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        PoolSubData storage poolSub = poolSubdata[0];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHfsPerShare = pool.accHfsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier;
            if(block.number >= stopBlock){
                multiplier = getMultiplier(pool.lastRewardBlock, stopBlock);
            } else {
                multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            }
            uint256 hfsReward = multiplier.mul(hfsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accHfsPerShare = accHfsPerShare.add(hfsReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accHfsPerShare).div(1e12).sub(user.rewardDebt);
        uint256 pendingToClaim;
        if (pending > 0){
            if(poolSub.rewardFee > 0){
                uint256 feeReward = pending.mul(poolSub.rewardFee).div(10000);
                uint256 RewardToMint = pending.sub(feeReward);
                if (feeReward > 0){
                    pendingToClaim = RewardToMint;
                } else {
                    pendingToClaim = pending;
                }
            
            } else {
                pendingToClaim = pending;
            }
        } else {
            pendingToClaim = pending;
        }
        return pendingToClaim;
    }
    
        //  View function to see pending hfs on frontend.
    function pendingHfsInternal(uint256 _pid, address _user) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        PoolSubData storage poolSub = poolSubdata[0];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHfsPerShare = pool.accHfsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier;
            if(block.number >= stopBlock){
                multiplier = getMultiplier(pool.lastRewardBlock, stopBlock);
            } else {
                multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            }
            uint256 hfsReward = multiplier.mul(hfsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accHfsPerShare = accHfsPerShare.add(hfsReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accHfsPerShare).div(1e12).sub(user.rewardDebt);
        uint256 pendingToClaim;
        if (pending > 0){
            if(poolSub.rewardFee > 0){
                uint256 feeReward = pending.mul(poolSub.rewardFee).div(10000);
                uint256 RewardToMint = pending.sub(feeReward);
                if (feeReward > 0){
                    pendingToClaim = RewardToMint;
                } else {
                    pendingToClaim = pending;
                }
            
            } else {
                pendingToClaim = pending;
            }
        } else {
            pendingToClaim = pending;
        }
        return pendingToClaim;
    }

     function userHfsperDay(uint256 _pid, address _user) external view returns (uint256) {
        PoolSubData storage poolSub = poolSubdata[_pid];
        UserInfo storage user = userInfo[_pid][_user];
       
        return user.stakedPosition.mul(poolSub.totalDailyEarning).mul(blockTimeLock).div(1e12);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        PoolSubData storage poolSub = poolSubdata[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier;
        if(block.number >= stopBlock){
            multiplier = getMultiplier(pool.lastRewardBlock, stopBlock);
            pool.lastRewardBlock = stopBlock;
        } else {
            multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            pool.lastRewardBlock = block.number;
        }
        uint256 hfsReward = multiplier.mul(hfsPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accHfsPerShare = pool.accHfsPerShare.add(hfsReward.mul(1e12).div(lpSupply));
        
        poolSub.totalLpSupply = pool.lpToken.totalSupply();
        poolSub.thisBalanceOfLp = lpSupply;
        poolSub.totalRewardsSupply = hfs.totalSupply();
        poolSub.totalDailyEarning = hfsPerBlock.mul(uint256(28800));
        poolSub.percentRewardsToEarn = poolSub.totalDailyEarning.mul(poolSub.dayLock).div(poolSub.totalRewardsSupply);
        poolSub.percentOfMultiplyByShare = poolSub.totalLpSupply.mul(1e12).div(lpSupply);
        poolSub.poolApr = poolSub.percentRewardsToEarn.mul(poolSub.percentOfMultiplyByShare).div(1e12);
        poolSub.percentStaked = lpSupply.mul(1e12).div(poolSub.totalLpSupply);
        poolSub.dayLock = blockTimeLock.mul(1e12).div(uint256(28800));
    }

    // Stake HFIBusdLp tokens to HolderStake
    function enterStaking(uint256 _amount) public nonReentrant{
        require(_amount > 0, "amount must be greater than 0");
        require(block.number < stopBlock, "pool rewards are closed");
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.startBlock = block.number;
        user.stakedPosition = user.amount.mul(1e12).div(pool.lpToken.balanceOf(address(this)));
        user.rewardDebt = user.amount.mul(pool.accHfsPerShare).div(1e12);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Claim reward tokens to HolderStake
    function claimRewards() public nonReentrant{
        PoolInfo storage pool = poolInfo[0];
        PoolSubData storage poolSub = poolSubdata[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        require(user.lastClaim == 0 || block.number > user.lastClaim.add(28800), "please wait 24h to claim");
        uint256 pending = user.amount.mul(pool.accHfsPerShare).div(1e12).sub(user.rewardDebt);
        require(pending > 0, "no more rewards pending");
        uint256 feeReward = pending.mul(poolSub.rewardFee).div(10000);
        uint256 feeRewardDev = feeReward.div(5);
        uint256 feeRewardBurn = feeReward.sub(feeRewardDev);
        uint256 RewardToMint = pending.sub(feeReward);
        if (feeReward > 0 && feeRewardDev > 0 && feeRewardBurn > 0){
            hfs.mint(burnAddress, feeRewardBurn);
            hfs.mint(devAddress, feeRewardDev);
            hfs.mint(msg.sender, RewardToMint);
        } else {
            hfs.mint(msg.sender, pending);
        }
        user.rewardDebt = user.amount.mul(pool.accHfsPerShare).div(1e12);
        user.lastClaim = block.number;
    }

    // Withdraw HFIBusdLp tokens from STAKING.
    function leaveStaking(uint256 _amount) public nonReentrant {
        require(_amount > 0, "amount must be greater than 0");
        PoolInfo storage pool = poolInfo[0];
        PoolSubData storage poolSub = poolSubdata[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(block.number >= startBlock.add(blockTimeLock), "not yet time to withdraw");
        updatePool(0);
        if(_amount > 0 && poolSub.lpFee > 0) {
            uint256 LpToStakeForever = _amount.mul(poolSub.lpFee).div(10000);
            uint256 LpToMint = _amount.sub(LpToStakeForever);
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), LpToMint);
        }else if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accHfsPerShare).div(1e12);
        emit Withdraw(msg.sender, 0, _amount);
    }

        // Get current block number
    function getCurrentBlockNumber() public view returns(uint256){
        uint256 currentBlock = block.number;
        return currentBlock;
    }
    
     // Update burn address by the previous dev.
    function changeBurnAddress(address _burnAddress) public onlyOwner {
        burnAddress = _burnAddress;
    }
    
     // Update dev address by the previous dev.
    function changeDevAddress(address _devAddress) public onlyOwner {
        devAddress = _devAddress;
    }
    
    function getData() external view returns(uint256[9]memory){
            PoolSubData storage poolSub = poolSubdata[0];
            UserInfo storage user = userInfo[0][msg.sender];
        return  [user.amount, pendingHfsInternal(0, msg.sender), poolSub.poolApr, poolSub.thisBalanceOfLp, poolSub.percentStaked, poolSub.dayLock, startBlock, getCurrentBlockNumber(), stopBlock];
                
    }
    
     // Set new emergency blockStop
    function setNewStopBlock(uint256 _newBlockNumber) public onlyOwner{
        stopBlock = _newBlockNumber;
    }
     // set new lp fee
    function setLpFee(uint256 _lpFee) public onlyOwner {
        PoolSubData storage poolSub = poolSubdata[0];
        poolSub.lpFee = _lpFee;
       
    }
    
    // set new reward fee
    function setRewardFee(uint256 _rewardFee) public onlyOwner {
        PoolSubData storage poolSub = poolSubdata[0];
        poolSub.rewardFee = _rewardFee;
       
    }
}

