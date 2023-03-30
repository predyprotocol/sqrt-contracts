// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/libraries/Reallocation.sol";
import "../src/libraries/InterestRateModel.sol";

contract ReallocationTest is Test {
    DataType.AssetStatus underlyingAssetStatus;
    ScaledAsset.TokenStatus stableAssetStatus;

    function setUp() public {
        underlyingAssetStatus = DataType.AssetStatus(
            1,
            address(0),
            address(0),
            DataType.AssetRiskParams(0, 1000, 500),
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(address(0), -1000, 1000),
            false,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp,
            0
        );

        stableAssetStatus = ScaledAsset.createTokenStatus();
    }

    function testGetNewRange() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 0;

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, 0, 10
        );

        assertEq(lower, -1000);
        assertEq(upper, 1000);
    }

    function testGetNewRange_IfToken0() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(underlyingAssetStatus.tokenStatus, 1e4);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, 500, 10
        );

        assertEq(lower, -790);
        assertEq(upper, 1200);
    }

    function testGetNewRange_IfToken0_Enough() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(underlyingAssetStatus.tokenStatus, 1e6);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, 500, 10
        );

        assertEq(lower, -500);
        assertEq(upper, 1500);
    }

    function testGetNewRange_IfToken0_Min() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(underlyingAssetStatus.tokenStatus, 1);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, 500, 10
        );

        assertEq(lower, -990);
        assertEq(upper, 1010);
    }

    function testGetNewRange_IfToken0_TooHigh() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(underlyingAssetStatus.tokenStatus, 1);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, 1500, 10
        );

        assertEq(lower, 500);
        assertEq(upper, 2500);
    }

    function testGetNewRange_IfToken1() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(stableAssetStatus, 1e4);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, -500, 10
        );

        assertEq(lower, -1200);
        assertEq(upper, 790);
    }

    function testGetNewRange_IfToken1_Enough() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(stableAssetStatus, 1e6);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, -500, 10
        );

        assertEq(lower, -1500);
        assertEq(upper, 500);
    }

    function testGetNewRange_IfToken1_TooLow() public {
        underlyingAssetStatus.sqrtAssetStatus.totalAmount = 1e6;

        ScaledAsset.addAsset(stableAssetStatus, 1e4);

        (int24 lower, int24 upper) = Reallocation._getNewRange(
            underlyingAssetStatus, underlyingAssetStatus.tokenStatus, stableAssetStatus, -1500, 10
        );

        assertEq(lower, -2500);
        assertEq(upper, -500);
    }

    function testIsInRange() public {
        assertTrue(Reallocation._isInRange(underlyingAssetStatus.sqrtAssetStatus, 0));
    }

    function testIsOutOfRange() public {
        assertFalse(Reallocation._isInRange(underlyingAssetStatus.sqrtAssetStatus, -1001));
        assertFalse(Reallocation._isInRange(underlyingAssetStatus.sqrtAssetStatus, 1000));
    }

    function testCalculateMinLowerTick() public {
        assertEq(Reallocation.calculateMinLowerTick(1000, 1e4, 1e6, 10), 818);
    }

    function testCalculateMinLowerTickFuzz(uint256 _tick, uint256 _available, uint256 _liquidityAmount) public {
        int24 tick = int24(uint24(bound(_tick, 0, 40000))) - 20000;
        uint256 available = bound(_available, 0, 1e18);
        uint256 liquidityAmount = bound(_liquidityAmount, 1, 1e18);

        int24 minLowerTick = Reallocation.calculateMinLowerTick(tick, available, liquidityAmount, 10);

        assertLe(minLowerTick, tick);
    }

    function testCalculateMaxUpperTick() public {
        assertEq(Reallocation.calculateMaxUpperTick(1000, 1e4, 1e6, 10), 1201);
    }

    function testCalculateMaxUpperTickFuzz(uint256 _tick, uint256 _available, uint256 _liquidityAmount) public {
        int24 tick = int24(uint24(bound(_tick, 0, 40000))) - 20000;
        uint256 available = bound(_available, 0, 1e18);
        uint256 liquidityAmount = bound(_liquidityAmount, 1, 1e18);

        int24 minLowerTick = Reallocation.calculateMaxUpperTick(tick, available, liquidityAmount, 10);

        assertGe(minLowerTick, tick);
    }
}
