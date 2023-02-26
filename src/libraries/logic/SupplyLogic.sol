// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../interfaces/ISupplyToken.sol";
import "../AssetGroupLib.sol";
import "../DataType.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";
import "../VaultLib.sol";
import "../../tokenization/SupplyToken.sol";

library SupplyLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event TokenSupplied(address account, uint256 assetId, uint256 suppliedAmount);
    event TokenWithdrawn(address account, uint256 assetId, uint256 finalWithdrawnAmount);

    function deploySupplyToken(address _tokenAddress) external returns (address) {
        IERC20Metadata erc20 = IERC20Metadata(_tokenAddress);

        return address(
            new SupplyToken(
            address(this),
            string.concat("Predy-Supply-", erc20.name()),
            string.concat("p", erc20.symbol())
            )
        );
    }

    function supply(DataType.AssetStatus storage _asset, uint256 _amount) external returns (uint256 mintAmount) {
        mintAmount = _asset.tokenStatus.addAsset(_amount);

        TransferHelper.safeTransferFrom(_asset.token, msg.sender, address(this), _amount);

        ISupplyToken(_asset.supplyTokenAddress).mint(msg.sender, mintAmount);

        emit TokenSupplied(msg.sender, _asset.id, _amount);
    }

    function withdraw(DataType.AssetStatus storage _asset, uint256 _amount)
        external
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        address supplyTokenAddress = _asset.supplyTokenAddress;

        (finalburntAmount, finalWithdrawalAmount) =
            _asset.tokenStatus.removeAsset(IERC20(supplyTokenAddress).balanceOf(msg.sender), _amount);

        ISupplyToken(supplyTokenAddress).burn(msg.sender, finalburntAmount);

        TransferHelper.safeTransfer(_asset.token, msg.sender, finalWithdrawalAmount);

        emit TokenWithdrawn(msg.sender, _asset.id, finalWithdrawalAmount);
    }
}
