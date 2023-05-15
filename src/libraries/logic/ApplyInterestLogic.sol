// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../AssetGroupLib.sol";
import "../Perp.sol";
import "../ScaledAsset.sol";
import "../AssetLib.sol";

library ApplyInterestLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event InterestGrowthUpdated(
        uint256 assetId,
        uint256 underlyingAssetGrowth,
        uint256 underlyingDebtGrowth,
        uint256 stableAssetGrowth,
        uint256 stableDebtGrowth,
        uint256 underlyingAccumulatedProtocolRevenue,
        uint256 stableAccumulatedProtocolRevenue
    );

    event PremiumGrowthUpdated(
        uint256 assetId,
        uint256 borrowPremium0Growth,
        uint256 borrowPremium1Growth,
        uint256 fee0Growth,
        uint256 fee1Growth
    );

    function applyInterestForAssetGroup(
        DataType.AssetGroup storage _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets
    ) external {
        for (uint256 i = 1; i < _assetGroup.assetsCount; i++) {
            applyInterestForToken(_assets, i);
        }
    }

    function applyInterestForToken(mapping(uint256 => DataType.AssetStatus) storage _assets, uint256 _assetId) public {
        DataType.AssetStatus storage assetStatus = _assets[_assetId];

        require(assetStatus.id > 0, "A0");

        if (block.timestamp <= assetStatus.lastUpdateTimestamp) {
            return;
        }

        assetStatus.stablePool.accumulatedProtocolRevenue += Perp.updateFeeAndPremiumGrowth(
            assetStatus.sqrtAssetStatus,
            assetStatus.squartIRMParams,
            assetStatus.isMarginZero,
            assetStatus.lastUpdateTimestamp
        );

        applyInterestForPoolStatus(assetStatus.underlyingPool, assetStatus.lastUpdateTimestamp);

        applyInterestForPoolStatus(assetStatus.stablePool, assetStatus.lastUpdateTimestamp);

        // Update last update timestamp
        assetStatus.lastUpdateTimestamp = block.timestamp;

        emitInterestGrowthEvent(assetStatus);
        emitPremiumGrowthEvent(assetStatus);
    }

    function applyInterestForPoolStatus(DataType.AssetPoolStatus storage _poolStatus, uint256 _lastUpdateTimestamp)
        internal
    {
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

    function emitInterestGrowthEvent(DataType.AssetStatus memory _assetStatus) internal {
        emit InterestGrowthUpdated(
            _assetStatus.id,
            _assetStatus.underlyingPool.tokenStatus.assetGrowth,
            _assetStatus.underlyingPool.tokenStatus.debtGrowth,
            _assetStatus.stablePool.tokenStatus.assetGrowth,
            _assetStatus.stablePool.tokenStatus.debtGrowth,
            _assetStatus.underlyingPool.accumulatedProtocolRevenue,
            _assetStatus.stablePool.accumulatedProtocolRevenue
        );
    }

    function emitPremiumGrowthEvent(DataType.AssetStatus memory _assetStatus) internal {
        emit PremiumGrowthUpdated(
            _assetStatus.id,
            _assetStatus.sqrtAssetStatus.supplyPremiumGrowth,
            _assetStatus.sqrtAssetStatus.borrowPremiumGrowth,
            _assetStatus.sqrtAssetStatus.fee0Growth,
            _assetStatus.sqrtAssetStatus.fee1Growth
        );
    }

    function reallocate(mapping(uint256 => DataType.AssetStatus) storage _assets, uint256 _assetId)
        external
        returns (bool reallocationHappened, int256 profit)
    {
        DataType.AssetStatus storage underlyingAsset = _assets[_assetId];

        AssetLib.checkUnderlyingAsset(underlyingAsset);

        (reallocationHappened, profit) = Perp.reallocate(underlyingAsset, underlyingAsset.sqrtAssetStatus, false);

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
