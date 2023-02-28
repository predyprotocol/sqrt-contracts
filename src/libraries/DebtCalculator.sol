// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@solmate/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./UniHelper.sol";
import "./DataType.sol";
import "./Constants.sol";
import "./PerpFee.sol";
import "./math/Math.sol";

library DebtCalculator {
    function calculateDebtValue(
        DataType.AssetStatus memory _underlyingAssetStatus,
        Perp.UserStatus memory _perpUserStatus,
        uint160 _sqrtPrice
    ) internal pure returns (uint256) {
        (int256 amountUnderlying, int256 amountStable) = Perp.getAmounts(
            _underlyingAssetStatus.sqrtAssetStatus, _perpUserStatus, _underlyingAssetStatus.isMarginZero, _sqrtPrice
        );

        return _calculateDebtValue(_sqrtPrice, amountUnderlying, amountStable);
    }

    function _calculateDebtValue(uint256 _sqrtPrice, int256 amountUnderlying, int256 amountStable)
        internal
        pure
        returns (uint256)
    {
        uint256 price = (_sqrtPrice * _sqrtPrice) >> Constants.RESOLUTION;

        uint256 debtAmountStable = amountStable < 0 ? uint256(-amountStable) : 0;
        uint256 debtAmountUnderlying = amountUnderlying < 0 ? uint256(-amountUnderlying) : 0;

        return ((debtAmountUnderlying * price) >> Constants.RESOLUTION) + debtAmountStable;
    }
}
