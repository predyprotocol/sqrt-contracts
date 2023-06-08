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
import "./libraries/logic/ApplyInterestLogic.sol";
import "./libraries/logic/LiquidationLogic.sol";
import "./libraries/logic/ReaderLogic.sol";
import "./libraries/logic/SettleUserFeeLogic.sol";
import "./libraries/logic/SupplyLogic.sol";
import "./libraries/logic/TradeLogic.sol";
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

    mapping(address => bool) public allowedUniswapPools;

    event OperatorUpdated(address operator);
    event PairAdded(uint256 pairId, address _uniswapPool);
    event AssetGroupInitialized(address stableAsset, uint256[] assetIds);
    event VaultCreated(uint256 vaultId, address owner, bool isMainVault);
    event ProtocolRevenueWithdrawn(uint256 pairId, uint256 withdrawnProtocolFee);
    event AssetRiskParamsUpdated(uint256 pairId, DataType.AssetRiskParams riskParams);
    event IRMParamsUpdated(
        uint256 pairId, InterestRateModel.IRMParams stableIrmParams, InterestRateModel.IRMParams underlyingIrmParams
    );

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

    function initialize(address _stableAssetAddress, DataType.AddAssetParams[] memory _addAssetParams)
        public
        initializer
    {
        vaultCount = 1;

        operator = msg.sender;

        initializeAssetGroup(_stableAssetAddress, _addAssetParams);
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
     * @notice Adds token pair to the contract
     * @dev Only operator can call this function.
     * @param _addAssetParam parameters to define asset risk and interest rate model
     * @return pairId The id of pair
     */
    function addPair(DataType.AddAssetParams memory _addAssetParam) external onlyOperator returns (uint256) {
        return _addPair(_addAssetParam);
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
        validateRiskParams(_riskParams);

        DataType.PairStatus storage asset = pairs[_pairId];

        asset.riskParams.riskRatio = _riskParams.riskRatio;
        asset.riskParams.rangeSize = _riskParams.rangeSize;
        asset.riskParams.rebalanceThreshold = _riskParams.rebalanceThreshold;

        emit AssetRiskParamsUpdated(_pairId, _riskParams);
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
        validateIRMParams(_stableIrmParams);
        validateIRMParams(_underlyingIrmParams);

        DataType.PairStatus storage asset = pairs[_pairId];

        asset.stablePool.irmParams = _stableIrmParams;
        asset.underlyingPool.irmParams = _underlyingIrmParams;

        emit IRMParamsUpdated(_pairId, _stableIrmParams, _underlyingIrmParams);
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
     * @return vaultId The id of vault created
     */
    function updateMargin(int256 _marginAmount) external override(IController) nonReentrant returns (uint256 vaultId) {
        vaultId = ownVaultsMap[msg.sender].mainVaultId;

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
    function openIsolatedVault(uint256 _depositAmount, uint64 _pairId, TradeLogic.TradeParams memory _tradeParams)
        external
        nonReentrant
        returns (uint256 isolatedVaultId, DataType.TradeResult memory tradeResult)
    {
        uint256 vaultId = ownVaultsMap[msg.sender].mainVaultId;

        DataType.Vault storage vault = vaults[vaultId];

        VaultLib.checkVault(vault, msg.sender);

        applyInterest(vault);
        settleUserFee(vault);

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
    function tradePerp(uint256 _vaultId, uint64 _pairId, TradeLogic.TradeParams memory _tradeParams)
        external
        override(IController)
        nonReentrant
        returns (DataType.TradeResult memory)
    {
        Perp.UserStatus storage perpUserStatus = VaultLib.getUserStatus(pairGroup, pairs, vaults[_vaultId], _pairId);

        applyInterest(vaults[_vaultId]);
        settleUserFee(vaults[_vaultId], _pairId);

        return TradeLogic.execTrade(
            pairs, rebalanceFeeGrowthCache, vaults[_vaultId], _pairId, perpUserStatus, _tradeParams
        );
    }

    /**
     * @notice Executes liquidation call and gets reward.
     * Anyone can call this function.
     * @param _vaultId The id of vault
     * @param _closeRatio If you'll close all position, set 1e18.
     */
    function liquidationCall(uint256 _vaultId, uint256 _closeRatio) external nonReentrant {
        DataType.Vault storage vault = vaults[_vaultId];

        require(vault.owner != address(0));

        applyInterest(vault);

        uint256 mainVaultId = ownVaultsMap[vault.owner].mainVaultId;

        (int256 penaltyAmount, bool isClosedAll) = LiquidationLogic.execLiquidationCall(
            pairs, rebalanceFeeGrowthCache, vault, vaults[mainVaultId], _closeRatio
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

    /**
     * @notice Sets an asset group
     * @param _stableAssetAddress The address of stable asset
     * @param _addAssetParams The list of asset parameters
     * @return assetIds underlying asset ids
     */
    function initializeAssetGroup(address _stableAssetAddress, DataType.AddAssetParams[] memory _addAssetParams)
        internal
        returns (uint256[] memory assetIds)
    {
        pairGroup.stableTokenAddress = _stableAssetAddress;
        pairGroup.assetsCount = 1;

        assetIds = new uint256[](_addAssetParams.length);

        for (uint256 i; i < _addAssetParams.length; i++) {
            assetIds[i] = _addPair(_addAssetParams[i]);
        }

        emit AssetGroupInitialized(_stableAssetAddress, assetIds);
    }

    /**
     * @notice add token pair
     */
    function _addPair(DataType.AddAssetParams memory _addAssetParam) internal returns (uint256 pairId) {
        pairId = pairGroup.assetsCount;

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(_addAssetParam.uniswapPool);

        address stableTokenAddress = pairGroup.stableTokenAddress;

        require(uniswapPool.token0() == stableTokenAddress || uniswapPool.token1() == stableTokenAddress, "C3");

        bool isMarginZero = uniswapPool.token0() == stableTokenAddress;

        _storePairStatus(
            pairId,
            isMarginZero ? uniswapPool.token1() : uniswapPool.token0(),
            isMarginZero,
            _addAssetParam.isIsolatedMode,
            _addAssetParam.uniswapPool,
            _addAssetParam.assetRiskParams,
            _addAssetParam.stableIrmParams,
            _addAssetParam.underlyingIrmParams
        );

        pairGroup.assetsCount++;

        emit PairAdded(pairId, _addAssetParam.uniswapPool);
    }

    function _storePairStatus(
        uint256 _pairId,
        address _tokenAddress,
        bool _isMarginZero,
        bool _isolatedMode,
        address _uniswapPool,
        DataType.AssetRiskParams memory _assetRiskParams,
        InterestRateModel.IRMParams memory _stableIrmParams,
        InterestRateModel.IRMParams memory _underlyingIrmParams
    ) internal {
        validateRiskParams(_assetRiskParams);

        require(pairs[_pairId].id == 0);

        pairs[_pairId] = DataType.PairStatus(
            _pairId,
            DataType.AssetPoolStatus(
                pairGroup.stableTokenAddress,
                SupplyLogic.deploySupplyToken(pairGroup.stableTokenAddress),
                ScaledAsset.createTokenStatus(),
                _stableIrmParams
            ),
            DataType.AssetPoolStatus(
                _tokenAddress,
                SupplyLogic.deploySupplyToken(_tokenAddress),
                ScaledAsset.createTokenStatus(),
                _underlyingIrmParams
            ),
            _assetRiskParams,
            Perp.createAssetStatus(_uniswapPool, -_assetRiskParams.rangeSize, _assetRiskParams.rangeSize),
            _isMarginZero,
            _isolatedMode,
            block.timestamp
        );

        if (_uniswapPool != address(0)) {
            allowedUniswapPools[_uniswapPool] = true;
        }
    }

    function applyInterest(DataType.Vault memory _vault) internal {
        ApplyInterestLogic.applyInterestForVault(_vault, pairs);
    }

    function settleUserFee(DataType.Vault storage _vault) internal returns (int256[] memory latestFees) {
        return settleUserFee(_vault, 0);
    }

    function settleUserFee(DataType.Vault storage _vault, uint256 _excludeAssetId)
        internal
        returns (int256[] memory latestFees)
    {
        return SettleUserFeeLogic.settleUserFee(pairs, rebalanceFeeGrowthCache, _vault, _excludeAssetId);
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

    function getLatestAssetStatus(uint256 _id) external returns (DataType.AssetStatus memory) {
        ApplyInterestLogic.applyInterestForToken(assets, _id);

        return assets[_id];
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

    function validateRiskParams(DataType.AssetRiskParams memory _assetRiskParams) internal pure {
        require(1e8 < _assetRiskParams.riskRatio && _assetRiskParams.riskRatio <= 10 * 1e8, "C0");

        require(_assetRiskParams.rangeSize > 0 && _assetRiskParams.rebalanceThreshold > 0, "C0");
    }

    function validateIRMParams(InterestRateModel.IRMParams memory _irmParams) internal pure {
        require(
            _irmParams.baseRate <= 1e18 && _irmParams.kinkRate <= 1e18 && _irmParams.slope1 <= 1e18
                && _irmParams.slope2 <= 10 * 1e18,
            "C4"
        );
    }
}
