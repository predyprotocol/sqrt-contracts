// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@solmate/utils/FixedPointMathLib.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./base/Multicall.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/AssetGroupLib.sol";
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
contract Controller is
    Multicall,
    Initializable,
    ReentrancyGuard,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    IController
{
    using AssetGroupLib for DataType.AssetGroup;
    using ScaledAsset for ScaledAsset.TokenStatus;

    DataType.AssetGroup internal assetGroup;

    mapping(uint256 => DataType.AssetStatus) internal assets;

    mapping(uint256 => DataType.Vault) internal vaults;

    /// @dev account -> vaultId
    mapping(address => uint256) internal mainVaults;

    uint256 reserve;

    uint256 public vaultCount;

    address public operator;

    mapping(address => bool) public allowedUniswapPools;

    event OperatorUpdated(address operator);
    event PairAdded(uint256 assetId, address _uniswapPool);
    event AssetGroupInitialized(uint256 stableAssetId, uint256[] assetIds);
    event VaultCreated(uint256 vaultId, address owner, bool isMainVault);
    event ProtocolRevenueWithdrawn(uint256 assetId, uint256 withdrawnProtocolFee);
    event AssetRiskParamsUpdated(uint256 assetId, DataType.AssetRiskParams riskParams);
    event IRMParamsUpdated(
        uint256 assetId, InterestRateModel.IRMParams irmParams, InterestRateModel.IRMParams squartIRMParams
    );

    modifier onlyOperator() {
        require(operator == msg.sender, "C1");
        _;
    }

    constructor() {}

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
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
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
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
        InterestRateModel.IRMParams memory _irmParams,
        DataType.AddAssetParams[] memory _addAssetParams
    ) public initializer {
        vaultCount = 1;

        operator = msg.sender;

        initializeAssetGroup(_stableAssetAddress, _irmParams, _addAssetParams);
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
     * @notice Withdraws accumulated protocol revenue.
     * @dev Only operator can call this function.
     * @param _amount amount of stable token to withdraw
     */
    function withdrawProtocolRevenue(uint256 _assetId, uint256 _amount) external onlyOperator {
        require(_amount > 0 && assets[_assetId].accumulatedProtocolRevenue >= _amount, "C8");

        assets[_assetId].accumulatedProtocolRevenue -= _amount;

        if (_amount > 0) {
            TransferHelper.safeTransfer(assets[_assetId].token, msg.sender, _amount);
        }

        emit ProtocolRevenueWithdrawn(_assetId, _amount);
    }

    /**
     * @notice Updates asset risk parameters.
     * @dev The function can be called by operator.
     * @param _assetId The id of asset to update params.
     * @param _riskParams Asset risk parameters.
     */
    function updateAssetRiskParams(uint256 _assetId, DataType.AssetRiskParams memory _riskParams)
        external
        onlyOperator
    {
        validateIRMParams(_riskParams);

        DataType.AssetStatus storage asset = assets[_assetId];

        asset.riskParams.riskRatio = _riskParams.riskRatio;
        asset.riskParams.rangeSize = _riskParams.rangeSize;
        asset.riskParams.rebalanceThreshold = _riskParams.rebalanceThreshold;

        emit AssetRiskParamsUpdated(_assetId, _riskParams);
    }

    /**
     * @notice Updates interest rate model parameters.
     * @dev The function can be called by operator.
     * @param _assetId The id of asset to update params.
     * @param _irmParams Asset interest-rate parameters.
     * @param _squartIRMParams Squart interest-rate parameters.
     */
    function updateIRMParams(
        uint256 _assetId,
        InterestRateModel.IRMParams memory _irmParams,
        InterestRateModel.IRMParams memory _squartIRMParams
    ) external onlyOperator {
        validateIRMParams(_irmParams);
        validateIRMParams(_squartIRMParams);

        DataType.AssetStatus storage asset = assets[_assetId];

        asset.irmParams = _irmParams;
        asset.squartIRMParams = _squartIRMParams;

        emit IRMParamsUpdated(_assetId, _irmParams, _squartIRMParams);
    }

    /**
     * @notice Reallocates range of Uniswap LP position.
     * @param _assetId The id of asset to reallocate.
     */
    function reallocate(uint256 _assetId) external returns (bool, int256) {
        applyInterest();

        return ApplyInterestLogic.reallocate(assetGroup, assets, _assetId);
    }

    /**
     * @notice Supplys token and mints claim token
     * @param _assetId Asset id of the asset being supplied to the pool
     * @param _amount The amount of asset being supplied
     * @return finalMintAmount The amount of claim token being minted
     */
    function supplyToken(uint256 _assetId, uint256 _amount) external nonReentrant returns (uint256 finalMintAmount) {
        ApplyInterestLogic.applyInterestForToken(assets, _assetId);

        return SupplyLogic.supply(assets[_assetId], _amount);
    }

    /**
     * @notice Withdraws token and burns claim token
     * @param _assetId Asset id of the asset being withdrawn from the pool
     * @param _amount The amount of asset being withdrawn
     * @return finalBurnAmount The amount of claim token being burned
     * @return finalWithdrawAmount The amount of token being withdrawn
     */
    function withdrawToken(uint256 _assetId, uint256 _amount)
        external
        nonReentrant
        returns (uint256 finalBurnAmount, uint256 finalWithdrawAmount)
    {
        ApplyInterestLogic.applyInterestForToken(assets, _assetId);

        return SupplyLogic.withdraw(assets[_assetId], _amount);
    }

    /**
     * @notice Deposit or withdraw margin
     * @param _vaultId The id of vault. If 0 then the contract create new one.
     * @param _marginAmount The amount of margin. Positive means deposit and negative means withdraw.
     * @return vaultId The id of vault created
     */
    function updateMargin(uint256 _vaultId, int256 _marginAmount)
        external
        override(IController)
        nonReentrant
        returns (uint256 vaultId)
    {
        vaultId = createVaultIfNeeded(_vaultId, msg.sender, true);

        DataType.Vault storage vault = vaults[vaultId];

        UpdateMarginLogic.updateMargin(assetGroup, assets, vault, _marginAmount);
    }

    /**
     * @notice Creates new isolated vault and open perp positions.
     * @param _depositAmount The amount of margin to deposit from main vault.
     * @param _assetId Asset id of the asset
     * @param _tradeParams The trade parameters
     * @return isolatedVaultId The id of isolated vault
     * @return tradeResult The result of perp trade
     */
    function openIsolatedVault(
        uint256 _vaultId,
        uint256 _depositAmount,
        uint256 _assetId,
        TradeLogic.TradeParams memory _tradeParams
    ) external nonReentrant returns (uint256 isolatedVaultId, DataType.TradeResult memory tradeResult) {
        DataType.Vault storage vault = vaults[_vaultId];

        require(vault.owner == msg.sender, "C2");

        applyInterest();
        settleUserFee(vault);

        isolatedVaultId = createVaultIfNeeded(0, msg.sender, false);

        tradeResult = IsolatedVaultLogic.openIsolatedVault(
            assetGroup, assets, vault, vaults[isolatedVaultId], _depositAmount, _assetId, _tradeParams
        );
    }

    /**
     * @notice Close positions in the isolated vault and move margin to main vault.
     * @param _isolatedVaultId The id of isolated vault
     * @param _assetId Asset id of the asset
     * @param _closeParams The close parameters
     * @return TradeResult The result of perp trade
     */
    function closeIsolatedVault(
        uint256 _vaultId,
        uint256 _isolatedVaultId,
        uint256 _assetId,
        IsolatedVaultLogic.CloseParams memory _closeParams
    ) external nonReentrant returns (DataType.TradeResult memory) {
        DataType.Vault storage vault = vaults[_vaultId];
        DataType.Vault storage isolatedVault = vaults[_isolatedVaultId];

        require(vault.owner == msg.sender, "C2");

        applyInterest();

        return IsolatedVaultLogic.closeIsolatedVault(assetGroup, assets, vault, isolatedVault, _assetId, _closeParams);
    }

    /**
     * @notice Trades perps of x and sqrt(x)
     * @param _assetId Asset id of the asset
     * @param _tradeParams The trade parameters
     * @return TradeResult The result of perp trade
     */
    function tradePerp(uint256 _vaultId, uint256 _assetId, TradeLogic.TradeParams memory _tradeParams)
        external
        override(IController)
        returns (DataType.TradeResult memory)
    {
        DataType.UserStatus storage perpUserStatus = VaultLib.getUserStatus(assetGroup, vaults[_vaultId], _assetId);

        applyInterest();
        settleUserFee(vaults[_vaultId], _assetId);

        return TradeLogic.execTrade(assets, vaults[_vaultId], _assetId, perpUserStatus, _tradeParams);
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

        applyInterest();

        uint256 mainVaultId = mainVaults[vault.owner];

        uint256 penaltyAmount = LiquidationLogic.execLiquidationCall(assets, vault, vaults[mainVaultId], _closeRatio);

        if (penaltyAmount > 0) {
            TransferHelper.safeTransfer(assets[Constants.STABLE_ASSET_ID].token, msg.sender, penaltyAmount);
        }
    }

    ///////////////////////
    // Private Functions //
    ///////////////////////

    /**
     * @notice Sets an asset group
     * @param _stableAssetAddress The address of stable asset
     * @param _irmParams Interest rate model params for stable asset
     * @param _addAssetParams The list of asset parameters
     * @return stableAssetId  New stable asset id
     * @return assetIds underlying asset ids
     */
    function initializeAssetGroup(
        address _stableAssetAddress,
        InterestRateModel.IRMParams memory _irmParams,
        DataType.AddAssetParams[] memory _addAssetParams
    ) internal returns (uint256 stableAssetId, uint256[] memory assetIds) {
        // add stable token
        stableAssetId = Constants.STABLE_ASSET_ID;

        _addPair(
            stableAssetId,
            _stableAssetAddress,
            false,
            address(0),
            DataType.AssetRiskParams(0, 0, 0),
            _irmParams,
            InterestRateModel.IRMParams(0, 0, 0, 0)
        );

        assetGroup.setStableAssetId(stableAssetId);

        assetIds = new uint256[](_addAssetParams.length);

        for (uint256 i; i < _addAssetParams.length; i++) {
            assetIds[i] = addPair(i + 2, _addAssetParams[i]);
        }

        emit AssetGroupInitialized(stableAssetId, assetIds);
    }

    /**
     * @notice add token pair
     */
    function addPair(uint256 _assetId, DataType.AddAssetParams memory _addAssetParam) internal returns (uint256) {
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(_addAssetParam.uniswapPool);

        address stableTokenAddress = assets[Constants.STABLE_ASSET_ID].token;

        require(uniswapPool.token0() == stableTokenAddress || uniswapPool.token1() == stableTokenAddress, "C3");

        bool isMarginZero = uniswapPool.token0() == stableTokenAddress;

        _addPair(
            _assetId,
            isMarginZero ? uniswapPool.token1() : uniswapPool.token0(),
            isMarginZero,
            _addAssetParam.uniswapPool,
            _addAssetParam.assetRiskParams,
            _addAssetParam.irmParams,
            _addAssetParam.squartIRMParams
        );

        assetGroup.appendTokenId(_assetId);

        emit PairAdded(_assetId, _addAssetParam.uniswapPool);

        return _assetId;
    }

    function _addPair(
        uint256 _assetId,
        address _tokenAddress,
        bool _isMarginZero,
        address _uniswapPool,
        DataType.AssetRiskParams memory _assetRiskParams,
        InterestRateModel.IRMParams memory _irmParams,
        InterestRateModel.IRMParams memory _squartIRMParams
    ) internal {
        if (_uniswapPool != address(0)) {
            validateIRMParams(_assetRiskParams);
        }

        require(assets[_assetId].id == 0);

        assets[_assetId] = DataType.AssetStatus(
            _assetId,
            _tokenAddress,
            SupplyLogic.deploySupplyToken(_tokenAddress),
            _assetRiskParams,
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(_uniswapPool, -_assetRiskParams.rangeSize, _assetRiskParams.rangeSize),
            _isMarginZero,
            _irmParams,
            _squartIRMParams,
            block.timestamp,
            0
        );

        if (_uniswapPool != address(0)) {
            allowedUniswapPools[_uniswapPool] = true;
        }
    }

    function applyInterest() internal {
        ApplyInterestLogic.applyInterestForAssetGroup(assetGroup, assets);
    }

    function settleUserFee(DataType.Vault storage _vault) internal returns (int256[] memory latestFees) {
        return settleUserFee(_vault, 0);
    }

    function settleUserFee(DataType.Vault storage _vault, uint256 _excludeAssetId)
        internal
        returns (int256[] memory latestFees)
    {
        return SettleUserFeeLogic.settleUserFee(assetGroup, assets, _vault, _excludeAssetId);
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
                require(mainVaults[_caller] == 0, "C5");
                mainVaults[_caller] = vaultId;
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
            UniHelper.getSqrtPrice(assets[_tokenId].sqrtAssetStatus.uniswapPool), assets[_tokenId].isMarginZero
        );
    }

    function getSqrtIndexPrice(uint256 _tokenId) external view returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtTWAP(assets[_tokenId].sqrtAssetStatus.uniswapPool), assets[_tokenId].isMarginZero
        );
    }

    function getAssetGroup() external view override(IController) returns (DataType.AssetGroup memory) {
        return assetGroup;
    }

    function getAsset(uint256 _id) external view override(IController) returns (DataType.AssetStatus memory) {
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
        applyInterest();

        DataType.Vault storage vault = vaults[_vaultId];

        return ReaderLogic.getVaultStatus(assetGroup, assets, vault, mainVaults[vault.owner]);
    }

    /**
     * @notice Gets latest main vault status that the caller has.
     * @dev This function should not be called on chain.
     */
    function getVaultStatusWithAddress() external returns (uint256 vaultId, DataType.VaultStatusResult memory) {
        vaultId = mainVaults[msg.sender];

        return (vaultId, getVaultStatus(vaultId));
    }

    function getUtilizationRatio(uint256 _tokenId) external view returns (uint256, uint256) {
        return ReaderLogic.getUtilizationRatio(assets[_tokenId]);
    }

    function validateIRMParams(DataType.AssetRiskParams memory _assetRiskParams) internal pure {
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
