// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "../ApplyInterestLib.sol";
import "./TradePerpLogic.sol";

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
        DataType.GlobalData storage _globalData,
        uint256 _depositAmount,
        uint64 _pairId,
        TradePerpLogic.TradeParams memory _tradeParams
    ) external returns (uint256 isolatedVaultId, DataType.TradeResult memory tradeResult) {
        // Checks pairId exists
        PairLib.validatePairId(_globalData, _pairId);

        DataType.PairGroup memory pairGroup;
        DataType.Vault storage vault;

        {
            uint256 pairGroupId = _globalData.pairs[_pairId].pairGroupId;
            uint256 vaultId = _globalData.ownVaultsMap[msg.sender][pairGroupId].mainVaultId;

            pairGroup = _globalData.pairGroups[pairGroupId];
            vault = _globalData.vaults[vaultId];

            // Checks account has mainVault
            VaultLib.checkVault(vault, msg.sender);

            // Checks pair and main vault belong to same pairGroup
            VaultLib.checkVaultBelongsToPairGroup(vault, pairGroupId);

            // Update interest rate related to main vault
            ApplyInterestLib.applyInterestForVault(vault, _globalData.pairs);

            isolatedVaultId = VaultLib.createVaultIfNeeded(_globalData, 0, msg.sender, pairGroupId, false);
        }

        DataType.Vault storage isolatedVault = _globalData.vaults[isolatedVaultId];

        Perp.UserStatus storage openPosition =
            VaultLib.createOrGetOpenPosition(_globalData.pairs, isolatedVault, _pairId);

        vault.margin -= int256(_depositAmount);
        isolatedVault.margin += int256(_depositAmount);

        // Checks main vault safety
        PositionCalculator.checkSafe(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, vault);

        tradeResult = TradePerpLogic.execTradeAndValidate(
            pairGroup, _globalData, isolatedVault, _pairId, openPosition, _tradeParams
        );

        emit IsolatedVaultOpened(vault.id, isolatedVault.id, _depositAmount);
    }

    function closeIsolatedVault(
        DataType.GlobalData storage _globalData,
        uint256 _isolatedVaultId,
        uint64 _pairId,
        CloseParams memory _closeParams
    ) external returns (DataType.TradeResult memory tradeResult) {
        // Checks pairId exists
        PairLib.validatePairId(_globalData, _pairId);
        // Checks isolatedVaultId exists
        VaultLib.validateVaultId(_globalData, _isolatedVaultId);

        uint256 pairGroupId = _globalData.pairs[_pairId].pairGroupId;
        DataType.Vault storage vault;

        {
            uint256 vaultId = _globalData.ownVaultsMap[msg.sender][pairGroupId].mainVaultId;

            // Check account has mainVault
            VaultLib.validateVaultId(_globalData, vaultId);

            vault = _globalData.vaults[vaultId];
        }

        DataType.Vault storage isolatedVault = _globalData.vaults[_isolatedVaultId];

        // Checks vaults owner is caller
        VaultLib.checkVault(isolatedVault, msg.sender);
        VaultLib.checkVault(vault, msg.sender);

        // Checks pair, isolated vault and main vault belong to same pairGroup
        VaultLib.checkVaultBelongsToPairGroup(vault, pairGroupId);
        VaultLib.checkVaultBelongsToPairGroup(isolatedVault, pairGroupId);

        // Updates interest rate related to isolated vault
        ApplyInterestLib.applyInterestForVault(isolatedVault, _globalData.pairs);

        // Check isolated vault safety
        tradeResult = closeVault(_globalData.pairGroups[pairGroupId], _globalData, isolatedVault, _pairId, _closeParams);

        require(tradeResult.minDeposit == 0, "I2");

        // _isolatedVault.margin must be greater than 0

        int256 withdrawnMargin = isolatedVault.margin;

        vault.margin += isolatedVault.margin;

        isolatedVault.margin = 0;

        VaultLib.removeIsolatedVaultId(_globalData.ownVaultsMap[msg.sender][vault.pairGroupId], isolatedVault.id);

        emit IsolatedVaultClosed(vault.id, isolatedVault.id, uint256(withdrawnMargin));
    }

    function closeVault(
        DataType.PairGroup memory _pairGroup,
        DataType.GlobalData storage _globalData,
        DataType.Vault storage _vault,
        uint64 _pairId,
        CloseParams memory _closeParams
    ) internal returns (DataType.TradeResult memory tradeResult) {
        Perp.UserStatus storage openPosition = VaultLib.createOrGetOpenPosition(_globalData.pairs, _vault, _pairId);

        int256 tradeAmount = -openPosition.perp.amount;
        int256 tradeAmountSqrt = -openPosition.sqrtPerp.amount;

        return TradePerpLogic.execTradeAndValidate(
            _pairGroup,
            _globalData,
            _vault,
            _pairId,
            openPosition,
            TradePerpLogic.TradeParams(
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
