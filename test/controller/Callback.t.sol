// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerCallback is TestController {
    uint256 vaultId;

    address internal user = vm.addr(uint256(1));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user, type(uint128).max);
        weth.mint(user, type(uint128).max);

        vm.startPrank(user);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        controller.supplyToken(1, 1e10, true);
        controller.supplyToken(1, 1e10, false);
        vm.stopPrank();

        vaultId = controller.updateMargin(1e8, 0);
    }

    function predyTradeCallback(DataType.TradeResult memory, bytes calldata _data) external pure returns (int256) {
        int256 margin = abi.decode(_data, (int256));

        return margin;
    }

    function testCannotTradePerp() public {
        TradePerpLogic.TradeParams memory tradeParams = TradePerpLogic.TradeParams(
            5 * 1e8,
            0,
            getLowerSqrtPrice(WETH_ASSET_ID),
            getUpperSqrtPrice(WETH_ASSET_ID),
            block.timestamp,
            true,
            abi.encode(int256(-1e6))
        );

        vm.expectRevert(bytes("T3"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    function testTradePerp() public {
        TradePerpLogic.TradeParams memory tradeParams = TradePerpLogic.TradeParams(
            5 * 1e8,
            0,
            getLowerSqrtPrice(WETH_ASSET_ID),
            getUpperSqrtPrice(WETH_ASSET_ID),
            block.timestamp,
            true,
            abi.encode(int256(1e6))
        );

        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.openPositions[0].perp.amount, 500000000);
    }
}
