// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.13;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../DataType.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";
import "../VaultLib.sol";
import "./SettleUserFeeLogic.sol";

library UpdateMarginLogic {
    event MarginUpdated(uint256 vaultId, int256 marginAmount);

    function updateMargin(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        int256 _marginAmount
    ) external {
        VaultLib.checkVault(_vault, msg.sender);
        // settle user fee and balance
        if (_marginAmount < 0) {
            SettleUserFeeLogic.settleUserFee(_assets, _vault);
        }

        _vault.margin += _marginAmount;

        // if debt is 0 we should check margin is greater than 0 directly
        require(_vault.margin >= 0, "M1");
        PositionCalculator.isSafe(_assets, _vault);

        proceedMarginUpdate(_vault, getStableToken(_assets), _marginAmount);
    }

    function proceedMarginUpdate(DataType.Vault memory _vault, address _stable, int256 _marginAmount) internal {
        if (_marginAmount > 0) {
            TransferHelper.safeTransferFrom(_stable, msg.sender, address(this), uint256(_marginAmount));
        } else if (_marginAmount < 0) {
            TransferHelper.safeTransfer(_stable, _vault.owner, uint256(-_marginAmount));
        }

        emit MarginUpdated(_vault.id, _marginAmount);
    }

    function getStableToken(mapping(uint256 => DataType.AssetStatus) storage _assets) internal view returns (address) {
        return _assets[Constants.STABLE_ASSET_ID].token;
    }
}
