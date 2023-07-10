const fs = require('fs')
const path = require('path')

const files = [
    'Controller_Implementation.json',
    'AddAssetLogic.json',
    'ApplyInterestLogic.json',
    'LiquidationLogic.json',
    'SupplyLogic.json',
    'TradePerpLogic.json',
    'TradeLogic.json',
    'UpdateMarginLogic.json',
    'IsolatedVaultLogic.json'
]

const deployments = files.map(filename => fs.readFileSync(path.join(__dirname, '../deployments/goerliArbitrum', filename)).toString()).map(str => JSON.parse(str))

const abis = deployments.map(deployment => deployment.abi).reduce((abis, abi) => abis.concat(abi), [])

console.log(
    JSON.stringify(abis, undefined, 2)
)
