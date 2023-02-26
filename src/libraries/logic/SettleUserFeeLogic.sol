// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../AssetGroupLib.sol";
import "../Trade.sol";
import "../ScaledAsset.sol";

library SettleUserFeeLogic {
    event FeeCollected(uint256 vaultId, uint256 assetId, int256 feeCollected);

    function settleUserFee(
        DataType.AssetGroup storage _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault
    ) external returns (int256[] memory latestFees) {
        return settleUserFee(_assetGroup, _assets, _vault, 0);
    }

    function settleUserFee(
        DataType.AssetGroup storage _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        uint256 _excludeAssetId
    ) public returns (int256[] memory latestFees) {
        latestFees = new int256[](_vault.openPositions.length);

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            uint256 stableAssetId = _assetGroup.stableAssetId;
            uint256 assetId = _vault.openPositions[i].assetId;

            if (assetId == stableAssetId || assetId == _excludeAssetId) {
                continue;
            }

            int256 fee = Trade.settleFee(_assets[assetId], _assets[stableAssetId], _vault.openPositions[i].perpTrade);

            latestFees[i] = fee;

            _vault.margin += fee;

            emit FeeCollected(_vault.id, assetId, fee);
        }
    }
}
