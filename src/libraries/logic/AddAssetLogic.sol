// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../DataType.sol";
import "../../tokenization/SupplyToken.sol";

library AddAssetLogic {
    event PairAdded(uint256 pairId, address _uniswapPool);
    event AssetGroupInitialized(address stableAsset, uint256[] assetIds);
    event AssetRiskParamsUpdated(uint256 pairId, DataType.AssetRiskParams riskParams);
    event IRMParamsUpdated(
        uint256 pairId, InterestRateModel.IRMParams stableIrmParams, InterestRateModel.IRMParams underlyingIrmParams
    );

    /**
     * @notice Sets an asset group
     * @param _stableAssetAddress The address of stable asset
     * @param _addAssetParams The list of asset parameters
     * @return assetIds underlying asset ids
     */
    function initializeAssetGroup(
        DataType.PairGroup storage pairGroup,
        mapping(uint256 => DataType.PairStatus) storage pairs,
        mapping(address => bool) storage allowedUniswapPools,
        address _stableAssetAddress,
        uint8 _marginRounder,
        DataType.AddAssetParams[] memory _addAssetParams
    ) external returns (uint256[] memory assetIds) {
        pairGroup.stableTokenAddress = _stableAssetAddress;
        pairGroup.assetsCount = 1;
        pairGroup.marginRoundedDecimal = _marginRounder;

        assetIds = new uint256[](_addAssetParams.length);

        for (uint256 i; i < _addAssetParams.length; i++) {
            assetIds[i] = _addPair(pairGroup, pairs, allowedUniswapPools, _addAssetParams[i]);
        }

        emit AssetGroupInitialized(_stableAssetAddress, assetIds);
    }

    /**
     * @notice add token pair
     */
    function _addPair(
        DataType.PairGroup storage _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(address => bool) storage allowedUniswapPools,
        DataType.AddAssetParams memory _addAssetParam
    ) public returns (uint256 pairId) {
        pairId = _pairGroup.assetsCount;

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(_addAssetParam.uniswapPool);

        address stableTokenAddress = _pairGroup.stableTokenAddress;

        require(uniswapPool.token0() == stableTokenAddress || uniswapPool.token1() == stableTokenAddress, "C3");

        bool isMarginZero = uniswapPool.token0() == stableTokenAddress;

        _storePairStatus(
            _pairGroup,
            _pairs,
            pairId,
            isMarginZero ? uniswapPool.token1() : uniswapPool.token0(),
            isMarginZero,
            _addAssetParam
        );

        allowedUniswapPools[_addAssetParam.uniswapPool] = true;

        _pairGroup.assetsCount++;

        emit PairAdded(pairId, _addAssetParam.uniswapPool);
    }

    function updateAssetRiskParams(DataType.PairStatus storage _pairStatus, DataType.AssetRiskParams memory _riskParams)
        external
    {
        validateRiskParams(_riskParams);

        _pairStatus.riskParams.riskRatio = _riskParams.riskRatio;
        _pairStatus.riskParams.rangeSize = _riskParams.rangeSize;
        _pairStatus.riskParams.rebalanceThreshold = _riskParams.rebalanceThreshold;

        emit AssetRiskParamsUpdated(_pairStatus.id, _riskParams);
    }

    function updateIRMParams(
        DataType.PairStatus storage _pairStatus,
        InterestRateModel.IRMParams memory _stableIrmParams,
        InterestRateModel.IRMParams memory _underlyingIrmParams
    ) external {
        validateIRMParams(_stableIrmParams);
        validateIRMParams(_underlyingIrmParams);

        _pairStatus.stablePool.irmParams = _stableIrmParams;
        _pairStatus.underlyingPool.irmParams = _underlyingIrmParams;

        emit IRMParamsUpdated(_pairStatus.id, _stableIrmParams, _underlyingIrmParams);
    }

    function _storePairStatus(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        uint256 _pairId,
        address _tokenAddress,
        bool _isMarginZero,
        DataType.AddAssetParams memory _addAssetParam
    ) internal {
        validateRiskParams(_addAssetParam.assetRiskParams);

        require(_pairs[_pairId].id == 0);

        _pairs[_pairId] = DataType.PairStatus(
            _pairId,
            DataType.AssetPoolStatus(
                _pairGroup.stableTokenAddress,
                deploySupplyToken(_pairGroup.stableTokenAddress),
                ScaledAsset.createTokenStatus(),
                _addAssetParam.stableIrmParams
            ),
            DataType.AssetPoolStatus(
                _tokenAddress,
                deploySupplyToken(_tokenAddress),
                ScaledAsset.createTokenStatus(),
                _addAssetParam.underlyingIrmParams
            ),
            _addAssetParam.assetRiskParams,
            Perp.createAssetStatus(
                _addAssetParam.uniswapPool,
                -_addAssetParam.assetRiskParams.rangeSize,
                _addAssetParam.assetRiskParams.rangeSize
            ),
            _isMarginZero,
            _addAssetParam.isIsolatedMode,
            block.timestamp
        );
    }

    function deploySupplyToken(address _tokenAddress) internal returns (address) {
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
