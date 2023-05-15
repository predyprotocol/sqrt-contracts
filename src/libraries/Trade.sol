// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@solmate/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./DataType.sol";
import "./Perp.sol";
import "./PerpFee.sol";
import "./SwapLib.sol";
import "./ScaledAsset.sol";

library Trade {
    using ScaledAsset for ScaledAsset.TokenStatus;

    function settleFee(DataType.PairStatus storage _underlyingAssetStatus, Perp.UserStatus storage _perpUserStatus)
        internal
        returns (int256 fee, bool isSettled)
    {
        Perp.updateRebalanceFeeGrowth(_underlyingAssetStatus, _underlyingAssetStatus.sqrtAssetStatus);

        int256 underlyingFee;
        int256 stableFee;

        (underlyingFee, stableFee, isSettled) = settleUserBalanceAndFee(_underlyingAssetStatus, _perpUserStatus);

        // swap
        SwapLib.SwapStableResult memory swapResult = SwapLib.swap(
            _underlyingAssetStatus.sqrtAssetStatus.uniswapPool,
            SwapLib.SwapUnderlyingParams(0, 0, underlyingFee),
            _underlyingAssetStatus.isMarginZero
        );

        fee = roundAndAddProtocolFee(_underlyingAssetStatus.stablePool, stableFee + swapResult.fee);
    }

    function trade(
        DataType.PairStatus storage _underlyingAssetStatus,
        Perp.UserStatus storage _perpUserStatus,
        int256 _tradeAmount,
        int256 _tradeAmountSqrt
    ) internal returns (DataType.TradeResult memory tradeResult) {
        Perp.updateRebalanceFeeGrowth(_underlyingAssetStatus, _underlyingAssetStatus.sqrtAssetStatus);

        int256 underlyingFee;
        int256 stableFee;

        (underlyingFee, stableFee,) = settleUserBalanceAndFee(_underlyingAssetStatus, _perpUserStatus);

        (int256 underlyingAmountForSqrt, int256 stableAmountForSqrt) =
            Perp.computeRequiredAmounts(_underlyingAssetStatus, _perpUserStatus, _tradeAmountSqrt);

        // swap
        SwapLib.SwapStableResult memory swapResult = SwapLib.swap(
            _underlyingAssetStatus.sqrtAssetStatus.uniswapPool,
            SwapLib.SwapUnderlyingParams(-_tradeAmount, underlyingAmountForSqrt, underlyingFee),
            _underlyingAssetStatus.isMarginZero
        );

        // update position
        tradeResult.payoff = Perp.updatePosition(
            _underlyingAssetStatus,
            _perpUserStatus,
            Perp.UpdatePerpParams(_tradeAmount, swapResult.amountPerp),
            Perp.UpdateSqrtPerpParams(_tradeAmountSqrt, swapResult.amountSqrtPerp + stableAmountForSqrt)
        );

        tradeResult.payoff.perpPayoff =
            roundAndAddProtocolFee(_underlyingAssetStatus.stablePool, tradeResult.payoff.perpPayoff);
        tradeResult.payoff.sqrtPayoff =
            roundAndAddProtocolFee(_underlyingAssetStatus.stablePool, tradeResult.payoff.sqrtPayoff);

        tradeResult.fee = roundAndAddProtocolFee(_underlyingAssetStatus.stablePool, stableFee + swapResult.fee);
    }

    function settleUserBalanceAndFee(
        DataType.PairStatus storage _underlyingAssetStatus,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 underlyingFee, int256 stableFee, bool isSettled) {
        (underlyingFee, stableFee) = PerpFee.settleUserFee(_underlyingAssetStatus, _userStatus);

        isSettled = Perp.settleUserBalance(_underlyingAssetStatus, _userStatus);
    }

    function roundAndAddProtocolFee(DataType.AssetPoolStatus storage _stablePoolStatus, int256 _amount)
        internal
        returns (int256)
    {
        int256 rounded = roundMargin(_amount, Constants.MARGIN_ROUNDED_DECIMALS);
        if (_amount > rounded) {
            _stablePoolStatus.accumulatedProtocolRevenue += uint256(_amount - rounded);
        }
        return rounded;
    }

    function roundMargin(int256 _amount, uint256 _roundedDecimals) internal pure returns (int256) {
        if (_amount > 0) {
            return int256(FixedPointMathLib.mulDivDown(uint256(_amount), 1, _roundedDecimals) * _roundedDecimals);
        } else {
            return -int256(FixedPointMathLib.mulDivUp(uint256(-_amount), 1, _roundedDecimals) * _roundedDecimals);
        }
    }
}
