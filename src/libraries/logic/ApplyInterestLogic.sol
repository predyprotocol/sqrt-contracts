// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../Perp.sol";
import "../ScaledAsset.sol";
import "../AssetLib.sol";

library ApplyInterestLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event InterestGrowthUpdated(
        uint256 pairId,
        ScaledAsset.TokenStatus stableStatus,
        ScaledAsset.TokenStatus underlyingStatus,
        uint256 interestRateStable,
        uint256 interestRateUnderlying
    );

    function applyInterestForVault(DataType.Vault memory _vault, mapping(uint256 => DataType.PairStatus) storage _pairs)
        external
    {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            uint256 pairId = _vault.openPositions[i].pairId;

            applyInterestForToken(_pairs, pairId);
        }
    }

    function applyInterestForToken(mapping(uint256 => DataType.PairStatus) storage _pairs, uint256 _pairId) public {
        DataType.PairStatus storage pairStatus = _pairs[_pairId];

        require(pairStatus.id > 0, "A0");

        Perp.updateFeeAndPremiumGrowth(_pairId, pairStatus.sqrtAssetStatus);

        uint256 interestRateStable = applyInterestForPoolStatus(pairStatus.stablePool, pairStatus.lastUpdateTimestamp);

        uint256 interestRateUnderlying =
            applyInterestForPoolStatus(pairStatus.underlyingPool, pairStatus.lastUpdateTimestamp);

        // Update last update timestamp
        pairStatus.lastUpdateTimestamp = block.timestamp;

        if (interestRateStable > 0 || interestRateUnderlying > 0) {
            emitInterestGrowthEvent(pairStatus, interestRateStable, interestRateUnderlying);
        }
    }

    function applyInterestForPoolStatus(DataType.AssetPoolStatus storage _poolStatus, uint256 _lastUpdateTimestamp)
        internal
        returns (uint256 interestRate)
    {
        if (block.timestamp <= _lastUpdateTimestamp) {
            return 0;
        }

        // Gets utilization ratio
        uint256 utilizationRatio = _poolStatus.tokenStatus.getUtilizationRatio();

        if (utilizationRatio == 0) {
            return 0;
        }

        // Calculates interest rate
        interestRate = InterestRateModel.calculateInterestRate(_poolStatus.irmParams, utilizationRatio)
            * (block.timestamp - _lastUpdateTimestamp) / 365 days;

        // Update scaler
        _poolStatus.tokenStatus.updateScaler(interestRate);
    }

    function emitInterestGrowthEvent(
        DataType.PairStatus memory _assetStatus,
        uint256 _interestRatioStable,
        uint256 _interestRatioUnderlying
    ) internal {
        emit InterestGrowthUpdated(
            _assetStatus.id,
            _assetStatus.stablePool.tokenStatus,
            _assetStatus.underlyingPool.tokenStatus,
            _interestRatioStable,
            _interestRatioUnderlying
        );
    }

    function reallocate(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        uint256 _pairId
    ) external returns (bool reallocationHappened, int256 profit) {
        DataType.PairStatus storage pairStatus = _pairs[_pairId];

        AssetLib.checkUnderlyingAsset(pairStatus);

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        (reallocationHappened, profit) = Perp.reallocate(pairStatus, pairStatus.sqrtAssetStatus, false);

        if (reallocationHappened) {
            _rebalanceFeeGrowthCache[AssetLib.getRebalanceCacheId(_pairId, pairStatus.sqrtAssetStatus.numRebalance)] =
            DataType.RebalanceFeeGrowthCache(
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthStable,
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthUnderlying
            );
            pairStatus.sqrtAssetStatus.lastRebalanceTotalSquartAmount = pairStatus.sqrtAssetStatus.totalAmount;
            pairStatus.sqrtAssetStatus.numRebalance++;
        }

        if (profit < 0) {
            address token;

            if (pairStatus.isMarginZero) {
                token = pairStatus.underlyingPool.token;
            } else {
                token = pairStatus.stablePool.token;
            }

            TransferHelper.safeTransferFrom(token, msg.sender, address(this), uint256(-profit));
        }
    }
}
