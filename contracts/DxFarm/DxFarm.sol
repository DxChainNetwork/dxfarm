// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./DxFarmStorage.sol";
import "../interfaces/IDxSupplier.sol";

// Dx Farm manages your LP and takes good care of you DX!
contract DxFarm is DxFarmStorage, ReentrancyGuard {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ========== EVENTS ========== */

    event Deposit(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 amount);

    event EmergencyWithdraw(address indexed user, uint256 amount);

    /* ========== STRUCT ========== */

    // Info of each user.
    struct UserInfo {
        // How many LP tokens the user has provided.
        uint256 amount;
        // Reward debt. What has been paid so far
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        // Address of LP token contract.
        IERC20 lpToken;
        // Last block number that DXs distribution occurs.
        uint256 lastRewardBlock;
        // Accumulated DXs per share.
        uint256 accDxPerShare;
        // Accumulated Share
        uint256 accShare;
    }

    /* ========== STATES ========== */

    // The DX ERC20 token
    IERC20 public dx;

    // Dx Supplier
    IDxSupplier public supplier;

    // farm pool info
    PoolInfo public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public constant SAFE_MULTIPLIER = 1e16;

    /* ========== INITALIZE ========== */

    /**
     * @dev initialize basic params
     */
    function initialize(
        address _dx,
        address _supplier,
        address lpToken,
        uint256 _startBlock
    ) public onlyOwner {
        dx = IERC20(_dx);
        supplier = IDxSupplier(_supplier);
        poolInfo = PoolInfo({
            lpToken: IERC20(lpToken),
            lastRewardBlock: block.number.max(_startBlock),
            accDxPerShare: 0,
            accShare: 0
        });
    }

    /* ========== PUBLIC ========== */

    /**
     * @dev View `_user` pending DXs
     */
    function pendingDx(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 accDxPerShare = poolInfo.accDxPerShare;
        uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this));

        if (block.number > poolInfo.lastRewardBlock && lpSupply != 0) {
            uint256 total =
                supplier.preview(address(this), poolInfo.lastRewardBlock);

            accDxPerShare = accDxPerShare.add(
                total.mul(SAFE_MULTIPLIER).div(poolInfo.accShare)
            );
        }
        return
            user.amount.mul(accDxPerShare).div(SAFE_MULTIPLIER).sub(
                user.rewardDebt
            );
    }

    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }

        uint256 reward = supplier.distribute(poolInfo.lastRewardBlock);
        poolInfo.accDxPerShare = poolInfo.accDxPerShare.add(
            reward.mul(SAFE_MULTIPLIER).div(poolInfo.accShare)
        );

        poolInfo.lastRewardBlock = block.number;
    }

    /**
     * @dev Deposit LP tokens to DxFarm for DX allocation.
     */
    function deposit(uint256 _amount) public nonReentrant {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount > 0) {
            uint256 pending =
                user
                    .amount
                    .mul(poolInfo.accDxPerShare)
                    .div(SAFE_MULTIPLIER)
                    .sub(user.rewardDebt);
            if (pending > 0) {
                _safeDxTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            poolInfo.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            poolInfo.accShare = poolInfo.accShare.add(_amount);
        }

        user.rewardDebt = user.amount.mul(poolInfo.accDxPerShare).div(
            SAFE_MULTIPLIER
        );
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @dev Withdraw LP tokens from DxFarm.
     */
    function withdraw(uint256 _amount) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "DxFarm: invalid amount");

        updatePool();
        uint256 pending =
            user.amount.mul(poolInfo.accDxPerShare).div(SAFE_MULTIPLIER).sub(
                user.rewardDebt
            );

        if (pending > 0) {
            _safeDxTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            poolInfo.lpToken.safeTransfer(address(msg.sender), _amount);
            poolInfo.accShare = poolInfo.accShare.sub(_amount);
        }

        user.rewardDebt = user.amount.mul(poolInfo.accDxPerShare).div(
            SAFE_MULTIPLIER
        );
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards.
    // EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "DxFarm: insufficient balance");

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        poolInfo.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    /* ========== PRIVATE ========== */

    // Safe dx transfer function, just in case if rounding error causes pool to not have enough DXs.
    function _safeDxTransfer(address _to, uint256 _amount) private {
        uint256 dxBal = dx.balanceOf(address(this));
        if (_amount > dxBal) {
            dx.transfer(_to, dxBal);
        } else {
            dx.transfer(_to, _amount);
        }
    }
}
