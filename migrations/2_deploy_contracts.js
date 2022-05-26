const ZUSD = artifacts.require("ZUSD");
const Vault = artifacts.require("Vault");

module.exports = async function (deployer) {
  await deployer.deploy(ZUSD);
  const zUSD = await ZUSD.deployed();
  deployer.deploy(Vault, zUSD.address);
};
