// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./Perp.sol";

library PerpFee {
    using ScaledAsset for ScaledAsset.TokenStatus;

    function computeUserFee(DataType.PairStatus memory _assetStatus, Perp.UserStatus memory _userStatus)
        internal
        pure
        returns (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable)
    {
        unrealizedFeeUnderlying = _assetStatus.underlyingPool.tokenStatus.computeUserFee(_userStatus.underlying);
        unrealizedFeeStable = _assetStatus.stablePool.tokenStatus.computeUserFee(_userStatus.stable);

        {
            (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) =
                computeRebalanceEntryFee(_assetStatus.sqrtAssetStatus, _userStatus);
            unrealizedFeeUnderlying += rebalanceFeeUnderlying;
            unrealizedFeeStable += rebalanceFeeStable;
        }

        // settle premium
        {
            int256 premium = computePremium(_assetStatus, _userStatus.sqrtPerp);
            unrealizedFeeStable += premium;
        }

        {
            (int256 feeUnderlying, int256 feeStable) = computeTradeFee(_assetStatus, _userStatus.sqrtPerp);
            unrealizedFeeUnderlying += feeUnderlying;
            unrealizedFeeStable += feeStable;
        }
    }

    function settleUserFee(DataType.PairStatus memory _assetStatus, Perp.UserStatus storage _userStatus)
        internal
        returns (int256 totalFeeUnderlying, int256 totalFeeStable)
    {
        // settle asset interest
        totalFeeUnderlying = _assetStatus.underlyingPool.tokenStatus.settleUserFee(_userStatus.underlying);
        totalFeeStable = _assetStatus.stablePool.tokenStatus.settleUserFee(_userStatus.stable);

        // settle rebalance interest
        (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) =
            settleRebalanceEntryFee(_assetStatus.sqrtAssetStatus, _userStatus);

        // settle premium
        int256 premium = settlePremium(_assetStatus, _userStatus.sqrtPerp);

        // settle trade fee
        (int256 feeUnderlying, int256 feeStable) = settleTradeFee(_assetStatus, _userStatus.sqrtPerp);

        totalFeeStable += feeStable + premium + rebalanceFeeStable;
        totalFeeUnderlying += feeUnderlying + rebalanceFeeUnderlying;
    }

    // Trade fee

    function computeTradeFee(
        DataType.PairStatus memory _underlyingAssetStatus,
        Perp.SqrtPositionStatus memory _sqrtPerp
    ) internal pure returns (int256 feeUnderlying, int256 feeStable) {
        int256 fee0;
        int256 fee1;

        if (_sqrtPerp.amount > 0) {
            fee0 = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.fee0Growth - _sqrtPerp.entryTradeFee0, _sqrtPerp.amount
            );
            fee1 = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.fee1Growth - _sqrtPerp.entryTradeFee1, _sqrtPerp.amount
            );
        }

        if (_underlyingAssetStatus.isMarginZero) {
            feeStable = fee0;
            feeUnderlying = fee1;
        } else {
            feeUnderlying = fee0;
            feeStable = fee1;
        }
    }

    function settleTradeFee(
        DataType.PairStatus memory _underlyingAssetStatus,
        Perp.SqrtPositionStatus storage _sqrtPerp
    ) internal returns (int256 feeUnderlying, int256 feeStable) {
        (feeUnderlying, feeStable) = computeTradeFee(_underlyingAssetStatus, _sqrtPerp);

        _sqrtPerp.entryTradeFee0 = _underlyingAssetStatus.sqrtAssetStatus.fee0Growth;
        _sqrtPerp.entryTradeFee1 = _underlyingAssetStatus.sqrtAssetStatus.fee1Growth;
    }

    // Premium

    function computePremium(DataType.PairStatus memory _underlyingAssetStatus, Perp.SqrtPositionStatus memory _sqrtPerp)
        internal
        pure
        returns (int256 premium)
    {
        if (_sqrtPerp.amount > 0) {
            premium = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.supplyPremiumGrowth - _sqrtPerp.entryPremium, _sqrtPerp.amount
            );
        } else if (_sqrtPerp.amount < 0) {
            premium = mulDivToInt256(
                _underlyingAssetStatus.sqrtAssetStatus.borrowPremiumGrowth - _sqrtPerp.entryPremium, _sqrtPerp.amount
            );
        }
    }

    function settlePremium(DataType.PairStatus memory _underlyingAssetStatus, Perp.SqrtPositionStatus storage _sqrtPerp)
        internal
        returns (int256 premium)
    {
        premium = computePremium(_underlyingAssetStatus, _sqrtPerp);

        if (_sqrtPerp.amount > 0) {
            _sqrtPerp.entryPremium = _underlyingAssetStatus.sqrtAssetStatus.supplyPremiumGrowth;
        } else if (_sqrtPerp.amount < 0) {
            _sqrtPerp.entryPremium = _underlyingAssetStatus.sqrtAssetStatus.borrowPremiumGrowth;
        }
    }

    // Rebalance fee

    function computeRebalanceEntryFee(Perp.SqrtPerpAssetStatus memory _assetStatus, Perp.UserStatus memory _userStatus)
        internal
        pure
        returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable)
    {
        if (_userStatus.sqrtPerp.amount > 0) {
            rebalanceFeeUnderlying = (
                _assetStatus.rebalanceFeeGrowthUnderlying - _userStatus.rebalanceEntryFeeUnderlying
            ) * _userStatus.sqrtPerp.amount / int256(Constants.ONE);

            rebalanceFeeStable = (_assetStatus.rebalanceFeeGrowthStable - _userStatus.rebalanceEntryFeeStable)
                * _userStatus.sqrtPerp.amount / int256(Constants.ONE);
        }
    }

    function settleRebalanceEntryFee(Perp.SqrtPerpAssetStatus memory _assetStatus, Perp.UserStatus storage _userStatus)
        internal
        returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable)
    {
        (rebalanceFeeUnderlying, rebalanceFeeStable) = computeRebalanceEntryFee(_assetStatus, _userStatus);

        _userStatus.rebalanceEntryFeeUnderlying = _assetStatus.rebalanceFeeGrowthUnderlying;
        _userStatus.rebalanceEntryFeeStable = _assetStatus.rebalanceFeeGrowthStable;
    }

    function mulDivToInt256(uint256 x, int256 y) internal pure returns (int256) {
        return SafeCast.toInt256(x) * y / int256(Constants.ONE);
    }
}
