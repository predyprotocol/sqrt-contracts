import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const Controller = await ethers.getContract('Controller', deployer)
  const Reader = await ethers.getContract('Reader', deployer)
  const DeployStrategyTokenLogic = await ethers.getContract('DeployStrategyTokenLogic', deployer)

  await deploy('GammaShortStrategy', {
    from: deployer,
    args: [],
    libraries: {
      DeployStrategyTokenLogic: DeployStrategyTokenLogic.address
    },
    log: true,
    proxy: {
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            Controller.address,
            Reader.address,
            {
              lower: '100000000000000000',
              upper: '900000000000000000'
            }
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
