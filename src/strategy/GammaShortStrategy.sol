// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@solmate/utils/FixedPointMathLib.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/IStrategyVault.sol";
import "../interfaces/IPredyTradeCallback.sol";
import "./base/BaseStrategy.sol";
import "../libraries/Constants.sol";
import "../Reader.sol";

/**
 * Error Codes
 * GSS0: already initialized
 * GSS1: not initialized
 * GSS2: required margin amount must be less than maximum
 * GSS3: withdrawn margin amount must be greater than minimum
 * GSS4: invalid leverage
 * GSS5: caller must be Controller
 */
contract GammaShortStrategy is BaseStrategy, IStrategyVault, IPredyTradeCallback {
    Reader immutable reader;

    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    uint256 finalDepositAmountCached;

    uint256 strategyRevenue;

    event DepositedToStrategy(address indexed account, uint256 strategyTokenAmount, uint256 depositedAmount);
    event WithdrawnFromStrategy(address indexed account, uint256 strategyTokenAmount, uint256 withdrawnAmount);

    constructor(
        address _controller,
        address _reader,
        uint256 _assetId,
        MinPerValueLimit memory _minPerValueLimit,
        string memory _name,
        string memory _symbol
    ) BaseStrategy(_controller, _assetId, _minPerValueLimit, _name, _symbol) {
        reader = Reader(_reader);
    }

    /**
     * @dev Callback for Predy Controller
     */
    function predyTradeCallback(DataType.TradeResult memory _tradeResult, bytes calldata _data)
        external
        override(IPredyTradeCallback)
    {
        require(msg.sender == address(controller), "GSS5");

        (uint256 share, address caller, bool isQuoteMode) = abi.decode(_data, (uint256, address, bool));

        (int256 entryUpdate, int256 entryValue, uint256 totalMargin) = calEntryValue(_tradeResult.payoff);

        uint256 finalDepositMargin = calShareToMargin(entryUpdate, entryValue, share, totalMargin);

        uint256 finalDepositMarginRoundUp = roundUpMarginAndAddStrategyRevenue(finalDepositMargin);

        finalDepositAmountCached = finalDepositMarginRoundUp;

        if (isQuoteMode) {
            revertMarginAmount(finalDepositMarginRoundUp);
        }

        TransferHelper.safeTransferFrom(usdc, caller, address(this), finalDepositMarginRoundUp);

        controller.updateMargin(vaultId, int256(finalDepositMargin));
    }

    /**
     * Initializes strategy
     * @param _initialMarginAmount initial margin amount
     * @param _initialPerpAmount initial perp amount
     * @param _initialSquartAmount initial squart amount
     * @param _tradeParams trade parameters
     */
    function initialize(
        uint256 _initialMarginAmount,
        int256 _initialPerpAmount,
        int256 _initialSquartAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external onlyOwner {
        require(totalSupply() == 0, "GSS0");

        TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _initialMarginAmount);

        vaultId = controller.updateMargin(vaultId, int256(_initialMarginAmount));

        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                _initialPerpAmount,
                _initialSquartAmount,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        _mint(msg.sender, _initialMarginAmount);

        emit DepositedToStrategy(msg.sender, _initialMarginAmount, _initialMarginAmount);
    }

    function deposit(
        uint256 _strategyTokenAmount,
        address _recepient,
        uint256 _maxMarginAmount,
        bool isQuoteMode,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external override returns (uint256 finalDepositMargin) {
        require(totalSupply() > 0, "GSS1");

        uint256 share = calMintToShare(_strategyTokenAmount, totalSupply());

        DataType.Vault memory vault = controller.getVault(vaultId);

        int256 tradePerp = calShareToMint(share, vault.openPositions[0].perpTrade.perp.amount);
        int256 tradeSqrt = calShareToMint(share, vault.openPositions[0].perpTrade.sqrtPerp.amount);

        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                tradePerp,
                tradeSqrt,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                true,
                abi.encode(share, msg.sender, isQuoteMode)
            )
        );

        finalDepositMargin = finalDepositAmountCached;

        finalDepositAmountCached = DEFAULT_AMOUNT_IN_CACHED;

        require(finalDepositMargin <= _maxMarginAmount, "GSS2");

        _mint(_recepient, _strategyTokenAmount);

        emit DepositedToStrategy(_recepient, _strategyTokenAmount, finalDepositMargin);
    }

    function withdraw(
        uint256 _withdrawStrategyAmount,
        address _recepient,
        int256 _minWithdrawAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external returns (uint256 finalWithdrawAmount) {
        uint256 strategyShare = _withdrawStrategyAmount * 1e18 / totalSupply();

        DataType.Vault memory vault = controller.getVault(vaultId);

        DataType.TradeResult memory tradeResult = controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                -int256(strategyShare) * vault.openPositions[0].perpTrade.perp.amount / int256(1e18),
                -int256(strategyShare) * vault.openPositions[0].perpTrade.sqrtPerp.amount / int256(1e18),
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        // Calculates realized and unrealized PnL.
        int256 withdrawMarginAmount = (vault.margin + tradeResult.fee) * int256(strategyShare) / int256(1e18)
            + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        require(withdrawMarginAmount >= _minWithdrawAmount && _minWithdrawAmount >= 0, "GSS3");

        _burn(msg.sender, _withdrawStrategyAmount);

        finalWithdrawAmount = roundDownMarginAndAddStrategyRevenue(uint256(withdrawMarginAmount));

        controller.updateMargin(vaultId, -withdrawMarginAmount);

        TransferHelper.safeTransfer(usdc, _recepient, finalWithdrawAmount);

        emit WithdrawnFromStrategy(_recepient, _withdrawStrategyAmount, finalWithdrawAmount);
    }

    function withdrawStrategyRevenue(address _recepient) external onlyOwner returns (uint256 withdrawAmount) {
        withdrawAmount = strategyRevenue;

        strategyRevenue = 0;

        if (withdrawAmount > 0) {
            TransferHelper.safeTransfer(usdc, _recepient, withdrawAmount);
        }
    }

    function execDeltaHedge(IStrategyVault.StrategyTradeParams memory _tradeParams) external onlyOwner {
        int256 delta = reader.getDelta(assetId, vaultId);

        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                -delta, 0, _tradeParams.lowerSqrtPrice, _tradeParams.upperSqrtPrice, _tradeParams.deadline, false, ""
            )
        );
    }

    /**
     * Changes gamma size per share.
     * @param _squartAmount squart amount
     * @param _tradeParams trade parameters
     */
    function updateGamma(int256 _squartAmount, IStrategyVault.StrategyTradeParams memory _tradeParams)
        external
        onlyOwner
    {
        controller.tradePerp(
            vaultId,
            assetId,
            TradeLogic.TradeParams(
                0,
                _squartAmount,
                _tradeParams.lowerSqrtPrice,
                _tradeParams.upperSqrtPrice,
                _tradeParams.deadline,
                false,
                ""
            )
        );

        uint256 minPerVaultValue = getMinPerVaultValue();

        require(minPerValueLimit.lower <= minPerVaultValue && minPerVaultValue <= minPerValueLimit.upper, "GSS4");
    }

    /**
     * @dev The function should not be called on chain.
     */
    function getPrice() external returns (uint256) {
        DataType.VaultStatusResult memory vaultStatusResult = controller.getVaultStatus(vaultId);

        if (vaultStatusResult.vaultValue <= 0) {
            return 0;
        }

        return uint256(vaultStatusResult.vaultValue) * 1e18 / totalSupply();
    }

    function getMinPerVaultValue() internal returns (uint256) {
        DataType.VaultStatusResult memory vaultStatusResult = controller.getVaultStatus(vaultId);

        return SafeCast.toUint256(vaultStatusResult.minDeposit * 1e18 / vaultStatusResult.vaultValue);
    }

    // private functions

    function calEntryValue(Perp.Payoff memory payoff)
        internal
        view
        returns (int256 entryUpdate, int256 entryValue, uint256 totalMargin)
    {
        DataType.Vault memory vault = controller.getVault(vaultId);

        DataType.UserStatus memory userStatus = vault.openPositions[0];

        entryUpdate = payoff.perpEntryUpdate + payoff.sqrtEntryUpdate + payoff.sqrtRebalanceEntryUpdateStable;

        entryValue = userStatus.perpTrade.perp.entryValue + userStatus.perpTrade.sqrtPerp.entryValue
            + userStatus.perpTrade.sqrtPerp.stableRebalanceEntryValue;

        totalMargin = uint256(vault.margin);
    }

    function calMintToShare(uint256 _mint, uint256 _total) internal pure returns (uint256) {
        return _mint * 1e18 / (_total + _mint);
    }

    function calShareToMint(uint256 _share, int256 _total) internal pure returns (int256) {
        return _total * int256(_share) / int256(1e18 - _share);
    }

    function calShareToMargin(int256 _entryUpdate, int256 _entryValue, uint256 _share, uint256 _totalMarginBefore)
        internal
        pure
        returns (uint256)
    {
        uint256 t =
            SafeCast.toUint256(int256(_share) * (int256(_totalMarginBefore) + _entryValue) / 1e18 - _entryUpdate);

        return t * 1e18 / (1e18 - _share);
    }

    function roundUpMarginAndAddStrategyRevenue(uint256 _amount) internal returns (uint256 rounded) {
        rounded = roundUpMargin(_amount, Constants.MARGIN_ROUNDED_DECIMALS);

        strategyRevenue += rounded - _amount;
    }

    function roundDownMarginAndAddStrategyRevenue(uint256 _amount) internal returns (uint256 rounded) {
        rounded = roundDownMargin(_amount, Constants.MARGIN_ROUNDED_DECIMALS);

        strategyRevenue += _amount - rounded;
    }

    function roundUpMargin(uint256 _amount, uint256 _roundedDecimals) internal pure returns (uint256) {
        return FixedPointMathLib.mulDivUp(_amount, 1, _roundedDecimals) * _roundedDecimals;
    }

    function roundDownMargin(uint256 _amount, uint256 _roundedDecimals) internal pure returns (uint256) {
        return FixedPointMathLib.mulDivDown(_amount, 1, _roundedDecimals) * _roundedDecimals;
    }

    function revertMarginAmount(uint256 _marginAmount) internal pure {
        assembly {
            let ptr := mload(0x20)
            mstore(ptr, _marginAmount)
            mstore(add(ptr, 0x20), 0)
            mstore(add(ptr, 0x40), 0)
            revert(ptr, 96)
        }
    }
}
