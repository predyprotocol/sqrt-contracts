// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./mocks/MockERC20.sol";
import "../src/libraries/SwapLib.sol";

contract SwapLibTest is Test {
    MockERC20 internal usdc;
    MockERC20 internal weth;
    address internal token0;
    address internal token1;
    IUniswapV3Pool internal uniswapPool;
    bool isMarginZero;

    function setUp() public virtual {
        usdc = new MockERC20("usdc", "USDC", 6);
        weth = new MockERC20("weth", "WETH", 18);

        bool isTokenAToken0 = uint160(address(weth)) < uint160(address(usdc));

        if (isTokenAToken0) {
            token0 = address(weth);
            token1 = address(usdc);
        } else {
            token0 = address(usdc);
            token1 = address(weth);
        }

        isMarginZero = !isTokenAToken0;

        usdc.mint(address(this), type(uint256).max);
        weth.mint(address(this), type(uint256).max);

        address factory =
            deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        uniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(usdc), address(weth), 500));

        uniswapPool.initialize(2 ** 96);

        usdc.approve(address(uniswapPool), type(uint256).max);
        weth.approve(address(uniswapPool), type(uint256).max);

        uniswapPool.mint(address(this), -1000, 1000, 1e18, bytes(""));
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (amount0 > 0) {
            TransferHelper.safeTransfer(token0, msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(token1, msg.sender, amount1);
        }
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(token0, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(token1, msg.sender, uint256(amount1Delta));
        }
    }

    function testSwapToSendUnderlyingAsset() public {
        SwapLib.SwapStableResult memory swapResult =
            SwapLib.swap(address(uniswapPool), SwapLib.SwapUnderlyingParams(10, 10, 10), isMarginZero);

        assertEq(swapResult.amountPerp, 9);
        assertEq(swapResult.amountSqrtPerp, 9);
        assertEq(swapResult.fee, 10);
    }

    function testSwapToReceiveUnderlyingAsset() public {
        SwapLib.SwapStableResult memory swapResult =
            SwapLib.swap(address(uniswapPool), SwapLib.SwapUnderlyingParams(-10, -10, -10), isMarginZero);

        assertEq(swapResult.amountPerp, -10);
        assertEq(swapResult.amountSqrtPerp, -10);
        assertEq(swapResult.fee, -12);
    }

    function testSwapRelativeDirection1() public {
        SwapLib.SwapStableResult memory swapResult =
            SwapLib.swap(address(uniswapPool), SwapLib.SwapUnderlyingParams(1000, -100, 0), isMarginZero);

        assertEq(swapResult.amountPerp, 997);
        assertEq(swapResult.amountSqrtPerp, -99);
    }

    function testSwapRelativeDirection2() public {
        SwapLib.SwapStableResult memory swapResult =
            SwapLib.swap(address(uniswapPool), SwapLib.SwapUnderlyingParams(0, 1000, -100), isMarginZero);

        assertEq(swapResult.amountSqrtPerp, 997);
        assertEq(swapResult.fee, -99);
    }

    function testSwapRelativeDirection3() public {
        SwapLib.SwapStableResult memory swapResult =
            SwapLib.swap(address(uniswapPool), SwapLib.SwapUnderlyingParams(-1000, 1000, 100), isMarginZero);

        assertEq(swapResult.amountPerp, -980);
        assertEq(swapResult.amountSqrtPerp, 980);
        assertEq(swapResult.fee, 98);
    }

    function testSwapIfNetZero() public {
        SwapLib.SwapStableResult memory swapResult =
            SwapLib.swap(address(uniswapPool), SwapLib.SwapUnderlyingParams(1000, -900, -100), isMarginZero);

        assertEq(swapResult.amountPerp, 1000);
        assertEq(swapResult.amountSqrtPerp, -900);
        assertEq(swapResult.fee, -100);
    }
}
