//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@solmate/utils/FixedPointMathLib.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/PairGroupLib.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/Perp.sol";
import "./libraries/ScaledAsset.sol";
import "./libraries/SwapLib.sol";
import "./libraries/InterestRateModel.sol";
import "./libraries/logic/AddAssetLogic.sol";
import "./libraries/logic/ApplyInterestLogic.sol";
import "./libraries/logic/LiquidationLogic.sol";
import "./libraries/logic/ReaderLogic.sol";
import "./libraries/logic/SupplyLogic.sol";
import "./libraries/logic/TradePerpLogic.sol";
import "./libraries/logic/IsolatedVaultLogic.sol";
import "./libraries/logic/UpdateMarginLogic.sol";
import "./interfaces/IController.sol";

/**
 * Error Codes
 * C0: invalid asset rist parameters
 * C1: caller must be operator
 * C2: caller must be vault owner
 * C3: token0 or token1 must be registered stable token
 * C4: invalid interest rate model parameters
 * C5: invalid vault creation
 */
contract Controller is Initializable, ReentrancyGuard, IUniswapV3MintCallback, IUniswapV3SwapCallback, IController {
    using PairGroupLib for DataType.PairGroup;
    using ScaledAsset for ScaledAsset.TokenStatus;

    DataType.PairGroup internal pairGroup;

    mapping(uint256 => DataType.PairStatus) internal pairs;

    mapping(uint256 => DataType.RebalanceFeeGrowthCache) internal rebalanceFeeGrowthCache;

    mapping(uint256 => DataType.Vault) internal vaults;

    /// @dev account -> vaultId
    mapping(address => DataType.OwnVaults) internal ownVaultsMap;

    uint256 public vaultCount;

    address public operator;

    address public liquidator;

    mapping(address => bool) public allowedUniswapPools;

    event OperatorUpdated(address operator);
    event LiquidatorUpdated(address liquidator);
    event VaultCreated(uint256 vaultId, address owner, bool isMainVault);

    modifier onlyOperator() {
        require(operator == msg.sender, "C1");
        _;
    }

    constructor() {}

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external override {
        require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, amount1);
        }
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, uint256(amount1Delta));
        }
    }

    function initialize(
        address _stableAssetAddress,
        uint8 _marginRounder,
        DataType.AddAssetParams[] memory _addAssetParams
    ) public initializer {
        vaultCount = 1;

        operator = msg.sender;

        AddAssetLogic.initializeAssetGroup(
            pairGroup, pairs, allowedUniswapPools, _stableAssetAddress, _marginRounder, _addAssetParams
        );
    }

    /**
     * @notice Sets new operator
     * @dev Only operator can call this function.
     * @param _newOperator The address of new operator
     */
    function setOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0));
        operator = _newOperator;

        emit OperatorUpdated(_newOperator);
    }

    /**
     * @notice Sets new liquidator
     * @dev Only operator can call this function.
     * @param _newLiquidator The address of new operator
     */
    function setLiquidator(address _newLiquidator) external onlyOperator {
        require(_newLiquidator != address(0));
        liquidator = _newLiquidator;

        emit LiquidatorUpdated(_newLiquidator);
    }

    /**
     * @notice Adds token pair to the contract
     * @dev Only operator can call this function.
     * @param _addAssetParam parameters to define asset risk and interest rate model
     * @return pairId The id of pair
     */
    function addPair(DataType.AddAssetParams memory _addAssetParam) external onlyOperator returns (uint256) {
        return AddAssetLogic._addPair(pairGroup, pairs, allowedUniswapPools, _addAssetParam);
    }

    /**
     * @notice Updates asset risk parameters.
     * @dev The function can be called by operator.
     * @param _pairId The id of asset to update params.
     * @param _riskParams Asset risk parameters.
     */
    function updateAssetRiskParams(uint256 _pairId, DataType.AssetRiskParams memory _riskParams)
        external
        onlyOperator
    {
        AddAssetLogic.updateAssetRiskParams(pairs[_pairId], _riskParams);
    }

    /**
     * @notice Updates interest rate model parameters.
     * @dev The function can be called by operator.
     * @param _pairId The id of pair to update params.
     * @param _stableIrmParams Asset interest-rate parameters for stable.
     * @param _underlyingIrmParams Asset interest-rate parameters for underlying.
     */
    function updateIRMParams(
        uint256 _pairId,
        InterestRateModel.IRMParams memory _stableIrmParams,
        InterestRateModel.IRMParams memory _underlyingIrmParams
    ) external onlyOperator {
        AddAssetLogic.updateIRMParams(pairs[_pairId], _stableIrmParams, _underlyingIrmParams);
    }

    /**
     * @notice Reallocates range of Uniswap LP position.
     * @param _pairId The id of pair to reallocate.
     */
    function reallocate(uint256 _pairId) external returns (bool, int256) {
        ApplyInterestLogic.applyInterestForToken(pairs, _pairId);

        return ApplyInterestLogic.reallocate(pairs, rebalanceFeeGrowthCache, _pairId);
    }

    /**
     * @notice Supplys token and mints claim token
     * @param _pairId The id of pair being supplied to the pool
     * @param _amount The amount of asset being supplied
     * @param _isStable If true supplys to stable pool, if false supplys to underlying pool
     * @return finalMintAmount The amount of claim token being minted
     */
    function supplyToken(uint256 _pairId, uint256 _amount, bool _isStable)
        external
        nonReentrant
        returns (uint256 finalMintAmount)
    {
        ApplyInterestLogic.applyInterestForToken(pairs, _pairId);

        return SupplyLogic.supply(pairs[_pairId], _amount, _isStable);
    }

    /**
     * @notice Withdraws token and burns claim token
     * @param _pairId The id of pair being withdrawn from the pool
     * @param _amount The amount of asset being withdrawn
     * @param _isStable If true supplys to stable pool, if false supplys to underlying pool
     * @return finalBurnAmount The amount of claim token being burned
     * @return finalWithdrawAmount The amount of token being withdrawn
     */
    function withdrawToken(uint256 _pairId, uint256 _amount, bool _isStable)
        external
        nonReentrant
        returns (uint256 finalBurnAmount, uint256 finalWithdrawAmount)
    {
        ApplyInterestLogic.applyInterestForToken(pairs, _pairId);

        return SupplyLogic.withdraw(pairs[_pairId], _amount, _isStable);
    }

    /**
     * @notice Deposit or withdraw margin
     * @param _marginAmount The amount of margin. Positive means deposit and negative means withdraw.
     * @param _vaultId The id of vault to update margin. If _vaultId is 0, update margin of the main vault.
     * @return vaultId The id of vault created
     */
    function updateMargin(int256 _marginAmount, uint256 _vaultId)
        external
        override(IController)
        nonReentrant
        returns (uint256 vaultId)
    {
        if (_vaultId > 0) {
            // isolated vault
            vaultId = _vaultId;
        } else {
            // main vault
            vaultId = ownVaultsMap[msg.sender].mainVaultId;
        }

        vaultId = createVaultIfNeeded(vaultId, msg.sender, true);

        DataType.Vault storage vault = vaults[vaultId];

        UpdateMarginLogic.updateMargin(pairGroup, pairs, rebalanceFeeGrowthCache, vault, _marginAmount);
    }

    /**
     * @notice Creates new isolated vault and open perp positions.
     * @param _depositAmount The amount of margin to deposit from main vault.
     * @param _pairId The id of asset pair
     * @param _tradeParams The trade parameters
     * @return isolatedVaultId The id of isolated vault
     * @return tradeResult The result of perp trade
     */
    function openIsolatedVault(uint256 _depositAmount, uint64 _pairId, TradePerpLogic.TradeParams memory _tradeParams)
        external
        nonReentrant
        returns (uint256 isolatedVaultId, DataType.TradeResult memory tradeResult)
    {
        uint256 vaultId = ownVaultsMap[msg.sender].mainVaultId;

        DataType.Vault storage vault = vaults[vaultId];

        VaultLib.checkVault(vault, msg.sender);

        applyInterest(vault);

        isolatedVaultId = createVaultIfNeeded(0, msg.sender, false);

        tradeResult = IsolatedVaultLogic.openIsolatedVault(
            pairGroup,
            pairs,
            rebalanceFeeGrowthCache,
            vault,
            vaults[isolatedVaultId],
            _depositAmount,
            _pairId,
            _tradeParams
        );
    }

    /**
     * @notice Close positions in the isolated vault and move margin to main vault.
     * @param _isolatedVaultId The id of isolated vault
     * @param _pairId The id of asset pair
     * @param _closeParams The close parameters
     * @return tradeResult The result of perp trade
     */
    function closeIsolatedVault(
        uint256 _isolatedVaultId,
        uint64 _pairId,
        IsolatedVaultLogic.CloseParams memory _closeParams
    ) external nonReentrant returns (DataType.TradeResult memory tradeResult) {
        uint256 vaultId = ownVaultsMap[msg.sender].mainVaultId;

        DataType.Vault storage vault = vaults[vaultId];
        DataType.Vault storage isolatedVault = vaults[_isolatedVaultId];

        VaultLib.checkVault(vault, msg.sender);

        applyInterest(isolatedVault);

        tradeResult = IsolatedVaultLogic.closeIsolatedVault(
            pairGroup, pairs, rebalanceFeeGrowthCache, vault, isolatedVault, _pairId, _closeParams
        );

        VaultLib.removeIsolatedVaultId(ownVaultsMap[msg.sender], isolatedVault.id);
    }

    /**
     * @notice Trades perps of x and sqrt(x)
     * @param _vaultId The id of vault
     * @param _pairId The id of asset pair
     * @param _tradeParams The trade parameters
     * @return TradeResult The result of perp trade
     */
    function tradePerp(uint256 _vaultId, uint64 _pairId, TradePerpLogic.TradeParams memory _tradeParams)
        external
        override(IController)
        nonReentrant
        returns (DataType.TradeResult memory)
    {
        Perp.UserStatus storage openPosition = VaultLib.getUserStatus(pairGroup, pairs, vaults[_vaultId], _pairId);

        applyInterest(vaults[_vaultId]);

        return TradePerpLogic.execTrade(
            pairGroup, pairs, rebalanceFeeGrowthCache, vaults[_vaultId], _pairId, openPosition, _tradeParams
        );
    }

    /**
     * @notice Executes liquidation call and gets reward.
     * Anyone can call this function.
     * @param _vaultId The id of vault
     * @param _closeRatio If you'll close all position, set 1e18.
     * @param _sqrtSlippageTolerance if caller is liquidator, the caller can set custom slippage tolerance.
     */
    function liquidationCall(uint256 _vaultId, uint256 _closeRatio, uint256 _sqrtSlippageTolerance)
        external
        nonReentrant
    {
        DataType.Vault storage vault = vaults[_vaultId];

        require(vault.owner != address(0));
        require(msg.sender == liquidator || _sqrtSlippageTolerance == 0);

        applyInterest(vault);

        uint256 mainVaultId = ownVaultsMap[vault.owner].mainVaultId;

        (int256 penaltyAmount, bool isClosedAll) = LiquidationLogic.execLiquidationCall(
            pairGroup, pairs, rebalanceFeeGrowthCache, vault, vaults[mainVaultId], _closeRatio, _sqrtSlippageTolerance
        );

        if (isClosedAll) {
            VaultLib.removeIsolatedVaultId(ownVaultsMap[vault.owner], vault.id);
        }

        if (penaltyAmount > 0) {
            TransferHelper.safeTransfer(pairGroup.stableTokenAddress, msg.sender, uint256(penaltyAmount));
        } else if (penaltyAmount < 0) {
            TransferHelper.safeTransferFrom(
                pairGroup.stableTokenAddress, msg.sender, address(this), uint256(-penaltyAmount)
            );
        }
    }

    ///////////////////////
    // Private Functions //
    ///////////////////////

    function applyInterest(DataType.Vault memory _vault) internal {
        ApplyInterestLogic.applyInterestForVault(_vault, pairs);
    }

    function createVaultIfNeeded(uint256 _vaultId, address _caller, bool _isMainVault)
        internal
        returns (uint256 vaultId)
    {
        if (_vaultId == 0) {
            vaultId = vaultCount++;

            require(_caller != address(0), "C5");

            vaults[vaultId].id = vaultId;
            vaults[vaultId].owner = _caller;

            if (_isMainVault) {
                VaultLib.updateMainVaultId(ownVaultsMap[_caller], vaultId);
            } else {
                VaultLib.addIsolatedVaultId(ownVaultsMap[_caller], vaultId);
            }

            emit VaultCreated(vaultId, msg.sender, _isMainVault);

            return vaultId;
        } else {
            return _vaultId;
        }
    }

    // Getter functions

    /**
     * Gets square root of current underlying token price by quote token.
     */
    function getSqrtPrice(uint256 _tokenId) external view override(IController) returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtPrice(pairs[_tokenId].sqrtAssetStatus.uniswapPool), pairs[_tokenId].isMarginZero
        );
    }

    function getSqrtIndexPrice(uint256 _tokenId) external view returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtTWAP(pairs[_tokenId].sqrtAssetStatus.uniswapPool), pairs[_tokenId].isMarginZero
        );
    }

    function getPairGroup() external view override(IController) returns (DataType.PairGroup memory) {
        return pairGroup;
    }

    function getAsset(uint256 _id) external view override(IController) returns (DataType.PairStatus memory) {
        return pairs[_id];
    }

    function getLatestAssetStatus(uint256 _id) external returns (DataType.PairStatus memory) {
        ApplyInterestLogic.applyInterestForToken(pairs, _id);

        return pairs[_id];
    }

    function getVault(uint256 _id) external view override(IController) returns (DataType.Vault memory) {
        return vaults[_id];
    }

    /**
     * @notice Gets latest vault status.
     * @dev This function should not be called on chain.
     * @param _vaultId The id of the vault
     */
    function getVaultStatus(uint256 _vaultId) public returns (DataType.VaultStatusResult memory) {
        DataType.Vault storage vault = vaults[_vaultId];

        applyInterest(vault);

        return ReaderLogic.getVaultStatus(pairs, rebalanceFeeGrowthCache, vault);
    }

    /**
     * @notice Gets latest main vault status that the caller has.
     * @dev This function should not be called on chain.
     */
    function getVaultStatusWithAddress()
        external
        returns (DataType.VaultStatusResult memory, DataType.VaultStatusResult[] memory)
    {
        DataType.OwnVaults memory ownVaults = ownVaultsMap[msg.sender];

        DataType.VaultStatusResult[] memory vaultStatusResults =
            new DataType.VaultStatusResult[](ownVaults.isolatedVaultIds.length);

        for (uint256 i; i < ownVaults.isolatedVaultIds.length; i++) {
            vaultStatusResults[i] = getVaultStatus(ownVaults.isolatedVaultIds[i]);
        }

        return (getVaultStatus(ownVaults.mainVaultId), vaultStatusResults);
    }
}
