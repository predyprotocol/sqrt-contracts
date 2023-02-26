// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../DataType.sol";
import "../Perp.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";

library ReaderLogic {
    using Perp for Perp.SqrtPerpAssetStatus;
    using ScaledAsset for ScaledAsset.TokenStatus;

    function getVaultStatus(
        DataType.AssetGroup memory _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        uint256 _mainVaultId
    ) external view returns (DataType.VaultStatusResult memory) {
        DataType.AssetStatus memory stableAssetStatus = _assets[_assetGroup.stableAssetId];

        DataType.SubVaultStatusResult[] memory subVaults =
            new DataType.SubVaultStatusResult[](_vault.openPositions.length);

        for (uint256 i; i < _vault.openPositions.length; i++) {
            DataType.UserStatus memory userStatus = _vault.openPositions[i];

            bool isMarginZero = _assets[userStatus.assetId].isMarginZero;
            uint160 sqrtPrice = UniHelper.convertSqrtPrice(
                UniHelper.getSqrtTWAP(_assets[userStatus.assetId].sqrtAssetStatus.uniswapPool), isMarginZero
            );

            subVaults[i].assetId = userStatus.assetId;
            subVaults[i].stableAmount = userStatus.perpTrade.stable.positionAmount;
            subVaults[i].underlyingamount = userStatus.perpTrade.underlying.positionAmount;
            subVaults[i].sqrtAmount = userStatus.perpTrade.sqrtPerp.amount;

            {
                (int256 amount0, int256 amount1) = Perp.getAmounts(
                    _assets[userStatus.assetId].sqrtAssetStatus, userStatus.perpTrade, isMarginZero, sqrtPrice
                );

                if (isMarginZero) {
                    subVaults[i].delta = amount1;
                } else {
                    subVaults[i].delta = amount0;
                }
            }

            (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) =
                PerpFee.computeUserFee(_assets[userStatus.assetId], stableAssetStatus.tokenStatus, userStatus.perpTrade);

            subVaults[i].unrealizedFee = PositionCalculator.calculateValue(
                sqrtPrice, PositionCalculator.PositionParams(unrealizedFeeStable, 0, unrealizedFeeUnderlying)
            );
        }

        (int256 minDeposit, int256 vaultValue,) =
            PositionCalculator.calculateMinDeposit(_assets, _vault, true);

        return DataType.VaultStatusResult(
            _mainVaultId == _vault.id, vaultValue, _vault.margin, vaultValue - _vault.margin, minDeposit, subVaults
        );
    }

    /**
     * @notice Gets utilization ratio
     */
    function getUtilizationRatio(DataType.AssetStatus memory _assetStatus) external pure returns (uint256, uint256) {
        return (_assetStatus.sqrtAssetStatus.getUtilizationRatio(), _assetStatus.tokenStatus.getUtilizationRatio());
    }

    // getInterest

    function getDelta(
        uint256 _tokenId,
        Perp.SqrtPerpAssetStatus memory _sqrtAssetStatus,
        bool _isMarginZero,
        DataType.Vault memory _vault,
        uint160 _sqrtPrice
    ) internal pure returns (int256 _delta) {
        for (uint256 i; i < _vault.openPositions.length; i++) {
            if (_tokenId != _vault.openPositions[i].assetId) {
                continue;
            }

            (int256 amount0, int256 amount1) =
                Perp.getAmounts(_sqrtAssetStatus, _vault.openPositions[i].perpTrade, _isMarginZero, _sqrtPrice);

            if (_isMarginZero) {
                _delta += amount1;
            } else {
                _delta += amount0;
            }
        }
    }
}
