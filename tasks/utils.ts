import { BigNumber } from 'ethers'

export const networkNameToOperator = (name: string) => {
  switch (name) {
    case 'arbitrum':
      return '0xb8d843c8E6e0E90eD2eDe80550856b64da92ee30'
    default:
      return undefined
  }
}

export const networkNameToUSDC = (name: string) => {
  switch (name) {
    case 'goerliArbitrum':
      return '0xE060e715B6D20b899A654687c445ed8BC35f9dFF'
    case 'arbitrum':
      return '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8'
    default:
      return undefined
  }
}

export const networkNameToWETH = (name: string) => {
  switch (name) {
    case 'goerliArbitrum':
      return '0x163691b2153F4e18F3c3F556426b7f5C74a99FA4'
    case 'arbitrum':
      return '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'
    default:
      return undefined
  }
}

export const networkNameToController = (name: string) => {
  switch (name) {
    case 'goerliArbitrum':
      return '0x269558B44ceb53fbda9C7401f6AC6c781e3d59a8'
    case 'arbitrum':
      return '0x68a154fB3e8ff6e4DA10ECd54DEF25D9149DDBDE'
    default:
      return undefined
  }
}

export const networkNameToWethUniswapPool = (name: string) => {
  switch (name) {
    case 'goerliArbitrum':
      return '0xe506cCa8C784bF0911D6dF2A3A871B766a6D816E'
    case 'arbitrum':
      return '0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443'
    default:
      return undefined
  }
}

export const networkNameToArbUniswapPool = (name: string) => {
  switch (name) {
    case 'goerliArbitrum':
      return '0x790795655ef5C836B86B30CDbf6279db66660aa8'
    case 'arbitrum':
      return '0x81c48d31365e6b526f6bbadc5c9aafd822134863'
    default:
      return undefined
  }
}

export const getUSDC = async (ethers: any, deployer: string, networkName: string) => {
  const usdcAddress = networkNameToUSDC(networkName)
  if (usdcAddress === undefined) {
    // use to local deployment as USDC
    return ethers.getContract('MockERC20', deployer)
  }
  // get contract instance at address
  return ethers.getContractAt('MockERC20', usdcAddress)
}

export const getWETH = async (ethers: any, deployer: string, networkName: string) => {
  const wethAddress = networkNameToWETH(networkName)
  if (wethAddress === undefined) {
    return ethers.getContract('MockERC20', deployer)
  }
  // get contract instance at address
  return ethers.getContractAt('MockERC20', wethAddress)
}

export const getController = async (ethers: any, deployer: string, networkName: string) => {
  const perpetualMarketAddress = networkNameToController(networkName)
  if (perpetualMarketAddress === undefined) {
    return ethers.getContract('Controller', deployer)
  }
  return ethers.getContractAt('Controller', perpetualMarketAddress)
}

export const toUnscaled = (n: BigNumber, decimals: number) => {
  return n.toNumber() / BigNumber.from(10).pow(decimals).toNumber()
}
