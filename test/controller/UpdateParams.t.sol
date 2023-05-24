// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./Setup.t.sol";

contract TestControllerUpdateParams is TestController {
    address internal user = vm.addr(uint256(1));
    InterestRateModel.IRMParams internal newIrmParams;

    function setUp() public override {
        TestController.setUp();

        newIrmParams = InterestRateModel.IRMParams(2 * 1e16, 10 * 1e17, 10 * 1e17, 2 * 1e18);
    }

    function testCannotInitializeTwice() public {
        DataType.AddAssetParams[] memory addAssetParams = new DataType.AddAssetParams[](1);

        addAssetParams[0] = DataType.AddAssetParams(
            address(uniswapPool), false, DataType.AssetRiskParams(RISK_RATIO, 1000, 500), irmParams, irmParams
        );

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        controller.initialize(address(usdc), addAssetParams);
    }

    function testAddPair() public {
        DataType.AddAssetParams memory addPairParams = DataType.AddAssetParams(
            address(uniswapPool), false, DataType.AssetRiskParams(RISK_RATIO, 1000, 500), irmParams, irmParams
        );

        uint256 assetId = controller.addPair(addPairParams);

        DataType.PairStatus memory asset = controller.getAsset(assetId);

        assertEq(asset.id, 3);
    }

    function testCannotUpdateAssetRiskParams_IfAParamIsInvalid() public {
        vm.expectRevert(bytes("C0"));
        controller.updateAssetRiskParams(WETH_ASSET_ID, DataType.AssetRiskParams(1e8, 10, 5));
    }

    function testCannotUpdateAssetRiskParams_IfCallerIsNotOperator() public {
        vm.prank(user);
        vm.expectRevert(bytes("C1"));
        controller.updateAssetRiskParams(WETH_ASSET_ID, DataType.AssetRiskParams(RISK_RATIO, 10, 5));
    }

    function testUpdateAssetRiskParams() public {
        controller.updateAssetRiskParams(WETH_ASSET_ID, DataType.AssetRiskParams(110000000, 20, 10));

        DataType.PairStatus memory asset = controller.getAsset(WETH_ASSET_ID);

        assertEq(asset.riskParams.riskRatio, 110000000);
        assertEq(asset.riskParams.rangeSize, 20);
        assertEq(asset.riskParams.rebalanceThreshold, 10);
    }

    function testCannotUpdateIRMParams_IfCallerIsNotOperator() public {
        vm.prank(user);
        vm.expectRevert(bytes("C1"));
        controller.updateIRMParams(WETH_ASSET_ID, newIrmParams, newIrmParams);
    }

    function testCannotUpdateIRMParams_IfAParamIsInvalid() public {
        vm.expectRevert(bytes("C4"));
        controller.updateIRMParams(
            WETH_ASSET_ID, InterestRateModel.IRMParams(1e18 + 1, 10 * 1e17, 10 * 1e17, 2 * 1e18), newIrmParams
        );
    }

    function testUpdateAssetIRMParams() public {
        controller.updateIRMParams(WETH_ASSET_ID, newIrmParams, newIrmParams);

        DataType.PairStatus memory asset = controller.getAsset(WETH_ASSET_ID);

        assertEq(asset.stablePool.irmParams.baseRate, 2 * 1e16);
        assertEq(asset.stablePool.irmParams.kinkRate, 10 * 1e17);
        assertEq(asset.stablePool.irmParams.slope1, 10 * 1e17);
        assertEq(asset.stablePool.irmParams.slope2, 2 * 1e18);
        assertEq(asset.underlyingPool.irmParams.baseRate, 2 * 1e16);
        assertEq(asset.underlyingPool.irmParams.kinkRate, 10 * 1e17);
        assertEq(asset.underlyingPool.irmParams.slope1, 10 * 1e17);
        assertEq(asset.underlyingPool.irmParams.slope2, 2 * 1e18);
    }
}
