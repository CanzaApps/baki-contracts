
const ZUSD = artifacts.require("ZUSD");
const Vault = artifacts.require("Vault");


module.exports =  function (deployer) {
 deployer.deploy(ZUSD).then(async () => {
   const zUSD = await ZUSD.deployed();
   return await deployer.deploy(Vault, zUSD.address)
 })
};
