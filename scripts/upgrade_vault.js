const { ethers, upgrades } = require("hardhat");

// Current Address of the Vault
const currentVaultAddress = "0x3ab5E7a3466d0e5B556e0005D705cbC3ADc34767";

async function main() {
  const upgradedVault = await ethers.getContractFactory("Vault");

  const vault = await upgrades.upgradeProxy(currentVaultAddress, upgradedVault);

  console.log("Vault upgraded", vault.address);
}

main();
