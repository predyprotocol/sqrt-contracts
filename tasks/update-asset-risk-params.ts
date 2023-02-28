import { task } from 'hardhat/config'
import { getController } from './utils'

// Example execution
/**
 * npx hardhat update-asset-risk-params --network goerliArbitrum
 */
task('update-asset-risk-params', 'execute a hedge').setAction(async ({ }, hre) => {
  const { getNamedAccounts, ethers, network } = hre

  const { deployer } = await getNamedAccounts()

  const controller = await getController(ethers, deployer, network.name)

  console.log('Start updating')
  const tx = await controller.updateAssetRiskParams(2, {
    riskRatio: '109544511',
    rangeSize: 600,
    rebalanceThreshold: 300
  })
  await tx.wait()
  console.log('Succeed to update')
})
