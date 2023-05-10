// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/libraries/logic/ReaderLogic.sol";

contract ReaderLogicTest is Test {
    function testCalculateDelta() public {
        assertEq(ReaderLogic.calculateDelta(3464791421352347683617449, -500 * 1e12 / 2, 573 * 1e16), 13338238919106390);
    }
}
