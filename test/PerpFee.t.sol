// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/libraries/PerpFee.sol";

contract PerpFeeTest is Test {
    DataType.AssetStatus underlyingAssetStatus;
    ScaledAsset.TokenStatus stableAssetStatus;
    Perp.UserStatus perpUserStatus;

    function setUp() public {
        underlyingAssetStatus = DataType.AssetStatus(
            1,
            address(0),
            address(0),
            DataType.AssetRiskParams(0, 1000, 500),
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(address(0), -100, 100),
            false,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp,
            0
        );
        stableAssetStatus = ScaledAsset.createTokenStatus();
        perpUserStatus = Perp.createPerpUserStatus();

        underlyingAssetStatus.sqrtAssetStatus.supplyPremiumGrowth = 1 * 1e16;
        underlyingAssetStatus.sqrtAssetStatus.borrowPremiumGrowth = 2 * 1e16;
        underlyingAssetStatus.sqrtAssetStatus.fee0Growth = 200 * 1e12;
        underlyingAssetStatus.sqrtAssetStatus.fee1Growth = 5 * 1e12;
    }

    function testComputeTradeFeeForLong() public {
        perpUserStatus.sqrtPerp.amount = 10000000000;

        (int256 feeUnderlying, int256 feeStable) =
            PerpFee.computeTradeFee(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, 2000000);
        assertEq(feeStable, 50000);
    }

    function testComputeTradeFeeForShort() public {
        perpUserStatus.sqrtPerp.amount = -10000000000;

        (int256 feeUnderlying, int256 feeStable) =
            PerpFee.computeTradeFee(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, 0);
        assertEq(feeStable, 0);
    }

    function testSettleTradeFeeForLong() public {
        perpUserStatus.sqrtPerp.amount = 10000000000;

        (int256 feeUnderlying, int256 feeStable) =
            PerpFee.settleTradeFee(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, 2000000);
        assertEq(feeStable, 50000);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee0, 200 * 1e12);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee1, 5 * 1e12);
    }

    function testSettleTradeFeeForShort() public {
        perpUserStatus.sqrtPerp.amount = -10000000000;

        (int256 feeUnderlying, int256 feeStable) =
            PerpFee.settleTradeFee(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, 0);
        assertEq(feeStable, 0);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee0, 200 * 1e12);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee1, 5 * 1e12);
    }

    function testComputePremiumForLong() public {
        perpUserStatus.sqrtPerp.amount = 10000000000;

        int256 premium = PerpFee.computePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(premium, 100000000);
    }

    function testComputePremiumForShort() public {
        perpUserStatus.sqrtPerp.amount = -10000000000;

        int256 premium = PerpFee.computePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(premium, -200000000);
    }

    function testSettlePremiumForLong() public {
        perpUserStatus.sqrtPerp.amount = 10000000000;

        int256 premium = PerpFee.settlePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(premium, 100000000);
        assertEq(perpUserStatus.sqrtPerp.entryPremium, 1 * 1e16);
    }

    function testSettlePremiumForShort() public {
        perpUserStatus.sqrtPerp.amount = -10000000000;

        int256 premium = PerpFee.settlePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(premium, -200000000);
        assertEq(perpUserStatus.sqrtPerp.entryPremium, 2 * 1e16);
    }
}
