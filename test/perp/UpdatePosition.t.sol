// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./Setup.t.sol";

contract TestPerpUpdatePosition is TestPerp {
    Perp.UserStatus internal userStatus2;

    function setUp() public override {
        TestPerp.setUp();

        userStatus2 = Perp.createPerpUserStatus(1);

        Perp.updatePosition(
            underlyingAssetStatus, userStatus2, Perp.UpdatePerpParams(100, -100), Perp.UpdateSqrtPerpParams(100, -100)
        );
    }

    // Cannot open position if there is no enough supply
    function testCannotOpenLong() public {
        vm.expectRevert(bytes("S0"));
        Perp.updatePosition(
            underlyingAssetStatus, userStatus, Perp.UpdatePerpParams(1e18, -1e18), Perp.UpdateSqrtPerpParams(0, 0)
        );
    }

    // Opens long position
    function testOpenLong() public {
        Perp.updatePosition(
            underlyingAssetStatus, userStatus, Perp.UpdatePerpParams(10, -100), Perp.UpdateSqrtPerpParams(10, -100)
        );

        assertEq(userStatus.perp.amount, 10);
        assertEq(userStatus.perp.entryValue, -100);
        assertEq(userStatus.sqrtPerp.amount, 10);
        assertEq(userStatus.sqrtPerp.entryValue, -100);

        (
            uint256 assetAmountUnderlying,
            uint256 assetAmountStable,
            uint256 debtAmountUnderlying,
            uint256 debtAmountStable
        ) = Perp.getAmounts(underlyingAssetStatus.sqrtAssetStatus, userStatus, false, 2 ** 96);

        assertEq(assetAmountUnderlying, 19);
        assertEq(assetAmountStable, 0);
        assertEq(debtAmountUnderlying, 0);
        assertEq(debtAmountStable, 191);
    }

    // Closes long position
    function testCloseLong() public {
        Perp.Payoff memory payoff = Perp.updatePosition(
            underlyingAssetStatus, userStatus2, Perp.UpdatePerpParams(-100, 200), Perp.UpdateSqrtPerpParams(0, 0)
        );

        assertEq(payoff.perpPayoff, 100);
        assertEq(payoff.sqrtPayoff, 0);
        assertEq(userStatus2.perp.amount, 0);
        assertEq(userStatus2.perp.entryValue, 0);
    }

    function testCloseSqrtLong() public {
        Perp.Payoff memory payoff = Perp.updatePosition(
            underlyingAssetStatus, userStatus2, Perp.UpdatePerpParams(0, 0), Perp.UpdateSqrtPerpParams(-100, 200)
        );

        assertEq(payoff.perpPayoff, 0);
        assertEq(payoff.sqrtPayoff, 100);
        assertEq(userStatus2.sqrtPerp.amount, 0);
        assertEq(userStatus2.sqrtPerp.entryValue, 0);
    }

    function testCloseLongPartially() public {
        Perp.Payoff memory payoff = Perp.updatePosition(
            underlyingAssetStatus, userStatus2, Perp.UpdatePerpParams(-50, 100), Perp.UpdateSqrtPerpParams(0, 0)
        );

        assertEq(payoff.perpPayoff, 50);
        assertEq(payoff.sqrtPayoff, 0);
        assertEq(userStatus2.perp.amount, 50);
        assertEq(userStatus2.perp.entryValue, -50);
    }

    function testCloseLongAndOpenShort() public {
        Perp.Payoff memory payoff = Perp.updatePosition(
            underlyingAssetStatus, userStatus2, Perp.UpdatePerpParams(-200, 400), Perp.UpdateSqrtPerpParams(0, 0)
        );

        assertEq(payoff.perpPayoff, 100);
        assertEq(payoff.sqrtPayoff, 0);
        assertEq(userStatus2.perp.amount, -100);
        assertEq(userStatus2.perp.entryValue, 200);
    }

    // Opens gamma short position
    function testOpenGammaShort() public {
        Perp.updatePosition(
            underlyingAssetStatus,
            userStatus,
            Perp.UpdatePerpParams(-1e6, 1e6),
            Perp.UpdateSqrtPerpParams(1e6, -2 * 1e6)
        );

        (
            uint256 assetAmountUnderlying,
            uint256 assetAmountStable,
            uint256 debtAmountUnderlying,
            uint256 debtAmountStable
        ) = Perp.getAmounts(underlyingAssetStatus.sqrtAssetStatus, userStatus, false, 2 ** 96);

        assertEq(assetAmountUnderlying, 4987);
        assertEq(assetAmountStable, 4987);
        assertEq(debtAmountUnderlying, 4988);
        assertEq(debtAmountStable, 4988);
    }
}
