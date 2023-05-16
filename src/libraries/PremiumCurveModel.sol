// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./Constants.sol";

library PremiumCurveModel {
    /**
     * @notice Calculates premium curve
     * 0 {ur <= 0.4}
     * 1.8 * (UR-0.4)^2 {0.4 < ur}
     * @param _utilization utilization ratio scaled by 1e18
     * @return spread parameter scaled by 100
     */
    function calculatePremiumCurve(uint256 _utilization) internal pure returns (uint256) {
        if (_utilization <= Constants.SQUART_KINK_UR) {
            return 0;
        }

        uint256 b = (_utilization - Constants.SQUART_KINK_UR);

        return (160 * b * b / Constants.ONE) / Constants.ONE;
    }
}