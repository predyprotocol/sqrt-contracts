// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/libraries/logic/LiquidationLogic.sol";

contract LiquidationLogicTest is Test {
    function testCalculateLiquidationSlippageTolerance() public {
        assertEq(LiquidationLogic.calculateLiquidationSlippageTolerance(0), Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE);
        assertEq(LiquidationLogic.calculateLiquidationSlippageTolerance(12500), 12500);
        assertEq(
            LiquidationLogic.calculateLiquidationSlippageTolerance(Constants.MAX_LIQ_SLIPPAGE_SQRT_TOLERANCE + 1),
            Constants.MAX_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );
    }

    function testCalculatePenaltyAmount() public {
        assertEq(LiquidationLogic.calculatePenaltyAmount(4), 1e6);
    }
}
