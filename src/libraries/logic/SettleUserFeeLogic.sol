// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "../Trade.sol";
import "../ScaledAsset.sol";
import "../UniHelper.sol";

library SettleUserFeeLogic {
    event FeeCollected(uint256 vaultId, uint256 pairId, int256 feeCollected);

    function settleUserFee(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault
    ) external returns (int256[] memory latestFees) {
        return settleUserFee(_pairs, _rebalanceFeeGrowthCache, _vault, 0);
    }

    function settleUserFee(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        uint256 _excludeAssetId
    ) public returns (int256[] memory latestFees) {
        latestFees = new int256[](_vault.openPositions.length);

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            uint256 pairId = _vault.openPositions[i].pairId;

            if (pairId == _excludeAssetId) {
                continue;
            }

            int256 fee = Trade.settleFee(_pairs[pairId], _rebalanceFeeGrowthCache, _vault.openPositions[i]);

            latestFees[i] = fee;

            _vault.margin += fee;

            emit FeeCollected(_vault.id, pairId, fee);

            UniHelper.checkPriceByTWAP(_pairs[pairId].sqrtAssetStatus.uniswapPool);
        }
    }
}
