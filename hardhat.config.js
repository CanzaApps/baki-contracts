/** @type import('hardhat/config').HardhatUserConfig */
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-etherscan");

const dotenv = require('dotenv');
dotenv.config();

module.exports = {
   solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000
      }
    }
  },
  networks: {
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/MIaPbNNNaHPp9qf5cDCOEJPVxJ_GwLVY`,
      accounts: [
        process.env.TESTNET_PRIVATE_KEY || "ce823841483ccf5d4d6f35fc552fc6fb86a53473ff9fcae9f32b7ebb7a3af960",
      ],
    },
    fuji: {
      url: `https://omniscient-restless-thunder.avalanche-testnet.discover.quiknode.pro/933a2d24cf1a762fd73a569be25bdec21cb60a9f/ext/bc/C/rpc`,
      accounts: [
        process.env.TESTNET_PRIVATE_KEY || "ce823841483ccf5d4d6f35fc552fc6fb86a53473ff9fcae9f32b7ebb7a3af960",
      ],
      chainId: 43113,
    },
    mainnet: {
      url: `https://red-neat-putty.avalanche-mainnet.quiknode.pro/d54c9d0935c483e2f8e70b7a756d882e45cd9e3f/ext/bc/C/rpc/`,
      accounts: [
        process.env.MAINNET_PRIVATE_KEY || "ce823841483ccf5d4d6f35fc552fc6fb86a53473ff9fcae9f32b7ebb7a3af960",
      ],
      chainId: 43114
    }
    // etherscan: {
    //   apiKey: process.env.ETHERSCAN_API_KEY,
    // },
  },
};