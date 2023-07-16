// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Controller} from "../../src/Controller.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {InterestRateModel} from "../../src/libraries/InterestRateModel.sol";
import "../../src/libraries/DataType.sol";
import "../mocks/MockERC20.sol";

contract TestBaseStrategy is Test {
    uint256 internal constant RISK_RATIO = 109544511;

    uint64 internal constant WETH_ASSET_ID = 1;
    uint64 internal constant PAIR_GROUP_ID = 1;

    Controller internal controller;
    MockERC20 internal usdc;
    MockERC20 internal weth;
    address internal token0;
    address internal token1;
    IUniswapV3Pool internal uniswapPool;
    InterestRateModel.IRMParams internal irmParams;

    DataType.PairStatus internal underlyingAssetStatus;

    function setUp() public virtual {
        irmParams = InterestRateModel.IRMParams(1e16, 9 * 1e17, 5 * 1e17, 1e18);

        // Set up tokens
        usdc = new MockERC20("usdc", "USDC", 6);
        weth = new MockERC20("weth", "WETH", 18);

        bool isTokenAToken0 = uint160(address(weth)) < uint160(address(usdc));

        // require(isTokenAToken0);

        if (isTokenAToken0) {
            token0 = address(weth);
            token1 = address(usdc);
        } else {
            token0 = address(usdc);
            token1 = address(weth);
            (weth, usdc) = (usdc, weth);
        }

        usdc.mint(address(this), type(uint128).max);
        weth.mint(address(this), type(uint128).max);

        // Set up Uniswap pool
        address factory =
            deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        uniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(weth), address(usdc), 500));

        uniswapPool.initialize(2 ** 96);

        IUniswapV3PoolActions(address(uniswapPool)).increaseObservationCardinalityNext(180);

        usdc.approve(address(uniswapPool), type(uint256).max);
        weth.approve(address(uniswapPool), type(uint256).max);

        uniswapPool.mint(address(this), -20000, 20000, 10 * 1e18, bytes(""));

        // Set up Controller
        controller = new Controller();
        initializeController();

        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);

        vm.warp(block.timestamp + 1 minutes);
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
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
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(token0, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(token1, msg.sender, uint256(amount1Delta));
        }
    }

    function initializeController() internal {
        controller.initialize();

        controller.addPairGroup(address(usdc), 4);

        controller.addPair(
            DataType.AddPairParams(
                PAIR_GROUP_ID,
                address(uniswapPool),
                false,
                0,
                DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
                irmParams,
                irmParams
            )
        );
    }
}
