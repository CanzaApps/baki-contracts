const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault 
const currentVaultAddress = process.env.TESTNET_VAULT;

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();