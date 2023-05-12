// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@solmate/utils/FixedPointMathLib.sol";

library Math {
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    function mulDivDownInt256(int256 _x, int256 _y, uint256 _z) internal pure returns (int256) {
        if (_x > 0) {
            return int256(FixedPointMathLib.mulDivDown(uint256(_x), uint256(_y), _z));
        } else {
            return -int256(FixedPointMathLib.mulDivUp(uint256(-_x), uint256(_y), _z));
        }
    }
}
