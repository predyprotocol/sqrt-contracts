// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../../src/libraries/InterestRateModel.sol";
import "../mocks/MockERC20.sol";

contract TestPositionCalculator is Test {
    uint256 internal constant RISK_RATIO = 109544511;

    MockERC20 internal usdc;
    MockERC20 internal weth;
    MockERC20 internal wbtc;

    address internal token0;
    address internal token1;

    IUniswapV3Pool internal uniswapPool;
    IUniswapV3Pool internal wbtcUniswapPool;
    InterestRateModel.IRMParams internal irmParams;

    function setUp() public virtual {
        irmParams = InterestRateModel.IRMParams(1e16, 9 * 1e17, 5 * 1e17, 1e18);

        // Set up tokens
        usdc = new MockERC20("usdc", "USDC", 6);
        weth = new MockERC20("weth", "WETH", 18);
        wbtc = new MockERC20("wbtc", "WBTC", 18);

        bool isTokenAToken0 = uint160(address(weth)) < uint160(address(usdc));
        bool isTokenAToken0ForWBTC = uint160(address(wbtc)) < uint160(address(usdc));

        if (isTokenAToken0) {
            token0 = address(weth);
            token1 = address(usdc);
        } else {
            token0 = address(usdc);
            token1 = address(weth);
            (weth, usdc) = (usdc, weth);
        }

        if (!isTokenAToken0ForWBTC) {
            (wbtc, usdc) = (usdc, wbtc);
        }

        usdc.mint(address(this), type(uint128).max);
        weth.mint(address(this), type(uint128).max);
        wbtc.mint(address(this), type(uint128).max);

        // Set up Uniswap pool
        address factory =
            deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        uniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(weth), address(usdc), 500));
        wbtcUniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(wbtc), address(usdc), 500));

        uniswapPool.initialize(2 ** 96);
        wbtcUniswapPool.initialize(2 ** 96);

        IUniswapV3PoolActions(address(uniswapPool)).increaseObservationCardinalityNext(180);
        IUniswapV3PoolActions(address(wbtcUniswapPool)).increaseObservationCardinalityNext(180);

        usdc.approve(address(uniswapPool), type(uint256).max);
        weth.approve(address(uniswapPool), type(uint256).max);
        usdc.approve(address(wbtcUniswapPool), type(uint256).max);
        wbtc.approve(address(wbtcUniswapPool), type(uint256).max);

        uniswapPool.mint(address(this), -2000, 2000, 1e18, bytes(""));
        wbtcUniswapPool.mint(address(this), -2000, 2000, 1e18, bytes(""));

        vm.warp(block.timestamp + 1 minutes);
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        if (amount0 > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token1(), msg.sender, amount1);
        }
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token0(), msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token1(), msg.sender, uint256(amount1Delta));
        }
    }
}
