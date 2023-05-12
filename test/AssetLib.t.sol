// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/libraries/AssetLib.sol";

contract AssetLibTest is Test {
    function testGetRebalanceId() public {
        assertEq(AssetLib.getRebalanceCacheId(1, 100), 18446744073709551715);
        assertEq(AssetLib.getRebalanceCacheId(2, 100), 36893488147419103330);
    }
}
