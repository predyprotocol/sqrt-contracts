import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { networkNameToUSDC, networkNameToArbUniswapPool, networkNameToWethUniswapPool } from '../tasks/utils'

const operatorAddress = '0xb8d843c8E6e0E90eD2eDe80550856b64da92ee30'
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

const ASSET_RISK_PARAMS_MIDDLE = {
  riskRatio: '109544511',
  rangeSize: 720,
  rebalanceThreshold: 360
}
const ASSET_RISK_PARAMS_HIGH = {
  riskRatio: '109544511',
  rangeSize: 840,
  rebalanceThreshold: 420
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
      // await controller.setOperator(operatorAddress)
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
