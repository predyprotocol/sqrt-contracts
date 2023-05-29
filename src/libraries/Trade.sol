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

    function settleFee(
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _perpUserStatus
    ) internal returns (int256 fee) {
        Perp.updateRebalanceFeeGrowth(_pairStatus, _pairStatus.sqrtAssetStatus);

        int256 underlyingFee;
        int256 stableFee;

        (underlyingFee, stableFee) = settleUserBalanceAndFee(_pairStatus, _rebalanceFeeGrowthCache, _perpUserStatus);

        // swap
        SwapLib.SwapStableResult memory swapResult = SwapLib.swap(
            _pairStatus.sqrtAssetStatus.uniswapPool,
            SwapLib.SwapUnderlyingParams(0, 0, underlyingFee),
            _pairStatus.isMarginZero
        );

        fee = roundAndAddProtocolFee(_pairStatus, stableFee + swapResult.fee);
    }

    function trade(
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _perpUserStatus,
        int256 _tradeAmount,
        int256 _tradeAmountSqrt
    ) internal returns (DataType.TradeResult memory tradeResult) {
        Perp.updateRebalanceFeeGrowth(_pairStatus, _pairStatus.sqrtAssetStatus);

        int256 underlyingFee;
        int256 stableFee;

        (underlyingFee, stableFee) = settleUserBalanceAndFee(_pairStatus, _rebalanceFeeGrowthCache, _perpUserStatus);

        (int256 underlyingAmountForSqrt, int256 stableAmountForSqrt) = Perp.computeRequiredAmounts(
            _pairStatus.sqrtAssetStatus, _pairStatus.isMarginZero, _perpUserStatus, _tradeAmountSqrt
        );

        // swap
        SwapLib.SwapStableResult memory swapResult = SwapLib.swap(
            _pairStatus.sqrtAssetStatus.uniswapPool,
            SwapLib.SwapUnderlyingParams(-_tradeAmount, underlyingAmountForSqrt, underlyingFee),
            _pairStatus.isMarginZero
        );

        // update position
        tradeResult.payoff = Perp.updatePosition(
            _pairStatus,
            _perpUserStatus,
            Perp.UpdatePerpParams(_tradeAmount, swapResult.amountPerp),
            Perp.UpdateSqrtPerpParams(_tradeAmountSqrt, swapResult.amountSqrtPerp + stableAmountForSqrt)
        );

        tradeResult.payoff.perpPayoff = roundAndAddProtocolFee(_pairStatus, tradeResult.payoff.perpPayoff);
        tradeResult.payoff.sqrtPayoff = roundAndAddProtocolFee(_pairStatus, tradeResult.payoff.sqrtPayoff);

        tradeResult.fee = roundAndAddProtocolFee(_pairStatus, stableFee + swapResult.fee);
    }

    function settleUserBalanceAndFee(
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 underlyingFee, int256 stableFee) {
        // settle rebalance fee if settle balance happens
        (underlyingFee, stableFee) = PerpFee.settleUserFee(_pairStatus, rebalanceFeeGrowthCache, _userStatus);

        Perp.settleUserBalance(_pairStatus, _userStatus);
    }

    function roundAndAddProtocolFee(DataType.PairStatus storage _pairStatus, int256 _amount)
        internal
        returns (int256)
    {
        int256 rounded = roundMargin(_amount, Constants.MARGIN_ROUNDED_DECIMALS);
        if (_amount > rounded) {
            if (_pairStatus.sqrtAssetStatus.totalAmount > 0) {
                uint256 deltaFee = uint256(_amount - rounded) * Constants.Q128 / _pairStatus.sqrtAssetStatus.totalAmount;

                if (_pairStatus.isMarginZero) {
                    _pairStatus.sqrtAssetStatus.fee0Growth += deltaFee;
                } else {
                    _pairStatus.sqrtAssetStatus.fee1Growth += deltaFee;
                }
            } else {
                return _amount;
            }
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
