// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./Perp.sol";
import "./InterestRateModel.sol";

library DataType {
    struct PairGroup {
        address stableTokenAddress;
        uint256 assetsCount;
    }

    struct OwnVaults {
        uint256 mainVaultId;
        uint256[] isolatedVaultIds;
    }

    struct AddAssetParams {
        address uniswapPool;
        DataType.AssetRiskParams assetRiskParams;
        InterestRateModel.IRMParams stableIrmParams;
        InterestRateModel.IRMParams underlyingIrmParams;
        InterestRateModel.IRMParams squartIRMParams;
    }

    struct AssetRiskParams {
        uint256 riskRatio;
        int24 rangeSize;
        int24 rebalanceThreshold;
    }

    struct PairStatus {
        uint256 id;
        AssetPoolStatus stablePool;
        AssetPoolStatus underlyingPool;
        AssetRiskParams riskParams;
        Perp.SqrtPerpAssetStatus sqrtAssetStatus;
        bool isMarginZero;
        InterestRateModel.IRMParams squartIRMParams;
        uint256 lastUpdateTimestamp;
    }

    struct AssetPoolStatus {
        address token;
        address supplyTokenAddress;
        ScaledAsset.TokenStatus tokenStatus;
        InterestRateModel.IRMParams irmParams;
        uint256 accumulatedProtocolRevenue;
    }

    struct Vault {
        uint256 id;
        address owner;
        int256 margin;
        UserStatus[] openPositions;
    }

    struct UserStatus {
        uint256 assetId;
        Perp.UserStatus perpTrade;
    }

    struct AssetParams {
        uint256 assetGroupId;
        uint256 assetId;
    }

    struct TradeResult {
        Perp.Payoff payoff;
        int256 fee;
        int256 minDeposit;
    }

    struct SubVaultStatusResult {
        uint256 assetId;
        Perp.UserStatus position;
        int256 delta;
        int256 unrealizedFee;
    }

    struct VaultStatusResult {
        uint256 vaultId;
        bool isMainVault;
        int256 vaultValue;
        int256 margin;
        int256 positionValue;
        int256 minDeposit;
        SubVaultStatusResult[] subVaults;
    }
}
