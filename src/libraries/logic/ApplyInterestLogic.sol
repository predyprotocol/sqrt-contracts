// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../Perp.sol";
import "../ScaledAsset.sol";
import "../AssetLib.sol";

library ApplyInterestLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event InterestGrowthUpdated(
        uint256 assetId,
        uint256 stableAssetGrowth,
        uint256 stableDebtGrowth,
        uint256 underlyingAssetGrowth,
        uint256 underlyingDebtGrowth,
        uint256 fee0Growth,
        uint256 fee1Growth,
        uint256 borrowPremium0Growth,
        uint256 borrowPremium1Growth,
        uint256 stableAccumulatedProtocolRevenue,
        uint256 underlyingAccumulatedProtocolRevenue
    );

    function applyInterestForAssetGroup(
        DataType.PairGroup storage _assetGroup,
        mapping(uint256 => DataType.PairStatus) storage _assets
    ) external {
        for (uint256 i = 1; i < _assetGroup.assetsCount; i++) {
            applyInterestForToken(_assets, i);
        }
    }

    function applyInterestForToken(mapping(uint256 => DataType.PairStatus) storage _assets, uint256 _pairId) public {
        DataType.PairStatus storage assetStatus = _assets[_pairId];

        require(assetStatus.id > 0, "A0");

        Perp.updateFeeAndPremiumGrowth(assetStatus.sqrtAssetStatus);

        applyInterestForPoolStatus(assetStatus.underlyingPool, assetStatus.lastUpdateTimestamp);

        applyInterestForPoolStatus(assetStatus.stablePool, assetStatus.lastUpdateTimestamp);

        // Update last update timestamp
        assetStatus.lastUpdateTimestamp = block.timestamp;

        emitInterestGrowthEvent(assetStatus);
    }

    function applyInterestForPoolStatus(DataType.AssetPoolStatus storage _poolStatus, uint256 _lastUpdateTimestamp)
        internal
    {
        if (block.timestamp <= _lastUpdateTimestamp) {
            return;
        }

        // Gets utilization ratio
        uint256 utilizationRatio = _poolStatus.tokenStatus.getUtilizationRatio();

        if (utilizationRatio == 0) {
            return;
        }

        // Calculates interest rate
        uint256 interestRate = InterestRateModel.calculateInterestRate(_poolStatus.irmParams, utilizationRatio)
            * (block.timestamp - _lastUpdateTimestamp) / 365 days;

        // Update scaler
        _poolStatus.accumulatedProtocolRevenue += _poolStatus.tokenStatus.updateScaler(interestRate);
    }

    function emitInterestGrowthEvent(DataType.PairStatus memory _assetStatus) internal {
        emit InterestGrowthUpdated(
            _assetStatus.id,
            _assetStatus.stablePool.tokenStatus.assetGrowth,
            _assetStatus.stablePool.tokenStatus.debtGrowth,
            _assetStatus.underlyingPool.tokenStatus.assetGrowth,
            _assetStatus.underlyingPool.tokenStatus.debtGrowth,
            _assetStatus.sqrtAssetStatus.fee0Growth,
            _assetStatus.sqrtAssetStatus.fee1Growth,
            _assetStatus.sqrtAssetStatus.borrowPremium0Growth,
            _assetStatus.sqrtAssetStatus.borrowPremium1Growth,
            _assetStatus.stablePool.accumulatedProtocolRevenue,
            _assetStatus.underlyingPool.accumulatedProtocolRevenue
        );
    }

    function reallocate(
        mapping(uint256 => DataType.PairStatus) storage _assets,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        uint256 _assetId
    ) external returns (bool reallocationHappened, int256 profit) {
        DataType.PairStatus storage underlyingAsset = _assets[_assetId];

        AssetLib.checkUnderlyingAsset(underlyingAsset);

        Perp.updateRebalanceFeeGrowth(underlyingAsset, underlyingAsset.sqrtAssetStatus);

        (reallocationHappened, profit) = Perp.reallocate(underlyingAsset, underlyingAsset.sqrtAssetStatus, false);

        if (reallocationHappened) {
            _rebalanceFeeGrowthCache[AssetLib.getRebalanceCacheId(
                _assetId, underlyingAsset.sqrtAssetStatus.numRebalance
            )] = DataType.RebalanceFeeGrowthCache(
                underlyingAsset.sqrtAssetStatus.rebalanceFeeGrowthStable,
                underlyingAsset.sqrtAssetStatus.rebalanceFeeGrowthUnderlying
            );
            underlyingAsset.sqrtAssetStatus.lastRebalanceTotalSquartAmount = underlyingAsset.sqrtAssetStatus.totalAmount;
            underlyingAsset.sqrtAssetStatus.numRebalance++;
        }

        if (profit < 0) {
            address token;

            if (underlyingAsset.isMarginZero) {
                token = underlyingAsset.underlyingPool.token;
            } else {
                token = underlyingAsset.stablePool.token;
            }

            TransferHelper.safeTransferFrom(token, msg.sender, address(this), uint256(-profit));
        }
    }
}
