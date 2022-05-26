const Vault = artifacts.require("Vault");

contract("Vault", accounts => {
  it("should deposit cUSD", async () => {
    const vault = await Vault.deployed();
    await vault.deposit(web3.utils.toWei("1", "ether"), {
      from: "0x5488396763CcD71B64c68eD45fF831D39257a254",
    });
    const getVault = await vault.getVault(accounts[0]);
    assert.equal(getVault.collateralAmount, web3.utils.toWei("1", "ether"));
  });
});
