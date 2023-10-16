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
    // goerli: {
    //   url: `https://eth-goerli.g.alchemy.com/v2/MIaPbNNNaHPp9qf5cDCOEJPVxJ_GwLVY`,
    //   accounts: [
    //     process.env.TESTNET_PRIVATE_KEY,
    //   ],
    // },
    fuji: {
      url: `https://omniscient-restless-thunder.avalanche-testnet.discover.quiknode.pro/933a2d24cf1a762fd73a569be25bdec21cb60a9f/ext/bc/C/rpc`,
      accounts: [
       "72144489af80f0657a7f7df9e1291e0f9f19f84596e88f80888ab8fa5641993f"
      ],
      chainId: 43113,
    },
    // mainnet: {
    //   url: `https://red-neat-putty.avalanche-mainnet.quiknode.pro/d54c9d0935c483e2f8e70b7a756d882e45cd9e3f/ext/bc/C/rpc/`,
    //   accounts: [
    //     process.env.MAINNET_PRIVATE_KEY,
    //   ],
    //   chainId: 43114
    // }
    // etherscan: {
    //   apiKey: process.env.ETHERSCAN_API_KEY,
    // },
  },
};