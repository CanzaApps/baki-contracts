/** @type import('hardhat/config').HardhatUserConfig */
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-etherscan");

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
        `70c98cb21a3e0a15aaa81f98deae3f03c510b2e85a02a5963d05ad537c4bc51c`,
      ],
    },
    fuji: {
      url: `https://omniscient-restless-thunder.avalanche-testnet.discover.quiknode.pro/933a2d24cf1a762fd73a569be25bdec21cb60a9f/ext/bc/C/rpc`,
      accounts: [
        `4cacfec187b1b89b13e888784697c86de3cdb2c79b318777e92ebcfea52bef43`,
      ],
      chainId: 43113,
    },
    // etherscan: {
    //   apiKey: process.env.ETHERSCAN_API_KEY,
    // },
  },
};