// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/libraries/logic/LiquidationLogic.sol";

contract LiquidationLogicTest is Test {
    function testCalculateLiquidationSlippageTolerance() public {
        assertEq(
            LiquidationLogic.calculateLiquidationSlippageTolerance(1e6), Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );
        assertEq(
            LiquidationLogic.calculateLiquidationSlippageTolerance(100000 * 1e6),
            Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );
        assertEq(LiquidationLogic.calculateLiquidationSlippageTolerance(500000 * 1e6), 16556);
        assertEq(LiquidationLogic.calculateLiquidationSlippageTolerance(1000000 * 1e6), 23000);
    }

    function testCalculatePenaltyAmount() public {
        assertEq(LiquidationLogic.calculatePenaltyAmount(10 * 1e6), Constants.MIN_PENALTY);

        assertEq(LiquidationLogic.calculatePenaltyAmount(1000 * 1e6), 2 * 1e6);

        assertEq(LiquidationLogic.calculatePenaltyAmount(1000 * 1e6 + 100), 2 * 1e6);
    }
}
