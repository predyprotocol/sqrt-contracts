// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../DataType.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";
import "../VaultLib.sol";

library UpdateMarginLogic {
    event MarginUpdated(uint256 vaultId, int256 marginAmount);

    function updateMargin(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        int256 _marginAmount
    ) external {
        VaultLib.checkVault(_vault, msg.sender);
        // settle user fee and balance

        _vault.margin += _marginAmount;

        PositionCalculator.checkSafe(_pairs, _rebalanceFeeGrowthCache, _vault);

        execMarginTransfer(_vault, _pairGroup.stableTokenAddress, _marginAmount);

        emitEvent(_vault, _marginAmount);
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
