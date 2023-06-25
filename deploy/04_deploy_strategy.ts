import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const botAddress = '0xc622fd7adfe9aafa97d9bc6f269c186f07b59f0f'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers, network } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const Controller = await ethers.getContract('Controller', deployer)
  const Reader = await ethers.getContract('Reader', deployer)
  const DeployStrategyTokenLogic = await ethers.getContract('DeployStrategyTokenLogic', deployer)

  const result = await deploy('GammaShortStrategy', {
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
              upper: '840000000000000000'
            }
          ],
        },
      },
    },
  })

  const GammaShortStrategy = await ethers.getContract('GammaShortStrategy', deployer)

  if (result.newlyDeployed) {
    if (network.name === 'arbitrum') {
      await GammaShortStrategy.setHedger(botAddress)
    }
  }

  await deploy('StrategyQuoter', {
    from: deployer,
    args: [GammaShortStrategy.address],
    log: true,
  })
}

export default func
