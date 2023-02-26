import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { networkNameToUSDC } from '../tasks/utils'

const operatorAddress = '0xb8d843c8E6e0E90eD2eDe80550856b64da92ee30'
const USDC_IRM_PARAMS = {
  baseRate: '4000000000000000',
  kinkRate: '900000000000000000',
  slope1: '40000000000000000',
  slope2: '1400000000000000000',
}
const WETH_IRM_PARAMS = {
  baseRate: '4000000000000000',
  kinkRate: '850000000000000000',
  slope1: '40000000000000000',
  slope2: '1400000000000000000',
}
const PREMIUM_PARAMS = {
  baseRate: '30000000000000000',
  kinkRate: '500000000000000000',
  slope1: '120000000000000000',
  slope2: '1562500000000000000',
}
const ASSET_RISK_PARAMS = {
  riskRatio: '108627804',
  rangeSize: 600,
  rebalanceThreshold: 300
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const ApplyInterestLogic = await ethers.getContract('ApplyInterestLogic', deployer)
  const LiquidationLogic = await ethers.getContract('LiquidationLogic', deployer)
  const ReaderLogic = await ethers.getContract('ReaderLogic', deployer)
  const SettleUserFeeLogic = await ethers.getContract('SettleUserFeeLogic', deployer)
  const SupplyLogic = await ethers.getContract('SupplyLogic', deployer)
  const TradeLogic = await ethers.getContract('TradeLogic', deployer)
  const UpdateMarginLogic = await ethers.getContract('UpdateMarginLogic', deployer)
  const IsolatedVaultLogic = await ethers.getContract('IsolatedVaultLogic', deployer)

  const usdc = networkNameToUSDC(network.name)

  const result = await deploy('Controller', {
    from: deployer,
    args: [],
    libraries: {
      ApplyInterestLogic: ApplyInterestLogic.address,
      LiquidationLogic: LiquidationLogic.address,
      ReaderLogic: ReaderLogic.address,
      SettleUserFeeLogic: SettleUserFeeLogic.address,
      SupplyLogic: SupplyLogic.address,
      TradeLogic: TradeLogic.address,
      UpdateMarginLogic: UpdateMarginLogic.address,
      IsolatedVaultLogic: IsolatedVaultLogic.address
    },
    log: true,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            usdc,
            USDC_IRM_PARAMS,
            [{
              uniswapPool: '0xe506cCa8C784bF0911D6dF2A3A871B766a6D816E',
              assetRiskParams: ASSET_RISK_PARAMS,
              irmParams: WETH_IRM_PARAMS,
              premiumParams: PREMIUM_PARAMS
            }, {
              uniswapPool: '0x790795655ef5C836B86B30CDbf6279db66660aa8',
              assetRiskParams: ASSET_RISK_PARAMS,
              irmParams: WETH_IRM_PARAMS,
              premiumParams: PREMIUM_PARAMS
            }]
          ],
        },
      },
    },
  })

  if (result.newlyDeployed) {
    const controller = await ethers.getContract('Controller', deployer)

    // await controller.setOperator(operatorAddress)
  }
}

export default func
