import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const Controller = await ethers.getContract('Controller', deployer)
  const Reader = await ethers.getContract('Reader', deployer)

  await deploy('StrategyFactory', {
    from: deployer,
    args: [],
    log: true,
  })

  const StrategyFactory = await ethers.getContract('StrategyFactory', deployer)

  await StrategyFactory.createStrategy(
    Controller.address,
    Reader.address,
    2,
    {
      lower: '100000000000000000',
      upper: '500000000000000000'
    },
    'Strategy WETH-USDC',
    'GSETH'
  );
}

export default func
