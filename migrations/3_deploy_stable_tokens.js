
const ZCFA = artifacts.require("ZCFA");
const ZNGN = artifacts.require("ZNGN");
const ZZAR = artifacts.require("ZZAR");


module.exports = function (deployer) {
  deployer.deploy(ZCFA)
  deployer.deploy(ZNGN)
  deployer.deploy(ZZAR)
   
};