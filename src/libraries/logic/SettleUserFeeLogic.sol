// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "../Trade.sol";
import "../ScaledAsset.sol";
import "../UniHelper.sol";

library SettleUserFeeLogic {
    event FeeCollected(uint256 vaultId, uint256 assetId, int256 feeCollected);

    function settleUserFee(
        mapping(uint256 => DataType.PairStatus) storage _assets,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault
    ) external returns (int256[] memory latestFees) {
        return settleUserFee(_assets, _rebalanceFeeGrowthCache, _vault, 0);
    }

    function settleUserFee(
        mapping(uint256 => DataType.PairStatus) storage _assets,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        uint256 _excludeAssetId
    ) public returns (int256[] memory latestFees) {
        latestFees = new int256[](_vault.openPositions.length);

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            uint256 assetId = _vault.openPositions[i].assetId;

            if (assetId == _excludeAssetId) {
                continue;
            }

            int256 fee = Trade.settleFee(_assets[assetId], _rebalanceFeeGrowthCache, _vault.openPositions[i].perpTrade);

            latestFees[i] = fee;

            _vault.margin += fee;

            emit FeeCollected(_vault.id, assetId, fee);

            UniHelper.checkPriceByTWAP(_assets[assetId].sqrtAssetStatus.uniswapPool);
        }
    }
}
