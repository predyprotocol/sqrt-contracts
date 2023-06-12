import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  console.log(`Start deploying with ${deployer}`)

  const { deploy } = deployments

  await deploy('AddAssetLogic', {
    from: deployer,
    log: true,
  })

  const AddAssetLogic = await ethers.getContract('AddAssetLogic', deployer)

  await deploy('UpdateMarginLogic', {
    from: deployer,
    log: true
  })

  const UpdateMarginLogic = await ethers.getContract('UpdateMarginLogic', deployer)

  await deploy('TradeLogic', {
    from: deployer,
    log: true,
    libraries: {
      UpdateMarginLogic: UpdateMarginLogic.address
    }
  })

  const TradeLogic = await ethers.getContract('TradeLogic', deployer)

  await deploy('LiquidationLogic', {
    from: deployer,
    log: true,
    libraries: {
      TradeLogic: TradeLogic.address
    }
  })

  await deploy('IsolatedVaultLogic', {
    from: deployer,
    log: true,
    libraries: {
      TradeLogic: TradeLogic.address
    }
  })

  await deploy('ApplyInterestLogic', {
    from: deployer,
    log: true,
  })

  await deploy('ReaderLogic', {
    from: deployer,
    log: true,
  })

  await deploy('SupplyLogic', {
    from: deployer,
    log: true,
  })
}

export default func
