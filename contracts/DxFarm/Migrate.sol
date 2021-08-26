// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IPancakeRouter.sol";
import "../interfaces/IPancakePair.sol";

contract Migrate is Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IPancakeRouter public routerV1;
    IPancakeRouter public routerV2;

    // DX-BUSD
    IERC20 public fromLp;
    // DX-BNB
    IERC20 public toLp;

    address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public DX;

    receive() external payable {}

    fallback() external payable {}

    function initialize(
        address _dx,
        address _fromLp,
        address _toLp,
        address _routerV1,
        address _routerV2
    ) public initializer {
        fromLp = IERC20(_fromLp);
        toLp = IERC20(_toLp);
        DX = _dx;
        routerV1 = IPancakeRouter(_routerV1);
        routerV2 = IPancakeRouter(_routerV2);

        fromLp.safeApprove(address(routerV1), uint256(-1));
        IERC20(DX).safeApprove(address(routerV2), uint256(-1));
        IERC20(BUSD).safeApprove(address(routerV2), uint256(-1));
    }

    /**
     * @dev fromLp -> toLp
     */
    function migrate() public {
        uint256 fromLpBal = fromLp.balanceOf(msg.sender);
        if (fromLpBal == 0) {
            return;
        }

        fromLp.safeTransferFrom(msg.sender, address(this), fromLpBal);
        // remove liquidity
        (uint256 dxAmount, uint256 busdAmount) = routerV1.removeLiquidity(
            DX,
            BUSD,
            fromLpBal,
            0,
            0,
            address(this),
            block.timestamp + 60
        );

        // uint256[] memory amounts = routerV1.swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
        address[] memory path = new address[](2);
        path[0] = BUSD;
        path[1] = WBNB;

        // swap busd to bnb
        uint256[] memory amounts = routerV2.swapExactTokensForETH(
            busdAmount,
            0,
            path,
            address(this),
            block.timestamp + 60
        );

        uint256 receiveBnbAmount = amounts[1];

        // add new liquidity
        routerV2.addLiquidityETH{value: receiveBnbAmount}(
            DX,
            dxAmount,
            0,
            0,
            msg.sender,
            block.timestamp + 60
        );

        uint256 bnbBal = address(this).balance;
        uint256 dxbal = IERC20(DX).balanceOf(address(this));

        if (bnbBal > 0) {
            msg.sender.transfer(address(this).balance);
        }
        if (dxbal > 0) {
            IERC20(DX).transfer(msg.sender, dxbal);
        }
    }

    /**
     * @notice the new liquidity you will receive
     */
    function preview() public view returns (uint256) {
        uint256 fromLpBal = fromLp.balanceOf(msg.sender);

        if (fromLpBal == 0) {
            return 0;
        }

        uint256 fromLpTotalSupply = IPancakePair(address(fromLp)).totalSupply();

        uint256 fromLpDxBal = IERC20(DX).balanceOf(address(fromLp));
        uint256 fromLpBusdBal = IERC20(BUSD).balanceOf(address(fromLp));

        uint256 receiveDx = fromLpBal.mul(fromLpDxBal).div(fromLpTotalSupply);
        uint256 receiveBusd = fromLpBal.mul(fromLpBusdBal).div(
            fromLpTotalSupply
        );

        address[] memory path = new address[](2);
        path[0] = BUSD;
        path[1] = WBNB;

        uint256[] memory amounts = routerV1.getAmountsOut(receiveBusd, path);
        uint256 receiveBnb = amounts[1];

        (uint256 reserveDx, uint256 reserveBnb, ) = IPancakePair(address(toLp))
            .getReserves();

        if (IPancakePair(address(toLp)).token0() == WBNB) {
            (reserveDx, reserveBnb) = (reserveBnb, reserveDx);
        }
        uint256 needBnb = routerV2.quote(receiveDx, reserveDx, reserveBnb);

        uint256 amountDx;
        uint256 amountBnb;

        if (needBnb <= receiveBnb) {
            (amountDx, amountBnb) = (receiveDx, needBnb);
        } else {
            uint256 needDx = routerV2.quote(receiveBnb, reserveBnb, reserveDx);
            assert(needDx <= reserveDx);
            (amountDx, amountBnb) = (needDx, receiveBnb);
        }
        uint256 toLpTotalSupply = IPancakePair(address(toLp)).totalSupply();

        return
            Math.min(
                amountDx.mul(toLpTotalSupply).div(reserveDx),
                amountBnb.mul(toLpTotalSupply).div(reserveBnb)
            );
    }
}
