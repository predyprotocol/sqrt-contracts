// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/libraries/PerpFee.sol";
import "./helper/Helper.sol";

contract PerpFeeTest is Test, Helper {
    DataType.PairStatus underlyingAssetStatus;
    ScaledAsset.TokenStatus stableAssetStatus;
    Perp.UserStatus perpUserStatus;

    function setUp() public {
        underlyingAssetStatus = createAssetStatus(1, address(0), address(0));
        stableAssetStatus = ScaledAsset.createTokenStatus();
        perpUserStatus = Perp.createPerpUserStatus();
    }

    function testComputeTradeFeeForLong() public {
        perpUserStatus.sqrtPerp.amount = 10000000000;

        (int256 feeUnderlying, int256 feeStable) =
            PerpFee.computePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, 1999999);
        assertEq(feeStable, 49999);
    }

    function testComputeTradeFeeForShort() public {
        perpUserStatus.sqrtPerp.amount = -10000000000;

        (int256 feeUnderlying, int256 feeStable) =
            PerpFee.computePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, -100000000);
        assertEq(feeStable, -200000000);
    }

    function testSettleTradeFeeForLong() public {
        perpUserStatus.sqrtPerp.amount = 10000000000;

        (int256 feeUnderlying, int256 feeStable) = PerpFee.settlePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, 1999999);
        assertEq(feeStable, 49999);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee0, underlyingAssetStatus.sqrtAssetStatus.fee0Growth);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee1, underlyingAssetStatus.sqrtAssetStatus.fee1Growth);
    }

    function testSettleTradeFeeForShort() public {
        perpUserStatus.sqrtPerp.amount = -10000000000;

        (int256 feeUnderlying, int256 feeStable) = PerpFee.settlePremium(underlyingAssetStatus, perpUserStatus.sqrtPerp);

        assertEq(feeUnderlying, -100000000);
        assertEq(feeStable, -200000000);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee0, underlyingAssetStatus.sqrtAssetStatus.borrowPremium0Growth);
        assertEq(perpUserStatus.sqrtPerp.entryTradeFee1, underlyingAssetStatus.sqrtAssetStatus.borrowPremium1Growth);
    }
}
