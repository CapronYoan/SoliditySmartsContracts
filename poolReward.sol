// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.8.0;

import "./Context.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";



contract PoolReward is Context, AccessControl, ReentrancyGuard{
    bytes32 public constant TRANSFERER_ROLE = keccak256("TRANSFERER_ROLE");
    bytes32 public constant SUBADMIN_ROLE = keccak256("SUBADMIN_ROLE");

    // bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    ERC20 public rewardToken;

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     *
     * See {ERC20-constructor}.
     */

     using SafeERC20 for ERC20;

    modifier onlyTransferer{
        require(hasRole(TRANSFERER_ROLE, _msgSender()), "must have admin role to transfer");
        _;
    }

    modifier onlyOwner{
        require(hasRole(SUBADMIN_ROLE, _msgSender()), "must have admin role to transfer");
        _;
    }

    constructor(ERC20 _rewardToken) public {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(TRANSFERER_ROLE, _msgSender());
        _setupRole(SUBADMIN_ROLE, _msgSender());
        rewardToken = _rewardToken;
    }

    function transferRewardExternal(address _to, uint256 _amount) external  onlyTransferer nonReentrant {
        require(rewardToken.balanceOf(address(this)) > 0, "pool reward token is empty");
        require(rewardToken.balanceOf(address(this)) >= _amount, "reward superior to pool balance");
        rewardToken.safeTransfer(_to, _amount);
    }

     function decreaseRewardBalance(address _to, uint256 _amount) public  onlyOwner nonReentrant {
        require(rewardToken.balanceOf(address(this))>0, "pool reward token is empty");
        require(rewardToken.balanceOf(address(this)) >= _amount, "reward superior to pool balance");
        rewardToken.safeTransfer(_to, _amount);
    }

    function checkBalanceExternal() external view returns(uint256) {
        return rewardToken.balanceOf(address(this));
    }

     function checkBalance() public view returns(uint256) {
        return rewardToken.balanceOf(address(this));
    }

  
}

