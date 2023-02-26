import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  const { deploy } = deployments

  const Controller = await ethers.getContract('Controller', deployer)

  await deploy('Reader', {
    from: deployer,
    args: [Controller.address],
    log: true,
  })
}

export default func
