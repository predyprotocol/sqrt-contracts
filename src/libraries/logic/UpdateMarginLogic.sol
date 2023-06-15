// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../DataType.sol";
import "../PairGroupLib.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";
import "../VaultLib.sol";

library UpdateMarginLogic {
    event MarginUpdated(uint256 vaultId, int256 marginAmount);

    function updateMargin(DataType.GlobalData storage _globalData, uint64 _pairGroupId, int256 _marginAmount)
        external
        returns (uint256 vaultId)
    {
        // Checks margin is not 0
        require(_marginAmount != 0, "AZ");

        // Checks pairGroupId exists
        PairGroupLib.validatePairGroupId(_globalData, _pairGroupId);

        vaultId = _globalData.ownVaultsMap[msg.sender][_pairGroupId].mainVaultId;

        // Checks main vault belongs to pairGroup, or main vault does not exist
        vaultId = VaultLib.createVaultIfNeeded(_globalData, vaultId, msg.sender, _pairGroupId, true);

        DataType.Vault storage vault = _globalData.vaults[vaultId];

        vault.margin += _marginAmount;

        PositionCalculator.checkSafe(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, vault);

        execMarginTransfer(vault, _globalData.pairGroups[_pairGroupId].stableTokenAddress, _marginAmount);

        emitEvent(vault, _marginAmount);
    }

    function execMarginTransfer(DataType.Vault memory _vault, address _stable, int256 _marginAmount) public {
        if (_marginAmount > 0) {
            TransferHelper.safeTransferFrom(_stable, msg.sender, address(this), uint256(_marginAmount));
        } else if (_marginAmount < 0) {
            TransferHelper.safeTransfer(_stable, _vault.owner, uint256(-_marginAmount));
        }
    }

    function emitEvent(DataType.Vault memory _vault, int256 _marginAmount) internal {
        emit MarginUpdated(_vault.id, _marginAmount);
    }
}
