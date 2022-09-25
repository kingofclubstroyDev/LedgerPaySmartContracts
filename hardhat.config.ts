import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import { HardhatUserConfig } from 'hardhat/config'
import 'hardhat-deploy'
import '@nomiclabs/hardhat-etherscan'
import "@cronos-labs/hardhat-cronoscan";

import 'solidity-coverage'

import * as fs from 'fs'
import * as dotenv from "dotenv";



dotenv.config();

const mnemonicFileName = process.env.MNEMONIC_FILE ?? `${process.env.HOME}/.secret/testnet-mnemonic.txt`
let mnemonic = 'test '.repeat(11) + 'junk'
if (fs.existsSync(mnemonicFileName)) { mnemonic = fs.readFileSync(mnemonicFileName, 'ascii') }

function getNetwork1 (url: string): { url: string, accounts: { mnemonic: string } } {
  return {
    url,
    accounts: { mnemonic }
  }
}

function getNetwork (name: string): { url: string, accounts: { mnemonic: string } } {
  return getNetwork1(`https://${name}.infura.io/v3/${process.env.INFURA_ID}`)
  // return getNetwork1(`wss://${name}.infura.io/ws/v3/${process.env.INFURA_ID}`)
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.15',
    settings: {
      optimizer: { enabled: true, runs: 1000000 }
    }
  },
  networks: {
    dev: { url: 'http://localhost:8545' },
    // github action starts localgeth service, for gas calculations
    localgeth: { url: 'http://localgeth:8545' },
    goerli: getNetwork('goerli'),
    proxy: getNetwork1('http://localhost:8545'),
    kovan: getNetwork('kovan'),
    mumbai: {
      url: process.env.MUMBAI_RPC,
      accounts: [process.env.PRIVATE_KEY as string],
    },
    oasis: {
      url:"https://testnet.sapphire.oasis.dev",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    optimism: {
      chainId: 10,
      url:"https://mainnet.optimism.io",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    polygon: {
      url:"https://matic-mainnet.chainstacklabs.com",
      accounts: [process.env.PRIVATE_KEY as string],
    },
    cronosTestnet: {
      url: "https://evm-t3.cronos.org/",
      chainId: 338,
      accounts: [process.env.PRIVATE_KEY as string],
    },

    auroraTestnet: {
      url: "https://testnet.aurora.dev",
      chainId: 1313161555,
      accounts: [process.env.PRIVATE_KEY as string],
    }

  },
  mocha: {
    timeout: 10000
  },

  etherscan: {
    apiKey: process.env.POLYGON_ETHERSCAN_API
    //apiKey: process.env.ETHERSCAN_API_KEY
    //apiKey: process.env.OPTIMISM_ETHERSCAN_API
    //apiKey: process.env.CHRONOS_ETHERSCAN_API
    //apiKey: process.env.AUORA_ETHERSCAN_API

  }

}

export default config
