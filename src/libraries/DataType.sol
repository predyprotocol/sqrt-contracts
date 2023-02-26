// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ScaledAsset.sol";
import "./Perp.sol";
import "./InterestRateModel.sol";

library DataType {
    struct AssetGroup {
        uint256 stableAssetId;
        uint256[] assetIds;
    }

    struct AddAssetParams {
        address uniswapPool;
        DataType.AssetRiskParams assetRiskParams;
        InterestRateModel.IRMParams irmParams;
        InterestRateModel.IRMParams premiumParams;
    }

    struct AssetRiskParams {
        uint256 riskRatio;
        int24 rangeSize;
        int24 rebalanceThreshold;
    }

    struct AssetStatus {
        uint256 id;
        address token;
        address supplyTokenAddress;
        AssetRiskParams riskParams;
        ScaledAsset.TokenStatus tokenStatus;
        Perp.SqrtPerpAssetStatus sqrtAssetStatus;
        bool isMarginZero;
        InterestRateModel.IRMParams irmParams;
        InterestRateModel.IRMParams premiumParams;
        uint256 lastUpdateTimestamp;
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
        int256 stableAmount;
        int256 underlyingamount;
        int256 sqrtAmount;
        int256 delta;
        int256 unrealizedFee;
    }

    struct VaultStatusResult {
        bool isMainVault;
        int256 vaultValue;
        int256 margin;
        int256 positionValue;
        int256 minDeposit;
        SubVaultStatusResult[] subVaults;
    }
}
