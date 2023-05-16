// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "../../src/libraries/PositionCalculator.sol";

contract CalculateMinDepositTest is TestPositionCalculator {
    mapping(uint256 => DataType.AssetStatus) assets;

    function setUp() public override {
        TestPositionCalculator.setUp();

        assets[1] = DataType.AssetStatus(
            1,
            address(0),
            address(0),
            DataType.AssetRiskParams(0, 1000, 500),
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(address(0), -100, 100),
            false,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp,
            0
        );

        assets[2] = DataType.AssetStatus(
            2,
            address(0),
            address(0),
            DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(address(uniswapPool), -100, 100),
            false,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp,
            0
        );

        assets[3] = DataType.AssetStatus(
            3,
            address(0),
            address(0),
            DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(address(wbtcUniswapPool), -100, 100),
            false,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp,
            0
        );
    }

    function getVault(int256 _amountStable, int256 _amountSquart, int256 _amountUnderlying, int256 _margin)
        internal
        view
        returns (DataType.Vault memory)
    {
        DataType.UserStatus[] memory openPositions = new DataType.UserStatus[](1);

        openPositions[0] = DataType.UserStatus(2, Perp.createPerpUserStatus());

        openPositions[0].perpTrade.sqrtPerp.amount = _amountSquart;
        openPositions[0].perpTrade.underlying.positionAmount = _amountUnderlying;
        openPositions[0].perpTrade.perp.amount = _amountUnderlying;

        openPositions[0].perpTrade.perp.entryValue = _amountStable;
        openPositions[0].perpTrade.sqrtPerp.entryValue = 0;
        openPositions[0].perpTrade.stable.positionAmount = _amountStable;

        return DataType.Vault(1, address(this), _margin, openPositions);
    }

    function getMultiAssetVault(
        PositionCalculator.PositionParams memory _positionParams1,
        PositionCalculator.PositionParams memory _positionParams2,
        int256 _margin
    ) internal view returns (DataType.Vault memory) {
        DataType.UserStatus[] memory openPositions = new DataType.UserStatus[](2);

        openPositions[0] = DataType.UserStatus(2, Perp.createPerpUserStatus());

        openPositions[1] = DataType.UserStatus(3, Perp.createPerpUserStatus());

        openPositions[0].perpTrade.sqrtPerp.amount = _positionParams1.amountSqrt;
        openPositions[0].perpTrade.underlying.positionAmount = _positionParams1.amountUnderlying;
        openPositions[0].perpTrade.perp.amount = _positionParams1.amountUnderlying;

        openPositions[0].perpTrade.perp.entryValue = _positionParams1.amountStable;
        openPositions[0].perpTrade.sqrtPerp.entryValue = 0;
        openPositions[0].perpTrade.stable.positionAmount = _positionParams1.amountStable;

        openPositions[1].perpTrade.sqrtPerp.amount = _positionParams2.amountSqrt;
        openPositions[1].perpTrade.underlying.positionAmount = _positionParams2.amountUnderlying;
        openPositions[1].perpTrade.perp.amount = _positionParams2.amountUnderlying;
        openPositions[1].perpTrade.perp.entryValue = _positionParams2.amountStable;
        openPositions[1].perpTrade.sqrtPerp.entryValue = 0;
        openPositions[1].perpTrade.stable.positionAmount = _positionParams2.amountStable;

        return DataType.Vault(1, address(this), _margin, openPositions);
    }

    function testCalculateMinDepositZero() public {
        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, getVault(0, 0, 0, 0), false);

        assertEq(minDeposit, 0);
        assertEq(vaultValue, 0);
        assertFalse(hasPosition);
    }

    function testCalculateMinDepositStable(uint256 _amountStable) public {
        int256 amountStable = int256(bound(_amountStable, 0, 1e36));

        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, getVault(amountStable, 0, 0, 0), false);

        assertEq(minDeposit, 0);
        assertEq(vaultValue, amountStable);
        assertFalse(hasPosition);
    }

    function testCalculateMinDepositDeltaLong() public {
        DataType.Vault memory vault = getVault(-1000, 0, 1000, 0);

        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, vault, false);

        assertEq(minDeposit, 1000000);
        assertEq(vaultValue, 0);
        assertTrue(hasPosition);

        PositionCalculator.isDanger(assets, vault);
    }

    function testCalculateMinDepositGammaShort() public {
        DataType.Vault memory vault = getVault(-2 * 1e8, 1e8, 0, 0);
        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, vault, false);

        assertEq(minDeposit, 17425814);
        assertEq(vaultValue, 0);
        assertTrue(hasPosition);

        PositionCalculator.isDanger(assets, vault);
    }

    function testCalculateMinDepositGammaShortSafe() public {
        DataType.Vault memory vault = getVault(-2 * 1e8, 1e8, 0, 20000000);
        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, vault, false);

        assertEq(minDeposit, 17425814);
        assertEq(vaultValue, 20000000);
        assertTrue(hasPosition);

        PositionCalculator.isSafe(assets, vault, false);
    }

    function testCalculateMinDepositGammaLong() public {
        DataType.Vault memory vault = getVault(2 * 1e8, -1e8, 0, 0);
        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, vault, false);

        assertEq(minDeposit, 20089021);
        assertEq(vaultValue, 0);
        assertTrue(hasPosition);

        PositionCalculator.isDanger(assets, vault);
    }

    function testCalculateMinDepositGammaLongSafe() public {
        DataType.Vault memory vault = getVault(2 * 1e8, -1e8, 0, 22000000);
        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, vault, false);

        assertEq(minDeposit, 20089021);
        assertEq(vaultValue, 22000000);
        assertTrue(hasPosition);

        PositionCalculator.isSafe(assets, vault, false);
    }

    function testCalculateMinDeposit_MultiAsset() public {
        DataType.Vault memory vault = getMultiAssetVault(
            PositionCalculator.PositionParams(-1e8, 1e8, 0), PositionCalculator.PositionParams(-1e8, 1e8, 0), 0
        );

        (int256 minDeposit, int256 vaultValue, bool hasPosition) =
            PositionCalculator.calculateMinDeposit(assets, vault, false);

        assertEq(minDeposit, 34851628);
        assertEq(vaultValue, 2 * 1e8);
        assertTrue(hasPosition);

        PositionCalculator.isSafe(assets, vault, false);
    }

    function testIsSafe() public {
        DataType.Vault memory vault = getVault(0, 0, 0, -100);

        // check no revert
        PositionCalculator.isSafe(assets, vault, true);
        assertTrue(true);
    }
}
