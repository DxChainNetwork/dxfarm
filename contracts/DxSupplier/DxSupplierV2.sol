// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";

import "../AccessControl/ExternalAdminAccessControl.sol";

import "../interfaces/IDxSupplier.sol";
import "../interfaces/IDxVault.sol";
import "../interfaces/IDxFarm.sol";

contract DxSupplierV2 is
    IDxSupplier,
    ReentrancyGuard,
    Initializable,
    ExternalAdminAccessControl
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    IDxVault public vault;

    // Set of address that are approved consumer
    EnumerableSet.AddressSet private approvedConsumers;

    // map of consumer address to consumer info
    mapping(address => ConsumerInfo) public consumerInfo;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // number of DX tokens created per block.
    uint256 public dxPerBlock;

    // a week block nums in mainnet
    uint256 public constant A_WEEK_BLOCKNUMS = (7 * 24 * 3600) / 3;

    // Decrease weekly
    uint256 public min;

    uint256 public constant max = 1000;

    uint256 public constant SAFE_MULTIPLIER = 1e16;

    // Info of each consumer.
    struct ConsumerInfo {
        // Address of consumer.
        address consumer;
        // How many allocation points assigned to this consumer
        uint256 allocPoint;
        // Last block number that DXs distribution occurs.
        uint256 lastDistributeBlock;
        // week check point block nums
        uint256 weekPoint;
    }

    /**
     * @dev initialize basic params
     */
    function initialize(uint256 _dxPerBlock, address _vault)
        public
        initializer
    {
        dxPerBlock = _dxPerBlock;
        vault = IDxVault(_vault);
        min = 1000;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(EXTERNAL_ADMIN_ROLE, msg.sender);
    }

    function setMin(uint256 _min) public onlyAdmin {
        min = _min;
    }

    function isApprovedConsumer(address _consumer) public view returns (bool) {
        return approvedConsumers.contains(_consumer);
    }

    function distribute(uint256 _since)
        public
        override
        onlyApprovedConsumer
        nonReentrant
        returns (uint256)
    {
        address sender = _msgSender();

        ConsumerInfo storage consumer = consumerInfo[sender];
        uint256 multiplier = _getMultiplier(
            consumer.lastDistributeBlock,
            block.number,
            _since,
            consumer.weekPoint
        );
        if (multiplier == 0) {
            return 0;
        }

        consumer.lastDistributeBlock = block.number;
        uint256 amount = multiplier
            .mul(dxPerBlock)
            .mul(consumer.allocPoint)
            .div(totalAllocPoint)
            .div(SAFE_MULTIPLIER);

        vault.supply(amount);
        IERC20(vault.DX()).safeTransfer(sender, amount);

        uint256 _weekPoint = consumer.weekPoint.add(A_WEEK_BLOCKNUMS);

        // check week point block nums
        if (block.number > _weekPoint) {
            consumer.weekPoint = _weekPoint;
            dxPerBlock = dxPerBlock.mul(min).div(max);
        }

        return amount;
    }

    function preview(address _consumer, uint256 _since)
        public
        view
        override
        returns (uint256)
    {
        require(
            approvedConsumers.contains(_consumer),
            "DxSupplier: consumer isn't approved"
        );

        ConsumerInfo storage consumer = consumerInfo[_consumer];
        uint256 multiplier = _getMultiplier(
            consumer.lastDistributeBlock,
            block.number,
            _since,
            consumer.weekPoint
        );
        if (multiplier == 0) {
            return 0;
        }

        uint256 amount = multiplier
            .mul(dxPerBlock)
            .mul(consumer.allocPoint)
            .div(totalAllocPoint)
            .div(SAFE_MULTIPLIER);

        return amount;
    }

    // Return reward multiplier over the given _from to _to block.
    function _getMultiplier(
        uint256 _from,
        uint256 _to,
        uint256 _since,
        uint256 _weekPoint
    ) private view returns (uint256) {
        _from = _from.max(_since);
        if (_to <= _weekPoint) {
            return 0;
        }

        uint256 lastWeekPoint = _weekPoint.add(A_WEEK_BLOCKNUMS);
        if (_to <= lastWeekPoint) {
            return _to.sub(_from).mul(SAFE_MULTIPLIER);
        }
        if (_from <= lastWeekPoint && _to >= lastWeekPoint) {
            return
                lastWeekPoint.sub(_from).mul(SAFE_MULTIPLIER).add(
                    _to.sub(lastWeekPoint).mul(SAFE_MULTIPLIER).mul(min).div(
                        max
                    )
                );
        }
        if (_from > lastWeekPoint) {
            return _to.sub(_from).mul(SAFE_MULTIPLIER).mul(min).div(max);
        }
        return 0;
    }

    /* ========== OWNER ============= */

    /**
     * @dev Add a new consumer. Can be called by the Admin
     */
    function add(
        uint256 _allocPoint,
        address _consumer,
        uint256 _startBlock
    ) public onlyAdmin {
        approvedConsumers.add(_consumer);
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        consumerInfo[_consumer] = ConsumerInfo({
            consumer: _consumer,
            allocPoint: _allocPoint,
            lastDistributeBlock: _startBlock,
            weekPoint: _startBlock
        });
    }

    /**
     * @dev Removes a consumer. Can only be called by the owner
     */
    function remove(address _consumer) public onlyAdmin {
        require(
            approvedConsumers.contains(_consumer),
            "DxSupplier: consumer isn't approved"
        );

        approvedConsumers.remove(_consumer);

        totalAllocPoint = totalAllocPoint.sub(
            consumerInfo[_consumer].allocPoint
        );

        delete consumerInfo[_consumer];
    }

    /**
     * @dev Update the given consumer's DX allocation point. Can only be called by the owner.
     */
    function set(address _consumer, uint256 _allocPoint) public onlyAdmin {
        require(
            approvedConsumers.contains(_consumer),
            "DxSupplier: consumer isn't approved"
        );

        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(
            consumerInfo[_consumer].allocPoint
        );
        consumerInfo[_consumer].allocPoint = _allocPoint;
    }

    // Update number of DX to mint per block
    function setDxPerBlock(
        uint256 _dxPerBlock,
        address _farm,
        bool _updatePool
    ) external onlyAdmin {
        require(
            approvedConsumers.contains(_farm),
            "DxSupplier: consumer isn't approved"
        );
        if (_updatePool) {
            IDxFarm(_farm).updatePool();
        }

        dxPerBlock = _dxPerBlock;
    }

    /* ========== MODIFIER ========== */

    modifier onlyApprovedConsumer() {
        require(
            approvedConsumers.contains(_msgSender()),
            "DxSupplier: unauthorized"
        );
        _;
    }
}
