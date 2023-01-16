const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault 
const currentVaultAddress = /** PASTE ADDRESS HERE */ 

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const box = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded");
}

main();