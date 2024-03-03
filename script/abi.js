const fs = require('fs')
const path = require('path')

const files = [
    'Controller_Implementation.json',
    'AddPairLogic.json',
    'ReallocationLogic.json',
    'LiquidationLogic.json',
    'SupplyLogic.json',
    'TradePerpLogic.json',
    'TradeLogic.json',
    'UpdateMarginLogic.json'
]

const deployments = files.map(filename => fs.readFileSync(path.join(__dirname, '../deployments/arbitrum', filename)).toString()).map(str => JSON.parse(str))

const abis = deployments.map(deployment => deployment.abi).reduce((abis, abi) => abis.concat(abi), [])

console.log(
    JSON.stringify(abis, undefined, 2)
)
