// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../interfaces/ISupplyToken.sol";
import "../DataType.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";
import "../VaultLib.sol";
import "../../tokenization/SupplyToken.sol";

library SupplyLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event TokenSupplied(address account, uint256 pairId, uint256 suppliedAmount);
    event TokenWithdrawn(address account, uint256 pairId, uint256 finalWithdrawnAmount);

    function deploySupplyToken(address _tokenAddress) external returns (address) {
        IERC20Metadata erc20 = IERC20Metadata(_tokenAddress);

        return address(
            new SupplyToken(
            address(this),
            string.concat("Predy-Supply-", erc20.name()),
            string.concat("p", erc20.symbol()),
            erc20.decimals()
            )
        );
    }

    function supply(DataType.PairStatus storage _asset, uint256 _amount, bool _isStable)
        external
        returns (uint256 mintAmount)
    {
        if (_isStable) {
            mintAmount = _supply(_asset.stablePool, _amount);
        } else {
            mintAmount = _supply(_asset.underlyingPool, _amount);
        }

        emit TokenSupplied(msg.sender, _asset.id, _amount);
    }

    function _supply(DataType.AssetPoolStatus storage _pool, uint256 _amount) internal returns (uint256 mintAmount) {
        mintAmount = _pool.tokenStatus.addAsset(_amount);

        TransferHelper.safeTransferFrom(_pool.token, msg.sender, address(this), _amount);

        ISupplyToken(_pool.supplyTokenAddress).mint(msg.sender, mintAmount);
    }

    function withdraw(DataType.PairStatus storage _asset, uint256 _amount, bool _isStable)
        external
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        if (_isStable) {
            (finalburntAmount, finalWithdrawalAmount) = _withdraw(_asset.stablePool, _amount);
        } else {
            (finalburntAmount, finalWithdrawalAmount) = _withdraw(_asset.underlyingPool, _amount);
        }

        emit TokenWithdrawn(msg.sender, _asset.id, finalWithdrawalAmount);
    }

    function _withdraw(DataType.AssetPoolStatus storage _pool, uint256 _amount)
        internal
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        address supplyTokenAddress = _pool.supplyTokenAddress;

        (finalburntAmount, finalWithdrawalAmount) =
            _pool.tokenStatus.removeAsset(IERC20(supplyTokenAddress).balanceOf(msg.sender), _amount);

        ISupplyToken(supplyTokenAddress).burn(msg.sender, finalburntAmount);

        TransferHelper.safeTransfer(_pool.token, msg.sender, finalWithdrawalAmount);
    }
}
