import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { networkNameToUSDC, networkNameToArbUniswapPool, networkNameToWethUniswapPool, networkNameToWETH } from '../tasks/utils'

const operatorAddress = '0xb8d843c8E6e0E90eD2eDe80550856b64da92ee30'
const botAddress = '0xc622fd7adfe9aafa97d9bc6f269c186f07b59f0f'

const USDC_IRM_PARAMS = {
  baseRate: '10000000000000000',
  kinkRate: '900000000000000000',
  slope1: '40000000000000000',
  slope2: '1600000000000000000',
}
const WETH_IRM_PARAMS = {
  baseRate: '10000000000000000',
  kinkRate: '850000000000000000',
  slope1: '40000000000000000',
  slope2: '1600000000000000000',
}


const RISK_RATIO_1000 = '104880884'
const RISK_RATIO_1428 = '106904496'
const RISK_RATIO_1666 = '108012344'
const RISK_RATIO_2000 = '109544511'
const RISK_RATIO_2500 = '111803398'
const RANGE_SIZE_870 = 840
const RANGE_SIZE_740 = 720
const RANGE_SIZE_490 = 480
const ASSET_RISK_PARAMS_MIDDLE = {
  riskRatio: RISK_RATIO_2000,
  rangeSize: RANGE_SIZE_740,
  rebalanceThreshold: RANGE_SIZE_740 / 2
}
const ASSET_RISK_PARAMS_HIGH = {
  riskRatio: RISK_RATIO_2500,
  rangeSize: RANGE_SIZE_870,
  rebalanceThreshold: RANGE_SIZE_870 / 2
}


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const AddPairLogic = await ethers.getContract('AddPairLogic', deployer)
  const ReallocationLogic = await ethers.getContract('ReallocationLogic', deployer)
  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)
  const ReaderLogic = await ethers.getContract('ReaderLogic', deployer)
  const SupplyLogic = await ethers.getContract('SupplyLogic', deployer)
  const TradePerpLogic = await ethers.getContract('TradePerpLogic', deployer)
  const UpdateMarginLogic = await ethers.getContract('UpdateMarginLogic', deployer)

  const usdc = networkNameToUSDC(network.name)

  const result = await deploy('Controller', {
    from: deployer,
    args: [],
    libraries: {
      ReallocationLogic: ReallocationLogic.address,
      LiquidationLogic: LiquidationLogic.address,
      ReaderLogic: ReaderLogic.address,
      AddPairLogic: AddPairLogic.address,
      SupplyLogic: SupplyLogic.address,
      TradePerpLogic: TradePerpLogic.address,
      UpdateMarginLogic: UpdateMarginLogic.address
    },
    log: true,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [],
        },
      },
    },
  })

  if (result.newlyDeployed) {
    const controller = await ethers.getContract('Controller', deployer)

    if (network.name === 'arbitrum') {
      const bridgeUSDC = '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'
      const nativeUSDC = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831'
      const weth = networkNameToWETH(network.name)

      await controller.addPairGroup(
        bridgeUSDC,
        4
      );
      await controller.addPairGroup(
        nativeUSDC,
        4
      );
      await controller.addPairGroup(
        weth,
        13
      );

      // ETH-USDC.e 5bps
      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: '0xc31e54c7a869b9fcbecc14363cf510d1c41fa443',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_740,
          rebalanceThreshold: RANGE_SIZE_740 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })
      // ARB-USDC.e 30bps
      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: '0x81c48d31365e6b526f6bbadc5c9aafd822134863',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_870,
          rebalanceThreshold: RANGE_SIZE_870 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })
      // WBTC-USDC.e 30bps
      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: '0xa62ad78825e3a55a77823f00fe0050f567c1e4ee',
        isIsolatedMode: true,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_870,
          rebalanceThreshold: RANGE_SIZE_870 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })
      // GYEN-USDC.e 5bps
      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: '0x54b7fe035ac57892d68cba53dbb5156ce79058d6',
        isIsolatedMode: true,
        assetRiskParams: {
          riskRatio: RISK_RATIO_1428,
          rangeSize: RANGE_SIZE_490,
          rebalanceThreshold: RANGE_SIZE_490 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })
      // LUSD-USDC.e 5bps
      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: '0x1557fdfda61f135baf1a1682eebaa086a0fcab6e',
        isIsolatedMode: true,
        assetRiskParams: {
          riskRatio: RISK_RATIO_1428,
          rangeSize: RANGE_SIZE_490,
          rebalanceThreshold: RANGE_SIZE_490 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })


      // native

      // ETH-USDC 5bps
      await controller.addPair({
        pairGroupId: 2,
        uniswapPool: '0xc6962004f452be9203591991d15f6b388e09e8d0',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_740,
          rebalanceThreshold: RANGE_SIZE_740 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })
      // ARB-USDC 5bps
      await controller.addPair({
        pairGroupId: 2,
        uniswapPool: '0xb0f6ca40411360c03d41c5ffc5f179b8403cdcf8',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_870,
          rebalanceThreshold: RANGE_SIZE_870 / 2
        },
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })

      // WETH

      // WBTC-WETH 5bps
      await controller.addPair({
        pairGroupId: 3,
        uniswapPool: '0x2f5e87c9312fa29aed5c179e456625d79015299c',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_740,
          rebalanceThreshold: RANGE_SIZE_740 / 2
        },
        stableIrmParams: WETH_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })

      // WETH-ARB 5bps
      await controller.addPair({
        pairGroupId: 3,
        uniswapPool: '0xc6f780497a95e246eb9449f5e4770916dcd6396a',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_740,
          rebalanceThreshold: RANGE_SIZE_740 / 2
        },
        stableIrmParams: WETH_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })

      // WETH-USDT 5bps
      await controller.addPair({
        pairGroupId: 3,
        uniswapPool: '0x641c00a822e8b671738d32a431a4fb6074e5c79d',
        isIsolatedMode: false,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_740,
          rebalanceThreshold: RANGE_SIZE_740 / 2
        },
        stableIrmParams: WETH_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })

      // WETH-LINK 30bps
      await controller.addPair({
        pairGroupId: 3,
        uniswapPool: '0x468b88941e7cc0b88c1869d68ab6b570bcef62ff',
        isIsolatedMode: true,
        assetRiskParams: {
          riskRatio: RISK_RATIO_2000,
          rangeSize: RANGE_SIZE_870,
          rebalanceThreshold: RANGE_SIZE_870 / 2
        },
        stableIrmParams: WETH_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      })

      await controller.setLiquidator(botAddress)
      await controller.setOperator(operatorAddress)
    } else if (network.name === 'goerliArbitrum') {
      await controller.addPairGroup(
        usdc,
        4
      );

      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: networkNameToWethUniswapPool(network.name),
        isIsolatedMode: false,
        assetRiskParams: ASSET_RISK_PARAMS_MIDDLE,
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      });

      await controller.addPair({
        pairGroupId: 1,
        uniswapPool: networkNameToArbUniswapPool(network.name),
        isIsolatedMode: false,
        assetRiskParams: ASSET_RISK_PARAMS_HIGH,
        stableIrmParams: USDC_IRM_PARAMS,
        underlyingIrmParams: WETH_IRM_PARAMS
      });

    }
  }
}

export default func
