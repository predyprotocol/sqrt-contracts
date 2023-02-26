// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../interfaces/IPredyTradeCallback.sol";
import "../DataType.sol";
import "../Perp.sol";
import "../PositionCalculator.sol";
import "../Trade.sol";
import "../VaultLib.sol";
import "./UpdateMarginLogic.sol";

/*
 * Error Codes
 * T1: tx too old
 * T2: too much slippage
 */
library TradeLogic {
    struct TradeParams {
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
        bool enableCallback;
        bytes data;
    }

    event PositionUpdated(
        uint256 vaultId, uint256 assetId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );

    function execTrade(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        DataType.AssetStatus storage _underlyingAssetStatus,
        DataType.AssetStatus storage _stableAssetStatus,
        DataType.UserStatus storage _userStatus,
        TradeParams memory _tradeParams
    ) public returns (DataType.TradeResult memory tradeResult) {
        checkDeadline(_tradeParams.deadline);

        tradeResult = Trade.trade(
            _underlyingAssetStatus,
            _stableAssetStatus,
            _userStatus.perpTrade,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt
        );

        _vault.margin += tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        checkPrice(
            _underlyingAssetStatus.sqrtAssetStatus.uniswapPool, _tradeParams.lowerSqrtPrice, _tradeParams.upperSqrtPrice
        );

        if (_tradeParams.enableCallback) {
            // Calls callback function
            IPredyTradeCallback(msg.sender).predyTradeCallback(tradeResult, _tradeParams.data);
        }

        tradeResult.minDeposit = PositionCalculator.isSafe(_assets, _vault);

        emit PositionUpdated(
            _vault.id,
            _underlyingAssetStatus.id,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt,
            tradeResult.payoff,
            tradeResult.fee
            );
    }

    function checkDeadline(uint256 _deadline) internal view {
        require(block.timestamp <= _deadline, "T1");
    }

    function checkPrice(address _uniswapPool, uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice) internal view {
        uint256 sqrtPrice = UniHelper.getSqrtPrice(_uniswapPool);

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "T2");
    }
}
