// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./AssetLib.sol";
import "./Perp.sol";

library PerpFee {
    using ScaledAsset for ScaledAsset.TokenStatus;

    function computeUserFee(
        DataType.PairStatus memory _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus memory _userStatus
    ) internal view returns (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) {
        unrealizedFeeUnderlying = _assetStatus.underlyingPool.tokenStatus.computeUserFee(_userStatus.underlying);
        unrealizedFeeStable = _assetStatus.stablePool.tokenStatus.computeUserFee(_userStatus.stable);

        {
            (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) = computeRebalanceEntryFee(
                _assetStatus.id, _assetStatus.sqrtAssetStatus, _rebalanceFeeGrowthCache, _userStatus
            );
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

    function settleUserFee(
        DataType.PairStatus memory _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 totalFeeUnderlying, int256 totalFeeStable) {
        // settle asset interest
        totalFeeUnderlying = _assetStatus.underlyingPool.tokenStatus.settleUserFee(_userStatus.underlying);
        totalFeeStable = _assetStatus.stablePool.tokenStatus.settleUserFee(_userStatus.stable);

        // settle rebalance interest
        (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) = settleRebalanceEntryFee(
            _assetStatus.id, _assetStatus.sqrtAssetStatus, _rebalanceFeeGrowthCache, _userStatus
        );

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

    function computeRebalanceEntryFee(
        uint256 _assetId,
        Perp.SqrtPerpAssetStatus memory _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus memory _userStatus
    ) internal view returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) {
        if (_userStatus.sqrtPerp.amount > 0 && _userStatus.lastNumRebalance < _assetStatus.numRebalance) {
            uint256 rebalanceId = AssetLib.getRebalanceCacheId(_assetId, _userStatus.lastNumRebalance);

            rebalanceFeeUnderlying = Math.mulDivDownInt256(
                _assetStatus.rebalanceFeeGrowthUnderlying - _rebalanceFeeGrowthCache[rebalanceId].underlyingGrowth,
                _userStatus.sqrtPerp.amount,
                Constants.ONE
            );
            rebalanceFeeStable = Math.mulDivDownInt256(
                _assetStatus.rebalanceFeeGrowthStable - _rebalanceFeeGrowthCache[rebalanceId].stableGrowth,
                _userStatus.sqrtPerp.amount,
                Constants.ONE
            );
        }
    }

    function settleRebalanceEntryFee(
        uint256 _assetId,
        Perp.SqrtPerpAssetStatus memory _assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) {
        if (_userStatus.sqrtPerp.amount > 0 && _userStatus.lastNumRebalance < _assetStatus.numRebalance) {
            (rebalanceFeeUnderlying, rebalanceFeeStable) =
                computeRebalanceEntryFee(_assetId, _assetStatus, _rebalanceFeeGrowthCache, _userStatus);

            _userStatus.lastNumRebalance = _assetStatus.numRebalance;
            _assetStatus.lastRebalanceTotalSquartAmount -= uint256(_userStatus.sqrtPerp.amount);
        }
    }

    function mulDivToInt256(uint256 x, int256 y) internal pure returns (int256) {
        return SafeCast.toInt256(x) * y / int256(Constants.ONE);
    }
}
