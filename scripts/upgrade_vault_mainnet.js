const { ethers, upgrades } = require("hardhat");

// Current Impl Address of the Vault 
const currentVaultAddress = process.env.MAINNET_IMPL_ADDRESS;

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();