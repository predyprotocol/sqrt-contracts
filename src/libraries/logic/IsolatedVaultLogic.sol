// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./TradeLogic.sol";

/*
 * Error Codes
 * I1: vault is not safe
 * I2: vault must not have positions
 */
library IsolatedVaultLogic {
    struct CloseParams {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
    }

    event IsolatedVaultOpened(uint256 vaultId, uint256 isolatedVaultId, uint256 marginAmount);
    event IsolatedVaultClosed(uint256 vaultId, uint256 isolatedVaultId, uint256 marginAmount);

    function openIsolatedVault(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        DataType.Vault storage _isolatedVault,
        uint256 _depositAmount,
        uint64 _pairId,
        TradeLogic.TradeParams memory _tradeParams
    ) external returns (DataType.TradeResult memory tradeResult) {
        Perp.UserStatus storage openPosition = VaultLib.getUserStatus(_pairGroup, _pairs, _isolatedVault, _pairId);

        _vault.margin -= int256(_depositAmount);
        _isolatedVault.margin += int256(_depositAmount);

        PositionCalculator.isSafe(_pairs, _rebalanceFeeGrowthCache, _vault, false);

        tradeResult = TradeLogic.execTrade(
            _pairGroup, _pairs, _rebalanceFeeGrowthCache, _isolatedVault, _pairId, openPosition, _tradeParams
        );

        emit IsolatedVaultOpened(_vault.id, _isolatedVault.id, _depositAmount);
    }

    function closeIsolatedVault(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        DataType.Vault storage _isolatedVault,
        uint64 _pairId,
        CloseParams memory _closeParams
    ) external returns (DataType.TradeResult memory tradeResult) {
        tradeResult = closeVault(_pairGroup, _pairs, rebalanceFeeGrowthCache, _isolatedVault, _pairId, _closeParams);

        require(tradeResult.minDeposit == 0, "I2");

        // _isolatedVault.margin must be greater than 0

        int256 withdrawnMargin = _isolatedVault.margin;

        _vault.margin += _isolatedVault.margin;

        _isolatedVault.margin = 0;

        emit IsolatedVaultClosed(_vault.id, _isolatedVault.id, uint256(withdrawnMargin));
    }

    function closeVault(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        uint64 _pairId,
        CloseParams memory _closeParams
    ) internal returns (DataType.TradeResult memory tradeResult) {
        Perp.UserStatus storage openPosition = VaultLib.getUserStatus(_pairGroup, _pairs, _vault, _pairId);

        int256 tradeAmount = -openPosition.perp.amount;
        int256 tradeAmountSqrt = -openPosition.sqrtPerp.amount;

        return TradeLogic.execTrade(
            _pairGroup,
            _pairs,
            _rebalanceFeeGrowthCache,
            _vault,
            _pairId,
            openPosition,
            TradeLogic.TradeParams(
                tradeAmount,
                tradeAmountSqrt,
                _closeParams.lowerSqrtPrice,
                _closeParams.upperSqrtPrice,
                _closeParams.deadline,
                false,
                ""
            )
        );
    }
}
