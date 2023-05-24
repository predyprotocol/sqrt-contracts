import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const Controller = await ethers.getContract('Controller', deployer)
  const Reader = await ethers.getContract('Reader', deployer)

  await deploy('GammaShortStrategy', {
    from: deployer,
    args: [],
    log: true,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            Controller.address,
            Reader.address,
            1,
            {
              lower: '100000000000000000',
              upper: '200000000000000000'
            },
            'Strategy WETH-USDC',
            'GSETH'
          ],
        },
      },
    },
  })

  const GammaShortStrategy = await ethers.getContract('GammaShortStrategy', deployer)

  await deploy('StrategyQuoter', {
    from: deployer,
    args: [GammaShortStrategy.address],
    log: true,
  })
}

export default func
