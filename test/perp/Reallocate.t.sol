// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract TestPerpReallocate is TestPerp {
    function setUp() public override {
        TestPerp.setUp();

        ScaledAsset.addAsset(underlyingAssetStatus.tokenStatus, 1000000);
        ScaledAsset.addAsset(stableAssetStatus, 1000000);
    }

    function testReallocate() public {
        Perp.computeRequiredAmounts(underlyingAssetStatus, userStatus, 1000000);
        Perp.updatePosition(
            underlyingAssetStatus,
            stableAssetStatus,
            userStatus,
            Perp.UpdatePerpParams(-100, 100),
            Perp.UpdateSqrtPerpParams(1000000, -100)
        );

        uniswapPool.swap(address(this), false, 10000, TickMath.MAX_SQRT_RATIO - 1, "");

        Perp.reallocate(underlyingAssetStatus, stableAssetStatus, underlyingAssetStatus.sqrtAssetStatus);

        assertEq(underlyingAssetStatus.sqrtAssetStatus.tickLower, -910);
        assertEq(underlyingAssetStatus.sqrtAssetStatus.tickUpper, 1090);
    }
}
