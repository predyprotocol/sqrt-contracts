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
      return '0x3f366213fb56158D34d7838b8607a190D8eB5ECD'
    case 'arbitrum':
      return '0xAdBAeE9665C101413EbFF07e20520bdB67C71AB6'
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
